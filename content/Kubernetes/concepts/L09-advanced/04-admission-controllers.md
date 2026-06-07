# Admission Controllers and Webhooks

*"https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/"*

Admission controllers are **plugins that run in the API server** and can reject or mutate API requests **after authentication and authorization, before the object is stored in etcd**. They're how you enforce custom policy.

## Two flavors

* **Built-in admission controllers** — compiled into the kube-apiserver
* **Admission webhooks** — out-of-process services you deploy; the apiserver calls out to them

Both flavors come in two kinds:

* **Mutating** — can change the object (`request.kind` is `Create`, etc.)
* **Validating** — can only accept or reject; cannot change the object

## The flow

```
1. Authn     — who are you?
2. Authz     — can you do this?  (RBAC)
3. Mutating admission     ← can change the object
4. Validating admission   ← accept or reject
5. Object stored in etcd
```

A request can hit multiple mutating webhooks (in order) and multiple validating webhooks (in parallel).

## Built-in admission controllers

Enabled by default (the recommended set in modern k8s):

| Controller | What it does |
|---|---|
| `NamespaceLifecycle` | Prevents operations in terminating namespaces |
| `LimitRanger` | Enforces LimitRange defaults and limits |
| `ServiceAccount` | Auto-mounts the default ServiceAccount token |
| `DefaultStorageClass` | Sets a default StorageClass on PVCs without one |
| `DefaultTolerationSeconds` | Adds default toleration for not-ready / unreachable nodes |
| `MutatingAdmissionWebhook` | Calls out to mutating webhooks |
| `ValidatingAdmissionWebhook` | Calls out to validating webhooks |
| `NodeRestriction` | Limits what a kubelet can modify about its Node object |
| `ResourceQuota` | Enforces ResourceQuotas at admission time |

Other built-ins you might enable:

* `PodSecurity` — enforces Pod Security Standards (PSS)
* `DenyServiceExternalIPs` — prevents using Service `externalIPs`
* `ImagePolicyWebhook` — backends like Open Policy Agent can validate image sources

You enable / disable built-ins via `--enable-admission-plugins` / `--disable-admission-plugins` on the kube-apiserver flags. Managed clusters usually have a sensible set already.

## Webhooks

A webhook is **a service you run that the API server calls**. Two resources:

```yaml
# A mutating webhook
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: my-mutator
webhooks:
- name: mutate.example.com
  clientConfig:
    service:
      name: my-webhook
      namespace: default
      path: /mutate
    caBundle: <base64-CA>
  rules:
  - operations: ["CREATE", "UPDATE"]
    apiGroups: ["apps"]
    apiVersions: ["v1"]
    resources: ["deployments"]
  admissionReviewVersions: ["v1"]
  sideEffects: None
  namespaceSelector: {}                  # or matchExpressions
```

```yaml
# A validating webhook
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: my-validator
webhooks:
- name: validate.example.com
  clientConfig:
    service:
      name: my-webhook
      namespace: default
      path: /validate
  rules:
  - operations: ["CREATE"]
    apiGroups: [""]
    resources: ["pods"]
```

The API server sends a JSON `AdmissionReview` to your webhook, your service returns a response:

```json
{
  "apiVersion": "admission.k8s.io/v1",
  "kind": "AdmissionReview",
  "response": {
    "uid": "<request-uid>",
    "allowed": true,
    "patchType": "JSONPatch",
    "patch": "W3sib3AiOiAiYWRkIiwgInBhdGgiOiAiL3NwZWMvcmVwbGljYXMiLCAidmFsdWUiOiAzfV0="
  }
}
```

The base64-decoded patch adds `"replicas": 3` to the spec — that's a mutating webhook.

## Tools that build on webhooks

* **OPA / Gatekeeper** — Rego-based policy. You write rules, Gatekeeper runs them as a validating webhook.
* **Kyverno** — YAML-native policy. Mutating + validating + generating (it can create related resources).
* **Istio** — injects the sidecar as a mutating webhook on Pod creation.
* **cert-manager** — issues certificates via a webhook watching Certificate CRs.
* **Velero** — backup webhook for namespace deletion.

## When to use a webhook vs a CRD controller

* **Webhook** — when you need to **reject / mutate** objects at admission time. Runs synchronously in the request path — slow webhooks block the API.
* **Controller** — when you need to **reconcile** objects asynchronously. Doesn't block the request.

A webhooked validation is "you can't apply this Pod". A controller is "this Deployment should have 3 replicas".

## Gotchas

* **Webhooks are on the API request hot path.** A slow or unavailable webhook will block or fail all requests to the resources it watches. Always:
  * Set `timeoutSeconds` (default 10s, usually too high)
  * Have at least 2 replicas
  * Use `failurePolicy: Ignore` for non-critical validations (admission proceeds if the webhook is unreachable)
* **`failurePolicy` is dangerous by default.** It defaults to `Fail`, which means "if the webhook is down, reject all requests". For mutating webhooks especially, you almost always want `Ignore`.
* **`namespaceSelector` and `objectSelector`** can limit which requests hit the webhook — important for not calling out on every system namespace.
* **`sideEffects: None` is required for webhooks that don't have side effects** (most validating webhooks). `Unknown` is also allowed. `None` is the safe choice.
* **The `caBundle` must be the CA that signed the webhook's serving cert.** If the webhook uses a public CA, use the standard CA. If it uses an internal CA (most cases), you need to provide the CA bundle.
* **Built-in admission controllers are not optional in the way webhooks are** — they're compiled in. If a required one (like `MutatingAdmissionWebhook`) is disabled, webhooks won't work.
* **Webhooks see EVERY object that matches the rule.** Be careful with broad rules like `apiGroups: [""]` `resources: ["*"]` — that's a lot of requests.
* **The webhook gets the FULL object**, including secrets (if it has the RBAC to read them). Be careful with logging — don't log Secret contents.

## When to use a webhook

* Enforce policy that's too custom for PSS (`PodSecurity` admission is built-in, but you might want "no images from public registries" — that's a webhook)
* Inject sidecars (Istio, Linkerd, Dapr)
* Set defaults that `LimitRanger` can't handle
* Cross-namespace validation ("every Namespace must have a specific label")
