---
title: Advanced Networking
tags: [eks, advanced, networking]
date: 2026-05-17
description: Advanced networking scenarios for EKS
---

# Advanced Networking on EKS

## Multi-cluster Networking

### VPC Peering

```bash
# Create VPC peering connection
aws ec2 create-vpc-peering-connection \
  --vpc-id vpc-12345678 \
  --peer-vpc-id vpc-87654321

# Accept peering connection
aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id pcx-12345678

# Update route tables
aws ec2 describe-route-tables
```

### CoreDNS Configuration for Cross-cluster DNS

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           upstream
           fallthrough in-addr.arpa ip6.arpa
        }
        forward . 10.0.0.2  # On-premises DNS
        prometheus :9153
        cache 30
        loop
        reload
        loadbalance
    }
    cluster2.local:53 {
        forward . 10.1.0.2  # Cluster 2's CoreDNS
    }
```

## Global Accelerator for Multi-region

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
    service.beta.kubernetes.io/aws-load-balancer-globally-accessible: "true"
```

## Network Policies with Calico

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-to-backend
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: frontend
    ports:
    - protocol: TCP
      port: 8080
```

## External Traffic Policies

### Local External Traffic Policy

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
spec:
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 8080
  externalTrafficPolicy: Local
  healthCheckNodePort: 30778
```

## Load Balancer Attributes

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-attributes: |
      idle_timeout_timeout_seconds=3600
      cross_zone_load_balancing_enabled=true
    service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags: |
      Environment=production,Team=platform
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 8080
```

## NLB with TLS

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-tls
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
    service.beta.kubernetes.io/aws-load-balancer-ssl-cert: arn:aws:acm:us-west-2:123456789:certificate/xxxxx
    service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
  - port: 443
    targetPort: 8080
```

## References

- [EKS Networking](https://docs.aws.amazon.com/eks/latest/userguide/eks-networking.html)
- [VPC CNI Documentation](https://docs.aws.amazon.com/eks/latest/userguide/pod-networking.html)