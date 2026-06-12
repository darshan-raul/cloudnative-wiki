---
title: Kustomize
tags:
  - Kubernetes
  - Templating
  - Kustomize
  - Patching
---

Kustomize is the **declarative, template-free** way to manage k8s manifests. It overlays patches on top of base manifests, no templating language needed. Built into `kubectl`, supported by every GitOps controller, and almost always the right choice for "I need different configs per environment."

## The problem it solves

You have the same Deployment running in dev, staging, and prod. They differ in:
- Number of replicas (1 / 2 / 5)
- Image tag (`:dev` / `:staging` / `:v1.2.3`)
- Resource limits
- Environment variables
- Ingress hostnames

**Naive solution:** maintain 3 copies of the Deployment. Drift. Pain.

**Helm solution:** one template, three values files. Powerful but templates are complex (Go template language, lots of logic).

**Kustomize solution:** one base, three overlays. **No templating language.** Pure yaml patches.

## The structure

```
my-app/
├── base/                        # the source of truth
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   ├── kustomization.yaml       # the base kustomization
│   └── namespace.yaml
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml   # the dev overlay
    │   ├── patch-replicas.yaml
    │   └── patch-resources.yaml
    ├── staging/
    │   ├── kustomization.yaml
    │   └── patch-configmap.yaml
    └── prod/
        ├── kustomization.yaml
        ├── patch-replicas.yaml
        ├── patch-resources.yaml
        ├── patch-hpa.yaml
        └── ingress.yaml
```

**The base is unchanged across environments.** The overlays add/transform.

## The base

```yaml
# base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- deployment.yaml
- service.yaml
- configmap.yaml
- namespace.yaml

# common labels added to all resources
labels:
- includeSelectors: false
  pairs:
    app.kubernetes.io/name: my-app
    app.kubernetes.io/managed-by: kustomize

# common annotations
annotations:
  contact: ops@example.com
```

```yaml
# base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3
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
        image: myregistry/myapp:latest
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        envFrom:
        - configMapRef:
            name: my-app-config
```

## The overlays

### Dev overlay

```yaml
# overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: dev   # all resources go in dev namespace

resources:
- ../../base

# patch the deployment
patches:
- path: patch-replicas.yaml
- path: patch-resources.yaml
- path: patch-image.yaml

# override the configmap
configMapGenerator:
- name: my-app-config
  behavior: merge
  literals:
  - LOG_LEVEL=debug
  - ENVIRONMENT=dev
```

```yaml
# overlays/dev/patch-replicas.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 1   # dev runs 1 replica
```

```yaml
# overlays/dev/patch-resources.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
      - name: my-app
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 256Mi
```

```yaml
# overlays/dev/patch-image.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
      - name: my-app
        image: myregistry/myapp:dev
```

### Prod overlay

```yaml
# overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: prod

resources:
- ../../base
- ingress.yaml    # prod-specific

patches:
- path: patch-replicas.yaml
- path: patch-resources.yaml
- path: patch-image.yaml
- path: patch-hpa.yaml

configMapGenerator:
- name: my-app-config
  behavior: merge
  literals:
  - LOG_LEVEL=info
  - ENVIRONMENT=prod
```

## Patches

Patches are the heart of kustomize. Three types:

### Strategic merge patch (default)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 5
```

Merges with the base. Lists are merged by name.

### JSON merge patch (RFC 7396)

```yaml
- op: replace
  path: /spec/replicas
  value: 5
```

JSON-patch syntax. Use when you need precise control.

### JSON patch (RFC 6902)

```yaml
- op: add
  path: /spec/template/spec/containers/0/env
  value:
  - name: NEW_VAR
    value: newvalue
```

Most precise. Useful for adding to lists.

## Common operations

### Add a label to all resources

```yaml
labels:
- includeSelectors: true
  pairs:
    environment: prod
    cost-center: engineering
```

`includeSelectors: true` also adds to selector fields (so the label is in the matchLabels).

### Override the namespace

```yaml
namespace: prod
```

All resources get the `prod` namespace.

### Override the name prefix

```yaml
namePrefix: prod-
```

`my-app` becomes `prod-my-app`. Useful for shared clusters.

### Override the name suffix

```yaml
nameSuffix: -v1
```

`my-app` becomes `my-app-v1`.

### Image transformation

```yaml
images:
- name: myregistry/myapp   # match the base image
  newName: myregistry/myapp-prod
  newTag: v1.2.3
