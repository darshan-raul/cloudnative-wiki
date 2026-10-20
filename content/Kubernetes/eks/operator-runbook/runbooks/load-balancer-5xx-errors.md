---
title: "Runbook: ALB or NLB Returning 5xx Errors"
description: "Clients get 502, 503 or 504 from a load balancer created by the AWS Load Balancer Controller. Separate load-balancer-generated errors from application errors and fix target health, network path or rollout draining."
tags:
  [
    kubernetes/eks/operator-runbook,
    eks,
    runbook,
    alb,
    nlb,
    load-balancing,
    incident,
  ]
date: 2026-10-20
aliases:
  [EKS ALB 502 runbook, EKS ALB 503 504, AWS Load Balancer Controller 5xx]
---

# Runbook: ALB or NLB Returning 5xx Errors

**Applies to:** ALBs created from Ingress and NLBs from `Service type: LoadBalancer`, managed by the AWS Load Balancer Controller (or by EKS Auto Mode's built-in load balancing), with target type `ip` or `instance`.
**Typical severity:** Sev 1–2: user-facing errors.
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

- Clients get `502 Bad Gateway`, `503 Service Temporarily Unavailable` or `504 Gateway Time-out` from the ALB, or TCP resets and timeouts through an NLB.
- Errors often cluster during **deployments** or **node scale-in**.

## Impact

It depends on which side generates the error. The first job is to find out, because it decides everything else.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export REGION=us-east-1 NS=<namespace> ING=<ingress or service name>
export HOST=$(kubectl get ingress "$ING" -n "$NS" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
export LB_ARN=$(aws elbv2 describe-load-balancers --region "$REGION" \
  --query "LoadBalancers[?DNSName=='$HOST'].LoadBalancerArn" --output text)
export LB_DIM=$(echo "$LB_ARN" | sed 's#.*:loadbalancer/##')     # e.g. app/k8s-prod-web-1a2b3c/50dc6c495c0c9188
```

## Triage

**1. Who generated the 5xx: the ALB or your Pods?**

```bash
for m in HTTPCode_ELB_502_Count HTTPCode_ELB_503_Count HTTPCode_ELB_504_Count HTTPCode_Target_5XX_Count; do
  printf '%-28s ' "$m"
  aws cloudwatch get-metric-statistics --region "$REGION" --namespace AWS/ApplicationELB --metric-name "$m" \
    --dimensions Name=LoadBalancer,Value="$LB_DIM" --statistics Sum --period 300 \
    --start-time "$(date -u -d '-1 hour' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
    --query 'sort_by(Datapoints,&Timestamp)[-3:].Sum' --output text
done
```

- `HTTPCode_Target_5XX_Count` → **your application** returned the 5xx. The load balancer is fine; debug the app (logs, dependencies).
- `HTTPCode_ELB_*` → **the ALB** generated it. Continue below. In ALB access logs, these rows have `target_status_code` set to `-`.

| ALB code | Usual cause on EKS                                                                                      |
| -------- | ------------------------------------------------------------------------------------------------------- |
| **503**  | No healthy, registered targets in the target group                                                      |
| **502**  | Target closed or reset the connection: Pod killed mid-request, keep-alive mismatch, or bad response     |
| **504**  | Target didn't respond in time, or the ALB couldn't connect (security group, network policy, wrong port) |

**2. Target health, with reasons.** The controller records each target group in a `TargetGroupBinding`:

```bash
kubectl get targetgroupbindings -n "$NS" -o custom-columns=NAME:.metadata.name,SVC:.spec.serviceRef.name,PORT:.spec.serviceRef.port,TYPE:.spec.targetType,ARN:.spec.targetGroupARN
export TG_ARN=<arn from above>
aws elbv2 describe-target-health --region "$REGION" --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].[Target.Id,Target.Port,TargetHealth.State,TargetHealth.Reason]' --output table
kubectl get endpointslices -n "$NS" -l kubernetes.io/service-name=<service> -o wide
```

| Reason                            | Meaning                                                                           |
| --------------------------------- | --------------------------------------------------------------------------------- |
| `Target.Timeout`                  | Health check can't connect: security group, network policy or port                |
| `Target.FailedHealthChecks`       | Connects, but the check fails or gets reset                                       |
| `Target.ResponseCodeMismatch`     | Health-check path returns a code outside `success-codes` (for example 404 or 301) |
| `Target.NotRegistered`            | Pod IP not in the target group; the controller hasn't reconciled                  |
| `Target.DeregistrationInProgress` | Draining: normal during rollout, a problem if traffic still reaches it            |
| `Target.NotInUse`                 | Target's AZ isn't enabled on the load balancer (subnet missing)                   |

- **If** the registered Pod IPs don't match the ready EndpointSlice addresses → the controller is behind (cause D).

**3. Is the controller reconciling?**

```bash
kubectl describe ingress "$ING" -n "$NS" | sed -n '/Events:/,$p'
kubectl logs -n kube-system deploy/aws-load-balancer-controller --tail=200 | grep -iE 'error|denied|throttl' | tail -20
```

`FailedDeployModel` and `FailedBuildModel` events name the problem: a missing subnet tag, IAM `AccessDenied`, a certificate ARN not found, or an annotation error.

**4. Do errors line up with rollouts or scale-in?**

```bash
kubectl rollout history deploy/<name> -n "$NS"
kubectl get events -n "$NS" --field-selector reason=Killing --sort-by=.lastTimestamp | tail
```

## Diagnosis

| Signal                                                    | Cause                                                   | Fix                             |
| --------------------------------------------------------- | ------------------------------------------------------- | ------------------------------- |
| `HTTPCode_Target_5XX`                                     | Application error                                       | Debug the app; not this runbook |
| 503; no healthy targets; `Target.Timeout`                 | A. Load balancer can't reach Pods                       | Fix A                           |
| 503; `Target.ResponseCodeMismatch` / `FailedHealthChecks` | B. Health check misconfigured, or app unhealthy         | Fix B                           |
| 502 or 503 bursts during deploys or scale-in              | C. Pods removed before the load balancer stops sending  | Fix C                           |
| Registered targets ≠ ready endpoints; `FailedDeployModel` | D. Controller not reconciling                           | Fix D                           |
| Steady trickle of 502s on idle connections                | E. Keep-alive timeout shorter than the ALB idle timeout | Fix E                           |
| 504s on slow endpoints                                    | F. Request longer than idle timeout                     | Fix F                           |

## Fix

### A. Load balancer can't reach Pods

- **Security groups:** with target type `ip`, the ALB connects to the **Pod IP and container port**. The controller normally adds an inbound rule from the ALB's security group to the node security group (or the Pod's, with security groups for Pods). Check that it exists, and that nothing removed it. In CloudTrail, look for `RevokeSecurityGroupIngress`.
- **NetworkPolicy:** a default-deny ingress policy in the namespace must allow the VPC CIDR, or the load balancer subnets, on the container port.
- **Wrong port:** the Service `targetPort` must match what the container listens on.

**Verify:** targets go `healthy` within a few health-check intervals (`describe-target-health`).

### B. Health check misconfigured or app unhealthy

Set the health check to a cheap endpoint that returns 200 without depending on downstream services. Use Ingress annotations so the controller keeps it:

```yaml
metadata:
  annotations:
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
    alb.ingress.kubernetes.io/success-codes: "200"
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: "10"
    alb.ingress.kubernetes.io/healthy-threshold-count: "2"
```

If the endpoint is right and the app is failing it, this is an application incident. Roll back the deploy.

### C. Pods removed before the load balancer stops sending

The Pod's readiness drops and it's deregistered, but the load balancer keeps sending to it for a few seconds while the change propagates. If the Pod exits immediately, those requests get 502 or 503.

1. **Pod readiness gates**, so a rollout waits until new targets are healthy in the target group, not just Ready in Kubernetes:

   ```bash
   kubectl label namespace "$NS" elbv2.k8s.aws/pod-readiness-gate-inject=enabled
   kubectl rollout restart deploy/<name> -n "$NS"     # gates are injected at Pod creation
   ```

2. **Keep the Pod serving while it deregisters.** Use a `preStop` sleep longer than the propagation time, and a grace period that covers it:

   ```yaml
   spec:
     terminationGracePeriodSeconds: 60
     containers:
       - name: app
         lifecycle:
           preStop:
             sleep:
               seconds: 20
   ```

   (Or `exec: {command: ["sleep", "20"]}` on images where you prefer that.)

3. **Shorten the deregistration delay** from the 300-second default, so rollouts don't take forever:

   ```yaml
   alb.ingress.kubernetes.io/target-group-attributes: deregistration_delay.timeout_seconds=30
   ```

Instance-mode targets add a kube-proxy hop, so node scale-in also drops traffic. Prefer `ip` mode.

### D. Controller not reconciling

Fix what the `FailedDeployModel` event says. Common causes: the controller's IAM role lacks a permission after a controller upgrade (compare it with the IAM policy published for that version); subnets lack the `kubernetes.io/role/elb` (public) or `kubernetes.io/role/internal-elb` (internal) tag; or a webhook outage (see [[Kubernetes/eks/operator-runbook/runbooks/webhook-blocking-deployments|webhook blocking deployments]]). Restarting the controller is safe; it re-reconciles every Ingress and Service.

### E. Keep-alive mismatch

If the application closes idle keep-alive connections **sooner** than the ALB's idle timeout (60 s by default), the ALB occasionally reuses a connection the app just closed, and returns 502. Set the application's keep-alive timeout **longer** than the ALB idle timeout, for example 75 s in Node.js `server.keepAliveTimeout`, or gunicorn `--keep-alive`.

### F. Request longer than idle timeout

Raise the idle timeout for endpoints that legitimately run long, or make them asynchronous:

```yaml
alb.ingress.kubernetes.io/load-balancer-attributes: idle_timeout.timeout_seconds=120
```

## NLB notes

NLBs don't generate HTTP codes. Watch `UnHealthyHostCount`, `TCP_Target_Reset_Count` and `TCP_ELB_Reset_Count` in `AWS/NetworkELB`. Two EKS-specific traps:

- **Hairpin timeouts:** a Pod calling its own Service through an internal NLB with client IP preservation enabled can time out when the load balancer picks the same node. Call the Service's ClusterIP instead, or disable client IP preservation (`preserve_client_ip.enabled=false` target group attribute).
- **Security groups:** if the NLB has no security group (older NLBs), traffic arrives with the **client's** IP. The node or Pod security group must allow the client CIDRs, not the NLB.

## Verify recovery

- `HTTPCode_ELB_5XX` returns to zero and `HealthyHostCount` matches the replica count.
- Run a rollout (`kubectl rollout restart deploy/<name>`) while sending steady traffic (`hey`, `k6` or a curl loop), and confirm zero 5xx. That's the real test of Fix C.

## Escalate

Open an AWS Support case if `HTTPCode_ELB_5XX` persists with healthy targets, correct security groups and no application errors, or if target health shows `Elb.InternalError`. Attach the load balancer ARN, target group ARN, UTC time window and ALB access-log excerpts.

## Prevent

- Alert separately on `HTTPCode_ELB_5XX_Count` (platform side) and `HTTPCode_Target_5XX_Count` (application side), and on `UnHealthyHostCount > 0`.
- Make readiness gates, a `preStop` delay and a 30-second deregistration delay the platform default for every ingress-backed Deployment.
- Turn on ALB access logs to S3. Without them, you can't tell later which side generated the errors.
- Pin the controller IAM policy to the controller version in IaC, and upgrade both together.

## Background

- [[AWS/networking/load-balancing/README|AWS load balancing]]
- [[Kubernetes/concepts/L04-services-networking/04-ingress|Ingress]]
- [[Kubernetes/guides/troubleshooting/service-unreachable|Troubleshooting unreachable Services]]
- [AWS Load Balancer Controller: pod readiness gate](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/pod_readiness_gate/)
- [Troubleshoot your Application Load Balancers](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-troubleshooting.html)
