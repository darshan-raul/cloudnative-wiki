---
title: Amazon VPC Lattice
tags: [eks, networking, vpc-lattice]
date: 2026-05-17
description: Service mesh and service networking for EKS with VPC Lattice
---

# Amazon VPC Lattice

## Overview

VPC Lattice provides a service mesh solution for EKS with automatic load balancing, health checking, and traffic management.

## Key Features

- Automatic service discovery
- Layer 7 load balancing
- Health checking
- Traffic management
- mTLS encryption
- Access controls

## Service Mesh Comparison

| Feature | VPC Lattice | Istio/Linkerd |
|---------|-------------|---------------|
| Management | Fully managed | Self-managed |
| mTLS | Automatic | Manual/config |
| Cost | Pay per use | Infrastructure |
| Complexity | Low | High |

## Create a Service

```yaml
apiVersion: vpc-lattice.sks.aws/v1
kind: Service
metadata:
  name: my-service
spec:
  port: 8080
  backend:
    name: my-app
    port: 80
```

## Register Targets

```yaml
apiVersion: vpc-lattice.sks.aws/v1
kind: TargetGroup
metadata:
  name: my-app-tg
spec:
  type: IP
  port: 80
  target:
    - ip: 10.0.0.1
      port: 80
    - ip: 10.0.0.2
      port: 80
```

## Access Policy

```yaml
apiVersion: vpc-lattice.aws/v1
kind: AccessPolicy
metadata:
  name: allow-consumer
spec:
  source:
    serviceAccounts:
      - name: consumer
        namespace: default
  action:
    - vpc-lattice:Invoke
```

## When to Use VPC Lattice

- Microservices requiring service-to-service communication
- Need for automatic mTLS
- Multi-VPC service access
- Reduce operational burden of service mesh

## References

- [VPC Lattice](https://docs.aws.amazon.com/eks/latest/userguide/vpc-lattice.html)
- [EKS Workshop - VPC Lattice](https://www.eksworkshop.com/docs/networking/vpc-lattice/)
- [[AWS/concepts/vpc-lattice|VPC Lattice Concepts]]