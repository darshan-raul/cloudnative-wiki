---
title: Helm GitOps
tags: [kubernetes, helm, gitops, argocd, flux, cicd]
date: 2026-05-16
description: GitOps workflows for Helm with ArgoCD and Flux
---

# Helm GitOps

GitOps automates Kubernetes deployments through Git as the source of truth. Both ArgoCD and Flux provide first-class Helm support.

## GitOps Principles

1. **Declarative** - All desired state is declared in Git
2. **Versioned** - Every change is versioned and auditable
3. **Pull-based** - Agents pull updates from Git
4. **Automated** - Changes are automatically applied when Git is updated

## Repository Structure

### Recommended Structure

```
├── charts/
│   ├── myapp/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   └── common-lib/
│       └── ...
├── environments/
│   ├── dev/
│   │   └── values.yaml
│   ├── staging/
│   │   └── values.yaml
│   └── prod/
│       └── values.yaml
├── apps/
│   ├── myapp/
│   │   ├── argo-app.yaml      # ArgoCD Application
│   │   └── kustomization.yaml  # Flux Kustomization
│   └── Helmfile               # Helmfile for local dev
└── README.md
```

## ArgoCD

### ArgoCD Application (Helm)

```yaml
# apps/myapp/argo-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/org/monorepo.git
    targetRevision: main
    path: charts/myapp
    helm:
      valueFiles:
        - values.yaml
        - environments/prod/values.yaml
      parameters:
        - name: image.tag
          value: v1.2.3
        - name: replicaCount
          value: "3"
      fileParameters:
        - name: secrets
          path: environments/prod/secrets.yaml.gpg
  destination:
    server: https://kubernetes.default.svc
    namespace: myapp-prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - PrunePropagation=foreground
      - RespectIgnoreDifferences=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### ArgoCD with Helmfile

```yaml
# apps/myapp/helmfile-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp-helmfile
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/monorepo.git
    targetRevision: main
    path: apps/myapp
    plugin:
      name: helmfile
  destination:
    server: https://kubernetes.default.svc
    namespace: myapp-prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### ArgoCD ApplicationSet (Multi-Cluster)

```yaml
# apps/myapp/appset.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapp-prod
  namespace: argocd
spec:
  generators:
    - clusters:
        values:
          environment: prod
          clusterSecretRef: prod-cluster
          # These values are injected into the template
          values:
            image.tag: v1.2.3
            replicaCount: "5"
    - clusters:
        values:
          environment: staging
          clusterSecretRef: staging-cluster
          values:
            image.tag: v1.2.4-rc.1
            replicaCount: "2"

  template:
    spec:
      project: default
      source:
        repoURL: https://github.com/org/monorepo.git
        targetRevision: main
        path: charts/myapp
        helm:
          valueFiles:
            - values.yaml
            - environments/{{ values.environment }}/values.yaml
          parameters:
            - name: image.tag
              value: "{{ values.image.tag }}"
            - name: replicaCount
              value: "{{ values.replicaCount }}"
      destination:
        server: "{{ server }}"
        namespace: myapp-{{ values.environment }}
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

### ArgoCD with Values from Git

```yaml
# apps/myapp/argocd-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
spec:
  source:
    helm:
      parameters:
        - name: image.repository
          value: ghcr.io/org/myapp
        - name: image.tag
          value: v1.0.0
        - name: ingress.host
          value: myapp.example.com
      valueFiles:
        - values.yaml
        - values/prod.yaml
      values: |
        replicaCount: 3
        autoscaling:
          enabled: true
```

### Drift Detection & Reconciliation

```bash
# ArgoCD CLI - Sync and force reconcile
argocd app sync myapp --force

# View diff
argocd app diff myapp

# Sync with pruning
argocd app sync myapp --prune

# Get app status
argocd app get myapp

# View resource health
argocd app resourceHealth myapp
```

## Flux

### Flux Installation

```bash
# Install Flux v2
curl -s https://fluxcd.io/install.sh | sh

# Bootstrap
flux bootstrap github \
  --owner=org \
  --repository=flux-repo \
  --branch=main \
  --path=clusters/prod \
  --personal

# Or GitLab
flux bootstrap gitlab \
  --owner=org \
  --repository=flux-repo \
  --path=clusters/prod
```

### HelmRepository

```yaml
# flux/helmrepository.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: bitnami
  namespace: flux-system
spec:
  interval: 1m
  url: https://charts.bitnami.com
  timeout: 60s
```

### HelmRelease (Basic)

```yaml
# flux/myapp-helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: myapp
  namespace: myapp
