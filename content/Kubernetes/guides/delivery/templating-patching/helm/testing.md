---
title: Helm Chart Testing
tags: [kubernetes, helm, testing, linting, ci-cd]
date: 2026-05-16
description: Testing and validating Helm charts
---

# Helm Chart Testing

Comprehensive testing ensures Helm charts work correctly before deployment.

## Testing Overview

| Type | Purpose | When |
|------|---------|------|
| Lint | Validate chart structure and syntax | Every commit |
| Template render | Verify templates produce valid YAML | Every commit |
| Schema validation | Enforce values structure | Every commit |
| Unit tests | Test template logic and helpers | Every commit |
| Integration tests | Test actual deployment | PR/merge |
| Smoke tests | Verify basic functionality | Post-deploy |

## Helm Lint

The `helm lint` command validates chart structure and best practices.

```bash
# Basic lint
helm lint ./mychart

# Strict lint (includes schema validation)
helm lint --strict ./mychart

# Lint with values
helm lint -f values.prod.yaml ./mychart

# Lint with set values
helm lint --set image.tag=v1.0 ./mychart

# Lint multiple charts
helm lint ./charts/*
```

### Lint Checks Performed

- Chart.yaml syntax and required fields
- values.yaml schema validation (if present)
- Template file syntax
- Reference to undefined values
- Best practices (image pull policy, resource limits)
- CRD validity

## Template Rendering (Dry Run)

Render templates locally to verify output.

```bash
# Basic dry-run
helm template myapp ./mychart

# With values file
helm template myapp -f values.prod.yaml ./mychart

# With set values
helm template myapp --set replicaCount=3 ./mychart

# Include CRDs
helm template myapp --include-crds ./mychart

# Show only specific templates
helm template myapp --show-only templates/deployment.yaml ./mychart

# Debug output
helm template myapp --debug ./mychart
```

## Schema Validation

Use `values.schema.json` to enforce values structure.

```bash
# Lint with schema (--strict includes schema check)
helm lint --strict ./mychart

# Test schema manually
helm template --skip-schema-validation ./mychart  # Skip for testing
```

