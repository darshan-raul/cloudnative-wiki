---
title: Network Policies with VPC CNI
tags: [eks, networking, vpc-cni, network-policy]
date: 2026-05-17
description: Kubernetes network policies with Amazon VPC CNI
---

# Network Policies with VPC CNI

## Overview

Kubernetes Network Policies control traffic between pods. The VPC CNI supports Calico network policies.

## Install Calico

```bash
helm repo add projectcalico https://docs.tigera.io/calico/charts
helm install calico projectcalico/tigera-operator \
  --namespace kube-system
```

## Basic Network Policy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow-web
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: web
    ports:
    - protocol: TCP
      port: 8080
```

## Default Deny All

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

## Allow DNS Egress

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

## References

- [Network Policies](https://docs.aws.amazon.com/eks/latest/userguide/network-requirements.html)
- [EKS Workshop - Network Policies](https://www.eksworkshop.com/docs/networking/vpc-cni/network-policies/)