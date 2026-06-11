# Admission Controllers and Webhooks

>*"https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/"*

Admission controllers are **plugins that run in the API server** and can reject or mutate API requests **after authentication and authorization, before the object is stored in etcd**. They're how you enforce custom policy — and how built-in k8s features like ResourceQuota and PodSecurity actually work.

## Table of Contents

1. [The request flow](#1-the-request-flow)
2. [Mutating vs validating](#2-mutating-vs-validating)
3. [The built-in controllers](#3-the-built-in-controllers)
4. [Webhook configuration](#4-webhook-configuration)
5. [Mutating webhook examples](#5-mutating-webhook-examples)
6. [Validating webhook examples](#6-validating-webhook-examples)
7. [The AdmissionReview object](#7-the-admissionreview-object)
8. [Webhook ordering and mutating chains](#8-webhook-ordering-and-mutating-chains)
9. [failurePolicy and timeouts](#9-failurepolicy-and-timeouts)
10. [matchPolicy and rules](#10-matchpolicy-and-rules)
11. [Namespace/object selectors](#11-namespaceobject-selectors)
12. [sideEffects and dry-run](#12-sideeffects-and-dry-run)
13. [Tools that use webhooks](#13-tools-that-use-webhooks)
14. [Debugging webhook failures](#14-debugging-webhook-failures)
15. [When webhooks vs CRD controllers vs operators](#15-when-webhooks-vs-crd-controllers-vs-operators)
16. [Admission controllers in managed clusters](#16-admission-controllers-in-managed-clusters)
17. [The built-in admission chain (annotated)](#17-the-built-in-admission-chain-annotated)
18. [Gotchas](#18-gotchas)

---

### 1. The request flow

```
Client (kubectl, controller, SDK)
   │
   ▼
1. Authentication  — who are you? (certificates, tokens, OIDC, ...)
   │
   ▼
2. Authorization   — RBAC — can you do this operation?
   │
   ▼
3. Mutating Admission   ← can MODIFY the object
   │  (Webhook or built-in)
   │
   ▼
4. Validating Admission  ← can REJECT or APPROVE
   │  (Webhook or built-in)
   │
   ▼
5. Object written to etcd
```

Mutating webhooks run **before** validating webhooks. A request can hit multiple mutating webhooks (in sequence), then all validating webhooks (in parallel). Mutating webhooks can be **re-run** after a change — if a mutating webhook modifies an object, other mutating webhooks get the modified version.

---

### 2. Mutating vs validating

| | Mutating | Validating |
|---|---|---|
| Can modify object | ✅ Yes | ❌ No |
| Can reject request | ✅ Yes | ✅ Yes |
| Can approve request | ✅ Yes | ✅ Yes |
| Runs first | ✅ Yes | ❌ No |
| Can be re-run after changes | ✅ Yes | ❌ No (runs once) |

Both can exist for the same resource. Istio uses mutating webhooks to inject sidecars. OPA/Gatekeeper uses validating webhooks to enforce policies.

---

### 3. The built-in controllers

The kube-apiserver ships with ~30 admission controllers. The recommended set (enabled by default in most distros):

#### Namespace and lifecycle

| Controller | What it does |
|---|---|
| `NamespaceLifecycle` | Prevents `create`/`update`/`delete` in `Terminating` or `Unknown` namespaces |
| `NamespaceAutoProvision` | (removed in 1.14) Creates namespaces on demand — deprecated |
| `LimitRanger` | Enforces `LimitRange` defaults and limits per namespace |
| `ResourceQuota` | Enforces `ResourceQuota` across the namespace |
| `NodeRestriction` | Limits kubelet's ability to modify Node and Pod objects |

#### Defaults and mutating

| Controller | What it does |
|---|---|
| `DefaultStorageClass` | Sets default StorageClass on PVCs that don't specify one |
| `DefaultTolerationSeconds` | Adds 5-minute toleration for `node.kubernetes.io/not-ready` and `node.kubernetes.io/unreachable` |
| `PodSecurity` | Enforces Pod Security Standards (PSS) — replaces the removed PodSecurityPolicy |
| `ServiceAccount` | Auto-mounts the default ServiceAccount token if not disabled |
| `MutatingAdmissionWebhook` | Calls registered mutating webhooks |
| `ValidatingAdmissionWebhook` | Calls registered validating webhooks |

#### Storage and persistence

| Controller | What it does |
|---|---|
| `StorageObjectInUseProtection` | Adds a finalizer to PVCs and PVs to prevent accidental deletion |
| `PersistentVolumeClaimResize` | Validates PVC resize requests against StorageClass allowVolumeExpansion |

#### Security and network

| Controller | What it does |
|---|---|
| `DenyServiceExternalIPs` | Rejects `Service.spec.externalIPs` — prevents a common lateral movement vector |
| `DenyExecOnNameNode` | (removed) Denied exec on kube-system pods |
| `DenyProxyOnNameNode` | (removed) Denied proxy on kube-system pods |
| `EventRateLimit` | Limits event creation rate per namespace (requires config) |
| `ImagePolicyWebhook` | Delegates image policy to an external webhook |

#### Admission webhooks you might enable

```bash
# /etc/kubernetes/manifests/kube-apiserver.yaml
spec:
  containers:
  - name: kube-apiserver
    command:
      - kube-apiserver
      # Add to the default set:
      - --enable-admission-plugins=...,PodSecurity,EventRateLimit,...
      # Remove from the default set:
      - --disable-admission-plugins=...
```

---

### 4. Webhook configuration

A webhook is a **service you deploy + a registration resource**. Two resources:

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: my-validator
webhooks:
  - name: validate.example.com
    clientConfig:
      service:
        name: my-webhook
        namespace: webhook-ns
        path: /validate      # optional — defaults to /validate-<kind>
      caBundle: <base64-CA-cert>
    rules:
      - operations: [CREATE, UPDATE]
        apiGroups: [apps]
        apiVersions: [v1]
        resources: [deployments]
        scope: Namespaced
    matchPolicy: Equivalent      # Equivalent or Exact
    failurePolicy: Fail          # Fail or Ignore
    timeoutSeconds: 10           # max 30
    admissionReviewVersions: [v1, v1beta1]
    sideEffects: None
    namespaceSelector:           # only call webhook for namespaces matching this
      matchLabels:
        name: production
    objectSelector:              # only call webhook for objects matching this
      matchLabels:
        audited: "true"
```

Mutating webhooks use `MutatingWebhookConfiguration` and support `reinvocationPolicy`.

---

### 5. Mutating webhook examples

#### Patch replicas to minimum 2

```go
// Webhook handler for mutating replicas
type Replicator struct{}

func (m *Replicator) Handle(ctx context.Context, req admissiontypes.Request) admissiontypes.Response {
    pod := &corev1.Pod{}
    if err := Deserialize(req.Object.Raw, pod); err != nil {
        return Error(err)
    }

    // Only mutate Deployments
    if pod.Kind != "Deployment" {
        return Allow()
    }

    replicas := int32(2)
    for i, c := range pod.Spec.Containers {
        if c.Name == "processor" && c.Resources.Requests.Memory != nil {
            replicas = 3
        }
    }

    patch := fmt.Sprintf(`{"spec": {"replicas": %d}}`, replicas)
    return Patch(patch, types.MergePatchType)
}
```

#### Inject a sidecar

```json
// Response from Istio's sidecar injector mutating webhook
{
  "apiVersion": "admission.k8s.io/v1",
  "kind": "AdmissionReview",
  "response": {
    "uid": "<request-uid>",
    "allowed": true,
    "patchType": "JSONPatch",
    "patch": "W3sib3AiOiAiYWRkIi4uLl19"
  }
}
```

The base64-decoded patch:

```json
[
  {
    "op": "add",
    "path": "/spec/initContainers/-",
    "value": {
      "name": "istio-init",
      "image": "istio/proxyv2:1.20.0",
      "args": ["--mesh", "istio-system", "--registry", "external"]
    }
  }
]
```

---

### 6. Validating webhook examples

#### Enforce a label exists

```go
func ValidateDeployment(ctx context.Context, req admissiontypes.Request) admissiontypes.Response {
    pod := &corev1.Pod{}
    Deserialize(req.Object.Raw, pod)

    requiredLabels := []string{"app.kubernetes.io/name", "app.kubernetes.io/version"}
    for _, label := range requiredLabels {
        if _, ok := pod.Labels[label]; !ok {
            return Deny(
                "missing required label %q on Deployment %q",
                label, pod.Name,
            )
        }
    }
    return Allow()
}
```

Response shape:

```json
{
  "apiVersion": "admission.k8s.io/v1",
  "kind": "AdmissionReview",
  "response": {
    "uid": "<request-uid>",
    "allowed": false,
    "status": {
      "code": 403,
      "message": "missing required label 'app.kubernetes.io/name' on Deployment 'my-app'"
    }
  }
}
```

#### Reject images from untrusted registries

```go
func ValidateImage(req admissiontypes.Request) admissiontypes.Response {
    pod := &corev1.Pod{}
    Deserialize(req.Object.Raw, pod)

    allowed := []string{"gcr.io/my-project", "docker.io/my-org"}

    for _, c := range pod.Spec.Containers {
        if !IsAllowedRegistry(c.Image, allowed) {
            return Deny("image %q not from allowed registries: %v", c.Image, allowed)
        }
    }
    return Allow()
}
```

---

### 7. The AdmissionReview object

The API server sends this to your webhook:

```json
{
  "apiVersion": "admission.k8s.io/v1",
  "kind": "AdmissionReview",
  "request": {
    "uid": "705abd4c-5e5f-11ec-9bec-42010a8a0f5d",
    "kind": {"group": "apps", "version": "v1", "kind": "Deployment"},
    "resource": {"group": "apps", "version": "v1", "resource": "deployments"},
    "subResource": "",
    "requestKind": {"group": "apps", "version": "v1", "kind": "Deployment"},
    "requestResource": {"group": "apps", "version": "v1", "resource": "deployments"},
    "name": "my-deployment",
    "namespace": "default",
    "operation": "CREATE",
    "userInfo": {
      "username": "admin",
      "groups": ["system:masters", "system:authenticated"]
    },
    "object": { /* full object YAML/JSON */ },
    "oldObject": null,
    "dryRun": false,
    "options": { /* original request options */ }
  }
}
```

Your webhook returns:

```json
{
  "apiVersion": "admission.k8s.io/v1",
  "kind": "AdmissionReview",
  "response": {
    "uid": "<from-request>",
    "allowed": true,
    "patchType": "JSONPatch",
    "patch": "<base64-encoded-patch>",
    "patchType": "JSONPatch"
  }
}
```

For validating webhooks: `allowed: true/false`, no `patch`.

---

### 8. Webhook ordering and mutating chains

Mutating webhooks are **sorted by name** and run in order. Each mutating webhook sees the output of the previous one. If webhook A and B both mutate the same field, the **last one wins** (alphabetically by name).

```
Request → MutatingWebhook1 → MutatingWebhook2 → MutatingWebhook3 → ValidatingWebhook1 → ValidatingWebhook2 → etcd
```

Use `reinvocationPolicy` to re-run mutating webhooks after other mutating webhooks have run:

```yaml
reinvocationPolicy: IfNeeded   # IfNeeded or Never (default)
```

`IfNeeded` means: if any mutating webhook modified the object, re-run all mutating webhooks. Use carefully — it can cause loops.

---

### 9. failurePolicy and timeouts

```yaml
failurePolicy: Fail    # API server REJECTS the request if the webhook is unreachable
failurePolicy: Ignore  # API server PROCEEDS if the webhook is unreachable
```

| Policy | Behavior when webhook fails/unreachable |
|--------|----------------------------------------|
| `Fail` | Object is rejected with `500 Internal Server Error` |
| `Ignore` | Object proceeds past this webhook (but other webhooks still run) |

**`timeoutSeconds`** — defaults to 10s. If your webhook is slow, increase it. But: **slow webhooks block the API request path** — every request waits for your webhook to respond.

#### Production recommendations

```yaml
failurePolicy: Ignore    # if the webhook is down, don't block all deployments
timeoutSeconds: 5       # 5s is usually enough; 10s is the max
```

For **critical policies** (security, compliance), use `Fail` — but ensure you have 2+ webhook replicas with a readiness probe.

---

### 10. matchPolicy and rules

```yaml
rules:
  - operations: [CREATE, UPDATE]
    apiGroups: [""]
    apiVersions: ["v1"]
    resources: ["pods", "services"]
    scope: "*"
```

| Field | What it does |
|-------|-------------|
| `operations` | `CREATE`, `UPDATE`, `DELETE`, `CONNECT` |
| `apiGroups` | `""` for core API (`v1`), `apps`, `networking.k8s.io`, etc. |
| `apiVersions` | `v1`, `v1beta1`, `*` |
| `resources` | `pods`, `*/status` (subresource), `pods/log` (subresource) |
| `scope` | `Namespaced`, `Cluster`, `*` |

```yaml
# matchPolicy: how to interpret rules when a resource has multiple versions
matchPolicy: Equivalent   # matches if the request's version is in the list (default)
matchPolicy: Exact        # exact version match only
```

---

### 11. Namespace/object selectors

```yaml
# Only call this webhook for namespaces matching these labels
namespaceSelector:
  matchLabels:
    name: production
  matchExpressions:
    - key: environment
      operator: In
      values: [prod, staging]

# Only call this webhook for objects with these labels
objectSelector:
  matchLabels:
    webhook.enforce: "true"
  matchExpressions:
    - key: team
      operator: In
      values: [platform, infra]
```

Use `namespaceSelector` to **skip system namespaces** (`kube-system`, `kube-public`) — calling webhooks for every system object creates noise and load:

```yaml
namespaceSelector:
  matchExpressions:
    - key: kubernetes.io/metadata.name
      operator: NotIn
      values: [kube-system, kube-public]
```

---

### 12. sideEffects and dry-run

```yaml
sideEffects: None          # no side effects — safe to call during dry-run
sideEffects: NoneOnDryRun  # has side effects, but OK to call during dry-run
sideEffects: Unknown       # assume it has side effects
sideEffects: Some          # has side effects
```

| Value | Can be called during dry-run? |
|-------|-------------------------------|
| `None` | ✅ Yes |
| `NoneOnDryRun` | ✅ Yes |
| `Unknown` | ❌ No |
| `Some` | ❌ No |

`sideEffects: None` is required for webhooks that don't have side effects. Most validating webhooks are `None`. Mutating webhooks that modify the object are `Some` or `Unknown` — they won't be called during dry-run.

---

### 13. Tools that use webhooks

| Tool | Type | What it does |
|------|------|-------------|
| **OPA Gatekeeper** | Validating | Rego-based policy: no public images, label requirements, resource limits |
| **Kyverno** | Mutating + Validating | YAML-native policy: generate sidecars, validate resources, mutate on create |
| **Istio** | Mutating | Injects Envoy sidecar on every Pod creation |
| **Linkerd** | Mutating | Injects Linkerd proxy sidecar |
| **cert-manager** | Validating | Validates Certificate CRs, auto-writes to ACME/VA APIs |
| **Velero** | Validating | Protects namespaces from deletion during restore |
| **Datree** / **Polaris** | Validating (CI tool, not webhook) | Validates YAML before apply — not a webhook |

**Gatekeeper** (OPA) example policy:

```rego
package kubernetes.admission

deny[msg] {
  input.request.kind.kind == "Pod"
  not input.request.object.spec.securityContext.runAsNonRoot
  msg := "Pods must set runAsNonRoot: true"
}
```

**Kyverno** example policy:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-default-resources
spec:
  rules:
    - name: add-default-requests
      match:
        resources:
          kinds: [Container]
      mutate:
        patchStrategicMerge:
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
```

---

### 14. Debugging webhook failures

```bash
# Is the webhook service reachable?
kubectl run curl-test --image=curlimages/curl --rm -it -- \
  https://my-webhook.default.svc:443/validate \
  --cacert /tmp/ca.crt

# Check webhook registration
kubectl get validatingwebhookconfiguration
kubectl get mutatingwebhookconfiguration

# Get webhook admission reviews (requires API server log access)
kubectl logs -n kube-system kube-apiserver-<node> | grep admission

# Test locally with dry-run (doesn't call webhooks by default in k8s 1.18+)
kubectl apply -f my-deploy.yaml --dry-run=server

# Force call webhooks in dry-run (if sideEffects=None)
kubectl apply -f my-deploy.yaml --dry-run=server

# Check if webhook is called (audit annotation)
# Webhooks that support audit annotations add this to the response:
auditAnnotations:
  key: "value"

# The webhook pod logs
kubectl logs -n webhook-ns deployment/my-webhook
```

#### Common error codes

| HTTP Code | Meaning |
|-----------|---------|
| `400 Bad Request` | Webhook returned malformed response |
| `403 Forbidden` | RBAC — webhook SA can't read the object |
| `500 Internal Server Error` | Webhook panicked or returned error |
| `503 Service Unavailable` | Webhook timed out or is down |

---

### 15. When webhooks vs CRD controllers vs operators

| Tool | When to use | Runs |
|------|------------|------|
| **Validating webhook** | Reject objects that don't meet criteria | Synchronously, on every request |
| **Mutating webhook** | Set defaults, inject sidecars | Synchronously, on every request |
| **CRD controller** | Reconcile to desired state asynchronously | Background loop |
| **Operator** | CRD controller + domain-specific knowledge | Background loop |

**Webhook** = "you can't apply this object" (synchronous gate).
**Controller** = "this Deployment should always have 3 replicas and the right config" (asynchronous reconciliation).

---

### 16. Admission controllers in managed clusters

| Provider | Notes |
|----------|-------|
| **EKS** | Pod Security Standard enforced by default; OPA Gatekeeper available |
| **GKE** | Pod Security, Binary Authorization, Anthos Policy Controller (Gatekeeper) |
| **AKS** | Azure Policy (Gatekeeper-based) |
| **kind/minikube** | All admission controllers available, no restrictions |

On EKS, you can see which admission controllers are enabled:

```bash
kubectl get pod -n kube-system -l component=kube-apiserver -o jsonpath='{.items[0].spec.containers[0].command}' \
  | grep -oP 'enable-admission-plugins=\K[^ ]+'
```

---

### 17. The built-in admission chain (annotated)

For a `kubectl apply -f deployment.yaml` on a standard cluster:

```
1. Authentication        → Who is making the request? (user: admin)
2. Authorization         → Can admin CREATE deployments? (yes — RBAC)
3. LimitRanger           → Set defaults from LimitRange if present
4. ServiceAccount        → Auto-mount default SA token if not set
5. DefaultStorageClass  → Set default SC on PVC if not specified
6. DefaultTolerationSeconds → Add 5min toleration for not-ready/unreachable
7. PodSecurity           → Check Pod spec against PSS policy (privileged/baseline/restricted)
8. MutatingWebhook       → Kyverno/Istio/your-webhook runs here
9. ResourceQuota         → Check namespace quota (CPU/memory requests vs limit)
10. ValidatingWebhook    → Gatekeeper/your-validator runs here
11. StorageObjectInUse   → Add finalizer to PVC/PV
12. → etcd
```

---

### 18. Gotchas

* **Webhooks are on the API request hot path.** A slow or down webhook blocks or fails requests. Use `failurePolicy: Ignore` for non-critical validations. Use timeouts and run 2+ replicas.
* **`sideEffects: None` is mandatory** for webhooks without side effects. Without it, the API server can't call the webhook during dry-run and may reject the registration.
* **`failurePolicy: Fail` is dangerous for mutating webhooks.** If your mutating webhook is down and `failurePolicy: Fail`, no one can create/update deployments. This is a site-wide outage risk.
* **`namespaceSelector` excludes system namespaces by default.** If you need to audit system namespace changes, explicitly include them.
* **The `caBundle` must be the CA that signed the webhook's TLS cert.** For webhooks with a `Service` endpoint, this is the CA that issued the webhook's serving certificate — usually the cluster's CA, NOT the etcd CA.
* **Mutating + Validating on the same resource:** The mutating webhook runs first. If it approves, the validating webhook runs. If the mutating webhook modifies the object, the validating webhook sees the modified version.
* **Object and oldObject:** For UPDATE operations, both are provided. For CREATE, oldObject is null. For DELETE, object contains the object being deleted (but may be a stub).
* **Webhooks don't see Secret contents by default**, but they DO see them if the ServiceAccount has `secrets` read permission. Be careful what you log.
* **Kubelet's own Pod creation** goes through the same admission chain — but some controllers (like `NodeRestriction`) limit what kubelet can modify.
* **`kubectl apply` and `kubectl create`** both go through admission. Dry-run (`--dry-run=server`) goes through admission too (since k8s 1.18), but `sideEffects: Some` webhooks are skipped.

---

## See also

* [[Kubernetes/concepts/L09-advanced/07-aggregation-layer|Aggregation Layer]] — for extending the API, not just mutating/validating
* [[Kubernetes/concepts/L09-advanced/03-customresourcedefinitions|CRDs]] — what the webhook is validating/mutating
* [[Kubernetes/concepts/L07-security/04-admission-policy/10-admission-controllers|L07: Admission Controllers]] — the security context
* [[Kubernetes/concepts/L07-security/04-admission-policy/11-opa-gatekeeper|L07: OPA Gatekeeper]] — Rego-based policy as a webhook
* [[Kubernetes/concepts/L07-security/04-admission-policy/12-kyverno|L07: Kyverno]] — YAML-native policy engine
