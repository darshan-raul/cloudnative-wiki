---
title: Helm Commands
tags: [kubernetes, helm, cli, commands]
date: 2026-05-16
description: Complete reference for all Helm CLI commands
---

# Helm Commands

Complete reference for Helm CLI commands. Run `helm <command> --help` for detailed help.

## Installation & Upgrades

### helm install
Install a chart into Kubernetes.

```bash
# Basic install
helm install <release-name> <chart>

# Generate name automatically
helm install myapp bitnami/wordpress

# Install with values file
helm install -f values.prod.yaml myapp ./mychart

# Install with multiple value files (later takes precedence)
helm install -f values.yaml -f values.prod.yaml myapp ./mychart

# Set individual values
helm install --set image.tag=v1.2.3 --set replicaCount=3 myapp ./mychart

# Dry-run (template locally)
helm install --dry-run --debug myapp ./mychart

# Atomic install (rollback on failure)
helm install --atomic myapp ./mychart

# Wait for resources to be ready
helm install --wait --timeout 10m myapp ./mychart

# Skip schema validation
helm install --skip-schema-validation myapp ./mychart

# Install from OCI registry
helm install myapp oci://ghcr.io/org/charts/app --version 1.0.0

# Install from specific digest (most secure)
helm install myapp oci://ghcr.io/org/charts/app@sha256:abc123...
```

### helm upgrade
Upgrade a release to a new chart version.

```bash
# Basic upgrade
helm upgrade <release-name> <chart>

# Upgrade with install (create if not exists)
helm upgrade --install myapp ./mychart

# Atomic upgrade with rollback on failure
helm upgrade --install --atomic myapp ./mychart

# Force replace (delete and recreate resources)
helm upgrade --force myapp ./mychart

# Recreate pods (deprecated in Helm 3)
helm upgrade --recreate-pods myapp ./mychart

# Upgrade with reset values
helm upgrade --reset-values myapp ./mychart

# Upgrade with timeout and wait
helm upgrade --wait --timeout 5m myapp ./mychart

# Upgrade from OCI with version
helm upgrade myapp oci://ghcr.io/org/charts/app --version 2.0.0
```

### helm rollback
Roll back a release to a previous revision.

```bash
# Rollback to previous revision
helm rollback <release-name>

# Rollback to specific revision
helm rollback <release-name> 3

# Rollback with timeout
helm rollback --timeout 5m <release-name>

# Rollback with wait
helm rollback --wait <release-name>
```

### helm uninstall
Uninstall a release from Kubernetes.

```bash
# Basic uninstall
helm uninstall <release-name>

# Keep release history
helm uninstall --keep-history <release-name>

# Wait for resources to be deleted
helm uninstall --wait <release-name>
```

## Release Management

### helm list
List all releases in a namespace.

```bash
# List releases in current namespace
helm list

# List releases in specific namespace
helm list -n mynamespace

# List all releases across namespaces
helm list --all-namespaces

# List with status filter
helm list --filter 'status=deployed'

# Show deleted releases
helm list --uninstalled

# Show all releases including failed/deleted
helm list --all

# Output in JSON/YAML
helm list -o json
helm list -o yaml

# Limit results
helm list --max 20
```

### helm status
Display the status of a named release.

```bash
helm status <release-name>
helm status <release-name> -n mynamespace

# Show resources (Helm 3.2+)
helm status <release-name> --show-resources
```

### helm history
Fetch release history.

```bash
helm history <release-name>
helm history <release-name> --max 10
```

### helm get
Download extended information for a named release.

```bash
# All information
helm get all <release-name>

# Values
helm get values <release-name>
helm get values <release-name> --revision 2

# Manifest (rendered templates)
helm get manifest <release-name>
helm get manifest <release-name> --revision 3

# Notes
helm get notes <release-name>

# Hooks
helm get hooks <release-name>

# Metadata
helm get metadata <release-name>
```

## Chart Operations

### helm create
Create a new chart with the given name.

```bash
# Create new chart
helm create mychart

# Create in specific directory
helm create ./charts/myservice

# Create from starter template
helm create mychart --starter common
```

### helm package
Package a chart directory into a chart archive.

```bash
# Package current directory
helm package ./mychart

# Package with version
helm package ./mychart --version 1.2.3

# Sign the package
helm package --sign --key 'My Key' --keyring ~/.gnupg/secring.gpg ./mychart

# Sign with specific algorithm
helm package --sign --key 'My Key' --keyring ~/.gnupg/secring.gpg --sign-algorithm ECDSA ./mychart
```

### helm lint
Examine a chart for possible issues.

```bash
# Lint chart
helm lint ./mychart

# Strict linting (including schema validation)
helm lint --strict ./mychart

# Set values during lint
helm lint --set image.tag=v1.0 ./mychart
```

### helm template
Locally render templates.

```bash
# Basic template
helm template myrelease ./mychart

# With values file
helm template myrelease -f values.yaml ./mychart

# With set values
helm template myrelease --set image.tag=v1.2.3 ./mychart

# Include hooks
helm template myrelease --include-crds ./mychart

# Show notes
helm template myrelease --show-only templates/NOTES.txt ./mychart
```

### helm diff (requires helm-diff plugin)
Show differences between chart versions.

