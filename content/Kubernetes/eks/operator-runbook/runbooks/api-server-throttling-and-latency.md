---
title: "Runbook: API Server 429s and Slow API Responses"
description: "kubectl, controllers or CI get 429 TooManyRequests or slow API calls. Separate client-side throttling from API priority and fairness, find the noisy caller, and contain it."
tags:
  [
    kubernetes/eks/operator-runbook,
    eks,
    runbook,
    api-server,
    apf,
    control-plane,
    incident,
  ]
date: 2026-10-20
aliases:
  [
    EKS API throttling runbook,
    EKS 429 TooManyRequests,
    API priority and fairness EKS,
  ]
---

# Runbook: API Server 429s and Slow API Responses

**Applies to:** all EKS clusters. The control plane is managed and scales automatically, but API priority and fairness (APF) still sheds load per caller, and expensive requests are slow at any scale.
**Typical severity:** Sev 2. Controllers fall behind: rollouts, autoscaling and load-balancer reconciliation slow down or stall.
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

| Message                                                                                                               | Where it comes from                                                               |
| --------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `Waited for 1.2s due to client-side throttling, not priority and fairness, request: GET ...`                          | **The client's own rate limiter** (`client-go` QPS and burst). The server is fine |
| `Error from server (TooManyRequests): the server has received too many requests and has temporarily limited the rate` | **APF on the server** rejected the request (HTTP 429 with `Retry-After`)          |
| `context deadline exceeded`, or `the server was unable to return a response in the time allotted`                     | Request queued or ran too long: expensive LISTs, slow webhooks, etcd load         |
| Controllers log `rate: Wait(n=1) would exceed context deadline`                                                       | Client-side limiter on a busy controller                                          |

## Impact

