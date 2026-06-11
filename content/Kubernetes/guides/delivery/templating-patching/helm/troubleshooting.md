---
title: Helm Troubleshooting
tags: [kubernetes, helm, debugging, troubleshooting]
date: 2026-05-16
description: Debugging Helm releases, common issues, and rollback strategies
---

# Helm Troubleshooting

Guide to diagnosing and resolving common Helm issues.

## Quick Debugging Commands

```bash
# Get full status of release
helm status myapp

# Get release history
helm history myapp

# Get rendered manifest
helm get manifest myapp

# Get values
helm get values myapp --all

# Get hooks
helm get hooks myapp

# Debug template rendering
helm template myapp ./charts/myapp --debug --dry-run

# Verbose install
helm install myapp ./charts/myapp --dry-run --debug
```

## Debugging Failed Releases

### 1. Identify the Failure

```bash
# Check release status
helm status myapp

# Get history with all revisions
helm history myapp --max 10

# Check what went wrong
kubectl get events --namespace myapp-namespace --sort-by='.lastTimestamp'
```

### 2. Get Detailed Information

```bash
# Get all release info
helm get all myapp

# Get values with revision
helm get values myapp --revision 3

# Get manifest at failed revision
helm get manifest myapp --revision 3

# Get notes
helm get notes myapp
```

### 3. Check Kubernetes Resources

```bash
# List all resources created by release
kubectl get all -n myapp-namespace -l "app.kubernetes.io/instance=myapp"

# Get detailed resource info
kubectl describe deployment -n myapp-namespace myapp

# Check pod logs
kubectl logs -n myapp-namespace -l "app.kubernetes.io/instance=myapp"

# Get events sorted by time
kubectl get events -n myapp-namespace --sort-by='.lastTimestamp' | tail -50
```

## Common Issues

### Issue: `Error: cannot reuse a name that is still in use`

```bash
# Check existing release
helm list -n mynamespace

# Either uninstall first or use upgrade --install
helm upgrade --install myapp ./charts/myapp

# Or force replace
helm upgrade --install myapp ./charts/myapp --force
```

### Issue: `Error: no schema validation`

```bash
# Skip schema validation temporarily
helm upgrade --install myapp ./charts/myapp --skip-schema-validation

# Fix values.schema.json
helm lint --strict ./charts/myapp
```

### Issue: `Error: release failed`

```bash
# Get last failed release details
helm status myapp --show-resources

# View release notes (may have error message)
helm get notes myapp

# Check release metadata
helm get metadata myapp

# Check what resources were created
helm get manifest myapp | kubectl apply --dry-run
```

### Issue: `Error: Kubernetes cluster unreachable`

```bash
# Check kubeconfig
kubectl config current-context
kubectl cluster-info

# Specify kubeconfig explicitly
helm upgrade --install myapp ./charts/myapp --kubeconfig /path/to/kubeconfig

# Switch context
kubectl config use-context my-cluster
```

### Issue: `Error: job failed`

```bash
# Find failed hook job
kubectl get jobs -n mynamespace --show-labels | grep hook

# Get job logs
kubectl logs job/myapp-migrate -n mynamespace

# Describe job
kubectl describe job/myapp-migrate -n mynamespace

# Delete failed hook (allows retry)
kubectl delete job myapp-migrate -n mynamespace

# Retry release
helm upgrade --install myapp ./charts/myapp
```

## Hook Failures

### Debug Hooks

```bash
# Get hooks for release
helm get hooks myapp

# List all hook pods
kubectl get pods -n mynamespace -l "helm.sh/hook"

# Get hook job logs
kubectl logs -n mynamespace myapp-pre-install-hook

# Force delete hook resources
kubectl delete job -n mynamespace -l "helm.sh/release=myapp"

# Retry with hook deletion
helm upgrade --install myapp ./charts/myapp --no-hooks
helm upgrade --install myapp ./charts/myapp  # Re-run with hooks
```

### Common Hook Annotations

```yaml
# templates/backup-hook.yaml
metadata:
  annotations:
    helm.sh/hook: pre-upgrade,post-upgrade
    helm.sh/hook-weight: "5"
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
```

