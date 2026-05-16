---
title: Helm Production - Multi-Cluster & Multi-Env
tags: [kubernetes, helm, production, multi-cluster, multi-env]
date: 2026-05-16
description: Production Helm deployment strategies for multi-cluster and multi-environment setups
---

# Helm Production - Multi-Cluster & Multi-Environment

Production Helm deployments require managing configurations across multiple clusters and environments with proper tooling, patterns, and security considerations.

## Environment Architecture

### Typical Environment Hierarchy

```
environments/
├── dev/
│   ├── values.yaml
│   ├── secrets.yaml.enc
│   └── helmfile.yaml
├── staging/
│   ├── values.yaml
│   ├── secrets.yaml.enc
│   └── helmfile.yaml
└── prod/
    ├── values.yaml
    ├── secrets.yaml.enc
    └── helmfile.yaml
```

### Cluster Topology

```
Management Plane
    │
    ├── dev-cluster (us-east-1)
    │   ├── namespace: app-dev
    │   └── releases: myapp (v1.0.0)
    │
    ├── staging-cluster (us-east-1)
    │   ├── namespace: app-staging
    │   └── releases: myapp (v1.0.0-rc.1)
    │
    └── prod-cluster (us-west-2, eu-west-1)
        ├── namespace: app-prod
        └── releases: myapp (v0.9.5)
```

## Values File Strategy

### Layering Pattern

Multiple `-f` flags stack values with later files taking precedence:

```bash
# Base values + environment overrides
helm upgrade --install myapp ./charts/myapp \
  -f charts/myapp/values.yaml \
  -f environments/dev/values.yaml
```

### Base values.yaml

```yaml
# charts/myapp/values.yaml
image:
  repository: myapp
  tag: latest
  pullPolicy: IfNotPresent

replicaCount: 1

service:
  type: ClusterIP
  port: 8080

resources:
  limits:
    cpu: 500m
    memory: 512Mi

ingress:
  enabled: false
  className: nginx

config:
  logLevel: info
  maxConnections: 100

autoscaling:
  enabled: false

monitoring:
  enabled: false
```

### Environment Overrides

```yaml
# environments/dev/values.yaml
replicaCount: 1
ingress:
  enabled: true
  host: myapp.dev.example.com

config:
  logLevel: debug

resources:
  limits:
    cpu: 250m
    memory: 256Mi
```

```yaml
# environments/staging/values.yaml
replicaCount: 2
ingress:
  enabled: true
  host: myapp.staging.example.com

config:
  logLevel: info

resources:
  limits:
    cpu: 500m
    memory: 512Mi
```

```yaml
# environments/prod/values.yaml
replicaCount: 5
ingress:
  enabled: true
  host: myapp.example.com
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"

config:
  logLevel: warn
  maxConnections: 10000

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20
  targetCPUUtilizationPercentage: 70

monitoring:
  enabled: true
  prometheus:
    scrape: true
    path: /metrics

image:
  pullPolicy: Always

resources:
  limits:
    cpu: 1000m
    memory: 1Gi
```

## Helmfile