APF protects the API server by putting requests into **priority levels**. System traffic (`system`, `node-high`, `leader-election`) is protected from workload traffic (`workload-high`, `workload-low`, `global-default`). Usually only the noisy client and its neighbours in the same priority level suffer. When it's a controller (Karpenter, the load balancer controller, GitOps), the effects spread.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=my-cluster REGION=us-east-1
```

## Triage

**1. Client-side or server-side?** The message says it (table above). For a server-side 429, check which flow schema and priority level the request landed in. The API server returns them as response headers:

```bash
kubectl get pods -A -v=8 2>&1 | grep -iE 'X-Kubernetes-Pf-(Flowschema|Prioritylevel)-Uid' | head -2
kubectl get flowschemas -o custom-columns=NAME:.metadata.name,PRIORITY:.spec.priorityLevelConfiguration.name,PRECEDENCE:.spec.matchingPrecedence,UID:.metadata.uid
```

**2. Which priority levels are rejecting, and how much?**

```bash
kubectl get --raw /metrics | grep '^apiserver_flowcontrol_rejected_requests_total' | sort -t' ' -k2 -nr | head
kubectl get --raw /metrics | grep '^apiserver_flowcontrol_current_inqueue_requests' | sort -t' ' -k2 -nr | head
kubectl get prioritylevelconfigurations
```

The metric labels give `priority_level`, `flow_schema` and `reason` (`queue-full`, `time-out`, `concurrency-limit`).

**3. Who is calling?** Use the audit log query "Who is calling the API most" in [[Kubernetes/eks/operator-runbook/reference/control-plane-logs-and-metrics|control-plane logs and metrics]]. Without audit logs, check the metrics for expensive verbs:

```bash
kubectl get --raw /metrics | grep '^apiserver_request_total' | grep -E 'verb="(LIST|WATCH)"' | sort -t' ' -k2 -nr | head -15
```

Typical offenders:

- An operator or exporter doing **unpaginated cluster-wide LISTs** of Pods, Secrets, ConfigMaps or Events every few seconds, instead of using informers (WATCH).
- **CI or scripts** running `kubectl get ... -A` in loops.
- A controller **crash-looping**: each restart relists everything.
- **Very many objects**: thousands of Helm release Secrets, Events, completed Jobs or ReplicaSets, which make every LIST big.

**4. Is the database big?**

```bash
kubectl get --raw /metrics | grep '^apiserver_storage_size_bytes'
kubectl get --raw /metrics | grep -E '^apiserver_(storage|resource)_objects' | sort -t' ' -k2 -nr | head -10   # object counts (metric renamed in newer releases)
kubectl get secrets -A --field-selector type=helm.sh/release.v1 --no-headers | wc -l
```

**5. Are admission webhooks adding latency?**

```bash
kubectl get --raw /metrics | grep 'apiserver_admission_webhook_admission_duration_seconds_sum' | sort -t' ' -k2 -nr | head
```

## Diagnosis

| Signal                                                                        | Cause                                         | Fix      |
| ----------------------------------------------------------------------------- | --------------------------------------------- | -------- |
| `client-side throttling` messages only                                        | A. Client rate limit too low for its workload | Fix A    |
| 429s; one user or service account dominates calls                             | B. Noisy caller                               | Fix B    |
| Slow LISTs; large object counts for some resources                            | C. Object sprawl                              | Fix C    |
| Slow writes; high webhook duration                                            | D. Slow admission webhooks                    | Fix D    |
| High rejection across many callers, nothing stands out, steady organic growth | E. Real capacity need                         | Escalate |

## Fix

### A. Client-side throttling

The server isn't rejecting anything; the client is pacing itself. For a controller, raise its QPS and burst settings (most expose `--kube-api-qps` and `--kube-api-burst`, or Helm values for them) moderately. For scripts, slow the loop down, or use a watch. Don't raise them without limit; that moves the problem to APF.

### B. Noisy caller

1. **Fix the caller.** Upgrade the operator, set its resync period to minutes instead of seconds, make it use label or field selectors, or stop the CI loop. Scale a broken controller to 0 if it's harming the cluster and isn't critical.
2. **Contain it while you fix it.** Put its requests in the low-priority level with a FlowSchema, so it can't starve other workload traffic:

   ```yaml
   apiVersion: flowcontrol.apiserver.k8s.io/v1
   kind: FlowSchema
   metadata:
     name: contain-noisy-exporter
   spec:
     priorityLevelConfiguration:
       name: workload-low
     matchingPrecedence: 1000
     distinguisherMethod:
       type: ByUser
     rules:
       - subjects:
           - kind: ServiceAccount
             serviceAccount:
               name: exporter
               namespace: monitoring
         resourceRules:
           - verbs: ["get", "list", "watch"]
             apiGroups: ["*"]
             resources: ["*"]
             namespaces: ["*"]
             clusterScope: true
   ```

   A lower `matchingPrecedence` number wins, so make sure it's lower than the schema currently matching the caller (from Triage step 1). Don't edit the built-in `exempt` or `catch-all` objects; the API server restores them.

**Undo:** delete the FlowSchema once the caller is fixed.

### C. Object sprawl

- **Helm release Secrets:** cap history with `helm upgrade --history-max 5`. Delete superseded release Secrets for a release only through Helm, not by hand.
- **Completed Jobs:** set `ttlSecondsAfterFinished` on Jobs, and `successfulJobsHistoryLimit` and `failedJobsHistoryLimit` on CronJobs.
- **Old ReplicaSets:** set `revisionHistoryLimit` (the default is 10) on Deployments with many replicas.
- **Events:** high Event churn means something is failing in a loop. Find the reason with `kubectl get events -A --no-headers | awk '{print $3}' | sort | uniq -c | sort -rn | head` and fix it.

EKS enforces a database size limit. If `apiserver_storage_size_bytes` approaches it, writes start failing; treat that as Sev 1 and open an AWS Support case while you clean up.

### D. Slow admission webhooks

Every matching write waits for the webhook. Scope webhooks with selectors, shorten `timeoutSeconds`, and scale or fix slow backends. See [[Kubernetes/eks/operator-runbook/runbooks/webhook-blocking-deployments|Webhook blocking deployments]], Prevent.

## Verify recovery

- `apiserver_flowcontrol_rejected_requests_total` stops increasing for workload priority levels.
- `kubectl get pods -A` returns in a second or two.
- Controllers catch up: rollouts finish, Pending Pods schedule, and Ingresses reconcile.

## Escalate

Open an AWS Support case if rejection or latency is high across many well-behaved callers, the database size is close to its limit, or `system` or `leader-election` priority levels are rejecting. Attach the cluster ARN, the time window, the top callers from the audit log, and the APF metric output.

## Prevent

- Turn on the `audit` log type, so you can always answer "who is calling".
- Alert on `apiserver_flowcontrol_rejected_requests_total` rate, and on API request latency p99 by verb.
- Review new operators for LIST behaviour before installing them cluster-wide.
- Set history limits (Helm, Jobs, ReplicaSets) as platform defaults.

## Background

- [[Kubernetes/eks/operator-runbook/reference/control-plane-logs-and-metrics|Control-plane logs and metrics]]
- [API priority and fairness](https://kubernetes.io/docs/concepts/cluster-administration/flow-control/)
- [EKS best practices: control plane](https://docs.aws.amazon.com/eks/latest/best-practices/control-plane.html)
