---
title: "Runbook: HPA Not Scaling"
description: "A HorizontalPodAutoscaler shows unknown metrics, stays at its minimum under load, hits its maximum, or flaps. Read its conditions and fix metrics, requests, limits or behaviour."
tags:
  [
    kubernetes/eks/operator-runbook,
    eks,
    runbook,
    hpa,
    keda,
    autoscaling,
    incident,
  ]
date: 2026-10-20
aliases: [HPA unknown metrics runbook, HPA FailedGetResourceMetric]
---

# Runbook: HPA Not Scaling

**Applies to:** `autoscaling/v2` HorizontalPodAutoscalers using resource metrics (metrics-server), custom metrics (for example the Prometheus adapter) or external metrics (KEDA).
**Typical severity:** Sev 2 during a traffic peak; otherwise Sev 3.
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

```text
NAME   REFERENCE        TARGETS              MINPODS   MAXPODS   REPLICAS
api    Deployment/api   cpu: <unknown>/70%   3         12        3
```

Or the HPA shows real numbers but doesn't move, sits at `MAXPODS` while latency climbs, or flips the replica count up and down.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export NS=<namespace> HPA=<hpa name>
```

## Triage

**1. Read the conditions.** They state the reason in plain words:

```bash
kubectl describe hpa "$HPA" -n "$NS" | sed -n '/Conditions:/,$p'
```

| Condition                                                                | Meaning                                                                                                                                                                                                                              |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `ScalingActive False`, `FailedGetResourceMetric`                         | Can't read the metric (cause A or B)                                                                                                                                                                                                 |
| `ScalingActive False`, `FailedGetExternalMetric` / `FailedGetPodsMetric` | Custom or external metrics API problem (cause C)                                                                                                                                                                                     |
| `ScalingLimited True`, `TooManyReplicas`                                 | Wants more than `maxReplicas` (cause D)                                                                                                                                                                                              |
| `AbleToScale False`, `FailedGetScale`                                    | The target (`scaleTargetRef`) is wrong or missing                                                                                                                                                                                    |
| `ScalingActive True`, replicas changing, Pods `Pending`                  | The HPA works; the cluster has no room. Use [[Kubernetes/eks/operator-runbook/runbooks/karpenter-not-launching-nodes\|Karpenter]] or [[Kubernetes/eks/operator-runbook/runbooks/cluster-autoscaler-not-scaling\|Cluster Autoscaler]] |

**2. Do resource metrics work at all?**

```bash
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top pods -n "$NS"
kubectl get deploy metrics-server -n kube-system
```

**3. Does every container have the requests the HPA needs?** CPU and memory utilization targets are a percentage of **requests**:

```bash
kubectl get deploy <target> -n "$NS" -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\t"}{.resources.requests}{"\n"}{end}'
```

A sidecar without a CPU request makes the whole Pod's utilization unknown.

## Diagnosis

| Signal                                                          | Cause                                | Fix   |
| --------------------------------------------------------------- | ------------------------------------ | ----- |
| `kubectl top` fails; `metrics.k8s.io` not `Available`           | A. metrics-server missing or broken  | Fix A |
| `missing request for cpu in container ...`                      | B. A container lacks requests        | Fix B |
| Custom or external metric errors; KEDA ScaledObject not ready   | C. Metrics adapter or KEDA trigger   | Fix C |
| `TooManyReplicas`, latency still high                           | D. `maxReplicas` too low             | Fix D |
| Replicas flap up and down                                       | E. Behaviour and stabilization       | Fix E |
| Metric high but HPA scales little; low utilization at high load | F. Wrong metric or requests too high | Fix F |

## Fix

### A. metrics-server missing or broken

EKS doesn't run metrics-server by default. Install it with its Helm chart, or as an EKS add-on where your cluster offers it. If it's installed but `metrics.k8s.io` isn't `Available`:

```bash
kubectl describe apiservice v1beta1.metrics.k8s.io | sed -n '/Status:/,$p'
kubectl logs -n kube-system deploy/metrics-server --tail=50
```

The API server must reach the metrics-server Pod on its port (10250 or 4443, depending on the chart): the same control-plane-to-Pod path as admission webhooks. See [[Kubernetes/eks/operator-runbook/runbooks/webhook-blocking-deployments|webhook runbook]] Fix step 2 for the security group rule.

### B. A container lacks requests

Add CPU (and, if the HPA uses memory, memory) requests to **every** container in the Pod, including sidecars, then roll the Deployment. Injected sidecars (service mesh, logging) get their requests from the injector's configuration.

### C. Custom or external metrics

```bash
kubectl get apiservices | grep -E 'custom.metrics|external.metrics'
kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1" | jq '.resources[].name' | head
kubectl get scaledobjects -n "$NS"                 # KEDA
kubectl describe scaledobject <name> -n "$NS" | sed -n '/Conditions:/,$p'
```

For KEDA, the `ScaledObject` conditions name the failing trigger: often its authentication (`TriggerAuthentication` with Pod Identity or IRSA to read SQS, CloudWatch and so on), or a wrong queue URL or query. KEDA creates and owns the HPA, so don't edit that HPA directly.

### D. maxReplicas too low

Raise `maxReplicas` in the HPA's source (Git or chart values). Check the new maximum fits within namespace quotas, subnet addresses and node capacity.

### E. Flapping

Add a scale-down stabilization window and rate limits (the default scale-down window is 300 seconds):

```yaml
spec:
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 600
      policies:
        - type: Percent
          value: 20
          periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
```

Also check that only one autoscaler controls the replicas. Two HPAs on one Deployment, VPA in `Auto` mode on the same CPU metric, or GitOps setting `spec.replicas` (see [[Kubernetes/eks/operator-runbook/runbooks/gitops-drift-and-reverted-fixes|GitOps drift]] Fix B) all fight the HPA.

### F. Wrong metric

CPU is a poor signal for I/O-bound or queue-driven services. Requests set far above real use make utilization look low, so the HPA never scales. Scale on what tracks load (requests per second, queue depth, in-flight requests) with custom or external metrics or KEDA, and set requests from observed usage.

## Verify recovery

```bash
kubectl get hpa "$HPA" -n "$NS" -w
```

`TARGETS` shows real values, and replicas follow load during the next peak (or a load test).

## Escalate

Escalate to the workload owner for metric choice and requests, and to the platform team for metrics-server, the adapter or KEDA.

## Prevent

- Install metrics-server as part of cluster bootstrap, with two replicas and a PDB.
- Alert on HPAs with `ScalingActive=False` (`kube_horizontalpodautoscaler_status_condition`), and on HPAs at `maxReplicas` for more than 15 minutes.
- Require requests on every container through admission policy.

## Background

- [[Kubernetes/concepts/L06-scheduling-scaling/10-keda|KEDA]]
- [[Kubernetes/eks/advanced/autoscaling|Autoscaling on EKS]]
- [Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
