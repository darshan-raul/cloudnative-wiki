---
title: "Reference: Control-Plane Logs and Metrics"
description: "Turn on EKS control-plane logging, and the CloudWatch Logs Insights queries and API server metrics that answer 'who changed this', 'who is hammering the API' and 'is admission slow'."
tags: [kubernetes/eks/operator-runbook, eks, reference, audit, logging, metrics]
date: 2026-10-20
aliases: [EKS audit log queries, EKS API server metrics]
---

# Reference: Control-Plane Logs and Metrics

## Turn on control-plane logging

The log types are off by default. Turn them on before you need them; they can't be read retroactively.

```bash
aws eks update-cluster-config --name "$CLUSTER" --region "$REGION" --logging \
  '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}'
aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query 'cluster.logging'
```

Logs go to the CloudWatch log group `/aws/eks/<cluster>/cluster`, with stream prefixes `kube-apiserver-audit-`, `kube-apiserver-`, `authenticator-`, `kube-controller-manager-` and `kube-scheduler-`. Audit logs are the most useful and the most voluminous; set a retention period on the log group.

## Logs Insights queries

Run these in CloudWatch Logs Insights against `/aws/eks/<cluster>/cluster`.

**Who changed or deleted an object:**

```text
fields @timestamp, user.username, verb, objectRef.namespace, objectRef.resource, objectRef.name, responseStatus.code
| filter @logStream like /kube-apiserver-audit/
| filter verb in ["create","update","patch","delete"]
| filter objectRef.name = "aws-auth"
| sort @timestamp desc
| limit 50
```

Change the last filter to `objectRef.resource = "validatingwebhookconfigurations"`, `objectRef.namespace = "prod"` and so on.

**Who is calling the API most (for 429s and slowness):**

```text
fields user.username, userAgent, verb, objectRef.resource
| filter @logStream like /kube-apiserver-audit/
| stats count(*) as calls by user.username, userAgent, verb, objectRef.resource
| sort calls desc
| limit 25
```

**Requests rejected by API priority and fairness (429):**

```text
fields @timestamp, user.username, userAgent, verb, requestURI
| filter @logStream like /kube-apiserver-audit/ and responseStatus.code = 429
| stats count(*) by user.username, userAgent
```

**Authentication failures:**

```text
fields @timestamp, @message
| filter @logStream like /authenticator/ and @message like /denied|error|unauthorized/
| sort @timestamp desc
| limit 50
```

**Forbidden requests (RBAC):**

```text
fields @timestamp, user.username, verb, objectRef.resource, objectRef.namespace
| filter @logStream like /kube-apiserver-audit/ and responseStatus.code = 403
| stats count(*) by user.username, verb, objectRef.resource
```

## API server metrics

The EKS API server exposes Prometheus metrics. Spot checks:

```bash
kubectl get --raw /metrics | grep -E '^apiserver_request_total' | grep -E 'code="(429|5..)"' | sort -t' ' -k2 -nr | head
kubectl get --raw /metrics | grep -E '^apiserver_flowcontrol_rejected_requests_total' | sort -t' ' -k2 -nr | head
kubectl get --raw /metrics | grep -E '^apiserver_admission_webhook_rejection_count' | head
kubectl get --raw /metrics | grep -E '^apiserver_storage_size_bytes'
kubectl get --raw /metrics | grep -E '^apiserver_requested_deprecated_apis'
```

| Metric                                                   | Use                                                                                            |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `apiserver_request_total{code}`                          | Error rates by verb and resource                                                               |
| `apiserver_request_duration_seconds`                     | API latency (p99 by verb and resource)                                                         |
| `apiserver_flowcontrol_rejected_requests_total`          | APF rejections by priority level and flow schema; the source of 429s                           |
| `apiserver_flowcontrol_current_inqueue_requests`         | Queueing per priority level                                                                    |
| `apiserver_admission_webhook_admission_duration_seconds` | Webhook latency; alert as p99 nears the webhook timeout                                        |
| `apiserver_admission_webhook_rejection_count`            | Webhook call errors (`error_type="calling_webhook_error"`)                                     |
| `apiserver_storage_size_bytes`                           | etcd database size; EKS provisions etcd at the 8 GiB upstream maximum, so alert well before it |
| `apiserver_requested_deprecated_apis`                    | Deprecated API calls since the API server started; use before upgrades                         |

Scheduler and controller-manager metrics are exposed through EKS endpoints on supported versions:

```bash
kubectl get --raw "/apis/metrics.eks.amazonaws.com/v1/ksh/container/metrics" | head   # kube-scheduler
kubectl get --raw "/apis/metrics.eks.amazonaws.com/v1/kcm/container/metrics" | head   # kube-controller-manager
```

## Across the wiki

- [[Kubernetes/eks/observability/logging/control-plane-logs|EKS control-plane logs]]
- [[Kubernetes/eks/observability/metrics/prometheus|Prometheus on EKS]]
- [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/15-audit-logging|Audit logging]]
- [[Kubernetes/eks/operator-runbook/reference/first-five-minutes|First five minutes]]
