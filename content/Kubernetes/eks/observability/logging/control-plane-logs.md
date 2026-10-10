---
title: EKS Control Plane Logs
tags: [eks, observability, logging, audit, cloudwatch]
date: 2026-05-17
description: The five EKS control plane log types, what each is useful for, how to enable them, the Logs Insights queries worth saving, and how to keep the cost under control.
---

# EKS Control Plane Logs

The EKS control plane runs in an AWS account you cannot log into. Its logs are the only window into what the API server, scheduler and controllers are doing. They are **off by default**, delivered to [[AWS/monitoring/cloudwatch-logs/README|CloudWatch Logs]] when enabled, and billed at normal CloudWatch rates.

## The five log types

| Type                | Source                        | Answers                                                                     | Volume    |
| :------------------ | :---------------------------- | :-------------------------------------------------------------------------- | :-------- |
| `audit`             | API server audit log          | Who did what, when, from where? Who deleted that Deployment?                | Very high |
| `authenticator`     | IAM authenticator             | Which IAM principal mapped to which Kubernetes user? Why was access denied? | Low       |
| `api`               | kube-apiserver component logs | Is the API server healthy? Are webhooks timing out? Is etcd slow?           | Medium    |
| `controllerManager` | kube-controller-manager       | Why was the load balancer not created? Why is the PV not attaching?         | Medium    |
| `scheduler`         | kube-scheduler                | Why was a pod not scheduled, in more detail than the event gives            | Low       |

If you enable only two, enable `audit` and `authenticator`: they are the security record. Background on the audit format and policy is in [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/15-audit-logging|Kubernetes audit logging]]. On EKS the audit policy is fixed by AWS and cannot be customised.

## Enable

```bash
aws eks update-cluster-config \
  --name my-cluster \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}'
```

Logs land in the log group `/aws/eks/my-cluster/cluster`, with one stream per component instance (`kube-apiserver-audit-<id>`, `authenticator-<id>` and so on).

The log group is created with **never expire** retention. Set it explicitly, and create the group in your infrastructure code _before_ enabling logging so retention and encryption are yours from the first event:

```bash
aws logs put-retention-policy \
  --log-group-name /aws/eks/my-cluster/cluster --retention-in-days 90
```

## Queries worth saving

All of these are [[AWS/monitoring/cloudwatch-insights/README|CloudWatch Logs Insights]] queries against the cluster log group.

**Who deleted something?**

```
fields @timestamp, user.username, objectRef.namespace, objectRef.resource, objectRef.name, sourceIPs.0
| filter @logStream like /kube-apiserver-audit/
| filter verb = "delete" and objectRef.resource in ["deployments","secrets","namespaces"]
| sort @timestamp desc
```

**Which IAM principal is behind a Kubernetes username?**

```
fields @timestamp, @message
| filter @logStream like /authenticator/
| filter @message like /access granted/
| parse @message 'arn=\"*\"' as arn
| stats count() by arn
```

**Access denied — authentication or authorisation?**

```
fields @timestamp, user.username, verb, objectRef.resource, responseStatus.code, responseStatus.reason
| filter @logStream like /kube-apiserver-audit/
| filter responseStatus.code in [401, 403]
| stats count() by user.username, verb, objectRef.resource
```

A 401 means the identity was not recognised — look at the authenticator stream and [[Kubernetes/eks/security/access/cluster-access-management|access entries]]. A 403 means it was recognised and lacks [[Kubernetes/concepts/L07-security/01-api-access/03-rbac|RBAC]] permission.

**Who is hammering the API server?**

```
fields userAgent, verb
| filter @logStream like /kube-apiserver-audit/
| stats count() as calls by userAgent, verb
| sort calls desc
| limit 20
```

A controller in a hot loop shows up here immediately, and is a common cause of API throttling.

**Deprecated API usage before an upgrade**

```
fields @timestamp, objectRef.apiGroup, objectRef.apiVersion, objectRef.resource, userAgent
| filter @logStream like /kube-apiserver-audit/
| filter `annotations.k8s.io/deprecated` = "true"
| stats count() by objectRef.apiGroup, objectRef.apiVersion, objectRef.resource, userAgent
```

Run this well before an [[Kubernetes/eks/cluster-upgrades/upgrade-process|upgrade]]; it names the client still calling a removed API.

**Pod Security violations in audit mode**

```
fields @timestamp, objectRef.namespace, objectRef.name
| filter @logStream like /kube-apiserver-audit/
| filter ispresent(`annotations.pod-security.kubernetes.io/audit-violations`)
```

## Controlling cost

Audit logs dominate the bill. A busy cluster produces tens of gigabytes a day, and CloudWatch charges for ingestion, storage and each Insights scan.

- **Set retention.** Keep 30–90 days in CloudWatch for querying.
- **Archive, do not hoard.** Use a subscription filter with [[AWS/analytics/kinesis/data-firehose|Data Firehose]] to send audit logs to [[AWS/storage/s3/README|S3]] for long-term retention and query them with [[AWS/analytics/athena/README|Athena]] when needed.
- **Fix noisy clients.** The "who is hammering the API" query usually finds one misbehaving controller responsible for a large share of the volume.
- **Use the Infrequent Access log class** for clusters where you rarely query — lower ingestion price, reduced feature set.
- **Narrow Insights queries** with a `@logStream` filter and a tight time range; you pay per GB scanned.

## Alerting

Create metric filters on the log group and alarm on them ([[AWS/monitoring/cloudwatch-alarms/README|CloudWatch alarms]]):

- `responseStatus.code = 403` spikes for a single user — probing or a broken deployment role,
- any `exec` into `kube-system` pods,
- creation of ClusterRoleBindings to `cluster-admin`,
- anonymous requests that succeed.

[[Kubernetes/eks/security/guardduty|GuardDuty EKS Protection]] analyses the audit stream independently and does not need this logging enabled, but having the raw logs is what makes an investigation possible.

## Related

- [[Kubernetes/eks/observability/README|EKS observability overview]]
- [[Kubernetes/eks/observability/logging/pod-logging|Pod logging]] — application and node logs
- [[Observability/fundamentals|Observability fundamentals]]
- [[Security/siem/README|SIEM]] — forwarding audit logs for correlation
- [EKS control plane logging](https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html)

## Across the wiki

- [[Linux/security/auditd|auditd]] — audit trails (Linux)
- [[AWS/security/cloudtrail/README|AWS CloudTrail]] — audit trails (AWS)
- [[Security/siem/wazuh/README|Wazuh]] — audit trails (Security)
- [[Security/incident-response/forensics/README|Forensics]] — audit trails (Security)