spec:
  interval: 5m
  releaseName: myapp
  chart:
    spec:
      chart: ./charts/myapp
      version: "1.x.x"
      sourceRef:
        kind: GitRepository
        name: monorepo
        namespace: flux-system
  values:
    replicaCount: 2
    image:
      tag: v1.0.0
    ingress:
      enabled: true
      host: myapp.example.com
  install:
    createNamespace: true
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
      # Keep failing release for debugging
      cleanupOnFail: false
  rollback:
    timeout: 10m
  test:
    enable: true
    timeout: 5m
  postRenderers:
    - kustomize:
        patches:
          - target:
              kind: Deployment
            patch: |
              - op: add
                path: /spec/template/metadata/annotations
                value:
                  rollme: "{{ randAlphaNum 5 }}"
```

### HelmRelease from External Chart

```yaml
# flux/redis-helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: redis
  namespace: myapp
spec:
  interval: 1h
  releaseName: redis
  chart:
    spec:
      chart: redis
      version: "18.x"
      interval: 24h
      sourceRef:
        kind: HelmRepository
        name: bitnami
  values:
    architecture: replication
    auth:
      enabled: true
      password: ""
    master:
      persistence:
        enabled: true
        size: 10Gi
    replica:
      persistence:
        enabled: true
        size: 10Gi
  install:
    timeout: 10m
  upgrade:
    timeout: 10m
```

### Flux Kustomization (GitOps)

```yaml
# flux/kustomization.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1beta2
kind: Kustomization
metadata:
  name: myapp
  namespace: flux-system
spec:
  interval: 1m
  path: ./environments/prod
  prune: true
  sourceRef:
    kind: GitRepository
    name: monorepo
  wait: true
  timeout: 5m
```

### Multi-Environment Flux

```yaml
# flux/apps-prod.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1beta2
kind: Kustomization
metadata:
  name: apps-prod
  namespace: flux-system
spec:
  interval: 5m
  path: ./environments/prod
  prune: true
  sourceRef:
    kind: GitRepository
    name: monorepo
  targetNamespace: prod
  postBuild:
    substitute:
      environment: prod
      imageTag: v1.2.3
    substituteWith: environment
```

### Flux with OCI Source

```yaml
# flux/myapp-oci.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: myapp
spec:
  chart:
    spec:
      chart: myapp
      version: "1.0.0"
      sourceRef:
        kind: OCIRepository
        name: myapp-registry
  values:
    replicaCount: 3
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: OCIRepository
metadata:
  name: myapp-registry
spec:
  interval: 10m
  url: oci://ghcr.io/org/charts
  ref:
    tag: v1.0.0
```

## ArgoCD vs Flux Comparison

| Feature | ArgoCD | Flux |
|---------|--------|------|
| Helm Support | Native | Native |
| Application Definition | CRD + UI | CRD only |
| Multi-cluster | ApplicationSet | Kustomization + SOPS |
| GitOps | Declarative | Declarative |
| Dashboard | Web UI | CLI + Weave GitOps |
| Secret Management | External Secrets + Sealed Secrets | External Secrets + SOPS |
| Drift Detection | Yes | Yes |
| Rollback | Yes | Yes |
| Progressive Delivery | + Argo Rollouts | Flagger |

## GitOps Workflows

### Feature Branch Workflow

```
feature/myapp-v2
    │
    ├── PR created
    │   └── ArgoCD/Flux detects change
    │       └── Auto-deploy to dev/staging
    │
    └── PR merged to main
        └── Auto-deploy to all environments
```

### Promotion Workflow

```yaml
# ArgoCD App for promotion
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp-staging
spec:
  source:
    targetRevision: staging  # Branch or tag
    path: charts/myapp
    helm:
      valueFiles:
        - values.yaml
        - values/staging.yaml
```

```yaml
# Promotion - promote to prod
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp-prod
spec:
  source:
    targetRevision: v1.2.0  # Specific version
    path: charts/myapp
    helm:
      valueFiles:
        - values.yaml
        - values/prod.yaml
```

### Canary Promotion with Argo Rollouts

```yaml
# rollout.yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: myapp
spec:
  strategy:
    canary:
      steps:
        - setWeight: 10
        - pause: {duration: 5m}
        - setWeight: 50
        - pause: {duration: 10m}
        - analysis:
            templates:
              - templateName: success-rate
      canaryMetadata:
        labels:
          app: myapp
      stableMetadata:
        labels:
          app: myapp
  selector:
    matchLabels:
      app: myapp
  template:
    # Deployment spec
