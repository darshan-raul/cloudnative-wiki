---
title: Cluster Autoscaler
tags: [eks, compute, mng, autoscaling]
date: 2026-05-17
description: Configure Cluster Autoscaler with EKS Managed Node Groups
---

# Cluster Autoscaler with MNG

## Overview

Cluster Autoscaler adjusts the size of your node group based on pending pods and resource requests.

## Installation

```bash
# Add Helm repo
helm repo add cluster-autoscaler https://kubernetes.github.io/autoscaler
helm repo update

# Install Cluster Autoscaler
helm install cluster-autoscaler cluster-autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set awsRegion=us-west-2 \
  --set autoDiscovery.clusterName=my-cluster \
  --set expanders="least-waste,priority,skew"
```

## Configuration for MNG

IAM policy for Cluster Autoscaler:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup"
      ],
      "Resource": "*"
    }
  ]
}
```

## Node Group Annotation

```yaml
apiVersion: v1
kind: Node
metadata:
  annotations:
    eks.amazonaws.com/nodegroup: standard-workers
    cluster-autoscaler.kubernetes.io/safe-to-evict: "false"
```

## Scale Down Behavior

```bash
# Configure scale-down delay in deployment
--set expandParams.scale-down-delay-after-add=10m
--set expandParams.scale-down-unneeded-time=10m
--set expandParams.scale-down-utilization-threshold=0.5
```

## References

- [Cluster Autoscaler on AWS](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md)
- [EKS Workshop - Cluster Autoscaler](https://www.eksworkshop.com/docs/fundamentals/compute/managed-node-groups/cluster-autoscaler/)