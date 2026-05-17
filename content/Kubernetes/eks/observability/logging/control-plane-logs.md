---
title: Control Plane Logging
tags: [eks, observability, logging]
date: 2026-05-17
description: Enable and configure EKS control plane logging
---

# Control Plane Logging

## Overview

EKS provides audit logs for the Kubernetes control plane components.

## Log Types

| Log Type | Description |
|----------|-------------|
| API Server (api) | All Kubernetes API requests |
| Audit (audit) | Audit logs from API server |
| Authenticator (authenticator) | IAM Authenticator for EKS |
| Controller Manager (controllerManager) | Controller manager |
| Scheduler (scheduler) | Scheduler decisions |

## Enable Logging

```bash
# Enable all log types
aws eks update-cluster-config \
  --name my-cluster \
  --region us-west-2 \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}'

# Enable specific types
aws eks update-cluster-config \
  --name my-cluster \
  --region us-west-2 \
  --logging '{"clusterLogging":[{"types":["api","audit"],"enabled":true}]}'
```

## View Logs in CloudWatch

```bash
# List log groups
aws logs describe-log-groups \
  --log-group-name-prefix /aws/eks/my-cluster

# Query logs
aws logs insights-query \
  --log-group-name /aws/eks/my-cluster/cluster/api \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --query-string 'fields @timestamp, @message | filter @message like " pods" | limit 20'
```

## CloudWatch Logs Insights Examples

### Failed authentication attempts
```
fields @timestamp, @message
| filter @message like /authentication.*failed/i
| sort @timestamp desc
| limit 20
```

### API server errors
```
fields @timestamp, @message
| filter responseStatus.code >= 500
| sort @timestamp desc
```

### Pod scheduling decisions
```
fields @timestamp, @message
| filter @message like /pod.*scheduled|scheduler.*filter/i
| sort @timestamp desc
```

## References

- [Control Plane Logging](https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html)
- [EKS Workshop - Cluster Logging](https://www.eksworkshop.com/docs/observability/logging/cluster-logging/)