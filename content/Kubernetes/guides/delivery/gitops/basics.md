---
title: GitOps Basics
tags:
  - Kubernetes
  - GitOps
  - Delivery
  - Argo CD
  - Flux
---

GitOps: **git is the source of truth for both app code AND infrastructure**. A controller (Argo CD, Flux) pulls from git, applies to the cluster, and reconciles continuously. The cluster is always told what to look like, not told what to do.

## The two operations

| Pattern | Model | Tools | State |
|---------|-------|-------|-------|
| **Push** | CI pushes to cluster (kubectl apply) | Jenkins, GitHub Actions | Cluster state can drift |
| **Pull** (GitOps) | Controller pulls from git | Argo CD, Flux | Cluster state always matches git |

**GitOps is pull-based.** The cluster decides what to run, not CI.

## The flow

```
Developer          Git           CI              GitOps Controller       Cluster
    │              │              │                     │                  │
    │  commit      │              │                     │                  │
    │ ───────────> │              │                     │                  │
    │              │  push event  │                     │                  │
    │              │ ───────────> │                     │                  │
    │              │              │  test, build, push  │                  │
    │              │              │  image: myapp:v123  │                  │
    │              │ <──────────  │                     │                  │
    │              │  update tag  │                     │                  │
    │              │              │                     │                  │
    │              │  poll/webhook                                 │                  │
    │              │ <───────────────────────────────────────────  │                  │
    │              │              │                     │  detect diff    │
    │              │              │                     │  apply manifest │
    │              │              │                     │ ──────────────> │
    │              │              │                     │                  │
    │              │              │                     │  health check   │
    │              │              │                     │ <──────────────  │
    │              │              │                     │                  │
```

**Key insight:** CI does not touch the cluster. CI updates git (image tag, manifest, etc.). The GitOps controller reconciles.

## The four principles

