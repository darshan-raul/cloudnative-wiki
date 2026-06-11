# Kyverno

*"https://kyverno.io/"*

Kyverno is a **k8s-native policy engine**. Unlike OPA / Gatekeeper (which uses Rego), Kyverno policies are written as **YAML**, using standard k8s syntax. It runs as a **validating and mutating admission webhook**, and supports all the same policy use cases as Gatekeeper. The key differentiator: **no new language to learn**. If you know k8s YAML, you know Kyverno.

### Table of Contents

1. [The Kyverno Philosophy](#1-the-kyverno-philosophy)
2. [Kyverno Components](#2-kyverno-components)
3. [Policy Structure](#3-policy-structure)
4. [Validation Rules](#4-validation-rules)
5. [Mutation Rules](#5-mutation-rules)
6. [Generation Rules](#6-generation-rules)
7. [Verify Image Signatures](#7-verify-image-signatures)
8. [ClusterPolicy vs Policy](#8-clusterpolicy-vs-policy)
9. [Common Patterns](#9-common-patterns)
10. [Background Scans](#10-background-scans)
11. [Kyverno vs OPA / Gatekeeper](#11-kyverno-vs-opa--gatekeeper)
12. [Kyverno CLI](#12-kyverno-cli)
13. [Kyverno + CEL](#13-kyverno--cel)
14. [Operations and Debugging](#14-operations-and-debugging)
15. [Gotchas and Common Mistakes](#15-gotchas-and-common-mistakes)

---

## 1. The Kyverno Philosophy

Kyverno's bet: **policy should be k8s-native**. The same YAML you use to describe your apps should describe the policies. No new DSL (Rego), no new mental model.

```
OPA / Gatekeeper:
  Policy: Rego file
  Inputs: JSON
  Engine: OPA binary
  Output: allow / deny

Kyverno:
  Policy: YAML (ClusterPolicy / Policy)
  Inputs: k8s object
  Engine: Kyverno pod
  Output: allow / deny / warn / patch
```

Kyverno policies are k8s resources. You can `kubectl apply` them. You can `kubectl get` them. You can `kubectl describe` them. The "policy" is just another k8s object.

### 1.1 The trade-off

The trade-off:

* **Pros** — easy to learn, no new language, k8s-native, integrates with k8s tools (kubectl, GitOps).
* **Cons** — less expressive than Rego, can't share policies with non-k8s systems, the "match" syntax is Kyverno-specific.

For most k8s users, Kyverno is the right choice. For multi-system policy (k8s + API gateway + CI), OPA is more flexible.

## 2. Kyverno Components

Kyverno runs as a Deployment with two main components:

* **kyverno** — the main pod. Runs the admission webhook, evaluates policies, applies mutations.
* **kyverno-cleanup-controller** (in v1.7+) — cleans up background scan results.
* **kyverno-background-controller** (older versions) — runs background scans on existing objects.

The architecture:

```
apiserver
   │
   │ AdmissionReview
   │
kyverno (admission webhook)
   │
   ├── load policies (ClusterPolicy / Policy)
   │
   ├── evaluate
   │
   └── return allow / deny / warn / patch
```

Kyverno is one binary. It runs in `kyverno` namespace (or wherever you install it).

## 3. Policy Structure

A Kyverno policy is a **ClusterPolicy** (cluster-wide) or **Policy** (namespace-scoped):

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
spec:
  validationFailureAction: Enforce        # or Audit
  background: true                        # run on existing objects
  rules:
  - name: check-team-label
    match:
      any:
      - resources:
          kinds: ["Pod"]
    validate:
      message: "all Pods must have a 'team' label with a valid value"
      pattern:
        metadata:
          labels:
            team: "?*"
            # '?' is exactly 1 character, '*' is 0+ characters
            # so "?*" is 1+ characters (non-empty)
  - name: check-team-value
    match:
      any:
      - resources:
          kinds: ["Pod"]
    validate:
      message: "team label must be 'frontend', 'backend', or 'platform'"
      deny:
        conditions:
        - key: "{{ request.object.metadata.labels.team }}"
          operator: NotIn
          value: ["frontend", "backend", "platform"]
```

A policy has:

* **`validationFailureAction`** — `Enforce` (reject) or `Audit` (log only).
* **`background`** — run on existing objects too.
* **`rules`** — list of individual rules. Each rule can match, validate, mutate, or generate.

### 3.1 The match

```yaml
match:
  any:
  - resources:
      kinds: ["Pod"]
      namespaces: ["prod", "staging"]
      selector:
        matchLabels:
          enforce: true
  all:
  - resources:
      kinds: ["Deployment"]
  exclude:
    any:
    - resources:
        namespaces: ["kube-system"]
```

`match` says "this rule applies to these resources". `exclude` says "but not these". `any` is OR, `all` is AND.

### 3.2 The pattern syntax

Kyverno's `pattern` is a YAML pattern that the object must match. Wildcards:

* `?` — exactly 1 character.
* `*` — 0+ characters.
* `(...)` — group of alternative values.

```yaml
pattern:
  metadata:
    labels:
      app: "?*"      # 1+ characters
      team: "(frontend|backend|platform)"   # one of these values
      version: "v1.*"  # v1.something
```

If the object matches the pattern, the rule passes. If not, it's denied (or audited).

## 4. Validation Rules

A `validate` rule checks that the matched object conforms to a pattern. It can:

* **Pattern match** — check the object matches a YAML pattern.
* **Deny with conditions** — check explicit conditions.
* **Assert** — check that a fact is true.

### 4.1 Pattern matching

```yaml
validate:
  message: "all Pods must have resource limits"
  pattern:
    spec:
      containers:
      - name: "?*"
        resources:
          limits:
            memory: "?*"
            cpu: "?*"
          requests:
            memory: "?*"
            cpu: "?*"
```

If the object has containers without `resources.limits` or `resources.requests`, the pattern doesn't match, and the request is denied.

### 4.2 Deny with conditions

```yaml
validate:
  message: "image must come from the approved registry"
  deny:
    conditions:
    - key: "{{ request.object.spec.containers[?name=='app'].image }}"
      operator: NotContains
      value: "gcr.io/my-project/"
```

The `key` is a JMESPath or JSONPath query. The `operator` is the check. The `value` is what to compare against.

### 4.3 Assert

```yaml
validate:
  message: "all Pods must have a 'team' label"
  assert:
    conditions:
    - key: "{{ request.object.metadata.labels.team || '' }}"
      operator: NotEquals
      value: ""
```

`assert` is "this fact must be true". If false, deny.

## 5. Mutation Rules

A `mutate` rule **modifies the object** before it's stored. Common uses:

* **Inject labels** — add a label like `team: platform` if not set.
* **Inject sidecars** — add a sidecar container (e.g. Istio).
* **Set defaults** — set `spec.serviceAccountName` if not set.

```yaml
mutate:
  patchStrategicMerge:
    metadata:
      labels:
        +(team): "platform"     # '+' means "add if not present"
  patchesJson6902: |-
    - op: add
      path: /metadata/annotations/managed-by
      value: kyverno
```

### 5.1 The `+` notation

In `patchStrategicMerge`, `+(key): value` means "add this key with this value if not present". The `+` is the "add if missing" marker.

### 5.2 Mutating with `patchesJson6902`

For more complex mutations, use `patchesJson6902` with JSON Patch:

```yaml
patchesJson6902: |-
  - op: add
    path: /spec/containers/0/env/-
    value:
      name: LOG_LEVEL
      value: info
```

This adds an environment variable to the first container.

## 6. Generation Rules

A `generate` rule **creates new resources** when a matching object is created. Common uses:

* **Create a NetworkPolicy** for every new Namespace.
* **Create a ResourceQuota** for every new Namespace.
* **Create a RoleBinding** for a ServiceAccount.

```yaml
generate:
  apiVersion: v1
  kind: ConfigMap
  name: "{{ request.object.metadata.name }}-config"
  namespace: "{{ request.object.metadata.namespace }}"
  synchronize: true
  data:
    type: generated
    by: kyverno
```

When a matching object is created, Kyverno creates the generated object. With `synchronize: true`, Kyverno also keeps the generated object in sync (e.g. delete it when the source is deleted).

## 7. Verify Image Signatures

Kyverno can **verify image signatures** (cosign from Sigstore) at admission. This is the "only signed images run" pattern.

```yaml
verifyImages:
- imageReferences:
  - "ghcr.io/my-org/*"
  attestors:
  - entries:
    - keys:
        publicKeys: |-
          -----BEGIN PUBLIC KEY-----
          ...
          -----END PUBLIC KEY-----
```

The policy rejects Pods whose images aren't signed by the listed keys. See [[Kubernetes/concepts/L07-security/02-workload-sandboxing/19-image-hardening|Image Hardening]] for the full supply chain picture.

## 8. ClusterPolicy vs Policy

* **ClusterPolicy** — cluster-wide. The standard for most policies.
* **Policy** — namespace-scoped. Less common, useful for "this policy only applies to namespaces with a certain label".

Most policies are ClusterPolicy. The Policy kind is for per-tenant policies.

## 9. Common Patterns

### 9.1 Require labels

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: require-labels }
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-team-label
    match:
      any:
      - resources:
          kinds: ["Pod"]
    validate:
      message: "all Pods must have a 'team' label"
      pattern:
        metadata:
          labels:
            team: "?*"
```

### 9.2 Restrict registries

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: restrict-registries }
spec:
  validationFailureAction: Enforce
  rules:
  - name: approved-registries
    match:
      any:
      - resources:
          kinds: ["Pod"]
    validate:
      message: "images must come from approved registries"
      pattern:
        spec:
          containers:
          - name: "?*"
            image: "gcr.io/my-project/* | 1234.dkr.ecr.us-east-1.amazonaws.com/*"
```

### 9.3 Drop capabilities

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: drop-capabilities }
spec:
  validationFailureAction: Enforce
  rules:
  - name: drop-all
    match:
      any:
      - resources:
          kinds: ["Pod"]
    validate:
      message: "containers must drop ALL capabilities"
      pattern:
        spec:
          containers:
          - name: "?*"
            securityContext:
              capabilities:
                drop: ["ALL"]
```

### 9.4 Disallow host namespaces

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: disallow-host-namespaces }
spec:
  validationFailureAction: Enforce
  rules:
  - name: no-host-pid
    match:
      any:
      - resources:
          kinds: ["Pod"]
    validate:
      message: "hostPID is not allowed"
      pattern:
        spec:
          hostPID: "false|nil"
  - name: no-host-ipc
    match:
      any:
      - resources:
          kinds: ["Pod"]
    validate:
      message: "hostIPC is not allowed"
      pattern:
        spec:
          hostIPC: "false|nil"
  - name: no-host-network
    match:
      any:
      - resources:
          kinds: ["Pod"]
    validate:
      message: "hostNetwork is not allowed"
      pattern:
        spec:
          hostNetwork: "false|nil"
```

### 9.5 Add default labels

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: add-default-labels }
spec:
  rules:
  - name: add-team-label
    match:
      any:
      - resources:
          kinds: ["Pod", "Service", "Deployment"]
    mutate:
      patchStrategicMerge:
        metadata:
          labels:
            +(team): "platform"
```

## 10. Background Scans

A policy with `background: true` runs on **existing objects**, not just at admission. The background scan runs every few minutes (configurable).

```yaml
spec:
  background: true
```

The background scan produces **Policy Reports** (CRDs) that summarize violations:

```yaml
apiVersion: wgpolicyk8s.io/v1alpha2
kind: PolicyReport
metadata:
  name: polr-namespace-name
results:
- policy: restrict-registries
  rule: approved-registries
  message: "image 'docker.io/library/nginx' is not from an approved registry"
  resources:
  - name: my-pod
    namespace: default
  result: fail
```

The PolicyReport is the audit result. Tools (like the Kyverno CLI) can summarize it.

## 11. Kyverno vs OPA / Gatekeeper

| | Kyverno | OPA / Gatekeeper |
|---|---|---|
| **Policy language** | YAML (k8s-native) | Rego (DSL) |
| **Engine** | Kyverno pod | OPA + Gatekeeper |
| **Learning curve** | Low (k8s YAML) | Medium (Rego) |
| **Expressiveness** | Medium | High |
| **Multi-system** | k8s only | k8s, API gateway, CI, etc. |
| **Mutations** | First-class | Limited (in 3.7+) |
| **Image signature verification** | Built-in (cosign) | Separate (Connaisseur) |
| **Background scans** | Yes (`background: true`) | Yes (audit mode) |
| **CEL support** | Yes (Kyverno 1.7+) | No |
| **Performance** | Good (in-process for CEL) | Medium (separate process) |

The decision:

* **Use Kyverno** for k8s-only policies, especially if your team is YAML-fluent.
* **Use OPA / Gatekeeper** for multi-system policy or if you need Rego's expressiveness.

## 12. Kyverno CLI

The `kyverno` CLI is the **shift-left tool** for Kyverno. It validates manifests against policies in CI.

```bash
# install
brew install kyverno

# validate a manifest against a policy
kyverno apply policy.yaml --resource manifest.yaml

# validate a directory of manifests
kyverno apply policies/ --resource manifests/

# test mode
kyverno test policies/
# looks for test cases in the policies dir
```

The test mode is what makes Kyverno policies **CI-friendly**. You can write tests:

```yaml
# policy.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: test-policy }
spec: {...}

# test-valid.yaml
input:
  kind: Pod
  spec: {...}      # valid
result: pass
```

```bash
kyverno test policies/
# runs all tests in the policies dir
```

This is **the killer feature of Kyverno**: policies with tests, in CI. No "deploy and see what breaks".

## 13. Kyverno + CEL

Kyverno 1.7+ supports **CEL (Common Expression Language)** for conditions. CEL is the same language k8s uses for CRD validation and `ValidatingAdmissionPolicy`.

```yaml
validate:
  message: "image must come from approved registry"
  cel:
    expressions:
    - expression: "object.spec.containers.all(c, c.image.startsWith('gcr.io/'))"
      message: "image must start with gcr.io/"
```

CEL is faster (compiled, in-process) and more familiar (JavaScript-ish). For most simple policies, CEL is the better choice.

For complex policies, Kyverno's pattern matching or JMESPath is more readable.

## 14. Operations and Debugging

### 14.1 Common commands

```bash
# check the Kyverno pods
kubectl -n kyverno get pods

# list policies
kubectl get clusterpolicy

# describe a policy
kubectl describe clusterpolicy <name>

# check the policy report
kubectl get policyreport -A
# shows violations on existing objects
```

### 14.2 The "policy is rejecting everything" case

```bash
# 1. Find the violating object
kubectl get events --field-selector reason=FailedCreate -A
# look for "kyverno" in the event message

# 2. See which policy denied it
kubectl get events --field-selector involvedObject.kind=Pod -A
# the event has the policy name

# 3. Check the policy
kubectl get clusterpolicy <name> -o yaml

# 4. Test the policy in isolation
kyverno apply <policy> --resource <manifest>
```

### 14.3 The "Kyverno is slow" case

```bash
# 1. Check the response time metric
kubectl -n kyverno port-forward <kyverno-pod> 8000:8000
curl localhost:8000/metrics

# 2. Check the policy for expensive patterns
# large iterations, complex regex

# 3. Add namespaceSelector / objectSelector
# use the match's selector to limit scope
```

## 15. Gotchas and Common Mistakes

### 15.1 The 20+ common mistakes

1. **Kyverno policies are k8s objects.** A `kubectl delete` removes the policy. Be careful with GitOps rollbacks.

2. **`validationFailureAction: Enforce` blocks.** A typo in a policy blocks all matching resources. Use `Audit` first.

3. **`background: true` runs on existing objects.** It can find many violations. Plan to triage.

4. **The `match` is critical.** A `match` without a namespace selector applies cluster-wide.

5. **A pattern with a missing key doesn't match.** A pattern `metadata.labels.team: "?*"` requires the `team` label. If the label is missing, the pattern doesn't match, and the request is denied (or audited).

6. **The `?` and `*` wildcards are Kyverno-specific.** They're not standard regex. `?` = 1 char, `*` = 0+ chars.

7. **The `exclude` is for what NOT to match.** Use it to carve out exceptions (e.g. system namespaces).

8. **A `mutate` rule must be careful with patches.** A bad patch is rejected by the apiserver. The Pod fails to create.

9. **A `generate` rule creates new objects.** If the policy is wrong, the generated objects are wrong too. Use `synchronize: true` carefully.

10. **The `verifyImages` rule requires the image registry to support cosign signatures.** Some registries don't.

11. **Kyverno's CEL expressions are limited** compared to a full Rego. For complex logic, use JMESPath or Kyverno's native pattern matching.

12. **A `ClusterPolicy` and a `Policy` with the same name conflict.** Use unique names.

13. **The `kyverno` CLI is separate from the cluster component.** Install the CLI for CI, the Deployment for the cluster.

14. **Background scans produce PolicyReports.** The reports can grow large. Clean up old reports.

15. **A `match` with `any` is OR, `all` is AND.** A `match` with both `any` and `all` is "any of these, and all of these".

16. **The `exclude` doesn't have to be the inverse of `match`.** It's a separate filter.

17. **A policy that uses `request.object` is for the new object.** For UPDATE, use `request.oldObject` to access the previous state.

18. **The `validationFailureAction: Audit` mode still allows the request.** The violation is logged, not enforced.

19. **A `mutate` rule can run before or after validation.** The order is: mutators → validators. A mutation can affect the validation outcome.

20. **Kyverno's `patchesJson6902` is JSON Patch, not JSON Merge Patch.** Different syntax. JSON Patch uses `op` (add / remove / replace / test).

21. **The `name` field on a policy rule is for display.** It's used in the PolicyReport.

22. **A policy that depends on cluster state** (e.g. "no other Policy allows this image") can be hard to express. Kyverno can call out to external data, but it's complex.

23. **A `PolicyReport` is per-namespace by default.** Cluster-scoped PolicyReports are `ClusterPolicyReport`.

24. **A failed Kyverno admission is logged in the apiserver's audit log.** Use audit logs to find "what was blocked and why".

25. **The Kyverno pod's memory is correlated with the number of policies.** A cluster with 100 policies may need 1+ GB. Tune the Kyverno Deployment.

26. **`any` and `all` in `match` are different from logical OR/AND in `validate.deny.conditions`.** The match is resource-based; the conditions are object-based.

27. **A `pattern` with `containers` requires the array.** If the object has no containers, the pattern doesn't match.

28. **The `synchronize: true` on a generate rule can be expensive.** It runs on every change to the matched object.

29. **Kyverno's `request.userInfo` shows who's making the request.** Use it for "only allow alice to create Pods" policies.

30. **A policy that checks `metadata.generation` is for UPDATE.** Generation 1 = first update. The pattern is usually for the new state.

## See also

* [[Kubernetes/concepts/L07-security/04-admission-policy/11-opa-gatekeeper|OPA / Gatekeeper]] — the alternative policy engine
* [[Kubernetes/concepts/L07-security/04-admission-policy/10-admission-controllers|Admission Controllers]] — where Kyverno fits
* [[Kubernetes/concepts/L07-security/02-workload-sandboxing/06-pod-security-standards|PSS]] — the built-in alternative
* [[Kubernetes/concepts/L07-security/02-workload-sandboxing/19-image-hardening|Image Hardening]] — image signature verification
