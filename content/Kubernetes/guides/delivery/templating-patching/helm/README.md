---
title: Helm
tags: [kubernetes, helm, package-manager, deployment]
date: 2026-05-16
description: Comprehensive guide to Helm package management for Kubernetes
---

# Helm

[Helm](https://helm.sh/) is the package manager for Kubernetes, enabling you to define, install, and upgrade complex applications using charts. It is a CNCF graduated project.

## Overview

Helm uses a packaging format called **charts** - a collection of files that describe a related set of Kubernetes resources. Charts can be stored in repositories, OCI registries, or local directories.

### Key Concepts

| Concept        | Description                                               |
| -------------- | --------------------------------------------------------- |
| **Chart**      | A Helm package containing Kubernetes resource templates   |
| **Repository** | A place where charts are collected and shared             |
| **Release**    | An instance of a chart running in a Kubernetes cluster    |
| **Values**     | Configuration options that can be injected into templates |

## Documentation Index

### Getting Started

- [[Kubernetes/guides/delivery/templating-patching/helm/commands|commands]] - Complete Helm CLI commands reference
- [[Kubernetes/guides/delivery/templating-patching/helm/charts|charts]] - Chart structure, templates, values, and dependencies
- [[Kubernetes/guides/delivery/templating-patching/helm/library-charts|library charts]] - Creating shared library charts for code reuse

### Testing & Quality

- [[Kubernetes/guides/delivery/templating-patching/helm/testing|testing]] - Chart testing, linting, and validation

### Production & Operations

- [[Kubernetes/guides/delivery/templating-patching/helm/production|production]] - Multi-cluster, multi-environment deployments
- [[Kubernetes/guides/delivery/templating-patching/helm/oci|oci]] - OCI registries, provenance, and chart signing
- [[Kubernetes/guides/delivery/templating-patching/helm/troubleshooting|troubleshooting]] - Debugging failed releases and rollback strategies

### CI/CD & GitOps

- [[Kubernetes/guides/delivery/templating-patching/helm/gitops|gitops]] - GitOps workflows with ArgoCD and Flux
- [[Kubernetes/guides/delivery/templating-patching/helm/cicd|cicd]] - CI/CD pipeline integration

## Quick Reference

```bash
# Install a chart
helm install <release-name> <chart>

# Upgrade a release
helm upgrade <release-name> <chart>

# Rollback to previous revision
helm rollback <release-name>

# List all releases
helm list

# Get values for a release
helm get values <release-name>

# Template locally (dry-run)
helm template <release-name> <chart>

# Install with values file
helm install -f values.prod.yaml myapp ./mychart

# Upgrade with atomic rollback on failure
helm upgrade --install --atomic myapp ./mychart
```

## Helm 4 vs Helm 3

Helm 4 introduces several breaking changes and new features:

| Feature               | Change                                                              |
| --------------------- | ------------------------------------------------------------------- |
| Post-renderers        | Now implemented as plugins                                          |
| Registry login        | Domain name only, no URL scheme                                     |
| Server-side apply     | Default for new installs                                            |
| CLI flags             | `--atomic` → `--rollback-on-failure`, `--force` → `--force-replace` |
| Plugin system         | WebAssembly-based runtime for enhanced security                     |
| Multi-document values | Split complex values across multiple YAML files                     |

## Chart Repository

Charts are available on:

- [Artifact Hub](https://artifacthub.io/) - Search 800+ charts from multiple repositories
- [CNCF Landscape](https://landscape.cncf.io/card-mode?category=platform&grouping=category) - Enterprise-grade charts

## More in this section

- [[Kubernetes/guides/delivery/templating-patching/helm/helmfile|Helmfile]] — Helmfile declarative deployments for multi-environment Kubernetes

## References

- [Official Helm Documentation](https://helm.sh/docs/)
- [Helm GitHub Repository](https://github.com/helm/helm)
- [Helm Slack (#helm-users)](https://kubernetes.slack.com/messages/C1JANDFDT)
