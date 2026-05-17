---
title: CloudWatch Container Insights
tags: [eks, observability, metrics, cloudwatch]
date: 2026-05-17
description: Monitor EKS with CloudWatch Container Insights
---

# CloudWatch Container Insights

## Overview

Container Insights provides metrics, logs, and performance visibility for EKS workloads.

## Install CloudWatch Agent

```bash
helm repo add aws-cloudwatch-metrics https://aws.github.io/eks-charts
helm repo update

helm install aws-cloudwatch-metrics aws-cloudwatch-metrics/aws-cloudwatch-metrics \
  --namespace amazon-cloudwatch \
  --create-namespace \
  --set clusterName=my-cluster
```

## View Metrics in Console

Navigate to CloudWatch > Metrics > Container Insights to view:
- CPU utilization
- Memory usage
- Network throughput
- Disk I/O
- Pod count by namespace

## Container Insights Metrics

| Metric | Description |
|--------|-------------|
| pod_cpu_utilization | CPU usage % |
| pod_memory_working_set | Memory usage |
| pod_network_rx_bytes | Network received |
| pod_network_tx_bytes | Network transmitted |
| container_restart_count | Container restarts |

## CloudWatch Dashboard

```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["ContainerInsights", "pod_cpu_utilization", "ClusterName", "my-cluster"]
        ],
        "period": 60,
        "stat": "Average",
        "region": "us-west-2",
        "title": "CPU Utilization"
      }
    }
  ]
}
```

## Log Insights Queries

### Top CPU consumers
```
fields @timestamp, PodName, cpuUtilization as CPU
| sort CPU desc
| limit 10
```

### Memory pressure
```
fields @timestamp, PodName, memoryUtilization as Memory
| filter Memory > 80
| sort Memory desc
```

## References

- [Container Insights](https://docs.aws.amazon.com/eks/latest/userguide/container-insights.html)
- [EKS Workshop - Container Insights](https://www.eksworkshop.com/docs/observability/container-insights/)