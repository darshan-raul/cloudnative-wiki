---
title: Kubecost for EKS
tags: [eks, observability, cost, kubecost]
date: 2026-05-17
description: Monitor and optimize EKS costs with Kubecost
---

# Kubecost

## Overview

Kubecost provides real-time cost visibility and optimization recommendations for EKS clusters.

## Install Kubecost

```bash
helm repo add kubecost https://kubecost.github.io/cost-analyzer
helm repo update

helm install kubecost kubecost/cost-analyzer \
  --namespace kubecost \
  --create-namespace \
  --set kubecostToken="my-email@example.com" \
  --set prometheus.nodeExporter.enabled=true
```

## Access Dashboard

```bash
# Port-forward to access UI
kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9090

# Or use LoadBalancer
kubectl edit svc kubecost-cost-analyzer -n kubecost
# Change type to LoadBalancer
```

## Key Features

### Namespace Cost Breakdown
View costs by namespace, deployment, or service.

### Allocation View
```
Namespace    | CPU Cost | Memory Cost | Storage Cost | Total
-------------|----------|-------------|--------------|-------
frontend     | $120.50  | $45.30      | $10.00       | $175.80
backend      | $200.00  | $80.50      | $5.00        | $285.50
kube-system  | $30.00   | $15.00      | $0           | $45.00
```

### Cost Alerts

```yaml
apiVersion: kubecost.com/v1
kind: CostAlert
metadata:
  name: high-cost-alert
spec:
  threshold: 1000
  window: 1d
  conditions:
    namespace: production
  ownerContact:
    - email@example.com
```

### Savings Recommendations

| Type | Savings | Action |
|------|---------|--------|
| Idle resources | $150/mo | Right-size underutilized pods |
| Unused volumes | $50/mo | Delete orphaned PVCs |
| Spot instances | $300/mo | Migrate to Spot |
| Namespace cleanup | $75/mo | Remove unused namespaces |

## Cost Optimization Tips

1. **HPA with custom metrics** - Scale based on actual utilization
2. **Spot for non-critical workloads** - 60-90% savings
3. **Graviton for compute** - 20% better price-performance
4. **Empty pod cleanup** - Remove completed/failed pods
5. **Storage lifecycle** - Clean up unused PVCs

## References

- [Kubecost](https://www.kubecost.com/)
- [EKS Workshop - Kubecost](https://www.eksworkshop.com/docs/observability/kubecost/)