[Helmfile](https://github.com/helmfile/helmfile) provides declarative configuration for managing multiple releases across environments.

### Installation

```bash
# Binary
brew install helmfile

# From source
go install github.com/helmfile/helmfile@latest

# Helm plugin
helm plugin install https://github.com/helmfile/helmfile
```

### Basic Helmfile Structure

```yaml
# helmfile.yaml (root)
repositories:
  - name: bitnami
    url: https://charts.bitnami.com
  - name: prometheus-community
    url: https://prometheus-community.github.io/helm-charts

environments:
  dev:
    values:
      - environments/dev/values.yaml
  staging:
    values:
      - environments/staging/values.yaml
  prod:
    values:
      - environments/prod/values.yaml

---

# environments/prod/values.yaml (can also be separate files)
image:
  tag: v1.2.3
replicaCount: 5
```

### Helmfile with Releases

```yaml
# helmfile.yaml
repositories:
  - name: bitnami
    url: https://charts.bitnami.com

environments:
  dev:
    values:
      - env: dev
  staging:
    values:
      - env: staging
  prod:
    values:
      - env: prod

releases:
  - name: myapp
    chart: ./charts/myapp
    namespace: {{ .Environment.Name }}
    values:
      - values/{{ .Environment.Name }}/values.yaml
      - values/{{ .Environment.Name }}/secrets.yaml.gotpl
    secrets:
      - path: secrets/{{ .Environment.Name }}/secrets.yaml
        encrypted: true  # if using helm-secrets
    missingFileHandler: Warn

  - name: redis
    chart: bitnami/redis
    namespace: {{ .Environment.Name }}
    version: 18.x.x
    values:
      - values/{{ .Environment.Name }}/redis.yaml
    installed: {{ .Environment.Name != "dev" }}  # Skip in dev
```

### Multi-Cluster Helmfile

```yaml
# helmfile.yaml - Multi-cluster
bases:
  - bases/environments.yaml

environments:
  dev-us-east:
    context: kind-dev-us-east
    values:
      - environments/dev.yaml
  prod-us-west:
    context: arn:aws:eks:us-west-2:123456789:cluster/prod-cluster
    values:
      - environments/prod.yaml
  prod-eu-west:
    context: arn:aws:eks:eu-west-1:123456789:cluster/prod-eu-cluster
    values:
      - environments/prod.yaml

releases:
  - name: myapp
    chart: ./charts/myapp
    namespace: myapp
    values:
      - environments/shared.yaml
      - environments/{{ .Environment.Name }}/values.yaml
    clusters:
      - dev-us-east
      - prod-us-west
      - prod-eu-west
```

### Go Templating in Helmfile

```yaml
# helmfile.yaml with templating
{{ requiredEnv "ENVIRONMENT" }}

repositories:
  - name: bitnami
    url: https://charts.bitnami.com

environments:
  {{ .Environment.Name }}:
    values:
      - environments/{{ .Environment.Name }}/values.yaml

releases:
  - name: myapp-{{ .Environment.Name }}
    chart: ./charts/myapp
    namespace: myapp
    values:
      - environments/{{ .Environment.Name }}/values.yaml
      - values:
          environment: {{ .Environment.Name }}
          clusterDomain: {{ requiredEnv "CLUSTER_DOMAIN" }}
```

## Secret Management

### helm-secrets Plugin

Encrypt sensitive values with helm-secrets.

```bash
# Install plugin
helm plugin install https://github.com/jkroepke/helm-secrets

# Install sops (required)
brew install sops

# Encrypt a values file
sops --encrypt secrets.yaml > secrets.yaml.enc

# Edit encrypted file
helm secrets edit secrets.yaml.enc
```

### values.yaml with Secrets

```yaml
# environments/dev/secrets.yaml
image:
  pullSecrets:
    - name: regcred

database:
  host: postgres.dev.example.com
  password: changeme  # In prod, use encrypted value

apiKeys:
  stripe: ""
```

### Helmfile with Encrypted Secrets

```yaml
# helmfile.yaml
releases:
  - name: myapp
    chart: ./charts/myapp
    secrets:
      - secrets/{{ .Environment.Name }}/secrets.yaml.enc
```

### External Secrets Operator

For production, use External Secrets Operator with AWS Secrets Manager, GCP Secret Manager, or HashiCorp Vault:

```yaml
# external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: myapp-secrets
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: myapp-secrets
    creationPolicy: Owner
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: prod/myapp
        property: password
```

## Image Tag Management

### Dynamic Tag Patterns

```yaml
# values.yaml with image tag management
image:
  repository: ghcr.io/org/myapp
  tag: ""  # Set via --set or CI pipeline

# In deployment template
image: {{ .Values.image.repository }}:{{ .Values.image.tag | default "latest" }}
```

### CI/CD Image Tag Pattern

```bash
# In CI pipeline - get image tag from git commit
GIT_TAG=$(git describe --tags --always)
IMAGE_TAG=${GIT_TAG}-${SHORT_SHA}

# For production, use semantic versioning
RELEASE_VERSION=$(cat CHART_VERSION)

helm upgrade --install myapp ./charts/myapp \
  --set image.tag=$IMAGE_TAG \
  --set image.pullPolicy=Always
```

### Image Digest for Security

```bash
# Install with digest (immutable, most secure)
helm install myapp oci://ghcr.io/org/charts/myapp@sha256:abc123...

# In values.yaml
image:
  digest: sha256:abc123...  # Use digest instead of tag
```

## Atomic Upgrades & Rollback

### Atomic Install/Upgrade

```bash
# Rollback on failure automatically
helm upgrade --install myapp ./charts/myapp \
  --atomic \
  --timeout 5m

# Force replace (delete and recreate)
helm upgrade --install myapp ./charts/myapp \
  --force \
  --timeout 5m
```

### Rollback Strategy

```bash
# List revisions
helm history myapp

# Rollback to specific version
helm rollback myapp 3

# Rollback with wait
helm rollback myapp 3 --wait --timeout 5m
```

### Helmfile with Rollback

```yaml
# helmfile.yaml
releases:
  - name: myapp
    chart: ./charts/myapp
    atomic: true  # Automatic rollback on failure
    timeout: 5m
    wait: true
    cleanupOnFail: true
```

## RBAC for Helm

### Service Account for CI

```yaml
# ci-service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: helm-ci
  namespace: ci

---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: helm-ci
rules:
  - apiGroups: [""]
    resources: ["secrets", "configmaps"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets", "daemonsets"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["services", "pods"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: helm-ci
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: helm-ci
subjects:
  - kind: ServiceAccount
    name: helm-ci
    namespace: ci
```

### Namespace-Scoped Permissions

```yaml
# namespace-deployer.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-deployer
rules:
  - apiGroups: [""]
    resources: ["configmaps", "secrets", "services"]
    verbs: ["*"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets"]
    verbs: ["*"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["*"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-deployer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: app-deployer
subjects:
  - kind: ServiceAccount
    name: helm-deployer
    namespace: app-namespace
```

### Cluster-Wide Permissions (for CRDs)

```yaml
# cluster-deployer.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: helm-cluster-deployer
rules:
  - apiGroups: ["apiextensions.k8s.io"]
    resources: ["customresourcedefinitions"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["helm.toolkit.fluxcd.io"]
    resources: ["helmreleases"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: ["source.toolkit.fluxcd.io"]
    resources: ["gitrepositories", "helmrepositories"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["*"]
    resources: ["namespaces"]
    verbs: ["get", "list"]
```

## Release Storage Backends

### Default (Secrets)

Helm 3 stores release info in Secrets by default. Each release has multiple Secrets (one per revision).

```bash
# List release secrets
kubectl get secrets -l "owner=helm" -n mynamespace

# Get release history from secrets
kubectl get secret -l "owner=helm,name=myapp" --sort-by=.metadata.creationTimestamp
```

### ConfigMap Backend

For environments where Secret access is restricted:

```bash
export HELM_DRIVER=configmap
helm upgrade --install myapp ./charts/myapp
```

### SQL Backend (Beta)

For large releases (>1MB) or when SQL audit trail is needed:

```bash
export HELM_DRIVER=sql
export HELM_DRIVER_SQL_CONNECTION_STRING="postgresql://helm:password@postgres:5432/helm?sslmode=disable"

helm upgrade --install myapp ./charts/myapp
```

## Resource Management

### Checksum Annotation (Auto-Rollout)

Ensure Deployment rolls when ConfigMap/Secret changes:

```yaml
# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
        checksum/secret: {{ include (print $.Template.BasePath "/secret.yaml") . | sha256sum }}
```

### Always Roll Deployment

```yaml
# Force roll on every upgrade
spec:
  template:
    metadata:
      annotations:
        rollme: {{ randAlphaNum 5 | quote }}
```

## Production Checklist

### Pre-Deployment

- [ ] All templates render without errors
- [ ] Lint passes with --strict
- [ ] Values schema validates
- [ ] Tests pass (unit + integration)
- [ ] Chart signed and provenance verified
- [ ] Image scanned for vulnerabilities
- [ ] Resources have appropriate limits
- [ ] Secrets encrypted

### Deployment

- [ ] Backup current release
- [ ] Use --atomic or prepare rollback
- [ ] Use --wait with appropriate timeout
- [ ] Monitor rollout progress
- [ ] Verify pod health
- [ ] Check application logs

### Post-Deployment

- [ ] Run smoke tests
- [ ] Verify metrics/scraping
- [ ] Check alerting
- [ ] Update release documentation
- [ ] Notify stakeholders

## Environment-Specific Considerations

### Development

- Minimal resources
- Debug logging
- Exposed ingress (basic auth)
- Short timeouts
- Skip some tests

### Staging

- Production-like resources
- Info logging
- Staging ingress with TLS
- Standard timeouts
- Full test suite

### Production

- Auto-scaling enabled
- Warn/error logging
- Production ingress with cert-manager
- Extended timeouts
- Full test suite + canary
- Monitoring + alerting
- Backup strategy

## References

- [Helmfile Documentation](https://helmfile.readthedocs.io/)
- [helm-secrets Plugin](https://github.com/jkroepke/helm-secrets)
- [External Secrets Operator](https://external-secrets.io/)
- [Helm RBAC Documentation](https://helm.sh/docs/topics/rbac/)
- [ArgoCD Helm Integration](https://argo-cd.readthedocs.io/)
- [Flux HelmRelease](https://fluxcd.io/flux/guides/helmreleases/)