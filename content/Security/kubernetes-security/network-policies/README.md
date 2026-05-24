---
title: Kubernetes Network Policies
tags: [kubernetes, security, networking, network-policy, zero-trust]
date: 2025-05-24
description: Kubernetes Network Policies - micro-segmentation, egress control, and implementing zero-trust networking in EKS clusters
---

# Kubernetes Network Policies 🌐

Network policies provide micro-segmentation within a Kubernetes cluster, controlling which pods can talk to which.

## Default Behavior

Without network policies, all pods can communicate with all other pods ( AllowAll ). This is a significant risk — a compromised pod can reach every other workload.

## Calico / Cilium

Network policies require a CNI that supports them:
- **Calico** — Most widely used, native K8s NetworkPolicy support
- **Cilium** — eBPF-based, also supports Layer 7 policies

For EKS, use Calico Enterprise or the open-source Calico.

## Example: Allow Only Frontend to Backend

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-allow-frontend
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: backend
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
```

## Example: Lock Down Namespace Egress

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: lock-down-egress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector: {}  # Allow DNS
    ports:
    - protocol: UDP
      port: 53
  - to:
    - namespaceSelector:
        matchLabels:
          name: production
    ports:
    - protocol: TCP
      port: 443
```

## EKS VPC CNI + Calico

VPC CNI doesn't enforce network policies on its own — you need Calico:

```bash
# Install Calico on EKS
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# Or via EKS addons
aws eks create-addon --addon-name calico --cluster-name my-cluster
```

## Related

- [[Security/kubernetes-security/README|K8s Security Hub]]
- [[Kubernetes/eks/networking/vpc-cni/README|VPC CNI]]