---
title: Helmfile
tags: [kubernetes, helm, helmfile, deployment]
date: 2026-05-16
description: Helmfile declarative deployments for multi-environment Kubernetes
---

# Helmfile

[Helmfile](https://github.com/helmfile/helmfile) is a declarative specification for deploying Helm charts across multiple environments with flexible configuration management.

## Overview

Helmfile allows you to:

- Define releases, environments, and values in a single `helmfile.yaml`
- Manage multiple environments (dev, staging, prod)
- Share common configuration across releases
- Use Go templating for dynamic values
- Integrate with GitOps workflows

## Installation

```bash
# Binary installation
brew install helmfile

# Helm plugin
helm plugin install https://github.com/helmfile/helmfile

# From source
go install github.com/helmfile/helmfile@latest
```

## Basic Structure

```yaml
# helmfile.yaml
repositories:
  - name: bitnami
    url: https://charts.bitnami.com
  - name: prometheus-community
    url: https://prometheus-community.github.io/helm-charts

environments:
  dev:
    values:
      - environments/dev.yaml
  staging:
    values:
      - environments/staging.yaml
  prod:
    values:
      - environments/prod.yaml

releases:
  - name: myapp
    chart: ./charts/myapp
    namespace: {{ .Environment.Name }}
    values:
      - values/{{ .Environment.Name }}.yaml
    secrets:
      - secrets/{{ .Environment.Name }}.yaml.gpg
    installed: {{ .Environment.Name != "dev" || .Values.installMyapp }}
```

## Environment Configuration

### Basic Environment

```yaml
# helmfile.yaml
environments:
  dev:
    values:
      - path: environments/dev/values.yaml
        # Can include multiple files
      - path: environments/dev/secrets.yaml.enc
        encrypted: true
  staging:
    values:
      - environments/staging/values.yaml
  prod:
    values:
      - environments/prod/values.yaml
```

### Environment with Overrides

```yaml
environments:
  prod:
    values:
      - replicas: 5
      - image.tag: v1.2.3
      - environment: production
    secrets:
      - path: environments/prod/secrets.yaml
        Encrypted: true
```

## Releases Configuration

### Basic Release

```yaml
releases:
  - name: myapp
    chart: ./charts/myapp
    namespace: myapp
    values:
      - values/common.yaml
      - values/{{ .Environment.Name }}.yaml
    set:
      - name: image.tag
        value: latest
```

### Release with Version

```yaml
releases:
  - name: redis
    chart: bitnami/redis
    version: 18.x.x
    namespace: cache
    values:
      - values/redis.yaml
    installed: {{ .Environment.Name != "dev" }}
```

### Conditional Release

```yaml
releases:
  - name: monitoring
    chart: prometheus-community/prometheus
    installed: {{ .Values.enableMonitoring }}
    namespace: monitoring
    values:
      - values/monitoring.yaml
```

## Values Management

### Layered Values

```yaml
releases:
  - name: myapp
    chart: ./charts/myapp
    values:
      # Base values (always applied)
      - values/base.yaml
      # Environment-specific (takes precedence)
      - values/{{ .Environment.Name }}.yaml
      # Environment-local overrides
      - path: values/{{ .Environment.Name }}/local.yaml
        optional: true
```

### Go Templating in Values

```yaml
releases:
  - name: myapp
    chart: ./charts/myapp
    values:
      - image:
          repository: {{ requiredEnv "IMAGE_REPO" }}
          tag: {{ .Environment.Name | toYaml | quote }}
        replicaCount: {{ .Values.defaultReplicas | default 2 }}
```

### Environment-Specific Secrets

```yaml
releases:
  - name: myapp
    chart: ./charts/myapp
    secrets:
      - path: secrets/{{ .Environment.Name }}/db-creds.yaml
        Encrypted: true  # helm-secrets required
```

## Multiple Environments

### Directory Structure

```
├── helmfile.yaml
├── environments/
│   ├── base.yaml           # Shared values
│   ├── dev/
│   │   └── values.yaml
│   ├── staging/
│   │   └── values.yaml
│   └── prod/
│       └── values.yaml
├── charts/
│   └── myapp/
│       └── ...
└── secrets/
    ├── dev/
    │   └── secrets.yaml.enc
    ├── staging/
    │   └── secrets.yaml.enc
    └── prod/
        └── secrets.yaml.enc
```

### Environment Inheritance

```yaml
# helmfile.yaml
environments:
  dev:
    values:
      - base.yaml
      - environments/dev.yaml
  staging:
    values:
      - base.yaml
      - environments/staging.yaml
  prod:
    values:
      - base.yaml
      - environments/prod.yaml
```

## Multi-Cluster Deployments

### Cluster Contexts

```yaml
# helmfile.yaml
environments:
  dev-us:
    context: dev-us-cluster
    values:
      - clusters/dev-us.yaml
  prod-us:
    context: prod-us-cluster
    values:
      - clusters/prod-us.yaml
  prod-eu:
    context: prod-eu-cluster
    values:
      - clusters/prod-eu.yaml

releases:
  - name: myapp
    chart: ./charts/myapp
    namespaces:
      - myapp
    values:
      - environments/shared.yaml
    installed: true
    # Deploy to specific clusters
    environments:
      - dev-us
      - prod-us
      - prod-eu
```

### Kustomize Integration

```yaml
releases:
  - name: myapp
    chart: ./charts/myapp
    postRenderers:
      - kind: kustomize
        path: ./overlays/{{ .Environment.Name }}
```

## Helmfile Commands

### Apply to Environment

```bash
# Apply to default environment
helmfile apply

# Apply to specific environment
helmfile -e prod apply

# Apply with diff
helmfile -e prod diff

# Apply with cleanup (remove resources)
helmfile -e prod destroy
```

### Sync and Update

```bash
# Sync all releases
helmfile sync

# Sync specific release
helmfile -e prod sync myapp

# Update dependencies
helmfile deps

# List releases
helmfile list
```

### Template and Debug

```bash
# Render templates
helmfile template

# Debug output
helmfile -e prod diff --debug

# Lint
helmfile lint
```

## Advanced Configuration

### Labels and Selectors

```yaml
releases:
  - name: frontend
    labels:
      component: web
      tier: frontend
    chart: ./charts/frontend
  - name: backend
    labels:
      component: api
      tier: backend
    chart: ./charts/backend

# Use label selectors
helmfile -l tier=frontend sync
```

### Templates (Helmfile Templates)

```yaml
# _helpers.tpl (in same directory as helmfile.yaml)
{{- define "myapp.common" -}}
replicas: {{ .Values.myapp.replicas | default 2 }}
image:
  repository: myapp
  tag: {{ .Values.imageTag | default "latest" }}
{{- end -}}

# In helmfile.yaml
releases:
  - name: myapp
    chart: ./charts/myapp
    values:
      - inline: |
          {{ template "myapp.common" . }}
```

### Environment Variables

```bash
# Set environment variable
export ENVIRONMENT=prod
helmfile apply

# Or inline
ENVIRONMENT=prod helmfile apply
```

## Integration with ArgoCD

```yaml
# ArgoCD Application for Helmfile
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp-helmfile
spec:
  source:
    repoURL: https://github.com/org/repo.git
    path: .
    targetRevision: main
    plugin:
      name: helmfile
      parameters:
        - name: environment
          value: prod
```

## Best Practices

### 1. Use Version Control

```bash
# All helmfile configs in Git
git add helmfile.yaml environments/
git commit -m "Update helmfile for prod"
git push
```

### 2. Separate Secrets

```yaml
# helmfile.yaml
releases:
  - name: myapp
    secrets:
      - path: secrets/{{ .Environment.Name }}/secrets.yaml.enc
        Encrypted: true
```

### 3. Use Environment Inheritance

```yaml
# environments/base.yaml
common:
  imagePullPolicy: IfNotPresent
  resources:
    limits:
      cpu: 500m
      memory: 512Mi

# environments/prod.yaml
{{- load "environments/base.yaml" | toYaml | nindent 0 }}
replicas: 5
```

### 4. Test Before Production

```bash
# Dry-run in dev first
helmfile -e dev diff

# Apply to dev
helmfile -e dev apply

# Verify in dev
helmfile -e dev list

# Then promote to prod
helmfile -e prod diff
helmfile -e prod apply
```

## Common Patterns

### Atomic Deployments

```yaml
releases:
  - name: myapp
    chart: ./charts/myapp
    atomic: true  # Rollback on failure
    timeout: 5m
    wait: true
    cleanupOnFail: true
```

### Pre/Post Hooks

```yaml
releases:
  - name: myapp
    chart: ./charts/myapp
    hooks:
      - events: ["prepare", "pre-upgrade"]
        command: /bin/sh
        args: ["-c", "echo preparing release"]
```

### GitOps Automation

```bash
# In CI/CD
helmfile -e prod apply --interactive=false

# Or with auto-approve
helmfile -e prod apply --auto-approve
```

## Troubleshooting

### Debug Template Rendering

```bash
# Template locally
helmfile template

# Show diff
helmfile diff

# Verbose output
helmfile -e prod apply --debug
```

### Common Issues

| Issue | Solution |
|-------|----------|
| `helmfile: command not found` | Install helmfile binary |
| `multiple repositories with same name` | Check for duplicate entries |
| `environment not found` | Check `environments` section |
| `release not found` | Verify release name in `releases` |

### Reset Environment

```bash
# Clean up releases
helmfile -e prod destroy

# Remove lock file
rm helmfile.lock

# Re-apply
helmfile -e prod apply
```

## References

- [Helmfile Documentation](https://helmfile.readthedocs.io/)
- [Helmfile GitHub](https://github.com/helmfile/helmfile)
- [helm-secrets](https://github.com/jkroepke/helm-secrets)