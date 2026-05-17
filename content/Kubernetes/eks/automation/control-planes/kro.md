---
title: KRO - Kube Resource Orchestrator
tags: [eks, automation, kro]
date: 2026-05-17
description: Simplify custom resource creation with KRO
---

# KRO (Kube Resource Orchestrator)

## Overview

KRO extends native Kubernetes to create simplified custom building blocks from complex resource compositions.

## Install KRO

```bash
# Add Helm repo
helm repo add kro https://aws.github.io/eks-charts
helm repo update

# Install KRO
helm install kro aws-eks/kro \
  --namespace kro \
  --create-namespace
```

## Create ResourceDefinition

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: webservers.kro.aws.amazon.com
spec:
  group: kro.aws.amazon.com
  names:
    kind: WebServer
    plural: webservers
  scope: Namespaced
  versions:
  - name: v1alpha1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              replicas:
                type: integer
                default: 2
              image:
                type: string
              port:
                type: integer
                default: 80
```

## Create WebServer Resource

```yaml
apiVersion: kro.aws.amazon.com/v1alpha1
kind: WebServer
metadata:
  name: my-webserver
spec:
  replicas: 3
  image: nginx:latest
  port: 8080
```

## References

- [KRO Documentation](https://github.com/aws/kube-resource-orchestrator)
- [EKS Capabilities](https://docs.aws.amazon.com/eks/latest/userguide/capabilities.html)