```

Useful in CI: set the image tag dynamically without patching the deployment.

### ConfigMap / Secret generation

```yaml
configMapGenerator:
- name: my-app-config
  literals:
  - KEY=value
  files:
  - config.json

secretGenerator:
- name: my-app-secret
  literals:
  - password=secret
  type: Opaque
```

Generates a new ConfigMap/Secret with a hash suffix. When the contents change, the hash changes, triggering a rolling update.

**Disable hashing** (if you have a hardcoded reference):

```yaml
generatorOptions:
  disableNameSuffixHash: true
```

### Common labels and annotations

```yaml
commonLabels:
  app: my-app
  environment: prod

commonAnnotations:
  owner: ops@example.com
  runbook: https://wiki.example.com/runbooks/my-app
```

### Patch with reference

```yaml
patches:
- target:
    group: apps
    version: v1
    kind: Deployment
    name: my-app
  patch: |-
    - op: replace
      path: /spec/replicas
      value: 5
```

### Components (reusable pieces)

```yaml
# components/monitoring.yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component

resources:
- servicemonitor.yaml
- prometheusrule.yaml
```

```yaml
# overlay
components:
- ../components/monitoring
```

Reusable across many apps.

## The kustomize CLI

### Build and view output

```bash
# build and print the result
kubectl kustomize overlays/prod

# apply directly
kubectl apply -k overlays/prod

# build with a specific file
kustomize build overlays/prod
```

### Edit a resource

```bash
# set an image
kustomize edit set image myregistry/myapp=myregistry/myapp:v1.2.3

# set a namespace
kustomize edit set namespace prod

# add a label
kustomize edit add label environment:prod

# add a resource
kustomize edit add resource deployment.yaml
```

These edit the kustomization.yaml file in place.

## Kustomize in CI/CD

### Image tag injection in CI

```bash
# in CI
cd overlays/prod
kustomize edit set image myregistry/myapp=myregistry/myapp:$BUILD_TAG
git commit -am "bump to $BUILD_TAG"
git push
```

The CI doesn't patch the deployment — it patches the kustomization. The git diff is reviewable.

### Generate manifests in CI

```bash
# generate the final manifests
kustomize build overlays/prod > /tmp/manifests.yaml

# (or apply directly)
kubectl apply -k overlays/prod

# validate
kubectl apply -k overlays/prod --dry-run=server
```

### Diff between environments

```bash
# diff dev vs prod
diff <(kustomize build overlays/dev) <(kustomize build overlays/prod)
```

Useful for auditing what differs.

## Kustomize in GitOps

Argo CD and Flux both support kustomize natively.

### Argo CD

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app-prod
spec:
  source:
    repoURL: https://github.com/myorg/my-app
    path: overlays/prod
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: prod
```

Argo CD runs `kustomize build` on the path. No need to commit generated manifests.

### Flux

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: my-app-prod
spec:
  path: ./overlays/prod
  interval: 10m
  prune: true
  sourceRef:
    kind: GitRepository
    name: my-app