## Rollback Procedures

### Rollback to Previous Version

```bash
# List revisions
helm history myapp

# Rollback to specific revision
helm rollback myapp 3

# Rollback with wait
helm rollback myapp --wait --timeout 5m

# Rollback to previous with atomic
helm rollback myapp --atomic
```

### Rollback to Known Good Version

```bash
# Get current and previous revisions
helm history myapp

# Rollback to revision 2
helm rollback myapp 2

# Verify rollback
helm status myapp
kubectl rollout status deployment/myapp -n mynamespace
```

### Emergency Rollback Script

```bash
#!/bin/bash
# rollback.sh

RELEASE=$1
REVISION=${2:-""}

if [ -z "$RELEASE" ]; then
  echo "Usage: $0 <release-name> [revision]"
  exit 1
fi

# Get current revision
CURRENT=$(helm status $RELEASE -o json | jq -r '.info.revision')

if [ -z "$REVISION" ]; then
  REVISION=$((CURRENT - 1))
fi

echo "Rolling back $RELEASE from revision $CURRENT to $REVISION"

helm rollback $RELEASE $REVISION --wait --timeout 5m

if [ $? -eq 0 ]; then
  echo "Rollback successful!"
  helm history $RELEASE
else
  echo "Rollback failed!"
  exit 1
fi
```

## Memory / Resource Issues

### Large Release Values

```bash
# Check release size
helm get values myapp -o json | wc -c

# If > 1MB, use ConfigMap or SQL backend
export HELM_DRIVER=configmap
# or
export HELM_DRIVER=sql
export HELM_DRIVER_SQL_CONNECTION_STRING="postgresql://..."
```

### Storage Backend

```bash
# Check current driver
helm env | grep HELM_DRIVER

# Change to configmap
export HELM_DRIVER=configmap

# Change to SQL (requires Helm 3.11+)
export HELM_DRIVER=sql
export HELM_DRIVER_SQL_CONNECTION_STRING="postgresql://user:pass@host:5432/helm"
```

## Template Debugging

### Debug Template Rendering

```bash
# Template locally
helm template myapp ./charts/myapp

# With values
helm template myapp ./charts/myapp -f values.prod.yaml

# With set values
helm template myapp ./charts/myapp --set replicaCount=3

# Show only specific template
helm template myapp ./charts/myapp --show-only templates/deployment.yaml

# Debug output (verbose)
helm template myapp ./charts/myapp --debug

# Lint check
helm lint ./charts/myapp
```

### Print Template Values

```yaml
# templates/debug.yaml
# Temporary debug template - delete after use
{{- range $key, $value := .Values }}
{{ $key }}: {{ $value | toYaml }}
{{- end }}
```

### Test Template Functions

```bash
# Test include function
helm template myapp ./charts/myapp --debug | grep -A 10 "mychart.labels"

# Check values passed
helm template myapp ./charts/myapp --debug 2>&1 | grep "COMPUTED VALUES"
```

## Resource Check Sum Issues

### Auto-Rollout on ConfigMap Change

```yaml
# templates/deployment.yaml
spec:
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```

### Force Deployment Roll

```bash
# Patch deployment to force rollout
kubectl patch deployment myapp -n mynamespace -p '{"spec":{"template":{"metadata":{"annotations":{"rollme":"'$(date +%s)'"}}}}}}'

# Or use helm upgrade with force
helm upgrade --install myapp ./charts/myapp --force
```

## Cleanup Failed Install

```bash
# Uninstall keeping history
helm uninstall myapp --keep-history

# If release is stuck
helm uninstall myapp --wait

# Delete remaining resources
kubectl delete all -n mynamespace -l "app.kubernetes.io/instance=myapp"

# Clean up hooks
kubectl delete jobs -n mynamespace -l "helm.sh/release=myapp"

# Remove Helm labels
kubectl delete configmaps -n mynamespace -l "owner=helm"
```

## Release Revision Limit

### Clean Up Old Revisions

```bash
# List revisions
helm history myapp

# Keep only last 10 revisions
helm history myapp --max 10

# Or prune old revisions (manual)
helm rollback myapp 0  # Not supported - revisions are immutable
```