From the [OpenGitOps](https://opengitops.dev/) spec:

1. **Declarative** — the entire system is described declaratively (yaml, json, etc.)
2. **Versioned and immutable** — stored in git, with full version history
3. **Pulled automatically** — software agents pull the desired state, not humans pushing
4. **Continuously reconciled** — agents observe and apply, not just on event

## The two main tools

### Argo CD

CNCF Graduated. The most popular.

**Pros:**
- Web UI
- Multi-cluster support
- App of Apps pattern
- Rich RBAC
- Notifications
- Sync waves
- Resource hooks
- Helm, Kustomize, Jsonnet, plain manifests

**Cons:**
- More complex than Flux
- Stateful UI/DB (Redis)
- Heavier resource footprint

### Flux CD

CNCF Graduated. The CNCF reference.

**Pros:**
- Lighter weight
- Composable (GitOps Toolkit)
- Multi-tenancy
- Image automation
- Native Helm + Kustomize
- CRDs are the interface

**Cons:**
- No built-in UI (use Weave GitOps)
- Less out-of-box features

### Comparison

| Feature | Argo CD | Flux |
|---------|---------|------|
| Web UI | ✅ built-in | ❌ use Weave GitOps |
| Multi-cluster | ✅ hub-spoke | ✅ hub-spoke |
| Image automation | ✅ via Image Updater | ✅ built-in |
| RBAC | ✅ rich | ✅ simpler |
| Notifications | ✅ built-in | ✅ via Notification Controller |
| Helm | ✅ | ✅ |
| Kustomize | ✅ | ✅ |
| Jsonnet | ✅ | ❌ |
| Helm values | ✅ | ✅ |
| OCI registry | ✅ | ✅ |
| App of Apps | ✅ | ✅ (Kustomization) |
| Sync waves | ✅ | ✅ (dependsOn) |
| Drift detection | ✅ | ✅ |
| Resource hooks | ✅ | ❌ |
| Multi-tenancy | ✅ Projects | ✅ namespaces |

**For most teams:** Argo CD has better UX, Flux has better GitOps principles. Both work.

## The repository structure

A GitOps repo is structured around apps and environments.

### Pattern 1: one repo per app (simple)

```
my-app/
├── base/                    # common manifests
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
└── overlays/                # env-specific
    ├── dev/
    │   ├── kustomization.yaml
    │   └── patch-replicas.yaml
    ├── staging/
    │   ├── kustomization.yaml
    │   └── patch-resources.yaml
    └── prod/
        ├── kustomization.yaml
        ├── patch-replicas.yaml
        └── patch-resources.yaml
```

**One repo per app.** Each app has its own git history, RBAC, etc. Easy for app teams to own.

### Pattern 2: monorepo (centralized)

```
gitops/
├── apps/
│   ├── my-app/
│   │   ├── base/
│   │   └── overlays/
│   └── other-app/
├── infrastructure/
│   ├── cert-manager/
│   ├── ingress-nginx/
│   └── monitoring/
└── clusters/
    ├── dev/
    │   ├── apps.yaml       # which apps run in dev
    │   └── infra.yaml
    └── prod/
        ├── apps.yaml
        └── infra.yaml
```

**One repo for everything.** Easier to manage at scale, but more access control complexity.

### Pattern 3: environment-per-repo (separation of concerns)

```
gitops-dev/
└── apps/
gitops-staging/
└── apps/
gitops-prod/
└── apps/
```

**One repo per environment.** Strongest separation, but most overhead.

### When to use which

| Pattern | Best for |
|---------|----------|
| App-per-repo | Small orgs, independent apps |
| Monorepo | Platform team owns ops, app teams contribute |
| Env-per-repo | Strict change control, audit requirements |

## The reconciliation model

GitOps controllers continuously reconcile:

```
git commit  →  desired state in git
                 ↓
controller  →  reads git
                 ↓
controller  →  compares to cluster state
                 ↓
              diff exists?
              ├── no   →  done
              └── yes  →  apply desired state
                             ↓
                          health check
                             ↓
                          success?
                          ├── yes  →  done
                          └── no   →  retry / alert
```

**Self-healing:** if someone changes the cluster manually, the controller reverts. This is the key value of GitOps.

## Sync options

### Manual vs auto sync

```yaml
# manual sync
syncPolicy:
  automated: null   # requires manual click / API call
# OR
syncPolicy: {}      # no automated block, defaults to manual

# auto sync
syncPolicy:
  automated:
    prune: true      # delete resources removed from git
    selfHeal: true   # revert manual changes
    allowEmpty: false
```

**Manual sync** — the controller shows you the diff, you click sync. Safer for prod.

**Auto sync** — the controller applies changes without intervention. Faster, but risk of unintended changes.

**Prune** — when you remove a resource from git, it's also removed from the cluster.

**Self-heal** — when someone manually changes the cluster, the controller reverts.

### Sync waves

For ordered deployments:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"  # applied first
```

Higher numbers applied later. Use this for:
- Database migrations before app
- App before monitoring
- ConfigMaps before Pods

### Resource hooks

```yaml
metadata:
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
```

Hooks let you run a Job before/after sync (e.g., DB migration, cache invalidation).

### Retry and backoff

```yaml
syncPolicy:
  retry:
    limit: 5
    backoff:
      duration: 5s
      factor: 2
      maxDuration: 3m
```

**For flaky resources:** the controller retries. Useful for Jobs.

## Drift detection

The controller periodically (3-5 min) checks if cluster matches git. If drifted:

1. **Argo CD:** shows "OutOfSync" status, can be configured to alert
2. **Flux:** reconcile reverts to git state

```bash
# manually check for drift
argocd app diff my-app
```

**Drift sources:**
- Manual `kubectl apply`
- A different controller modifying the resource
- A bug in the GitOps controller

**Drift is bad** — it means the cluster state doesn't match what's documented. Investigate root cause.

## Secrets in GitOps

The classic problem: secrets shouldn't be in plain git.

### Solution 1: sealed-secrets

```bash
# install kubeseal
brew install kubeseal

# fetch the public key
kubeseal --fetch-cert \
  --controller-name=sealed-secrets \
  --controller-namespace=kube-system \
  > pub-cert.pem

# encrypt a secret
kubectl create secret generic my-secret \
  --from-literal=password=secretvalue \
  --dry-run=client -o yaml | \
  kubeseal --cert pub-cert.pem -o yaml > my-sealed-secret.yaml
```

The sealed secret is in git. The cluster's controller decrypts it.

**Pros:** simple, works with any GitOps controller
**Cons:** encrypted to a specific cluster, can't move between clusters

### Solution 2: external-secrets

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-secret
spec:
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: my-secret
  data:
  - secretKey: password
    remoteRef:
      key: my-app/prod/password
```

The controller reads from AWS Secrets Manager / Vault / etc. and creates a k8s Secret.

**Pros:** real secret store, rotation, audit
**Cons:** operator required, more complex

### Solution 3: SOPS

```bash
# install sops
brew install sops

# encrypt a secret
sops --encrypt --age <public-key> secret.yaml > secret.enc.yaml

# decrypt
sops --decrypt secret.enc.yaml
```

Encrypted YAML in git. The operator decrypts.

**Pros:** works with any controller
**Cons:** asymmetric encryption keys need management

### Solution 4: External Secret Operator (ESO)

The most production-ready for cloud-managed secrets.

See [[Kubernetes/guides/non-functional/security-baseline|security-baseline]] for the full secret management guide.

## Image automation

The hardest part of GitOps: how does the image tag in git get updated when a new image is built?

### Pattern 1: CI updates git

```bash
# in CI
git clone gitops-repo
sed -i 's|image: myapp:.*|image: myapp:'"$TAG"'|' apps/my-app/overlays/prod/kustomization.yaml
git commit -m "bump myapp to $TAG"
git push
```

CI has push access to the GitOps repo. Simple, works with any controller.

**Cons:** CI has production access, audit log noise.

### Pattern 2: Image updater (Argo CD)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  annotations:
    argocd-image-updater.argoproj.io/image-list: myapp=myregistry/myapp
    argocd-image-updater.argoproj.io/myapp.update-strategy: latest
spec:
  # ...
```

The Image Updater watches the registry, finds new tags, opens a PR (or commits).

**Pros:** no CI access needed, automation
**Cons:** additional controller

### Pattern 3: Flux Image Automation

Flux has built-in image automation:

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: my-app
spec:
  image: myregistry/myapp
  interval: 1m
---
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImagePolicy
metadata:
  name: my-app
spec:
  imageRepositoryRef:
    name: my-app
  policy:
    semver:
      range: 1.0.x
```

Flux updates the manifest in-cluster (or commits to git, your choice).

## Multi-cluster GitOps

The cluster topology question.

### Hub-spoke

```
┌────────────────┐
│  Hub cluster   │
│  (Argo CD)     │
│                │
│  connects to:  │
│  - prod-us     │
│  - prod-eu     │
│  - staging     │
│  - dev         │
└────────────────┘
```

One cluster runs the GitOps controller. Other clusters are connected to it.

**Pros:** single pane of glass, single set of credentials
**Cons:** hub cluster is critical

### Per-cluster

Each cluster has its own Argo CD / Flux.

**Pros:** no single point of failure, simpler blast radius
**Cons:** multiple UIs to manage, harder to see at scale

### AppSets and multi-tenancy

Argo CD ApplicationSets let you define one template, generate many apps:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: my-app-all-clusters
spec:
  generators:
  - list:
      elements:
      - cluster: prod-us
        url: https://prod-us.example.com
      - cluster: prod-eu
        url: https://prod-eu.example.com
  template:
    metadata:
      name: '{{cluster}}-my-app'
    spec:
      project: default
      source:
        repoURL: https://github.com/myorg/my-app
        targetRevision: HEAD
        path: overlays/{{cluster}}
      destination:
        server: '{{url}}'
```

One ApplicationSet, one source, N applications across clusters.

## Progressive delivery with GitOps

GitOps + progressive delivery = safe rollouts.

### Argo Rollouts

Replaces Deployments with Rollouts. Supports canary, blue-green, traffic shifting.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: my-app
spec:
  replicas: 5
  strategy:
    canary:
      steps:
      - setWeight: 10
      - pause: {duration: 5m}
      - setWeight: 50
      - pause: {duration: 5m}
      - setWeight: 100
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: myregistry/myapp:v1
```

See [[Kubernetes/guides/delivery/progressive-delivery/argo-rollouts|argo-rollouts]] for full details.

### Flagger

Flux-native progressive delivery.

```yaml
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: my-app
spec:
  provider: istio
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  progressDeadlineSeconds: 60
  canaryAnalysis:
    interval: 30s
    threshold: 5
    metrics:
    - name: request-success-rate
      thresholdRange:
        min: 99
    - name: request-duration
      thresholdRange:
        max: 500
```

Flagger uses Istio/Linkerd/App Mesh for traffic splitting.

## Common GitOps pitfalls

1. **CI pushing to cluster.** Defeats the purpose. CI updates git, controller applies.
2. **Long-lived credentials in GitOps controller.** Use OIDC / workload identity.
3. **No drift detection.** If someone uses kubectl, the controller should alert.
4. **Secrets in plain text.** Use sealed-secrets, SOPS, or external secret operators.
5. **No review process for git changes.** A bot that auto-commits can break prod.
6. **Sync waves in wrong order.** App before DB.
7. **Auto-prune enabled in dev.** Destructive when developing.
8. **No rollback procedure.** `git revert` is the rollback.
9. **Massive monorepo with no clear ownership.** Every team can break every team.
10. **GitOps controller as single point of failure.** Hub cluster down = no updates anywhere.

## GitOps for cluster add-ons

Same pattern, different scope:

```yaml
# infrastructure repo
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
spec:
  source:
    repoURL: https://charts.jetstack.io
    chart: cert-manager
    targetRevision: v1.14.0
  destination:
    server: https://kubernetes.default.svc
```

Same GitOps flow, but for cluster components (CNI, ingress, cert-manager, etc.).

## Common gotchas

* **Argo CD and the cluster-admin role.** The controller needs broad access to apply manifests. Restrict to specific namespaces / projects.
* **Flux with the GitOps Toolkit is more verbose than Argo CD.** Trade-off: more flexibility, more yaml.
* **Image updater can spam PRs** if you use floating tags (latest, semver ranges).
* **Sync windows (e.g., "no syncs on Friday")** can delay fixes. Use sparingly.
* **Multi-cluster with cluster-scoped resources** needs careful RBAC. Avoid cluster-scoped when possible.
* **Helm values in GitOps** — different controllers handle them differently. Argo CD has values files, Flux has Kustomization.
* **Manifests with side-effects** (e.g., creating a database) are dangerous in GitOps. Use a separate process for one-time infra.
* **The cluster that runs the GitOps controller** — is it a "trick question" if it's not in git? Use GitOps for the GitOps controller too.
* **GitOps != no CI.** You still need CI for tests, builds, image scans. GitOps handles deployment only.

## A worked example

**Goal:** deploy a stateless web service via GitOps, with auto-sync to dev, manual sync to prod, image automation, and secrets in external store.

**Setup:**

1. **Two repos:**
   - `my-app` (code, CI builds images)
   - `my-app-gitops` (manifests, GitOps deploys)

2. **CI (GitHub Actions):**
   - On push to main: test, build, push to ECR
   - Updates `my-app-gitops` overlay with new tag
   - Opens PR if dev, auto-merge
   - Opens PR for staging/prod (manual approval)

3. **Argo CD:**
   - Connects to `my-app-gitops` repo
   - Two Applications: `my-app-dev`, `my-app-prod`
   - dev: auto-sync, prune, self-heal
   - prod: manual sync, with notifications

4. **Secrets:**
   - External Secrets Operator reads from AWS Secrets Manager
   - Creates k8s Secret at sync time

5. **RBAC:**
   - Argo CD's ServiceAccount has admin in `my-app` namespace
   - No access to kube-system or other namespaces

**On push to main:**
1. CI builds image `myregistry/myapp:v123`
2. CI updates `overlays/dev/kustomization.yaml` to `v123`
3. Argo CD detects change, syncs
4. New pods roll out
5. Argo CD's notification fires: "dev deployment complete"
6. Engineer sees, opens PR to update staging tag to `v123`
7. After PR merge + manual sync: staging rolls out
8. Same for prod (with canary via Argo Rollouts)

**Total time from merge to dev:** 2-5 minutes
**Manual approval gates:** staging and prod

## See also

* [[Kubernetes/guides/delivery/templating-patching/kustomize|kustomize]] — patching layered with GitOps
* [[Kubernetes/guides/delivery/templating-patching/helm/cicd|helm-cicd]] — Helm in GitOps
* [[Kubernetes/guides/delivery/pipeline-workflows/argo-workflows|argo-workflows]] — CI for image builds
* [[Kubernetes/guides/delivery/progressive-delivery/argo-rollouts|argo-rollouts]] — safe rollouts
* [[Kubernetes/guides/non-functional/oidc-integration|oidc-integration]] — auth for the controller
