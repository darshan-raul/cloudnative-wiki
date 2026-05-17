---
title: Flux
tags: [eks, automation, gitops, flux]
date: 2026-05-17
description: GitOps with Flux for EKS
---

# Flux

## Overview

Flux is a GitOps operator that synchronizes Kubernetes manifests from Git to EKS clusters.

## Install Flux

```bash
# Install Flux CLI
brew install fluxcd/tap/flux

# Bootstrap Flux on cluster
flux bootstrap github \
  --owner=my-username \
  --repository=my-fleet-infra \
  --path=./clusters/my-cluster \
  --personal
```

## Create Source

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: app-repo
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/my-username/app-manifests
  ref:
    branch: main
```

## Create Kustomization

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: app
  namespace: flux-system
spec:
  interval: 5m
  path: ./app
  prune: true
  sourceRef:
    kind: GitRepository
    name: app-repo
  targetNamespace: default
```

## Directory Structure

```
app-manifests/
├── apps/
│   ├── production/
│   │   ├── kustomization.yaml
│   │   └── deployment.yaml
│   └── staging/
│       ├── kustomization.yaml
│       └── deployment.yaml
└── flux-system/
    ├── gotk-components.yaml
    └── gotk-sync.yaml
```

## Helm Integration

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: bitnami
  namespace: flux-system
spec:
  url: https://charts.bitnami.com/bitnami
  interval: 30m
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: nginx
  namespace: default
spec:
  interval: 5m
  chart:
    spec:
      chart: nginx
      version: "15.x"
      sourceRef:
        kind: HelmRepository
        name: bitnami
  values:
    service:
      type: LoadBalancer
```

## Multi-cluster Setup

```bash
# Add cluster to Flux
flux bootstrap github \
  --owner=my-org \
  --repository=fleet-infra \
  --path=./clusters/production \
  --personal

# Deploy to different cluster
flux create kustomization production \
  --path=./apps/production \
  --target-namespace=default \
  --source=app-repo \
  --prune=true \
  --interval=5m
```

## Image Automation

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImagePolicy
metadata:
  name: nginx
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: nginx
  policy:
    semver:
      range: "15.x"
```

## References

- [Flux Documentation](https://fluxcd.io/)
- [EKS Workshop - Flux](https://www.eksworkshop.com/docs/automation/gitops/flux/)