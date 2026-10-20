---
title: "Runbook: Admission Webhook Blocking Deployments"
description: "Creates and updates fail with 'failed calling webhook'. Find the webhook, restore its backend, and bypass only that one webhook if you must."
tags:
  [kubernetes/eks/operator-runbook, eks, runbook, admission, webhooks, incident]
date: 2026-10-20
aliases: [EKS webhook outage runbook, failed calling webhook]
---

# Runbook: Admission Webhook Blocking Deployments

**Applies to:** any EKS cluster with validating or mutating admission webhooks, for example the AWS Load Balancer Controller, Kyverno, Gatekeeper, cert-manager, Istio or Linkerd injectors.
**Typical severity:** Sev 1–2. Deploys, scaling and self-healing can stop cluster-wide while everything already running keeps working.
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

`kubectl apply` or a CI deploy fails, or a ReplicaSet can't create Pods (`kubectl describe rs` shows `FailedCreate`), with one of these messages:

```text
Internal error occurred: failed calling webhook "mservice.elbv2.k8s.aws": failed to call webhook:
  Post "https://aws-load-balancer-webhook-service.kube-system.svc:443/mutate-v1-service?timeout=10s":
  context deadline exceeded
... failed calling webhook "...": ... no endpoints available for service "kyverno-svc"
... failed calling webhook "...": ... tls: failed to verify certificate: x509: certificate signed by unknown authority
```

**Not an outage:** `admission webhook "..." denied the request: <policy message>`. The webhook is working and rejecting the object on purpose. Fix the object or the policy; never bypass the webhook for this.

## Impact

