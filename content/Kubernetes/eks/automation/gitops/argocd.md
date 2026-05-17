---
title: Argo CD
tags: [eks, automation, gitops, argocd]
date: 2026-05-17
description: GitOps continuous delivery with Argo CD on EKS
---

# Argo CD

## Overview

Argo CD is a declarative, GitOps-based continuous delivery tool for Kubernetes.

## Install Argo CD

```bash
# Add Helm repo
helm repo add argo https://argoproj.github.io/arg-helm-charts
helm repo update

# Install Argo CD
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set server.service.type=LoadBalancer
```

## Access Argo CD UI

```bash
# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port-forward to UI
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

## Create Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/my-org/app-manifests
    targetRevision: main
    path: ./app
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## ApplicationSet (Multi-cluster)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: my-app-multicluster
  namespace: argocd
spec:
  generators:
  - clusters:
      values:
        destinationServer: https://kubernetes.default.svc
  template:
    metadata:
      name: '{{name}}-my-app'
    spec:
      project: default
      source:
        repoURL: https://github.com/my-org/app-manifests
        targetRevision: main
        path: './apps/{{name}}'
      destination:
        server: '{{values.destinationServer}}'
        namespace: default
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

## Sync and Health

```bash
# Sync application
argocd app sync my-app

# View application status
argocd app get my-app

# Sync multiple apps
argocd app sync --all
```

## Resource Hooks

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
spec:
  syncPolicy:
    syncOptions:
      - PruneLast=true
  hooks:
    sync/PreSync:
      - name: database-migration
        selector:
          kind: Job
        template:
          name: database-migration
```

## Kustomize Integration

```yaml
# kustomization.yaml in Git
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- service.yaml
- ingress.yaml
commonLabels:
  app: my-app
```

```bash
# Argo CD automatically detects kustomization.yaml
argocd app create my-app \
  --repo https://github.com/my-org/app-manifests \
  --path ./app \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default
```

## References

- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [EKS Workshop - Argo CD](https://www.eksworkshop.com/docs/automation/gitops/argocd/)