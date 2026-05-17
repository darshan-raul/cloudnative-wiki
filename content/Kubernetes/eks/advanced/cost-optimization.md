---
title: EKS Cost Optimization
tags: [eks, advanced, cost, optimization]
date: 2026-05-17
description: Cost optimization strategies for EKS
---

# EKS Cost Optimization

## Optimization Strategies

### 1. Right-size Resources

```yaml
# Check actual vs requested resources
kubectl top pods -A --containers=true | head -20

# Right-size container requests
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

### 2. Use Spot Instances

```yaml
# Node group with mixed instances
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: my-cluster
managedNodeGroups:
  - name: spot
    instanceTypes: [t3.medium, t3a.medium, m5.large]
    spot: {}
    labels:
      lifecycle: Ec2Spot
    taints:
      - key: "spot"
        value: "true"
        effect: "NoSchedule"
```

### 3. Graviton for Compute

```bash
# Migrate to Graviton
eksctl create nodegroup \
  --cluster my-cluster \
  --name graviton \
  --node-type m6g.xlarge \
  --nodes 3 \
  --managed
```

### 4. Use Karpenter for Right-sizing

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: [spot]
        - key: karpenter.sh/provisioner-name
          operator: In
          values: [default]
      limits:
        cpu: 100
        memory: 100Gi
      consolidation:
        enabled: true
```

### 5. Storage Optimization

| Strategy | Savings |
|----------|---------|
| Use gp3 instead of gp2 | ~20% cheaper |
| Delete unused PVCs | $50-200/month |
| Use S3 for object storage | vs EBS for large data |

### 6. Cluster Autoscaler

```yaml
# Ensure proper resource requests
# HPA with scale-down enabled
behavior:
  scaleDown:
    stabilizationWindowSeconds: 300
    policies:
    - type: Percent
      value: 10
      periodSeconds: 60
```

### 7. Reserved Capacity / Savings Plans

| Option | Savings | Flexibility |
|--------|---------|------------|
| On-Demand | Baseline | Highest |
| 1yr Reserved | ~30% | Medium |
| 3yr Reserved | ~60% | Low |
| Savings Plans | ~30-60% | High |

### 8. kubecost Monitoring

```bash
helm install kubecost kubecost/cost-analyzer \
  --namespace kubecost \
  --create-namespace
```

### Cost Allocation Tags

```bash
# Enable cost allocation in AWS
aws ce enable-split-cost-allocation-resources
```

## Quick Wins Checklist

- [ ] Set resource requests/limits on all pods
- [ ] Use Spot for non-critical workloads
- [ ] Use Graviton for Linux workloads
- [ ] Enable Karpenter or Cluster Autoscaler
- [ ] Delete unused namespaces/deployments
- [ ] Use gp3 storage instead of gp2
- [ ] Review Kubecost recommendations weekly

## References

- [EKS Cost Optimization](https://docs.aws.amazon.com/eks/latest/userguide/cost-optimization.html)
- [Kubecost](https://www.kubecost.com/)
- [EKS Workshop - Cost](https://www.eksworkshop.com/docs/observability/kubecost/)