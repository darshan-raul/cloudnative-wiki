---
title: Spot Instances with MNG
tags: [eks, compute, mng, spot]
date: 2026-05-17
description: Using EC2 Spot Instances for cost optimization on EKS
---

# Spot Instances with MNG

## Overview

Spot Instances offer up to 90% discount vs On-Demand but can be interrupted with 2-minute warning.

## Create Spot Node Group

```yaml
# spot-nodegroup.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: my-cluster
  region: us-west-2
managedNodeGroups:
  - name: spot-workers
    instanceType: t3.medium
    desiredCapacity: 3
    minSize: 1
    maxSize: 10
    spot:
      instanceTypes:
        - t3.medium
        - t3a.medium
        - m5.large
      interruptionHandler: true
    labels:
      lifecycle: Ec2Spot
    taints:
      - key: "spotInstance"
        value: "true"
        effect: "NoSchedule"
```

```bash
eksctl create nodegroup -f spot-nodegroup.yaml
```

## Pod Configuration for Spot

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  nodeSelector:
    lifecycle: Ec2Spot
  tolerations:
  - key: "spotInstance"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
  containers:
  - name: app
    image: myapp:latest
```

## Interruption Handling

Enable the Node Termination Handler for graceful spot interruptions:

```bash
helm install aws-node-termination-handler aws-node-termination-handler/aws-node-termination-handler \
  --namespace kube-system \
  --set awsRegion=us-west-2
```

## Spot Best Practices

- Use multiple instance types for better availability
- Set `drainingTimeout` for graceful termination
- Run stateless workloads on Spot
- Use Pod Disruption Budgets

## References

- [EKS Workshop - Spot Instances](https://www.eksworkshop.com/docs/fundamentals/compute/managed-node-groups/spot/)
- [EC2 Spot Instances](https://docs.aws.amazon.com/ec2/latest/UserGuide/using-spotInstances.html)