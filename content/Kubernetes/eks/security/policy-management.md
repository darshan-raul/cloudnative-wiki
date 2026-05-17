---
title: Policy Management with Kyverno
tags: [eks, security, policy, kyverno]
date: 2026-05-17
description: Policy-based governance with Kyverno on EKS
---

# Policy Management with Kyverno

## Overview

Kyverno is a Kubernetes-native policy engine that validates, mutates, and generates resources based on policies.

## Install Kyverno

```bash
helm repo add kyverno https://kyverno.github.io/kyverno
helm repo update

helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --set replicaCount=2
```

## Cluster Policy Examples

### Require labels on pods

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-label
    match:
      resources:
        kinds:
        - Pod
    validate:
      message: "Label 'app' is required"
      pattern:
        metadata:
          labels:
            app: "?*"
```

### Restrict image registries

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: restrict-registries
spec:
  validationFailureAction: Enforce
  rules:
  - name: require-allowed-registry
    match:
      resources:
        kinds:
        - Pod
    validate:
      message: "Only approved registries allowed"
      pattern:
        spec:
          containers:
          - image: "!*registry.example.com*"
```

### Mutate pods for security

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-security-context
spec:
  mutation:
    rules:
    - name: add-runasnonroot
      match:
        resources:
          kinds:
          - Pod
      mutate:
        patchStrategicMerge:
          spec:
            securityContext:
              runAsNonRoot: true
              runAsUser: 10000
```

## Policy Reports

```bash
# View policy reports
kubectl get polr -A

# View violation details
kubectl describe polr -n default
```

## References

- [Kyverno Documentation](https://kyverno.io/)
- [EKS Workshop - Kyverno](https://www.eksworkshop.com/docs/security/kyverno/)