```bash
# Show upgrade diff
helm diff upgrade myapp ./mychart

# Show against specific revision
helm diff upgrade myapp --revision 2 ./mychart

# Show with value changes
helm diff values myapp -f values.prod.yaml ./mychart

# Ignore specific fields
helm diff upgrade myapp --ignore-annotations ./mychart
```

## Repository Management

### helm repo add
Add a chart repository.

```bash
# Add repository
helm repo add bitnami https://charts.bitnami.com

# Add with alias
helm repo add stable https://charts.helm.sh/stable

# Add with username/password
helm repo add internal https://charts.internal.com --username admin --password secret

# Add from OCI registry
helm repo add oci://ghcr.io/org/charts
```

### helm repo update
Update information of available charts locally.

```bash
helm repo update

# Update specific repository
helm repo update bitnami

# Update all repositories
helm repo update
```

### helm repo list
List chart repositories.

```bash
helm repo list
```

### helm repo remove
Remove one or more chart repositories.

```bash
helm repo remove bitnami
helm repo remove stable local
```

### helm repo index
Generate an index file from a directory of charts.

```bash
# Generate index for directory
helm repo index ./charts --url https://charts.example.com

# Merge with existing index
helm repo index ./charts --merge ./charts/index.yaml
```

## Search

### helm search
Search for charts.

```bash
# Search Artifact Hub
helm search hub wordpress

# Search specific repository
helm search repo bitnami/wordpress

# Search with version constraint
helm search repo nginx --version ">=1.0.0"

# Output in JSON
helm search hub wordpress -o json

# List repository URLs
helm search hub nginx --list-repo-url
```

## Dependency Management

### helm dependency build
Rebuild the `charts/` directory based on `Chart.lock`.

```bash
helm dependency build ./mychart
```

### helm dependency update
Update charts/ based on `Chart.yaml`.

```bash
helm dependency update ./mychart

# Update with specific repository cache
helm dependency update --repository-cache /path/to/cache ./mychart
```

### helm dependency list
List dependencies for a chart.

```bash
helm dependency list ./mychart
```

## Testing

### helm test
Run tests for a release.

```bash
# Run all tests
helm test <release-name>

# Run with output
helm test <release-name> --logs

# Keep pods after test
helm test <release-name> --keep-containers

# Run specific test
helm test <release-name> --filter "name=test-connection"
```

## Registry Operations

### helm registry login
Login to a registry.

```bash
# Interactive login
helm registry login ghcr.io

# With credentials
helm registry login -u username ghcr.io
```

### helm registry logout
Logout from a registry.

```bash
helm registry logout ghcr.io
```

### helm push
Push a chart to OCI registry.

```bash
# Push chart package
helm push mychart-1.0.0.tgz oci://ghcr.io/org/charts

# Push with provenance file
helm push mychart-1.0.0.tgz oci://ghcr.io/org/charts
```

## Plugin Management

### helm plugin install
Install Helm plugins.

```bash
# Install from URL
helm plugin install https://github.com/dataroots/helm-git

# Install from local plugin directory
helm plugin install ./path/to/plugin

# Install specific version
helm plugin install https://example.com/plugin-1.0.0.tgz --version 1.0.0
```

### helm plugin list
List installed plugins.

```bash
helm plugin list
```

### helm plugin update
Update plugins.

```bash
helm plugin update diff
helm plugin update
```

### helm plugin uninstall
Uninstall plugins.

```bash
helm plugin uninstall diff
```

## Environment & Configuration

### helm env
Print Helm client environment information.

```bash
helm env
```

### helm version
Print version information.

```bash
helm version
helm version --short
```

### helm completion
Generate autocompletion scripts.

```bash
# Bash
helm completion bash

# Zsh
helm completion zsh

# PowerShell
helm completion powershell

# Fish
helm completion fish

# Update completions in current shell
source <(helm completion bash)
```

## Verification

### helm verify
Verify that a chart at the given path has been signed and is valid.

```bash
# Verify chart
helm verify ./mychart-1.0.0.tgz

# Verify with keyring
helm verify --keyring ~/.gnupg/pubring.gpg ./mychart-1.0.0.tgz
```

### helm plugin verify
Verify that a plugin is signed and valid.

```bash
helm plugin verify ./path/to/plugin.tar.gz
```

## Global Flags

| Flag | Description |
|------|-------------|
| `--debug` | Enable verbose output |
| `--kube-context` | Set the kube context |
| `--namespace` / `-n` | Set the namespace |
| `--kubeconfig` | Path to kubeconfig file |
| `--dry-run` | Simulate operations |
| `--timeout` | Set timeout (Go duration format) |
| `--wait` | Wait for resources to be ready |
| `--no-hooks` | Skip running hooks |
| `--skip-schema-validation` | Skip schema validation |
| `--set` | Set values |
| `--set-file` | Set values from file |
| `--set-string` | Set string values |
| `--values` / `-f` | Set values from file |

## Common Patterns

### Install-or-Upgrade (Idempotent)
```bash
helm upgrade --install myapp ./mychart --wait --atomic
```

### Dry-Run Before Install
```bash
helm template myapp ./mychart -f values.prod.yaml | less
```

### Debug Template Rendering
```bash
helm template myapp ./mychart --debug --dry-run
```

### View Release History with Timestamps
```bash
helm list -o yaml | yq '.[] | {name: .name, revision: .revision, updated: .updated, status: .status}'
```

### Cleanup Failed Release
```bash
helm uninstall myapp --wait
kubectl delete job -l "helm.sh/release=myapp"
```