Every request the webhook matches fails while its `failurePolicy` is `Fail` (the default). This matters most when the webhook matches Pods. Then ReplicaSets, DaemonSets, Jobs and node replacement can't create Pods, and a node failure doesn't self-heal. A webhook can even block its own backend Pods from restarting, which deadlocks it.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=my-cluster REGION=us-east-1
export HOOK_NAME=<webhook name from the error, e.g. mservice.elbv2.k8s.aws>
```

## Triage

**1. Find the webhook configuration, its backend and its settings.**

```bash
for kind in validatingwebhookconfigurations mutatingwebhookconfigurations; do
  kubectl get "$kind" -o json | jq -r --arg k "$kind" '
    .items[] | .metadata.name as $cfg | .webhooks | to_entries[] |
    [$k, $cfg, (.key|tostring), .value.name, .value.failurePolicy, (.value.timeoutSeconds|tostring),
     (.value.clientConfig.service // {} | "\(.namespace)/\(.name):\(.port // 443)")] | @tsv'
done | column -t | grep -E "$HOOK_NAME|^$"
```

The columns are: kind, configuration name, index, webhook name, failurePolicy, timeout and backend Service. Set the variables from the matching row:

```bash
export HOOK_KIND=<kind> HOOK_CONFIG=<configuration name> HOOK_INDEX=<index>
export SVC_NS=<namespace> SVC=<service>
```

**2. Does the backend have ready endpoints?**

```bash
kubectl get endpointslices -n "$SVC_NS" -l kubernetes.io/service-name="$SVC" \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready}{"\n"}{end}'
kubectl get pods -n "$SVC_NS" -o wide
kubectl get events -n "$SVC_NS" --sort-by=.lastTimestamp | tail -20
```

- **If** there are no ready endpoints → the backend is down (cause A). Check whether its Pods are Pending, crash-looping, or missing because their ReplicaSet gets `FailedCreate` from **this same webhook** (cause A, deadlock).
- **If** endpoints are ready but calls time out → the control plane can't reach the Pod (cause B).
- **If** the error is `x509` → certificate or `caBundle` mismatch (cause C).

**3. How much is failing?** The API server's own metrics show it directly:

```bash
kubectl get --raw /metrics | grep -E 'apiserver_admission_webhook_rejection_count.*calling_webhook_error' | grep "$HOOK_NAME"
```

## Diagnosis

| Signal                                                       | Cause                                                                  | Fix                                 |
| ------------------------------------------------------------ | ---------------------------------------------------------------------- | ----------------------------------- |
| No ready endpoints                                           | A. Backend Pods down (sometimes blocked by their own webhook)          | Step 1; if deadlocked, step 4 first |
| Endpoints ready; `context deadline exceeded`                 | B. Control plane → Pod network path blocked                            | Step 2                              |
| `x509: certificate signed by unknown authority` or `expired` | C. Serving certificate and `caBundle` don't match, or the cert expired | Step 3                              |
| `denied the request`                                         | Policy working as intended                                             | Fix the object, not the webhook     |

## Fix

Restoring the backend is always the real fix. Bypassing the webhook (step 4) only buys time.

**1. Restore the backend (cause A).**

```bash
kubectl describe pod -n "$SVC_NS" <backend-pod>
kubectl logs -n "$SVC_NS" <backend-pod> --previous --tail=100
kubectl rollout status deploy/<backend-deployment> -n "$SVC_NS"
```

Usual reasons: all replicas were on a node that died (one replica, no anti-affinity); Pending because of insufficient capacity or [[Kubernetes/eks/operator-runbook/runbooks/pods-stuck-containercreating-ip-exhaustion|IP exhaustion]]; crash-looping after an upgrade; or the controller's IAM role broke (the AWS Load Balancer Controller logs `AccessDenied`). Fix that, and wait for ready endpoints.

If the backend's own Pods get `FailedCreate` from this webhook, it's deadlocked. Do step 4 for this one webhook, let the backend start, then restore it.

**2. Open the network path (cause B).** The EKS control plane calls the webhook at the **Pod IP** through the cluster's ENIs in your subnets.

- The node (or Pod, with security groups for Pods) security group must allow inbound from the **cluster security group** on the webhook's `targetPort`. That's often 9443 (AWS Load Balancer Controller, many controller-runtime webhooks), 8443 or 10250, rather than the Service port 443. Find it with `kubectl get svc "$SVC" -n "$SVC_NS" -o jsonpath='{.spec.ports[*].targetPort}'`.
- Check CloudTrail for recent `RevokeSecurityGroupIngress` events on the node or cluster security groups.
- If you run an overlay CNI such as Calico or Cilium in overlay mode instead of the VPC CNI, Pod IPs aren't routable from the control plane. The webhook Pod needs `hostNetwork: true` on a unique port.

```bash
aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text
```

**3. Fix the certificate (cause C).** Compare the `caBundle` in the webhook configuration with the CA that signed the serving certificate. With cert-manager, check the `Certificate` and the `cainjector`:

```bash
kubectl get certificate -n "$SVC_NS"
kubectl logs -n cert-manager deploy/cert-manager-cainjector --tail=50
```

Many controllers (the AWS Load Balancer Controller, Kyverno, Gatekeeper) generate or rotate their own certificates on start. Restarting the backend Deployment usually re-syncs the cert and the `caBundle`.

**4. Break-glass: bypass this one webhook.**

Use it only when restoring the backend will take longer than the outage can tolerate, or the webhook is blocking its own recovery. Follow your incident's change authority. Know the security cost before you do it:

- **Validating webhook set to `Ignore`:** objects are admitted _without the policy check_ while it's down.
- **Mutating webhook set to `Ignore`:** objects are created _without the mutation_: no sidecar, no readiness gate, no injected config. You'll need to restart those Pods afterwards.

Save the current configuration, then change only the matched webhook. The `test` operation makes the patch fail if the index no longer points at `HOOK_NAME`:

```bash
kubectl get "$HOOK_KIND" "$HOOK_CONFIG" -o yaml > "webhook-$HOOK_CONFIG-before.yaml"
kubectl patch "$HOOK_KIND" "$HOOK_CONFIG" --type=json -p "[
  {\"op\":\"test\",\"path\":\"/webhooks/$HOOK_INDEX/name\",\"value\":\"$HOOK_NAME\"},
  {\"op\":\"replace\",\"path\":\"/webhooks/$HOOK_INDEX/failurePolicy\",\"value\":\"Ignore\"}]"
date -u +%FT%TZ > webhook-bypass-start.txt
```

**Something may revert this:**

- **Argo CD with self-heal, or Flux:** pause sync for the app that owns the configuration (`argocd app set <app> --sync-policy none`, or `flux suspend helmrelease <name> -n <ns>`).
- **Kyverno** (and other engines that manage their own webhook configurations) rewrites them on its own. The engine's documented recovery is usually to scale it down and delete its webhook configurations, which it re-creates when it starts. Check that engine's troubleshooting guide.

**Undo (required).** Once the backend has ready endpoints and a test call succeeds (see Verify), set the policy back to `Fail` with the same name-checked patch, or let GitOps re-sync. Then resume any paused sync. For a mutating webhook, restart the workloads created during the bypass:

```bash
kubectl patch "$HOOK_KIND" "$HOOK_CONFIG" --type=json -p "[
  {\"op\":\"test\",\"path\":\"/webhooks/$HOOK_INDEX/name\",\"value\":\"$HOOK_NAME\"},
  {\"op\":\"replace\",\"path\":\"/webhooks/$HOOK_INDEX/failurePolicy\",\"value\":\"Fail\"}]"
kubectl get pods -A -o json | jq -r --arg t "$(cat webhook-bypass-start.txt)" \
  '.items[] | select(.metadata.creationTimestamp >= $t) | "\(.metadata.namespace)/\(.metadata.name)"'
```

Never patch every webhook in the cluster, and never delete a configuration unless its owner re-creates it.

## Verify recovery

A server-side dry run goes through admission webhooks without creating anything:

```bash
kubectl create deployment wh-test -n default --image=public.ecr.aws/docker/library/busybox:1.36 \
  --dry-run=server -o name
```

- **Expect:** `deployment.apps/wh-test` with no webhook error. (A webhook declared with side effects is skipped on dry runs. If yours is, test with a real throwaway object in a scratch namespace.)
- For a validating policy webhook, also submit an object that **should** be rejected, and confirm it is. That proves enforcement is back, not just availability.
- Check that stalled rollouts complete and that `FailedCreate` events have stopped:

  ```bash
  kubectl get events -A --field-selector reason=FailedCreate | tail
  ```

## Escalate

This is almost always fixed on the customer side. Open an AWS Support case only if endpoints are ready and the security groups and routes allow the cluster security group, yet the API server still times out on the webhook. Attach the cluster ARN, the webhook configuration, the backend Pod IPs, the time window and API server logs. Enable the `api` control-plane log type in CloudWatch if it's off.

## Prevent

- **Scope webhooks.** Use a `namespaceSelector` that excludes `kube-system` and the webhook's own namespace, and an `objectSelector` where possible. Most charts expose these values.
- **Keep timeouts short.** Use `timeoutSeconds: 5` or less (the default is 10, the maximum 30), so an outage fails fast instead of piling up requests.
- **Run backends highly available.** Use at least 2 replicas, topology spread across AZs, a PodDisruptionBudget, and `priorityClassName: system-cluster-critical` for webhooks that guard Pods.
- **Choose `failurePolicy` deliberately.** Use `Fail` only for webhooks whose absence would be a security or correctness problem; mutators that only add convenience can use `Ignore`.
- **Alert** on `apiserver_admission_webhook_rejection_count{error_type="calling_webhook_error"}` rising, and on `apiserver_admission_webhook_admission_duration_seconds` p99 approaching the timeout.
- **Allow the port in IaC.** When you add a webhook, open its `targetPort` from the cluster security group, so a security-group change can't silently break it.

## Background

- [[Kubernetes/concepts/L07-security/04-admission-policy/10-admission-controllers|Admission controllers]]
- [[Kubernetes/concepts/L07-security/04-admission-policy/12-kyverno|Kyverno]] and [[Kubernetes/concepts/L07-security/04-admission-policy/11-opa-gatekeeper|OPA Gatekeeper]]
- [Admission webhook good practices](https://kubernetes.io/docs/concepts/cluster-administration/admission-webhooks-good-practices/)
- [EKS security group requirements](https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html)