### Schema Example

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "properties": {
    "image": {
      "type": "object",
      "properties": {
        "repository": { "type": "string" },
        "tag": { "type": "string" },
        "pullPolicy": { "type": "string", "enum": ["IfNotPresent", "Always", "Never"] }
      },
      "required": ["repository"]
    },
    "replicaCount": {
      "type": "integer",
      "minimum": 1
    },
    "service": {
      "type": "object",
      "properties": {
        "port": { "type": "integer", "minimum": 1, "maximum": 65535 }
      },
      "required": ["port"]
    }
  },
  "required": ["image", "service"],
  "type": "object"
}
```

## Chart Tests (Helm Hook Tests)

Define tests as Kubernetes Jobs with the test hook annotation.

### Test Structure

```
mychart/
├── templates/
│   └── tests/
│       ├── test-connection.yaml
│       └── test-configuration.yaml
```

### Connection Test

```yaml
# templates/tests/test-connection.yaml
apiVersion: v1
kind: Pod
metadata:
  name: "{{ include "mychart.fullname" . }}-test-connection"
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
  annotations:
    helm.sh/hook: test
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
spec:
  containers:
    - name: wget
      image: busybox:1.36
      command:
        - /bin/sh
        - -c
        - |
          echo "Testing HTTP endpoint..."
          response=$(wget -O- -T 5 http://{{ include "mychart.fullname" . }}:{{ .Values.service.port }}/health || echo "FAILED")
          if echo "$response" | grep -q "ok"; then
            echo "Health check passed"
            exit 0
          else
            echo "Health check failed: $response"
            exit 1
          fi
  restartPolicy: Never
```

### Configuration Test

```yaml
# templates/tests/test-configmap.yaml
apiVersion: v1
kind: Pod
metadata:
  name: "{{ include "mychart.fullname" . }}-test-config"
  annotations:
    helm.sh/hook: test
    helm.sh/hook-delete-policy: hook-succeeded
spec:
  containers:
    - name: envtest
      image: bitnami/kubectl:latest
      command:
        - /bin/sh
        - -c
        - |
          echo "Checking ConfigMap..."
          cm=$(kubectl get configmap {{ include "mychart.fullname" . }}-config -o jsonpath='{.data.app\.ini}')
          if echo "$cm" | grep -q "log_level"; then
            echo "ConfigMap has expected keys"
            exit 0
          fi
          echo "ConfigMap missing expected content"
          exit 1
      env:
        - name: KUBECONFIG
          value: /tmp/kubeconfig
  restartPolicy: Never
```

### Running Tests

```bash
# Run all tests for a release
helm test <release-name>

# Run tests with output logs
helm test <release-name> --logs

# Keep test pods after completion
helm test <release-name> --keep-containers

# Filter tests by name
helm test <release-name> --filter "name=test-connection"
```

## Unit Testing with Helm Unittest

The [helm-unittest](https://github.com/lrills/helm-unittest) plugin enables unit testing charts.

### Installation

```bash
helm plugin install https://github.com/helm/helm-unittest
helm plugin list
```

### Test File Structure

```
mychart/
├── tests/
│   ├── deployment_test.yaml
│   └── service_test.yaml
```

### Deployment Tests

```yaml
# tests/deployment_test.yaml
suite: Deployment Tests
tests:
  - name: Deployment should exist
    template: templates/deployment.yaml
    released:
      - Revision: 1
        Name: myapp
    asserts:
      - isKind:
          of: Deployment
      - equal:
          path: metadata.name
          value: myapp-mychart

  - name: Deployment should have correct replicas
    template: templates/deployment.yaml
    set:
      replicaCount: 3
    asserts:
      - equal:
          path: spec.replicas
          value: 3

  - name: Deployment should use correct image
    template: templates/deployment.yaml
    values:
      - ../values.yaml
    asserts:
      - equal:
          path: spec.template.spec.containers[0].image
          value: nginx:1.21

  - name: Deployment should have resource limits
    template: templates/deployment.yaml
    asserts:
      - notNull:
          path: spec.template.spec.containers[0].resources.limits.cpu
      - notNull:
          path: spec.template.spec.containers[0].resources.limits.memory
```

### Service Tests

```yaml
# tests/service_test.yaml
suite: Service Tests
templates:
  - templates/deployment.yaml
  - templates/service.yaml
values:
  - ../values.yaml
tests:
  - name: Service should match deployment selector
    template: templates/service.yaml
    asserts:
      - equal:
          path: spec.selector.app.kubernetes.io/name
          value: mychart-mychart
      - equal:
          path: spec.ports[0].port
          value: 80
```

### Running Unit Tests

```bash
# Run all tests
helm unittest ./mychart

# Run with coverage output
helm unittest --coverage ./mychart

# Run specific test file
helm unittest ./mychart -f tests/deployment_test.yaml

# Update snapshots (when templates change)
helm unittest ./mychart -u
```

## Chart Testing (ct)

The [chart-testing](https://github.com/helm/chart-testing) tool provides linting and testing for chart repos.

### Installation

```bash
# Using ct CLI
go install github.com/helm/chart-testing/v3/cmd/ct@latest

# Using ct container
docker run -v $(pwd):/workspace quay.io/helmpack/chart-testing:latest
```

### ct.yaml Configuration

```yaml
# ct.yaml
remote: origin
target-branch: main
chart-repos:
  - name=bitnami https://charts.bitnami.com
lint-conf: .chart-lintconf.yaml
validate-maintainers: false
check-version-increment: true
```

### chart-lintconf.yaml

```yaml
# .chart-lintconf.yaml
disabledRules:
  - helm-lint
  - long-lines
  - no-tab-separation
remote: origin
target-branch: main
```

### Running ct

```bash
# Lint all charts
ct lint

# Lint and test
ct lint-and-test

# Specify charts to test
ct lint --charts mychart,myotherchart

# Skip tests (lint only)
ct lint --skip-charts
```

## GitHub Actions Integration

### Basic Lint Workflow

```yaml
# .github/workflows/lint.yml
name: Lint Charts
on: [push, pull_request]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Helm
        uses: azure/setup-helm@v4
        with:
          version: v3.14

      - name: Add chart repos
        run: |
          helm repo add bitnami https://charts.bitnami.com
          helm repo update

      - name: Lint all charts
        run: |
          for chart in charts/*/; do
            helm lint --strict "$chart" || exit 1
          done
```

### Comprehensive Testing Workflow

```yaml
# .github/workflows/test.yml
name: Test Charts
on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Helm
        uses: azure/setup-helm@v4
        with:
          version: v3.14

      - name: Set up kubectl
        uses: azure/setup-kubectl@v4

      - name: Add repos
        run: |
          helm repo add bitnami https://charts.bitnami.com
          helm repo update

      - name: Lint charts
        run: |
          helm lint --strict ./charts/myapp

      - name: Template test
        run: |
          helm template myapp ./charts/myapp -f ./charts/myapp/values.yaml --debug

      - name: Install and test (KinD cluster)
        uses: helm/kind-action@v1
        with:
          cluster_name: test-cluster

      - name: Install chart
        run: |
          helm install myapp ./charts/myapp \
            --wait --timeout 5m \
            --set image.tag=test

      - name: Run tests
        run: helm test myapp --logs

      - name: Get status
        run: helm status myapp

      - name: Uninstall
        run: helm uninstall myapp
```

### Using chart-testing Action

```yaml
# .github/workflows/ct.yml
name: Chart Testing
on: [push, pull_request]

jobs:
  ct:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: helm/chart-testing-action@v2
        with:
          command: lint-and-test
```

## Pre-commit Hooks

### Install pre-commit

```bash
pip install pre-commit
```

### .pre-commit-config.yaml

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: helm-lint
        name: Helm lint
        entry: helm lint --strict
        language: system
        files: ^charts/
        pass_filenames: false

      - id: helm-template-check
        name: Helm template check
        entry: helm template
        language: system
        files: ^charts/
        pass_filenames: false
        args:
          - myapp
          - charts/myapp
          - --validate

      - id: helm-unittest
        name: Helm unit tests
        entry: helm unittest
        language: system
        files: ^charts/
        pass_filenames: false
```

## Testing Best Practices

### 1. Test Template Logic

```yaml
# Test conditional rendering
tests:
  - name: Should render replicas correctly for production
    template: templates/deployment.yaml
    set:
      environment: production
    asserts:
      - equal:
          path: spec.replicas
          value: 3
```

### 2. Test Error Cases

```yaml
# Test required value missing
tests:
  - name: Should fail when required value missing
    template: templates/configmap.yaml
    release:
      name: test
      namespace: default
    asserts:
      - failed:
          message: "image.repository is required"
```

### 3. Test Image Digest Security

```yaml
# Verify image pull policy
tests:
  - name: Should use Always pull policy in production
    template: templates/deployment.yaml
    set:
      image.tag: latest
      environment: production
    asserts:
      - equal:
          path: spec.template.spec.containers[0].imagePullPolicy
          value: Always
```

### 4. Test Resource Limits

```yaml
# Ensure resource limits are set
tests:
  - name: Should have resource limits
    template: templates/deployment.yaml
    asserts:
      - notNull:
          path: spec.template.spec.containers[0].resources.limits.cpu
      - notNull:
          path: spec.template.spec.containers[0].resources.limits.memory
      - greaterOrEqual:
          path: spec.template.spec.containers[0].resources.limits.memory
          value: 64Mi
```

## CI/CD Testing Pipeline

```bash
#!/bin/bash
# ci/test-chart.sh

set -e

CHART="$1"
VERSION="${2:-latest}"

echo "Testing chart: $CHART"

# 1. Lint
echo "Running helm lint..."
helm lint --strict "$CHART"

# 2. Template render
echo "Rendering templates..."
helm template test-release "$CHART" -f "$CHART/values.yaml" --debug --validate

# 3. Schema validation
echo "Validating schema..."
helm lint --strict "$CHART"

# 4. Unit tests (if plugin installed)
if helm plugin list | grep -q unittest; then
  echo "Running unit tests..."
  helm unittest "$CHART"
fi

# 5. Verify CRDs
echo "Checking CRDs..."
for crd in "$CHART/crds/"*.yaml; do
  if [ -f "$crd" ]; then
    echo "CRD: $crd - OK"
  fi
done

echo "All tests passed!"
```

## Debugging Test Failures

```bash
# Get test pod logs
kubectl logs myapp-test-connection

# Describe test pod
kubectl describe pod myapp-test-connection

# Get release values
helm get values myapp

# Get rendered manifest
helm get manifest myapp

# Check release history
helm history myapp

# Test template with verbose
helm template myapp ./mychart --debug > /tmp/rendered.yaml
```

## References

- [Helm Lint Documentation](https://helm.sh/docs/helm/helm_lint/)
- [Helm Unittest Plugin](https://github.com/helm/helm-unittest)
- [Chart Testing Tool](https://github.com/helm/chart-testing)
- [Artifact Hub](https://artifacthub.io/) - Find tested charts