```

## Secret Management in GitOps

### Sealed Secrets (Bitnami)

```yaml
# apps/myapp/sealed-secret.yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: myapp-secrets
  namespace: myapp
spec:
  encryptedData:
    DB_PASSWORD: AgA2...
    API_KEY: AgA3...
  template:
    type: Opaque
    metadata:
      labels:
        app: myapp
```

### External Secrets + ArgoCD

```yaml
# apps/myapp/external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: myapp-secrets
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets
    kind: ClusterSecretStore
  target:
    name: myapp-secrets
    creationPolicy: Owner
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: /myapp/prod/db
        property: password
```

## CI/CD with GitOps

### GitHub Actions + ArgoCD

```yaml
# .github/workflows/deploy.yml
name: Deploy to Production

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Package and push chart
        run: |
          helm package charts/myapp
          helm push myapp-*.tgz oci://ghcr.io/org/charts

      - name: Update ArgoCD Image
        run: |
          # Update image tag in values
          sed -i 's/image.tag:.*/image.tag: ${{ github.sha }}/' environments/prod/values.yaml

      - name: Create PR for values update
        uses: peter-evans/create-pull-request@v5
        with:
          title: "Update myapp image to ${{ github.sha }}"
          base: main
          commit-message: "chore: update myapp image"
```

### GitHub Actions + Flux

```yaml
# .github/workflows/flux-sync.yml
name: Flux Sync

on:
  push:
    branches: [main]
    paths:
      - 'charts/**'
      - 'environments/**'

jobs:
  notify:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Flux
        uses: fluxcd/flux2@v2
        with:
          version: latest

      - name: Reconcile
        run: |
          flux reconcile source git monorepo

      - name: Notify ArgoCD
        if: contains(github.event.head_commit.message, '[skip ci]')
        run: |
          # Notify ArgoCD of new version
          argocd app sync myapp || true
```

### GitLab CI + ArgoCD

```yaml
# .gitlab-ci.yml
stages:
  - test
  - package
  - deploy

lint:
  stage: test
  script:
    - helm lint --strict charts/myapp

package:
  stage: package
  script:
    - helm package charts/myapp
    - helm push myapp-*.tgz oci://$CI_REGISTRY_IMAGE:$CI_COMMIT_TAG
  rules:
    - tag: [v*]

deploy-prod:
  stage: deploy
  script:
    - argocd app set myapp --helm-set image.tag=$CI_COMMIT_TAG
    - argocd app sync myapp
  environment:
    name: production
  rules:
    - tag: [v*]
```

## Helmfile + GitOps

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
    values:
      - environments/{{ .Environment.Name }}/values.yaml
    secrets:
      - path: environments/{{ .Environment.Name }}/secrets.yaml.enc
        # Requires helm-secrets plugin
```

### ArgoCD Helmfile Plugin

```yaml
# argocd-helmfile-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp-all-envs
spec:
  source:
    repoURL: https://github.com/org/repo.git
    path: .
    plugin:
      name: helmfile
      parameters:
        - name: environment
          value: prod
        - name: args
          value: "--no-progress"
```

## Best Practices

### 1. Separate App of Apps Pattern

```yaml
# Root app (ArgoCD)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: apps
spec:
  source:
    path: apps
  syncPolicy:
    automated:
      prune: true
```

### 2. UseRevision History

```yaml
# ArgoCD App with revision history
spec:
  source:
    targetRevision: main
    revisionHistoryLimit: 5
```

### 3. Health Checks

```yaml
# ArgoCD health override
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
```

### 4. Notifications

```yaml
# ArgoCD notifications
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argoproj.io/subscribe.on-sync-succeeded.slack: myapp-alerts
```

## Troubleshooting

### ArgoCD

```bash
# View application events
argocd app events myapp

# Sync application
argocd app sync myapp --force

# Get application resources
argocd app resources myapp

# View diff between Git and cluster
argocd app diff myapp

# Debug application
argocd app logs myapp --follow
```

### Flux

```bash
# Check HelmRelease status
flux get helmreleases myapp -n myapp

# Reconcile manually
flux reconcile helmrelease myapp -n myapp --with-source

# View logs
flux logs --all --follow --namespace=flux-system

# Debug Helm
flux logs --kind=HelmRelease --name=myapp
```

## References

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [ArgoCD Helm Guide](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/)
- [Flux Documentation](https://fluxcd.io/)
- [Flux HelmRelease API](https://fluxcd.io/flux/guides/helmreleases/)
- [Helmfile Documentation](https://helmfile.readthedocs.io/)
- [ArgoCD ApplicationSet](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/)