# CustomResourceDefinitions (CRDs)

>*"https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/"*

A CRD is how you **add a new object type to the Kubernetes API**. Once registered, your custom resource is first-class — `kubectl get` it, apply RBAC to it, watch it like any other object. The CRD just defines the schema; a controller (or operator) does the actual work.

## Table of Contents

1. [The point](#1-the-point)
2. [Minimal CRD anatomy](#2-minimal-crd-anatomy)
3. [Versions, served, and storage](#3-versions-served-and-storage)
4. [Schema validation](#4-schema-schema)
5. [Subresources: status and scale](#5-subresources-status-and-scale)
6. [Additional printer columns](#6-additional-printer-columns)
7. [Categories and short names](#7-categories-and-short-names)
8. [Cluster-scoped vs namespaced](#8-cluster-scoped-vs-namespaced)
9. [Webhook conversions](#9-webhook-conversions)
10. [The controller pattern](#10-the-controller-pattern)
11. [CRDs vs aggregated API servers](#11-crds-vs-aggregated-api-servers)
12. [ kubectl plugin ecosystem](#12-kubectl-plugin-ecosystem)
13. [CEL validation (k8s 1.25+)](#13-cel-validation-k8s-125)
14. [Default values and prune](#14-default-values-and-prune)
15. [Field selectors and label selectors](#15-field-selectors-and-label-selectors)
16. [CRD field reference](#16-crd-field-reference)
17. [Operations checklist](#17-operations-checklist)
18. [Gotchas](#18-gotchas)

---

### 1. The point

Built-in k8s objects (Pod, Service, ConfigMap) cover the basics. CRDs let you extend the API with your own types:

| Use case | Example CRs |
|----------|-------------|
| Application infra | `Redis`, `PostgresCluster`, `Kafka`, `MySQL` |
| Platform primitives | `IngressRoute`, `Gateway`, `Certificate`, `Tenant` |
| GitOps / delivery | `AppProject`, `Application`, `Pipeline` |
| Policy | `Policy`, `ComplianceReport`, `SecurityBaseline` |
| Infra | `Machine`, `MachineSet`, `Cluster` (capm3, EKS Blueprints) |

Without CRDs, you'd use a separate database or config store — and lose kubectl, RBAC, the watch loop, and every tool that understands k8s objects.

---

### 2. Minimal CRD anatomy

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: crontabs.stable.example.com
spec:
  group: stable.example.com          # API group: /apis/<group>/<version>
  names:
    plural: crontabs                  # URL path: /apis/stable.example.com/v1/crontabs
    singular: crontab
    shortNames: [ct]                 # kubectl get ct
    kind: CronTab                    # Go type name (PascalCase)
    listKind: CronTabList            # List type name
    categories: [all]                # kubectl get all (groups this with built-ins)
  scope: Namespaced                  # or Cluster (like Node / PersistentVolume)
  versions:
  - name: v1
    served: true                     # serve this version via the API
    storage: true                   # use this version for persistence in etcd
    schema:                         # OpenAPI v3 validation (required in v1)
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              cronSpec:
                type: string
              image:
                type: string
              replicas:
                type: integer
                minimum: 1
                maximum: 10
```

After apply:

```bash
kubectl get crontabs              # or: kubectl get ct
kubectl api-resources | grep crontab
# crontabs     stable.example.com/v1     true    CronTab
```

---

### 3. Versions, served, and storage

A CRD can have multiple versions. Common reasons:

- **Migrate the schema** — add a field, remove a field, change semantics
- **Support API consumers** — old clients use `v1alpha1`, new clients use `v1`

The `storage: true` version is the **one version that actually gets written to etcd**. All served versions must round-trip through it.

```
v1alpha1 ←→ storage (v1)  ←→ v1
```

If you change the stored representation, you need a **conversion webhook** (see section 9).

#### Versioning rules

- `served: true` — the API serves this version. Clients can request it.
- `storage: true` — exactly ONE version. This is what's persisted.
- You can serve multiple versions but store only one.
- Dropping a served version is a breaking change — existing clients break.

```yaml
versions:
  - name: v1
    served: true
    storage: true      # this one is written to etcd
  - name: v1beta1
    served: true
    storage: false     # not persisted
  - name: v1alpha1
    served: false      # hidden from discovery
    storage: false
```

---

### 4. Schema

The `openAPIV3Schema` validates objects at admission time. If validation fails, the object is rejected — **before it hits etcd**.

```yaml
schema:
  openAPIV3Schema:
    type: object
    required: [spec]               # required top-level fields
    properties:
      apiVersion:
        type: string
        description: APIVersion of the resource
      kind:
        type: string
      metadata:
        type: object
        properties:
          name:
            type: string
            maxLength: 63
            pattern: '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$'
          labels:
            type: object
            additionalProperties:
              type: string
      spec:
        type: object
        required: [image]
        properties:
          replicas:
            type: integer
            minimum: 1
            maximum: 100
            default: 1              # default if not specified
          image:
            type: string
            pattern: '^[a-z0-9.-]+/[a-z0-9./-:]+$'
          env:
            type: array
            items:
              type: object
              properties:
                name:
                  type: string
                value:
                  type: string
          resources:
            type: object
            properties:
              requests:
                type: object
                additionalProperties:
                  type: string
              limits:
                type: object
                additionalProperties:
                  type: string
          port:
            type: integer
            minimum: 1
            maximum: 65535
            default: 8080
```

The schema **cannot validate across objects**. It can't check "this ConfigMap exists" or "replicas ≤ cluster node count". For that, you need a **validating admission webhook**.

---

### 5. Subresources: status and scale

#### Status subresource

Separates `.spec` (desired state, set by user) from `.status` (observed state, set by controller). Enables the standard reconciliation loop pattern:

```yaml
versions:
  - name: v1
    served: true
    storage: true
    subresources:
      status: {}                    # enables .status on the CR
```

Without `subresources: status`, any change to `.status` is treated as a change to `.spec` and triggers a full reconciliation — causing loops.

#### Scale subresource

Lets HPA scale your custom resource:

```yaml
versions:
  - name: v1
    served: true
    storage: true
    subresources:
      scale:
        labelSelectorPath: .status.labelSelector
        specReplicasPath: .spec.replicas
        statusReplicasPath: .status.replicas
```

```bash
kubectl scale my-crontab --replicas=5   # works if the scale subresource is defined
kubectl get hpa                          # HPA can target my-crontab
```

---

### 6. Additional printer columns

Controls what `kubectl get` shows:

```yaml
additionalPrinterColumns:
  - name: Schedule
    type: string
    jsonPath: .spec.cronSpec
    description: The cron schedule
    priority: 0                         # 0 = standard column, 1 = wide-only
  - name: Replicas
    type: integer
    jsonPath: .spec.replicas
  - name: Age
    type: date
    jsonPath: .metadata.creationTimestamp
  - name: Status
    type: string
    jsonPath: .status.phase
    priority: 1                        # hidden in kubectl (wide only)
```

Priority `0` shows in `kubectl get` by default. Priority `1` shows only with `kubectl get -o wide`.

---

### 7. Categories and short names

```yaml
names:
  plural: crontabs
  singular: crontab
  shortNames: [ct]
  kind: CronTab
  listKind: CronTabList
  categories: [all, example]         # kubectl get all, kubectl get example
```

```bash
kubectl get all                           # includes crontabs if in "all"
kubectl get ct                            # short name
kubectl api-resources                    # shows all registered
```

---

### 8. Cluster-scoped vs namespaced

```yaml
scope: Namespaced        # like Deployment, lives in a namespace
scope: Cluster           # like Node, ClusterRole, PersistentVolume — cluster-wide
```

| Scope | RBAC verb | Default namespace |
|-------|-----------|-------------------|
| Namespaced | `get`, `list`, `watch`, `create`, `delete`, `deletecollection`, `patch`, `update` in a namespace | Yes |
| Cluster | Same verbs, no namespace | N/A (no namespace) |

```yaml
# Cluster-scoped: no namespace in metadata
apiVersion: stable.example.com/v1
kind: Zoo
metadata:
  name: my-zoo          # name must be unique cluster-wide
spec:
  capacity: 100
```

---

### 9. Webhook conversions

When you change the stored representation (rename a field, restructure), you need a **conversion webhook** to translate between versions.

#### No conversion (default — single version)

```yaml
# if you only have one version and never change it
# nothing needed — CRD works as-is
```

#### With conversion webhook

```yaml
spec:
  conversion:
    strategy: Webhook
    webhook:
      conversionReviewVersions: [v1, v1beta1]   # CRD calls your webhook with these
      clientConfig:
        service:
          name: my-crd-converter
          namespace: default
          path: /convert
        caBundle: <base64-CA>
```

Your webhook receives the object in the **storage version** and returns it in the requested version:

```json
// Request to /convert
{
  "apiVersion": "admission.k8s.io/v1",
  "kind": "ConversionReview",
  "request": {
    "uid": "...",
    "desiredApiVersion": "stable.example.com/v1alpha1",
    "objects": [
      { "apiVersion": "stable.example.com/v1", "kind": "CronTab", ... }
    ]
  }
}

// Response
{
  "apiVersion": "admission.k8s.io/v1",
  "kind": "ConversionReview",
  "response": {
    "uid": "<same-uid>",
    "convertedObjects": [
      { "apiVersion": "stable.example.com/v1alpha1", "kind": "CronTab",
        "spec": { "cronSpec": "0 * * * *" } }   // converted to v1alpha1 shape
    ],
    "result": { "status": "Success" }
  }
}
```

The conversion is bidirectional: your webhook must handle `v1 → v1alpha1` and `v1alpha1 → v1`.

#### Conversion strategies compared

| Strategy | Use when |
|----------|----------|
| None (default) | Single version only |
| Webhook | Schema changes between multiple served versions |

---

### 10. The controller pattern

A CRD without a controller is just dead data. The controller:

1. **Watches** the CR instances
2. **Reconciles** — compares desired (`.spec`) vs actual (`.status`)
3. **Updates `.status`** — reports what it did
4. **Owns child resources** — creates/updates/deletes dependent objects

```go
// Reconcile loop skeleton
func (r *CronTabReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    // Fetch the CR
    ct := &stablev1.CronTab{}
    if err := r.Get(ctx, req.NamespacedName, ct); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)
    }

    // Reconcile
    if err := r.reconcileCronJob(ctx, ct); err != nil {
        r.updateStatus(ctx, ct, err)
        return ctrl.Result{}, err
    }

    // Update status
    ct.Status.Phase = "Running"
    ct.Status.Replicas = *ct.Spec.Replicas
    return ctrl.Result{}, r.Status().Update(ctx, ct)
}
```

Frameworks: **Kubebuilder** and **Operator SDK** both scaffold CRD + controller projects. See [[Kubernetes/concepts/L09-advanced/01-operators|Operators]] and [[Kubernetes/concepts/L09-advanced/02-custom-controllers|Custom Controllers]].

---

### 11. CRDs vs aggregated API servers

| | CRD | Aggregated API Server |
|---|---|---|
| Storage | etcd (via kube-apiserver) | Custom (you choose) |
| Served by | kube-apiserver | Separate pod |
| Authentication | RBAC, same as k8s | Custom or delegated |
| Schema | OpenAPI v3 | Protobuf / OpenAPI |
| Performance | Good for low/moderate volume | Better for very high QPS |
| Operational burden | Low | High — run a full API server |
| When to use | 99% of cases | When you need a different storage backend, custom auth, or subresources |

**Start with CRDs.** Move to aggregated API servers when CRDs genuinely can't do what you need.

---

### 12. kubectl plugin ecosystem

CRDs can be extended with kubectl plugins. The standard approach:

```bash
# kubectl plugin: kubectl-<resource>
# e.g., kubectl-grpc for querying CRD schemas
# Or wrap your operator's CLI as a plugin:
mv my-operatorctl /usr/local/bin/kubectl-my_operator
chmod +x /usr/local/bin/kubectl-my_operator
kubectl my_operator help              # "kubectl <plugin_name>" calls it
```

---

### 13. CEL validation (k8s 1.25+)

Since k8s 1.25, CRDs support Common Expression Language (CEL) for validation, replacing the older webhook-based validation for many cases:

```yaml
schema:
  openAPIV3Schema:
    type: object
    properties:
      spec:
        type: object
        properties:
          replicas:
            type: integer
            minimum: 1
            maximum: 100
          image:
            type: string
        validations:
          - rule: "self.replicas <= 50 || self.image.startsWith('prod-')"
            message: "replicas over 50 only allowed for prod images"
```

CEL rules are evaluated by the API server — no webhook needed for simple cross-field validation. For complex rules, a validating admission webhook is still required.

---

### 14. Default values and prune

#### Default values

```yaml
schema:
  openAPIV3Schema:
    type: object
    properties:
      spec:
        type: object
        properties:
          replicas:
            type: integer
            default: 1          # applied on CREATE if not specified
```

Defaults are set by the CRD admission plugin when `spec.preserveUnknownFields` is not used (deprecated in 1.16+).

#### Field pruning

By default, CRDs **prune unknown fields** — fields in the YAML that aren't in the schema are rejected or stripped:

```yaml
spec:
  preserveUnknownFields: false    # default — strips unknown fields on write
```

Set to `true` only if you need forward compatibility with future versions.

---

### 15. Field selectors and label selectors

Custom resources support **field selectors** if you add them to the CRD:

```yaml
schema:
  openAPIV3Schema:
    type: object
    properties:
      spec:
        type: object
        properties:
          image:
            type: string
```

```bash
# List where image = nginx
kubectl get crontabs --field-selector spec.image=nginx
```

Label selectors are always supported (standard k8s):

```bash
kubectl get crontabs -l app=my-app
```

---

### 16. CRD field reference

| Field | Required | Description |
|-------|----------|-------------|
| `spec.group` | Yes | API group, e.g. `stable.example.com` |
| `spec.names.plural` | Yes | URL-safe plural name |
| `spec.names.kind` | Yes | CamelCase type name |
| `spec.scope` | Yes | `Namespaced` or `Cluster` |
| `spec.versions[].name` | Yes | Version string, e.g. `v1`, `v1beta1` |
| `spec.versions[].served` | Yes | Whether to serve this version |
| `spec.versions[].storage` | Yes | Exactly one `true` — the stored version |
| `spec.versions[].schema` | Yes (v1) | OpenAPI v3 schema |
| `spec.versions[].subresources.status` | No | Enables `.status` |
| `spec.versions[].subresources.scale` | No | Enables HPA targeting |
| `spec.versions[].additionalPrinterColumns` | No | `kubectl get` column config |
| `spec.conversion.strategy` | No | `None` (default) or `Webhook` |
| `spec.names.shortNames` | No | Short aliases |
| `spec.names.categories` | No | Group with `kubectl get all` |
| `spec.names.listKind` | Yes | List type name |

---

### 17. Operations checklist

```bash
# Install a CRD
kubectl apply -f my-crd.yaml

# Verify it's registered
kubectl get crd
kubectl api-resources | grep <plural>

# Try to create an invalid object (should be rejected)
kubectl apply -f invalid-crontab.yaml
# Error: spec.replicas in body must be less than or equal to 10

# Watch all CR instances
kubectl get <plural> -w

# Delete all instances (dangerous — deletes all data)
kubectl delete <plural> --all

# Delete the CRD (also deletes all instances)
kubectl delete crd <name>
# Warning: this deletes all objects of this type

# Get the schema
kubectl get crd <name> -o yaml | yq '.spec.versions[0].schema'

# Check if it's established
kubectl get crd <name> -o jsonpath='{.status.conditions[?(@.type=="Established")].status}'
# True = API server has accepted the CRD

# Get raw from API server
kubectl get --raw /apis/stable.example.com/v1/crontabs
```

---

### 18. Gotchas

* **Once `Established`, removing a CRD deletes all instances.** The data is gone. Always back up before deleting.
* **`schema` is required in CRD v1** (`apiextensions.k8s.io/v1`, k8s 1.16+). Old `v1beta1` CRDs without a schema are rejected.
* **CRD validation happens at admission.** It won't catch relationships between objects (e.g. "this Secret must exist") — use a validating webhook for that.
* **A CRD defines a type; it doesn't do anything.** You need a controller/operator to act on CR instances.
* **`preserveUnknownFields: true` breaks schema evolution.** It allows fields not in the schema to be stored, making future schema changes harder. Avoid it.
* **Status updates without `subresources: status`** trigger a full spec reconciliation — controllers that update `.status` frequently can cause update storms.
* **Multiple CRD versions need a conversion webhook** to maintain data integrity. The webhook must be written and deployed.
* **`kubectl explain <kind>`** works for CRDs if the CRD has schema — gives you the field tree.
* **`kubectl get` columns come from `additionalPrinterColumns`**, not from the schema. Without it, `kubectl get` shows only NAME/AGE.
* **The `categories: [all]` trick** makes `kubectl get all` show your CRs — useful for GitOps tools that use `kubectl get all`.

---

## See also

* [[Kubernetes/concepts/L09-advanced/01-operators|Operators]] — CRD + controller + domain knowledge
* [[Kubernetes/concepts/L09-advanced/02-custom-controllers|Custom Controllers]] — the watch/reconcile loop
* [[Kubernetes/concepts/L09-advanced/07-aggregation-layer|Aggregation Layer]] — when CRDs aren't enough
* [[Kubernetes/concepts/L09-advanced/04-admission-controllers|Admission Controllers]] — for policies that should block/mutate CRs