```

Flux's Kustomization CRD is essentially `kustomize build` + apply.

## Kustomize vs Helm

| Use case | Kustomize | Helm |
|----------|-----------|------|
| Plain yaml, just config diffs | ✅ best | Overkill |
| Templating, logic, conditionals | ❌ not great | ✅ best |
| Library reuse | Components | Library charts |
| Package distribution | ❌ not for that | ✅ OCI registries |
| Operator-friendly | ✅ | ✅ |
| Built into kubectl | ✅ | ❌ separate CLI |
| GitOps | ✅ | ✅ (with values) |
| Learning curve | Low | Medium-High |
| Industry adoption | High | Very High |

**Use Kustomize** when you have a base manifest and need environment-specific overlays.

**Use Helm** when you need templating, packaging, or a major project (Prometheus, cert-manager, etc.).

**Use both:** Helm for cluster components (CNI, ingress), Kustomize for app overlays.

## Common gotchas

* **Patches need the right `apiVersion` and `kind`.** Mismatches silently fail.
* **`configMapGenerator` adds a hash suffix** to the name. Update the references.
* **`patchesStrategicMerge` is deprecated** in favor of `patches` with strategic merge syntax.
* **`includeSelectors: true`** is needed for some labels (e.g., in `spec.selector.matchLabels`).
* **Order matters** in `resources:` — kustomize processes them in order, and some operations depend on the result of others.
* **Multi-document YAML** in resources needs `---` separators.
* **Kustomize is pure yaml** — no logic, no loops. If you need logic, use Helm.
* **Image transformations** require the image name to match exactly.
* **Generated Secrets/ConfigMaps** are immutable by default. Use `generatorOptions: { disableNameSuffixHash: false }` to keep updates working.
* **Patches in separate files** are easier to read. Don't put all patches inline.
* **`namespace:` is set on the overlay**, not the base. The base is namespace-agnostic.
* **The `kustomize` CLI is separate from `kubectl kustomize`.** Use the standalone for full features; kubectl's built-in is missing some.

## The "I have 50 overlays" anti-pattern

If you find yourself with 50 overlays, you're using kustomize wrong.

**Better:** fewer overlays with components.

```yaml
# overlays/prod/kustomization.yaml
components:
- ../../components/monitoring
- ../../components/security-baseline
- ../../components/production-tuning
- ../../components/ingress-public

resources:
- ../../base
```

**Components** are reusable, parameterizable pieces. They replace the copy-paste of overlays.

## A worked example

**Goal:** a web service with:
- Different replicas/resources per env
- Different config (log level, DB connection)
- Production has HPA, ingress, monitoring
- Dev has 1 replica, no HPA
- Common monitoring and security across all envs

**Structure:**

```
my-app/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   └── serviceaccount.yaml
├── components/
│   ├── monitoring.yaml
│   │   ├── kustomization.yaml
│   │   ├── servicemonitor.yaml
│   │   └── prometheusrule.yaml
│   ├── security-baseline.yaml
│   │   ├── kustomization.yaml
│   │   ├── networkpolicy.yaml
│   │   └── podsecuritycontext.yaml
│   └── production-tuning.yaml
│       ├── kustomization.yaml
│       ├── pdb.yaml
│       └── topology-spread.yaml
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml
    │   ├── patch-replicas.yaml
    │   └── patch-config.yaml
    ├── staging/
    │   ├── kustomization.yaml
    │   ├── patch-replicas.yaml
    │   └── patch-config.yaml
    └── prod/
        ├── kustomization.yaml
        ├── patch-replicas.yaml
        ├── patch-config.yaml
        ├── patch-image.yaml
        ├── hpa.yaml
        └── ingress.yaml
```

**Dev:**

```yaml
# overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: dev
resources:
- ../../base
components:
- ../../components/monitoring
- ../../components/security-baseline
patches:
- path: patch-replicas.yaml
- path: patch-config.yaml
configMapGenerator:
- name: my-app-config
  behavior: merge
  literals:
  - LOG_LEVEL=debug
  - DB_HOST=db.dev.example.com
```

**Prod:**

```yaml
# overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: prod
resources:
- ../../base
- hpa.yaml
- ingress.yaml
components:
- ../../components/monitoring
- ../../components/security-baseline
- ../../components/production-tuning
patches:
- path: patch-replicas.yaml
- path: patch-config.yaml
- path: patch-image.yaml
images:
- name: myregistry/myapp
  newName: myregistry/myapp
  newTag: v1.2.3
configMapGenerator:
- name: my-app-config
  behavior: merge
  literals:
  - LOG_LEVEL=info
  - DB_HOST=db.prod.example.com
```

**Build prod:**

```bash
kustomize build overlays/prod
```

**Apply:**

```bash
kubectl apply -k overlays/prod
```

## See also

* [[Kubernetes/guides/delivery/templating-patching/helm/cicd|helm-cicd]] — when to use Helm instead
* [[Kubernetes/guides/delivery/gitops/basics|gitops-basics]] — kustomize + GitOps
* [Kustomize docs](https://kubectl.docs.kubernetes.io/references/kustomize/)
* [Kustomize cheatsheet](https://kubectl.docs.kubernetes.io/references/kustomize/cheatsheet/)
