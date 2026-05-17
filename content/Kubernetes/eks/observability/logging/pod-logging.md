---
title: Pod Logging
tags: [eks, observability, logging]
date: 2026-05-17
description: Aggregate and analyze application logs from EKS pods
---

# Pod Logging

## Overview

Aggregate application logs from EKS pods using Fluent Bit or Fluentd.

## Install Fluent Bit

```bash
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update

helm install fluent-bit fluent/fluent-bit \
  --namespace kube-system \
  --set aws.region=us-west-2 \
  --set cloudWatchLogs.enabled=true
```

## Configure Fluent Bit

```ini
# values.yaml
daemonSetCreation: true
cloudWatchLogs:
  enabled: true
  region: us-west-2
  logGroupName: /aws/eks/my-cluster/pod-logs
  logStreamPrefix: pod-logs
  autoCreateGroup: true
```

## Use in Application

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: my-app
    # Write to stdout/stderr (Fluent Bit captures automatically)
```

## Structured Logging

```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "level": "info",
  "message": "Request processed",
  "request_id": "abc123",
  "duration_ms": 45
}
```

## CloudWatch Logs Query

```bash
# Query pod logs
aws logs insights-query \
  --log-group-name /aws/eks/my-cluster/pod-logs \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --query-string 'fields @timestamp, @message | filter @message like "ERROR" | limit 20'
```

## Log Aggregation Comparison

| Solution | Storage | Query | Cost |
|----------|---------|-------|------|
| Fluent Bit + CloudWatch | CloudWatch Logs | CloudWatch Insights | Pay per ingestion |
| Fluent Bit + OpenSearch | OpenSearch | OpenSearch DSL | EC2 + storage |
| Loki | Object storage | LogQL | Storage + EC2 |

## References

- [Logging Workshop](https://www.eksworkshop.com/docs/observability/logging/pod-logging/)
- [Fluent Bit Documentation](https://docs.fluentbit.io/)