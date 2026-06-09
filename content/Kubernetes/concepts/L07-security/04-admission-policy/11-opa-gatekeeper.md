# OPA and Gatekeeper

*"https://www.openpolicyagent.org/ | https://open-policy-agent.github.io/gatekeeper/"*

OPA (Open Policy Agent) is a **policy engine** that decouples policy from code. It evaluates policies written in **Rego** (a DSL) against inputs (typically JSON), and returns decisions. **Gatekeeper** is the k8s-specific implementation of OPA — it runs as a validating (and optionally mutating) admission webhook, evaluates Rego policies against k8s objects, and rejects (or warns about) non-compliant objects. OPA / Gatekeeper is one of the two major policy engines in the k8s ecosystem (the other being Kyverno).

### Table of Contents

1. [The Policy Engine Concept](#1-the-policy-engine-concept)
2. [OPA Architecture](#2-opa-architecture)
3. [Rego — the Policy Language](#3-rego--the-policy-language)
4. [Gatekeeper Components](#4-gatekeeper-components)
5. [The Constraint Template Pattern](#5-the-constraint-template-pattern)
6. [A Working Example](#6-a-working-example)
7. [The Audit Mode](#7-the-audit-mode)
8. [Mutating with Gatekeeper](#8-mutating-with-gatekeeper)
9. [OPA Outside Gatekeeper](#9-opa-outside-gatekeeper)
10. [The Rego vs CEL Decision](#10-the-rego-vs-cel-decision)
11. [Performance and Caching](#11-performance-and-caching)
12. [Common Policy Patterns](#12-common-policy-patterns)
13. [Operations and Debugging](#13-operations-and-debugging)
14. [Gotchas and Common Mistakes](#14-gotchas-and-common-mistakes)

---

## 1. The Policy Engine Concept

A **policy engine** is a system that takes inputs and returns decisions:

```
Input (JSON)         Policy (Rego)         Output (Decision)
+-----------------+  +----------------+  +----------------+
| Pod spec        |  | "all images    |  | allowed: true  |
| (kind, name,    |→ |  must come     |→ | OR             |
|  namespace,     |  |  from ECR"     |  | allowed: false |
|  spec, ...)     |  |                |  |                |
+-----------------+  +----------------+  +----------------+
```

In k8s, the input is a k8s object (Pod, Deployment, etc.), the policy is "must come from approved registries", and the output is "this Pod is allowed" or "this Pod is denied".

### 1.1 Why decouple policy from code

If policy is in the application code:

* Every change requires a code change.
* The team that owns the app is the only one that can review / change.
* Policy is per-app, not cluster-wide.

If policy is in a policy engine:

* Policy is declarative, not imperative.
* Multiple apps can share the same policy.
* The platform team can own policy without owning the apps.

OPA's design: policy is data, not code. Rego is the language; OPA is the evaluator. You can ship the same Rego package to multiple enforcement points (k8s admission, API gateway, CI checks, etc.).

## 2. OPA Architecture

```
OPA decision:
  1. Load Rego policy
  2. Load input (JSON)
  3. Evaluate
  4. Return decision
```

OPA is **stateless**. It doesn't have a database. It just evaluates Rego against the input. The "data" in OPA is the input + any data the policy imports (loaded from files, APIs, etc.).

The "decision" is whatever the policy returns. For Gatekeeper, it's `allowed: true | false`.

### 2.1 OPA vs Gatekeeper

* **OPA** — the engine. Generic. Can be embedded in any system. Has its own HTTP API.
* **Gatekeeper** — the k8s implementation. Runs as a webhook. Uses OPA under the hood (or a recent fork, see Conftest below).

Gatekeeper is the deployment; OPA is the engine.

### 2.2 The Conftest tool

Conftest is a CLI that runs OPA against config files. Useful for CI:

```bash
# install
brew install conftest

# run against a manifest
conftest test deployment.yaml
# applies the policy in /policy/*.rego
```

Conftest is the "shift-left" version of Gatekeeper. Same Rego, but for static files in CI.

## 3. Rego — the Policy Language

Rego is a **declarative logic language**. It's not imperative (no if/else); it's a set of rules that produce values.

### 3.1 A simple rule

```rego
package kubernetes.admission

# Rule: deny if the image doesn't come from the approved registry
deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    not startswith(container.image, "gcr.io/my-project/")
    msg := sprintf("image '%v' is not from the approved registry", [container.image])
}
```

The structure:

* `package` — the namespace for the rule.
* `deny[msg]` — a **set of denial messages**. If the set is non-empty, the request is denied.
* `input.request.kind.kind == "Pod"` — an expression. If true, the rule continues.
* `container := input.request.object.spec.containers[_]` — a variable. The `_` is a wildcard for array index.
* `not startswith(...)` — negation. The rule applies if the image is NOT in the approved registry.
* `msg := ...` — set the message.

The rule produces a denial message for every container with a bad image. If the set is empty, the request is allowed.

### 3.2 The input format

The input to OPA is a JSON object. For Gatekeeper, it's an `AdmissionReview` request:

```json
{
  "request": {
    "uid": "...",
    "kind": {"group": "", "version": "v1", "kind": "Pod"},
    "operation": "CREATE",
    "object": {... full Pod ...},
    "userInfo": {...}
  }
}
```

A Rego rule accesses `input.request.object.spec.containers` to get the Pod's containers.

### 3.3 Common Rego patterns

**Iterate over a list:**

```rego
deny[msg] {
    input.request.object.spec.containers[i]
    ...
}
```

The `[i]` binds `i` to each index. You can also use `[_]` for "any element" (no binding).

**Multiple conditions:**

```rego
deny[msg] {
    input.request.kind.kind == "Pod"
    input.request.object.spec.containers[_]
    # multiple conditions separated by newlines (implicit AND)
}
```

**Check existence:**

```rego
deny[msg] {
    not input.request.object.metadata.labels.app
    msg := "all Pods must have the 'app' label"
}
```

**Combine with OR:**

```rego
deny[msg] {
    input.request.object.spec.containers[_].securityContext.privileged == true
    msg := "privileged containers are not allowed"
}
# OR: separate deny rule
deny[msg] {
    input.request.object.spec.hostNetwork == true
    msg := "hostNetwork is not allowed"
}
```

The `deny` set is the union of all `deny` rules. If any rule produces a message, the request is denied.

### 3.4 The `data` builtin

OPA can load external data via the `data` builtin. For example:

```rego
deny[msg] {
    container := input.request.object.spec.containers[_]
    not data.approved_images[container.image]
    msg := sprintf("image %v is not in the approved list", [container.image])
}
```

The `data.approved_images` is loaded from outside OPA — a JSON file, a webhook, etc.

In Gatekeeper, this is the **"external data" provider** pattern. The Gatekeeper calls a sidecar to get data for the policy.

## 4. Gatekeeper Components

Gatekeeper is composed of:

* **`gatekeeper-controller-manager`** — the control plane. Watches for ConstraintTemplates and Constraints, configures the webhook, audits existing objects.
* **`gatekeeper-audit`** (in v3.7+) — runs periodically to check existing objects against the policies. Reports violations.
* **The admission webhook** — called by the apiserver for every request, evaluates policies.
* **Mutating webhook** (in v3.7+) — can mutate objects (e.g. add labels).
* **ConstraintTemplate** — a CRD that defines a parameterized policy.
* **Constraint** — an instance of a ConstraintTemplate with specific values.

The architecture:

```
apiserver
   │
   │ AdmissionReview
   │
gatekeeper-controller-manager (validating webhook)
   │
   ├── load templates, constraints, syncs
   │
   ├── evaluate policy (Rego)
   │
   └── return allowed / denied
```

## 5. The Constraint Template Pattern

A **ConstraintTemplate** is a CRD that defines a parameterized Rego policy. The "constraint" is an instance of the template with specific values.

### 5.1 A ConstraintTemplate

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sapprovedregistry
spec:
  crd:
    spec:
      names: { kind: K8sApprovedRegistry }
      validation:
        openAPIV3Schema:
          properties:
            registries:
              type: array
              items: { type: string }
  targets:
  - target: admission.k8s.gatekeeper.sh
    rego: |
      package k8sapprovedregistry

      violation[{"msg": msg, "details": {}}] {
          container := input.review.object.spec.containers[_]
          not startswith(container.image, input.parameters.registries[_])
          msg := sprintf("image '%v' is not from an approved registry", [container.image])
      }
```

The template:

* Defines a CRD `K8sApprovedRegistry` with a `registries` parameter.
* The Rego policy uses `input.parameters.registries` (the values from the constraint).

### 5.2 A Constraint (instance)

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sApprovedRegistry
metadata: { name: must-come-from-ecr }
spec:
  match:
    kinds: [{ apiGroups: [""], kinds: ["Pod"] }]
    namespaces: ["prod", "staging"]   # optional
  parameters:
    registries:
    - "123456789.dkr.ecr.us-east-1.amazonaws.com/"
    - "gcr.io/my-project/"
```

The constraint:

* Matches Pods in `prod` and `staging`.
* The `parameters.registries` is passed to the Rego as `input.parameters.registries`.

Gatekeeper combines the template + constraint to produce the final Rego. The result is the policy that's evaluated.

## 6. A Working Example

A complete policy: "all Pods must have a `team` label, and the value must be one of `frontend`, `backend`, or `platform`."

### 6.1 The template

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata: { name: k8srequiredlabels }
spec:
  crd:
    spec:
      names: { kind: K8sRequiredLabels }
      validation:
        openAPIV3Schema:
          properties:
            labels:
              type: array
              items: { type: object }
  targets:
  - target: admission.k8s.gatekeeper.sh
    rego: |
      package k8srequiredlabels

      violation[{"msg": msg, "details": {}}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_].key}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("missing labels: %v", [missing])
      }
```

### 6.2 The constraint

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata: { name: must-have-team-label }
spec:
  match:
    kinds: [{ apiGroups: [""], kinds: ["Pod"] }]
  parameters:
    labels:
    - key: team
      allowedRegex: "^(frontend|backend|platform)$"
```

Wait, that's a slightly different pattern. Let me redo with the team-only check:

```yaml
# (refined rego for the team label)
violation[{"msg": msg, "details": {}}] {
    value := input.review.object.metadata.labels.team
    not valid_team(value)
    msg := sprintf("invalid team label: '%v'", [value])
}

valid_team(team) {
    team == "frontend"
}
valid_team(team) {
    team == "backend"
}
valid_team(team) {
    team == "platform"
}
```

This is the "deny if the team label is not one of the allowed values" pattern. The Rego is the policy; the constraint is the instance.

## 7. The Audit Mode

Audit mode runs policies against **existing objects** in the cluster, not just at admission time.

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sApprovedRegistry
metadata: { name: must-come-from-ecr }
spec:
  enforcementAction: dryrun     # "warn" / "dryrun" / "deny"
  match: {...}
  parameters: {...}
```

The `enforcementAction` field:

* `deny` (default) — reject non-compliant objects at admission.
* `dryrun` — allow, but record a violation in the audit log.
* `warn` — allow, but warn the user via the admission response.

`dryrun` is the standard "I'm rolling out a new policy, let me see what's already broken" mode.

## 8. Mutating with Gatekeeper

Gatekeeper 3.7+ supports **mutating admission** via the `MutatingAdmissionPolicy` CRD. You write a Rego that returns a JSON patch:

```rego
package mutator.default_labels

mutate[patch] {
    not input.review.object.metadata.labels.app
    patch := {"op": "add", "path": "/metadata/labels/app", "value": input.review.object.metadata.name}
}
```

The patch is applied to the object before it's stored. This is the "inject default labels" pattern.

Mutating webhooks are riskier than validating. A bug in the mutator can corrupt objects. Use sparingly.

## 9. OPA Outside Gatekeeper

OPA is generic. It can be used for:

* **API gateway authorization** — OPA at the gateway, evaluates "can this user call this endpoint".
* **Microservice authorization** — the app calls OPA at request time: "can this user access this resource?"
* **Terraform validation** — Conftest (OPA) in CI, runs Rego against `.tf` files.
* **SSH / sudo authorization** — OPA at the authn layer.
* **Kafka authorization** — OPA at the broker, evaluates "can this client read this topic?"

For k8s, Gatekeeper is the deployment. For everything else, OPA is the engine.

## 10. The Rego vs CEL Decision

CEL (Common Expression Language) is the alternative to Rego, supported natively by k8s (no OPA needed).

| | Rego | CEL |
|---|---|---|
| **Used in** | OPA / Gatekeeper | k8s native (1.30+), Kyverno |
| **Standard** | OPA's DSL | Google's CEL (used in CEL-Go) |
| **Engine** | OPA (separate binary) | Built into the apiserver |
| **Performance** | Slower (separate process) | Faster (in-process) |
| **Expressiveness** | High (logic programming) | Medium (expression language) |
| **Familiarity** | Rego-specific | More familiar to most developers |

The decision:

* **Use Rego** if you want to share policies across systems (k8s, API gateway, CI, etc.) — OPA is the lingua franca.
* **Use CEL** if you're k8s-only and want the simplest deployment — no extra pods.
* **Use Kyverno** if you want k8s-native (no separate language) and YAML-style policies.

## 11. Performance and Caching

Gatekeeper is **on the admission hot path**. A slow Gatekeeper slows down all admission.

### 11.1 The cache

Gatekeeper caches the result of evaluation per (object UID, policy). If a request comes in for the same object with the same policy, the cached result is used. The cache is invalidated when constraints or templates change.

### 11.2 The metrics

```bash
# check the Gatekeeper pod's metrics
kubectl -n gatekeeper-system port-forward <gatekeeper-pod> 8888:8888
curl localhost:8888/metrics
```

Key metrics:

* `gatekeeper_admission_requests_total` — total admission requests.
* `gatekeeper_admission_response_time_seconds` — response time.
* `gatekeeper_violations_total` — number of policy violations.

### 11.3 The slow policy

A policy that's slow:

* Has a large iteration (e.g. over all containers, all env vars, all volumes).
* Calls out to external data.
* Has expensive string operations.

To speed up:

* Limit the constraint's `match` to specific resources / namespaces.
* Use the `match` to skip irrelevant requests.
* Avoid external data calls.

## 12. Common Policy Patterns

### 12.1 "All images must come from a specific registry"

```rego
violation[{"msg": msg}] {
    container := input.review.object.spec.containers[_]
    not startswith(container.image, input.parameters.registries[_])
    msg := sprintf("image '%v' is not from an approved registry", [container.image])
}
```

### 12.2 "All Pods must have resource requests and limits"

```rego
violation[{"msg": msg}] {
    container := input.review.object.spec.containers[_]
    not container.resources.requests
    msg := sprintf("container '%v' has no resource requests", [container.name])
}
violation[{"msg": msg}] {
    container := input.review.object.spec.containers[_]
    not container.resources.limits
    msg := sprintf("container '%v' has no resource limits", [container.name])
}
```

### 12.3 "No privileged containers"

```rego
violation[{"msg": msg}] {
    container := input.review.object.spec.containers[_]
    container.securityContext.privileged == true
    msg := sprintf("container '%v' is privileged", [container.name])
}
```

### 12.4 "No host namespaces"

```rego
violation[{"msg": msg}] {
    input.review.object.spec.hostNetwork == true
    msg := "hostNetwork is not allowed"
}
violation[{"msg": msg}] {
    input.review.object.spec.hostPID == true
    msg := "hostPID is not allowed"
}
violation[{"msg": msg}] {
    input.review.object.spec.hostIPC == true
    msg := "hostIPC is not allowed"
}
```

### 12.5 "All Deployments must have at least 3 replicas"

```rego
violation[{"msg": msg}] {
    input.review.object.kind == "Deployment"
    input.review.object.spec.replicas < 3
    msg := "Deployments must have at least 3 replicas"
}
```

(Note: this needs to be on a Deployment object, not a Pod. The match's `kinds` would be `apps/Deployment`.)

## 13. Operations and Debugging

### 13.1 Common commands

```bash
# check the Gatekeeper pods
kubectl -n gatekeeper-system get pods

# list templates
kubectl get constrainttemplates

# list constraints
kubectl get constraints
# or by kind
kubectl get k8sapprovedregistry

# describe a constraint
kubectl describe k8sapprovedregistry <name>

# check the audit status
kubectl get k8sapprovedregistry <name> -o jsonpath='{.status.violations}'
# shows existing violations
```

### 13.2 The "policy is rejecting everything" case

```bash
# 1. Find the violating object
kubectl get events --field-selector reason=FailedCreate -A
# look for "admission webhook denied the request"

# 2. Check which policy denied it
# the event message usually says "Denied by K8sApprovedRegistry" or similar

# 3. See the policy
kubectl get k8sapprovedregistry <name> -o yaml
# look at the parameters

# 4. See the violation
kubectl get k8sapprovedregistry <name> -o jsonpath='{.status.violations}'
# the violation object has the offending object name
```

### 13.3 The "Gatekeeper is slow" case

```bash
# 1. Check the response time metric
kubectl -n gatekeeper-system port-forward <gatekeeper-pod> 8888:8888
curl localhost:8888/metrics | grep response_time

# 2. Check the policy for expensive operations
# large iterations, external data calls

# 3. Add namespaceSelector / objectSelector to limit scope
# the constraint's match should be as narrow as possible
```

## 14. Gotchas and Common Mistakes

### 14.1 The 20+ common mistakes

1. **Rego is not a general-purpose language.** It's a DSL for policy. Don't try to do everything in it.

2. **A policy that catches "all" resources is dangerous.** Gatekeeper runs on every admission. A bad policy can block all Pods.

3. **Use `dryrun` first.** Don't go straight to `deny`. Run in audit mode, see the violations, then promote to `deny`.

4. **The `match` is critical.** A constraint without a namespace match applies cluster-wide. A constraint with a wrong resource match applies to the wrong objects.

5. **The `admissionReviewVersions` on the Gatekeeper's webhook config** is `["v1"]`. If you're on an older k8s, may be different.

6. **A mutating webhook is harder to debug than a validating one.** The patches must be correct. A bad patch is rejected by the apiserver.

7. **Rego's `[_]` is "any element".** A rule with multiple `[_]` is "any combination". Be careful — the rule may match more than you think.

8. **The `data` builtin requires external data providers.** Setting up external data is non-trivial. For most policies, the input is enough.

9. **A ConstraintTemplate's Rego must be valid Rego.** A syntax error in the Rego is a silent failure — Gatekeeper logs an error, but the policy is not active.

10. **Constraint parameters are validated against the CRD's OpenAPI schema.** A bad parameter is rejected by the apiserver.

11. **The `audit` mode runs periodically.** It doesn't run on every object. There's a default interval (60s) for audits.

12. **The `enforcementAction` field is on the Constraint, not the Template.** The same Template can have Constraints with different enforcement actions.

13. **A `dryrun` Constraint still produces audit records.** Look at the `status.violations` to see what would be denied.

14. **A `warn` Constraint produces a warning in the `kubectl` output.** The user sees "Warning: <policy> would have denied this."

15. **Gatekeeper's mutating webhook is in beta.** It works, but the API may change.

16. **A policy that depends on a `default` value of an unset field may not work.** Rego can't distinguish "field unset" from "field is empty string".

17. **The `input.review.object` is the full k8s object** (Pod, Deployment, etc.). The structure depends on the kind.

18. **A policy that requires the object to be in a specific state** (e.g. "Pod has a running status") doesn't work at admission time. The Pod is being created; the status is not yet set.

19. **Rego's `count()` is for set cardinality.** Use `count(...) > 0` to check non-emptiness.

20. **The `sprintf` function is for string formatting.** Use it to build dynamic messages.

21. **A ConstraintTemplate's CRD is auto-generated.** The CRD's name is the template's `metadata.name`, the kind is `crd.spec.names.kind`.

22. **A Constraint must reference a registered ConstraintTemplate.** If the template doesn't exist, the constraint is rejected.

23. **The audit results are in `status.violations` of the Constraint.** Not in events.

24. **Gatekeeper is a single point of failure for admission.** If Gatekeeper is down, `failurePolicy: Ignore` is the safe default (don't reject).

25. **The `rego` field in a ConstraintTemplate is a string.** Multi-line strings use YAML's `|` (literal) or `>` (folded).

26. **A Rego rule with a missing condition may not match.** The rule produces no violations, so the request is allowed. Be explicit.

27. **A policy that uses `time.now()` is not idempotent.** The same request evaluated twice may produce different results.

28. **A policy that uses `rand` is not idempotent.** Don't.

29. **The `match` selector supports `excludedNamespaces` and `labelSelector`.** Use them to scope the policy precisely.

30. **A `ClusterConstraint` (not `Constraint`) is cluster-scoped.** Most constraints are namespace-scoped. ClusterConstraints are for policies that need cluster-wide visibility.

## See also

* [[Kubernetes/concepts/L07-security/12-kyverno|Kyverno]] — the alternative to OPA / Gatekeeper
* [[Kubernetes/concepts/L07-security/10-admission-controllers|Admission Controllers]] — how Gatekeeper fits in
* [[Kubernetes/concepts/L07-security/06-pod-security-standards|PSS]] — the built-in alternative for basic checks
* [[Kubernetes/concepts/L07-security/19-image-hardening|Image Hardening]] — one of the most common policy targets