### Set Revision Limit

```yaml
# In ArgoCD or Helmfile
syncPolicy:
  historyLimit: 5
```

## Network / Timeout Issues

### Increase Timeout

```bash
# 10 minute timeout
helm upgrade --install myapp ./charts/myapp --timeout 10m

# Wait for all resources
helm upgrade --install myapp ./charts/myapp --wait --timeout 15m

# Combine with atomic
helm upgrade --install myapp ./charts/myapp --wait --atomic --timeout 15m
```

### Debug Connection

```bash
# Test cluster connectivity
kubectl cluster-info

# Check kubectl config
kubectl config current-context

# Switch context
kubectl config use-context production

# Check namespace
kubectl get namespaces
kubectl get pods -n mynamespace
```

## Helm Plugin Issues

### Reinstall Plugin

```bash
# List plugins
helm plugin list

# Update plugin
helm plugin update diff

# Uninstall and reinstall
helm plugin uninstall diff
helm plugin install https://github.com/dataroots/helm-diff
```

### Debug Plugin

```bash
# Run with verbose
helm diff upgrade myapp ./charts/myapp --debug

# Check plugin log
helm plugin logs diff
```

## Release Not Found

```bash
# List all releases (all namespaces)
helm list --all-namespaces

# Show deleted releases
helm list --uninstalled

# Show failed releases
helm list --failed

# If release is in failed state
helm status myapp  # Shows state

# Try to recover
helm uninstall myapp || true  # Clean up
helm install myapp ./charts/myapp  # Reinstall
```

## OCI Registry Issues

```bash
# Enable OCI support
export HELM_EXPERIMENTAL_OCI=1

# Check login
helm registry login ghcr.io

# Verify registry connectivity
curl -u user:pass https://ghcr.io/v2/

# Retry with debug
helm install --debug myapp oci://ghcr.io/org/charts/myapp
```

## Check Schema Validation

```bash
# Run lint with strict
helm lint --strict ./charts/myapp

# Template with validation
helm template myapp ./charts/myapp --validate

# Skip validation
helm upgrade --install myapp ./charts/myapp --skip-schema-validation
```

## Get Help

```bash
# General help
helm --help

# Command specific help
helm upgrade --help

# Get Helm environment
helm env

# Check version
helm version
```

## Common Error Messages

| Error | Cause | Solution |
|-------|-------|----------|
| `release failed` | Resource conflict or validation error | `helm status` to see details |
| `cannot reuse name` | Release already exists | Use `helm upgrade --install` |
| `timed out waiting` | Cluster slow or resources not ready | Increase `--timeout` |
| `validation error` | Values don't match schema | Check values or use `--skip-schema-validation` |
| `hook failed` | Job/hook annotation issue | Check hook annotations, delete hook job, retry |
| `cluster unreachable` | Kubeconfig issue | Check `kubectl config current-context` |
| `no such host` | DNS/registry issue | Check registry URL |
| `authentication required` | Not logged in to registry | `helm registry login` |
| `chart not found` | Chart doesn't exist in repo | `helm repo update` and verify chart name |
| `values file not found` | Wrong path | Check `-f` file paths |
| `missing value` | Required value not set | Use `--set` or check `values.yaml` |

## Debugging Checklist

- [ ] Check `helm status <release>`
- [ ] Check `helm history <release>`
- [ ] Review `helm get manifest <release>`
- [ ] Review `helm get values <release>`
- [ ] Check `kubectl get events`
- [ ] Check pod logs
- [ ] Verify namespace exists
- [ ] Verify image exists and is accessible
- [ ] Check resource limits (CPU/memory)
- [ ] Check image pull secrets
- [ ] Verify network policies
- [ ] Check storage class availability

## References

- [Helm Debug Guide](https://helm.sh/docs/topics/chart_template_guide/debugging/)
- [Helm Troubleshooting](https://helm.sh/docs/howto/charts_tips_and_tricks/)
- [Kubernetes Events](https://kubernetes.io/docs/tasks/debug-application-cluster/determine-reason-for-pod-failure/)