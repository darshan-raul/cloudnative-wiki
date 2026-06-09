# Admission Controllers

*"https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/"*

Admission controllers are the **plugins that run on the apiserver** for every request that creates, updates, or deletes a Kubernetes object. They run **after** authentication and authorization, but **before** the object is persisted to etcd. Two flavors: **mutating** (can modify the object) and **validating** (can reject it). This is where cluster policy actually gets enforced — PSS, OPA/Kyverno, default-resource-quota, and the dozens of built-in admission plugins all live here.

### Table of Contents

1. [Where Admission Fits in the Request Flow](#1-where-admission-fits-in-the-request-flow)
2. [Mutating vs Validating](#2-mutating-vs-validating)
3. [Built-in Admission Plugins](#3-built-in-admission-plugins)
4. [The `--enable-admission-plugins` Flag](#4-the---enable-admission-plugins-flag)
5. [Dynamic Admission: MutatingWebhookConfiguration and ValidatingWebhookConfiguration](#5-dynamic-admission-mutatingwebhookconfiguration-and-validatingwebhookconfiguration)
6. [The Webhook Flow](#6-the-webhook-flow)
7. [Webhook Configuration in Depth](#7-webhook-configuration-in-depth)
8. [The Webhook Server](#8-the-webhook-server)
9. [Failure Policy and Timeouts](#9-failure-policy-and-timeouts)
10. [Side Effects and Reinvocation](#10-side-effects-and-reinvocation)
11. [Built-in: PodSecurity (PSS)](#11-built-in-podsecurity-pss)
12. [Built-in: LimitRanger, ResourceQuota, DefaultStorageClass](#12-built-in-limitranger-resourcequota-defaultstorageclass)
13. [Built-in: NodeRestriction, ServiceAccount](#13-built-in-noderestriction-serviceaccount)
14. [Writing a Custom Webhook](#14-writing-a-custom-webhook)
15. [Operations and Debugging](#15-operations-and-debugging)
16. [Gotchas and Common Mistakes](#16-gotchas-and-common-mistakes)

---

## 1. Where Admission Fits in the Request Flow

Every request to the apiserver goes through:

```
1. TLS termination
2. Authentication → 401 if fail
3. Authorization → 403 if fail
4. Admission control        ← you are here
   a. Mutating admission
   b. Validating admission
5. Object stored in etcd
```

A request that fails admission **never reaches etcd**. The client gets a 4xx response with the admission error.

### 1.1 The two phases

Admission runs in **two phases**:

* **Mutating phase** — first. Each mutating plugin/webhook can modify the request. The output of one plugin is the input of the next.
* **Validating phase** — second. Validators can only accept or reject; they can't modify.

Within each phase, plugins run in **a configured order**. The order matters when one plugin's mutation is the input to another's validation.

### 1.2 The request types that go through admission

* **CREATE** — yes
* **UPDATE** — yes
* **DELETE** — yes (special admission: `ValidatingAdmissionWebhook` and `MutatingAdmissionWebhook` can intercept delete; most built-in plugins don't care)
* **READ** — no
* **WATCH** — no
* **CONNECT** — no
* **SUBRESOURCE** (e.g. `/scale`, `/status`, `/exec`) — yes, but the admission plugins see a synthetic object (the subresource, not the parent)

## 2. Mutating vs Validating

* **Mutating** — can modify the object (add labels, set defaults, inject sidecars). The modified object is what gets stored.
* **Validating** — can only accept or reject. Used for policy enforcement ("reject if not compliant").

A plugin is **either** mutating **or** validating, not both. **Webhooks** can be configured as either type (via the `ValidatingAdmissionWebhook` or `MutatingAdmissionWebhook` API).

```
Request: Pod with image nginx
    │
    ▼
Mutating phase (in order):
  ├─ DefaultIngressClass
  ├─ Sidecar (Istio)
  ├─ ServiceAccount admission (sets default SA)
  └─ PodSecurityPolicy (no-op in 1.25+)
    │
    ▼
Object: Pod with image nginx, sidecar.istio.io/inject: true, ...
    │
    ▼
Validating phase (in order):
  ├─ PodSecurity (PSS)
  ├─ LimitRanger
  ├─ ResourceQuota
  ├─ MutatingAdmissionWebhook (no, validating only)
  ├─ ValidatingAdmissionWebhook
  └─ (other validators)
    │
    ▼
Allow → store in etcd
Deny → return 403 with reason
```

## 3. Built-in Admission Plugins

The apiserver ships with **30+ built-in admission plugins**. They're enabled via `--enable-admission-plugins=<list>` on the apiserver. Some are enabled by default; some are off.

### 3.1 The default set

Default-enabled (since k8s 1.27+):

| Plugin | Type | What it does |
|---|---|---|
| `CertificateApproval` | V | Approves CSRs as system:certificates.k8s.io |
| `CertificateSigning` | V | Signs CSRs as system:certificates.k8s.io |
| `CertificateSubjectRestriction` | V | Rejects CSRs with disallowed subject fields |
| `DefaultIngressClass` | M | Sets `spec.ingressClassName` if unset |
| `DefaultStorageClass` | M | Sets `spec.storageClassName` if unset |
| `DefaultTolerationSeconds` | M | Sets 5-min toleration for not-ready / unreachable taints |
| `LimitRanger` | V | Enforces LimitRange defaults and constraints |
| `MutatingAdmissionWebhook` | M | Runs all `MutatingWebhookConfiguration`s |
| `NamespaceLifecycle` | V | Prevents creating objects in terminating namespaces |
| `NodeRestriction` | V | Restricts what kubelets can do (label, taint) |
| `PersistentVolumeClaimResize` | V | Allows volume resize (or not, by feature gate) |
| `PodSecurity` | V | Enforces Pod Security Standards (the `restricted` / `baseline` / `privileged` profiles) |
| `Priority` | M | Sets priority from PriorityClass if unset |
| `ResourceQuota` | V | Enforces ResourceQuota on the namespace |
| `RuntimeClass` | M | Sets `RuntimeClass` defaults |
| `ServiceAccount` | M | Sets the default ServiceAccount and ensures the SA exists |
| `StorageObjectInUseProtection` | V | Prevents deleting PVs / PVCs in use |
| `TaintNodesByCondition` | M | Adds taints to nodes with conditions |
| `ValidatingAdmissionWebhook` | V | Runs all `ValidatingWebhookConfiguration`s |

### 3.2 Some plugins that need to be explicitly enabled

| Plugin | Type | Notes |
|---|---|---|
| `PodNodeSelector` | M | Constrains `nodeSelector` to a cluster-wide set |
| `PodNodeConstraints` | V | Constrains `nodeName` to the Pod's node |
| `ImagePolicyWebhook` | V | Calls out to an external image policy service (deprecated in favor of OPA / Kyverno) |
| `EventRateLimit` | V | Caps the rate of events |
| `ExtendedResourceToleration` | M | Taints for extended resources (GPU, etc.) |
| `DenyServiceExternalIPs` | V | Rejects Services with `externalIPs` (k8s 1.27+) |
| `PodSecurityPolicy` | V | PSP — deprecated, removed in 1.25 |

### 3.3 The order

Within a phase, plugins run in a specific order. The order is hard-coded in the apiserver. You can see the order in the apiserver's source. As a rule:

* Mutating: defaults first, then user-driven mutations.
* Validating: cheap checks first, then expensive (webhooks last).

## 4. The `--enable-admission-plugins` Flag

The apiserver flag controls what's enabled:

```yaml
# /etc/kubernetes/manifests/kube-apiserver.yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --enable-admission-plugins=NodeRestriction,PodSecurity,...
    - --disable-admission-plugins=...
```

* `--enable-admission-plugins` — list of plugins to enable (additive to defaults).
* `--disable-admission-plugins` — list of plugins to disable (overrides defaults).

You can enable additional plugins. You can also disable defaults, but be careful — some are required for normal operation (e.g. `ServiceAccount` is required for Pod creation to work).

To check what's enabled on your cluster:

```bash
# if you have access to the apiserver manifest
cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep admission

# via the live configuration
kubectl -n kube-system get pod kube-apiserver-<node> -o yaml | grep admission
```

## 5. Dynamic Admission: MutatingWebhookConfiguration and ValidatingWebhookConfiguration

The built-in plugins are static. For custom logic, you use **dynamic admission** — webhooks. Two CRDs:

* `MutatingWebhookConfiguration` — list of mutating webhooks.
* `ValidatingWebhookConfiguration` — list of validating webhooks.

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata: { name: my-policy }
webhooks:
- name: validate.example.com
  rules:
  - operations: [CREATE, UPDATE]
    apiGroups: [""]
    apiVersions: ["v1"]
    resources: ["pods"]
  clientConfig:
    service:
      name: my-policy-server
      namespace: my-ns
      path: /validate
      port: 443
  admissionReviewVersions: ["v1"]
  sideEffects: None
  failurePolicy: Fail        # or Ignore
  namespaceSelector:         # optional: limit to namespaces
    matchLabels:
      enforce: my-policy
  objectSelector:            # optional: limit to objects
    matchLabels:
      enforce: my-policy
  timeoutSeconds: 10
```

The apiserver sees this CRD and **calls the webhook** for matching requests. The webhook is a server (typically a Pod) that returns an admission response.

### 5.1 The structure of a webhook configuration

* **`rules`** — what requests the webhook applies to. Operations (CREATE / UPDATE / DELETE), api groups, versions, resources.
* **`clientConfig`** — how to call the webhook. Either a service ref (Service in the cluster), URL, or a kubeconfig file.
* **`admissionReviewVersions`** — the AdmissionReview API versions the webhook supports.
* **`sideEffects`** — `None` (no side effects), `NoneOnDryRun`, or `Some` (has side effects). Affects whether dry-run works.
* **`failurePolicy`** — `Fail` (reject the request if the webhook fails) or `Ignore` (allow if the webhook fails).
* **`namespaceSelector` / `objectSelector`** — limit the webhook to specific namespaces or objects.
* **`timeoutSeconds`** — how long to wait for the webhook to respond (default 10s).
* **`reinvocationPolicy`** — whether the webhook is re-invoked if a previous mutator changed the object. `Never` or `IfNeeded`.

## 6. The Webhook Flow

```
apiserver                         Webhook
   │                                │
   │  POST /validate                │
   │  (AdmissionReview request)     │
   │ ──────────────────────────────►│
   │                                │
   │  (webhook processes)           │
   │                                │
   │  AdmissionReview response      │
   │  (allowed or denied)           │
   │ ◄──────────────────────────────│
   │                                │
   │  (apiserver enforces decision) │
   │                                │
```

The webhook receives a JSON `AdmissionReview` object containing the full object being admitted. The webhook:

1. Parses the request.
2. Decides allowed or denied.
3. (For mutating) returns patches.
4. Returns an `AdmissionReview` response with a `status` field.

### 6.1 The `AdmissionReview` request

```json
{
  "kind": "AdmissionReview",
  "apiVersion": "admission.k8s.io/v1",
  "request": {
    "uid": "...",
    "kind": {"group": "", "version": "v1", "kind": "Pod"},
    "resource": {"group": "", "version": "v1", "resource": "pods"},
    "subResource": "...",
    "name": "my-pod",
    "namespace": "default",
    "operation": "CREATE",
    "userInfo": {"username": "alice", "groups": ["developers"]},
    "object": { ... full Pod spec ... },
    "oldObject": { ... previous spec, for UPDATE ... },
    "dryRun": false,
    "options": { ... }
  }
}
```

The webhook sees the full object. It can also see the `oldObject` (for UPDATE), the `userInfo` (who's making the request), and the `dryRun` flag (whether this is a dry-run).

### 6.2 The `AdmissionReview` response

```json
{
  "kind": "AdmissionReview",
  "apiVersion": "admission.k8s.io/v1",
  "response": {
    "uid": "...",
    "allowed": true,
    "status": {"message": "..."},
    "patch": "base64-encoded-JSON-patch",
    "patchType": "JSONPatch"
  }
}
```

* `allowed: true` — the request is accepted.
* `allowed: false` — the request is rejected; `status.message` is shown to the user.
* `patch` — for mutating webhooks, a base64-encoded JSON patch to apply to the object.

## 7. Webhook Configuration in Depth

### 7.1 Multiple webhooks

A single CRD can have multiple webhooks. They run in order, and each is independent. If one denies, the rest don't run.

If a webhook is in the cluster and its CRD is updated, the apiserver picks up the change via watch.

### 7.2 The `caBundle`

When calling a webhook Service, the apiserver needs to verify the webhook server's TLS cert. The `caBundle` field in the webhook config provides the CA cert:

```yaml
clientConfig:
  service:
    name: my-webhook
    namespace: my-ns
    path: /validate
    port: 443
  caBundle: <base64-encoded CA cert>
```

The `caBundle` is required for `service`-type webhooks. For `url`-type webhooks, the apiserver uses the system trust store.

### 7.3 The `reinvocationPolicy`

If a mutating webhook modifies an object, and a later mutating webhook would have made a different decision based on the new state, the later webhook is **re-invoked**.

`reinvocationPolicy: IfNeeded` (default) — re-invoke if the object changed.
`reinvocationPolicy: Never` — don't re-invoke.

This is important for webhook ordering. If webhook A adds a label and webhook B checks the label, B is re-invoked after A's mutation.

### 7.4 The `matchPolicy`

`matchPolicy: Exact` (default) — the webhook is called only if the operation matches exactly.
`matchPolicy: Equivalent` — the webhook is called for any operation on a matching resource (e.g. if you specify `CREATE`, it's also called for any subresource operation).

`Equivalent` is useful for tools that need to see all operations on a resource.

## 8. The Webhook Server

A webhook server is an HTTPS server that:

* Listens on a port (typically 443).
* Has a valid TLS cert (signed by a CA the apiserver trusts).
* Accepts `AdmissionReview` requests.
* Returns `AdmissionReview` responses.

Common implementations:

* **Kubewatch** (Go) — a small framework.
* **Kyverno** (Go) — runs as a Deployment, exposes a webhook for policy.
* **OPA Gatekeeper** (Go) — runs as a Deployment, exposes a webhook for Rego-based policy.
* **Cert-manager's policy webhook** — for image verification.
* **Custom** — your own Go / Python / Rust / Node server.

The webhook server is a regular Pod (or Deployment) with a Service. The apiserver reaches it via the Service's DNS.

## 9. Failure Policy and Timeouts

### 9.1 `failurePolicy`

What happens when the webhook is unreachable or errors?

* `Fail` (default) — the request is rejected. "Admission webhook denied the request: failed calling webhook."
* `Ignore` — the request is allowed. "Admission webhook errored, but `failurePolicy: Ignore`."

For **policy enforcement** (you want strict), use `Fail`. For **best-effort checks** (warnings, telemetry), use `Ignore`.

**`Fail` is the safe default for security webhooks.** If the webhook is down, the request is rejected. This prevents "let me just take the webhook offline so I can deploy my thing" attacks.

### 9.2 `timeoutSeconds`

Default 10s. If the webhook doesn't respond in time, `failurePolicy` is applied. Long timeouts make admission slow; short timeouts cause false rejections.

For most webhooks, 3-5s is reasonable. 10s is the max.

### 9.3 The cascading effect

A slow webhook **slows down the entire apiserver**. The apiserver holds the request while waiting for the webhook. If 100 requests/sec hit the apiserver and each waits 1s for the webhook, the apiserver can be saturated.

**Use `namespaceSelector` and `objectSelector` to limit the webhook's scope.** Don't run a webhook on every Pod in every namespace unless you must.

## 10. Side Effects and Reinvocation

### 10.1 `sideEffects`

`sideEffects` tells the apiserver whether the webhook has side effects.

* `None` — no side effects. The webhook is safe to call during dry-run.
* `NoneOnDryRun` — no side effects during dry-run, may have side effects on real requests.
* `Some` — has side effects. Dry-run is **disabled** for this webhook.

`None` is the safe default for policy webhooks. `Some` is for webhooks that mutate state (e.g. a webhook that records metrics — though typically this is done out-of-band).

### 10.2 The reinvocation chain

```
Request: Pod
  │
  ▼
Mutating webhook A — adds label "team=foo"
  │
  ▼
Mutating webhook B — checks for label "team=foo", adds annotation
  │
  ▼
Mutating webhook A — sees annotation, doesn't add another label
  │
  ▼
Validating webhook C — checks the final state
  │
  ▼
Allow or deny
```

If `reinvocationPolicy: IfNeeded`, A is called again after B's mutation. A should be **idempotent** — calling it twice should be safe.

## 11. Built-in: PodSecurity (PSS)

The `PodSecurity` admission plugin enforces PSS. It's enabled by default in modern clusters.

```yaml
# apiserver flag
--enable-admission-plugins=PodSecurity
```

PSS is configured via **namespace labels**, not via the plugin directly:

```bash
kubectl label ns production pod-security.kubernetes.io/enforce=restricted
```

The plugin reads the labels and enforces the standard. See [[Kubernetes/concepts/L07-security/06-pod-security-standards|PSS]] for the full picture.

## 12. Built-in: LimitRanger, ResourceQuota, DefaultStorageClass

### 12.1 LimitRanger

`LimitRanger` enforces the `LimitRange` objects in the namespace. It applies defaults (e.g. if a container has no `requests.memory`, set it to the default) and validates (e.g. reject if a container exceeds the max).

`LimitRanger` is enabled by default. It runs in the mutating phase (for defaults) and the validating phase (for constraints). Actually, it's only validating — defaults are applied by the apiserver itself based on the LimitRange.

### 12.2 ResourceQuota

`ResourceQuota` enforces the namespace's quotas. It rejects requests that would exceed the quota.

`ResourceQuota` is validating only. It runs late in the validating phase.

### 12.3 DefaultStorageClass

`DefaultStorageClass` sets `spec.storageClassName` on PVCs that don't have one. The default is taken from the cluster's `StorageClass` objects that have `annotations: storageclass.kubernetes.io/is-default-class: "true"`.

Mutating only.

## 13. Built-in: NodeRestriction, ServiceAccount

### 13.1 NodeRestriction

`NodeRestriction` restricts what kubelets can do. A kubelet can only:

* Modify its own Node and Pod status.
* Add labels / taints to its own Node (with the `kubernetes.io/hostname` or `topology.kubernetes.io/zone` prefix).
* Read most API resources (for `kubectl exec`, `kubectl logs`, etc.).

`NodeRestriction` is enabled by default. It works with the Node authorizer.

### 13.2 ServiceAccount

`ServiceAccount` admission sets the default ServiceAccount for Pods that don't specify one. It also ensures the SA exists in the Pod's namespace (if it doesn't, the Pod is rejected).

Mutating only.

## 14. Writing a Custom Webhook

A custom webhook is a server. The simplest implementation:

1. **Generate a TLS cert** for the webhook server.
2. **Deploy the server** as a Pod with a Service.
3. **Create a `MutatingWebhookConfiguration` or `ValidatingWebhookConfiguration`** with the service ref and CA bundle.
4. **Test** with a sample request.

Libraries (Go):

* `k8s.io/apiserver/pkg/admission` — the apiserver's own admission framework.
* `sigs.k8s.io/controller-runtime/pkg/webhook` — controller-runtime's webhook helper.
* `github.com/kubernetes-sigs/kubebuilder` — generates the boilerplate.

Libraries (Python):

* `kubernetes.client` — the official client, with admission helpers.

Libraries (other):

* Most languages have a way to consume the `AdmissionReview` JSON and produce a response.

The webhook typically:

* Runs on HTTPS (TLS cert required).
* Listens for POST requests.
* Parses the `AdmissionReview` body.
* Returns the response.
* Is deployed as a Deployment with a Service.
* Has a cert-manager-issued cert (rotated automatically).

## 15. Operations and Debugging

### 15.1 Common commands

```bash
# check what's enabled
kubectl -n kube-system get pod kube-apiserver-<node> -o yaml | grep admission
# or
cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep admission

# list dynamic admission configs
kubectl get mutatingwebhookconfigurations
kubectl get validatingwebhookconfigurations

# describe
kubectl describe validatingwebhookconfiguration <name>
# look at: rules, clientConfig, caBundle, failurePolicy

# see admission failures
kubectl get events --field-selector reason=FailedCreate
# look at: "admission webhook denied the request"
```

### 15.2 The "admission webhook failed" case

A request is denied with "admission webhook denied the request".

```bash
# 1. Which webhook?
kubectl get events --field-selector reason=FailedCreate -A
# the event message says "admission webhook <name> denied the request"

# 2. Why?
# the webhook's response.status.message has the reason
# the apiserver logs the full AdmissionReview

# 3. Is the webhook reachable?
kubectl get endpoints -n <webhook-ns>
# look for endpoints in the Service

# 4. Is the webhook's cert valid?
# check the caBundle in the webhook config
# check the webhook server's serving cert
```

### 15.3 The "webhook is slow" case

A webhook is making admission slow.

```bash
# 1. Check the webhook's response time
# (most webhooks log this; check the metrics)

# 2. Look at the apiserver's metrics
# admission_duration_seconds histogram, labeled by webhook

# 3. Use namespaceSelector / objectSelector to limit scope
# or increase resources on the webhook

# 4. Consider moving to a non-admission control plane
# (e.g. controller that reconciles, instead of admission-time checks)
```

## 16. Gotchas and Common Mistakes

### 16.1 The 25+ common mistakes

1. **Admission runs on every CREATE / UPDATE / DELETE.** A slow webhook slows down all of these.

2. **Webhooks run on the apiserver's request path.** The apiserver waits for the webhook's response. If the webhook is down, requests hang (until `timeoutSeconds`).

3. **`failurePolicy: Fail` is the safe default.** With `Ignore`, a webhook outage means no enforcement. The Pod with a critical CVE slips through.

4. **The `caBundle` is required for Service-type webhooks.** Without it, the apiserver can't verify the webhook server's TLS cert.

5. **The `caBundle` must be a valid cert.** A typo or expired cert in the bundle means the webhook can't be called.

6. **Webhooks are called with the apiserver's identity, not the user's.** The webhook sees the user's identity in `request.userInfo`, but the network call is from the apiserver.

7. **A webhook that mutates an object is called twice** (if reinvocation is on). It must be idempotent.

8. **Admission plugins run in a specific order.** You can't reorder built-in plugins. You can disable some and re-enable others, but the order is fixed.

9. **Mutating webhooks can set fields, not the value of a field.** They can add to `metadata.labels` but can't change a specific label's value (well, they can — but a later webhook could change it back).

10. **The `objectSelector` on a webhook config is for objects, not webhook objects.** It filters which resources the webhook sees. Use it to limit scope.

11. **The webhook server's cert is independent of the cluster's CA.** The webhook server needs its own cert. cert-manager is the standard tool for this.

12. **A validating webhook can only accept or reject.** It can't return a patch. For modifications, use a mutating webhook.

13. **A mutating webhook can be either mutating or validating, not both.** If you need both, you register two webhooks.

14. **The `dryRun` flag in the AdmissionReview request is propagated from the apiserver.** If the user did `kubectl apply --dry-run=server`, the webhook sees `dryRun: true`. The webhook should respect it (don't have side effects in dry-run).

15. **A webhook that calls back to the apiserver is dangerous.** It can cause infinite loops (admission → webhook → apiserver → admission → ...). Avoid this.

16. **The `admissionReviewVersions` must be set.** The webhook must declare which API versions it supports. `["v1"]` is the current standard.

17. **`sideEffects: None` is required for dry-run.** If a webhook has `sideEffects: Some`, dry-run is disabled for that webhook.

18. **The `timeoutSeconds` is per-webhook.** The total admission time can be `timeoutSeconds * num_webhooks`. If you have 3 webhooks with 5s timeouts, admission can take 15s.

19. **The `failurePolicy: Fail` for a webhook that frequently fails is bad.** It causes spurious 4xx errors. Use `Ignore` for best-effort checks, `Fail` only for critical ones.

20. **A webhook that returns `allowed: true` with no `status` is fine.** A response with just `allowed: true` means "OK".

21. **A webhook can return `allowed: false` with a `status.message`.** The message is shown to the user. Use it to explain the rejection.

22. **A webhook that doesn't return a response causes a timeout.** The apiserver waits, then applies `failurePolicy`.

23. **The `ValidatingAdmissionPolicy` (k8s 1.30+) is a CEL-based admission policy** that's built into the apiserver. It can replace some webhooks (for CEL-compatible checks). It's still beta as of 1.30.

24. **A `MutatingAdmissionPolicy` (k8s 1.30+) is the mutating counterpart.** Also CEL-based. Both are new; the main adoption is still via webhooks.

25. **The `PodSecurityPolicy` (PSP) admission plugin is gone.** It was removed in k8s 1.25. If you have PSPs, they don't do anything. Migrate to PSS, Kyverno, or OPA.

26. **Admission doesn't see `kubectl exec` / `kubectl logs`.** These go through a different path (the kubelet's API). Webhooks can intercept them via the `pods/exec` and `pods/log` subresources, but the apiserver passes a synthetic object.

27. **The webhook's service account needs RBAC** to read the objects the webhook needs. The webhook runs in the cluster, talks to the apiserver, and has its own identity. The identity's RBAC determines what it can see.

28. **The `kube-system` namespace's webhooks affect the apiserver's own behavior.** A buggy webhook in `kube-system` can break cluster operation. Be careful.

29. **A webhook that returns patches must base64-encode the patches.** The response's `patch` field is base64-encoded JSON patch.

30. **The `objectSelector` and `namespaceSelector` use standard `MatchLabels` / `MatchExpressions`.** Same syntax as NetworkPolicy and Pod affinity.

## See also

* [[Kubernetes/concepts/L07-security/06-pod-security-standards|PSS]] — the most-used built-in admission
* [[Kubernetes/concepts/L07-security/11-opa-gatekeeper|OPA / Gatekeeper]] — the policy-engine webhook
* [[Kubernetes/concepts/L07-security/12-kyverno|Kyverno]] — the k8s-native policy engine
* [[Kubernetes/concepts/L07-security/15-audit-logging|Audit Logging]] — what gets logged for admission failures
