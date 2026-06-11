# RBAC (Role-Based Access Control)

*"https://kubernetes.io/docs/reference/access-authn-authz/rbac/"*

RBAC is the **standard authorization model** in Kubernetes. It defines who can do what via four resource types: **Role**, **ClusterRole**, **RoleBinding**, **ClusterRoleBinding**. Every action in the apiserver — every `kubectl`, every controller reconciliation, every admission webhook — is checked against RBAC. This note covers the full picture: the four objects, the verbs, the built-in roles, the aggregation mechanism, the impersonation rules, the kubelet's Node authorizer, and the operational patterns.

### Table of Contents

1. [The Four Objects](#1-the-four-objects)
2. [The Basic Example](#2-the-basic-example)
3. [The Role / ClusterRole Fields in Depth](#3-the-role--clusterrole-fields-in-depth)
4. [The API Groups Reference](#4-the-api-groups-reference)
5. [The Verbs in Depth](#5-the-verbs-in-depth)
6. [The `resourceNames` Field](#6-the-resourcenames-field)
7. [Subresources](#7-subresources)
8. [The Built-in ClusterRoles](#8-the-built-in-clusterroles)
9. [The Aggregation Rule (ClusterRole)](#9-the-aggregation-rule-clusterrole)
10. [The "Deny by Default" Rule](#10-the-deny-by-default-rule)
11. [The RoleBinding + ClusterRole Pattern](#11-the-rolebinding--clusterrole-pattern)
12. [Subjects in Depth](#12-subjects-in-depth)
13. [The Impersonation Verbs](#13-the-impersonation-verbs)
14. [The Escalate and Bind Verbs](#14-the-escalate-and-bind-verbs)
15. [Authorization for Kubelets](#15-authorization-for-kubelets)
16. [Authorization for System Components](#16-authorization-for-system-components)
17. [The SubjectAccessReview API](#17-the-subjectaccessreview-api)
18. [RBAC for Custom Resources](#18-rbac-for-custom-resources)
19. [The kubebuilder / controller-gen RBAC Markers](#19-the-kubebuilder--controller-gen-rbac-markers)
20. [Common Patterns](#20-common-patterns)
21. [Discovery and Debugging](#21-discovery-and-debugging)
22. [Operations and Debugging](#22-operations-and-debugging)
23. [Gotchas and Common Mistakes](#23-gotchas-and-common-mistakes)

---

## 1. The Four Objects

| Object | Scope | What it does |
|---|---|---|
| **Role** | Namespaced | Set of allowed verbs on resources, within one namespace |
| **ClusterRole** | Cluster-wide | Same, but cluster-wide (or for cluster-scoped resources) |
| **RoleBinding** | Namespaced | Assigns a Role to a User / Group / ServiceAccount, within one namespace |
| **ClusterRoleBinding** | Cluster-wide | Assigns a ClusterRole cluster-wide |

A **Role** is a set of allowed verbs. A **RoleBinding** is who gets that Role. The two are separate so you can reuse Roles across bindings.

A **ClusterRole** is the cluster-scoped counterpart to a Role. It can be:

* **Bound cluster-wide** via a `ClusterRoleBinding`.
* **Bound in a single namespace** via a `RoleBinding` (this is the most useful pattern).

The `RoleBinding` can reference a `ClusterRole`. The result: the **ClusterRole's rules apply in the RoleBinding's namespace**.

## 2. The Basic Example

```yaml
# a Role: "this person can read pods in the default namespace"
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: default
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
# a RoleBinding: "alice is a pod-reader in the default namespace"
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: default
subjects:
- kind: User
  name: alice
  apiGroup: rbac.authorization.k8s.io
- kind: Group
  name: developers
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

Alice can `get` / `list` / `watch` Pods in `default`. The "developers" group can too.

## 3. The Role / ClusterRole Fields in Depth

### `rules` — what this role allows

```yaml
rules:
- apiGroups: [""]
  resources: ["pods"]
  resourceNames: ["my-specific-pod"]   # optional, limit to specific instances
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "update", "patch"]
- apiGroups: ["batch"]
  resources: ["jobs"]
  verbs: ["*"]                         # all verbs
- nonResourceURLs: ["/healthz", "/readyz"]
  verbs: ["get"]
```

A Role can have multiple `rules`. Each rule is a list of (apiGroups, resources, verbs) tuples. The Role allows the union of all rules.

### `aggregationRule` (ClusterRole only)

```yaml
aggregationRule:
  clusterRoleSelectors:
  - matchLabels:
      rbac.example.com/aggregate-to-monitoring: "true"
```

The ClusterRole's permissions are the **union** of all ClusterRoles that match the selector. Used for building modular role hierarchies.

## 4. The API Groups Reference

| API Group | Resources |
|---|---|
| `""` (empty) | Pod, Service, ConfigMap, Secret, Event, Namespace, Node, PersistentVolume, PersistentVolumeClaim, ServiceAccount, Endpoints, ResourceQuota, LimitRange, etc. (the core group) |
| `apps` | Deployment, StatefulSet, DaemonSet, ReplicaSet, ControllerRevision |
| `batch` | Job, CronJob |
| `rbac.authorization.k8s.io` | Role, ClusterRole, RoleBinding, ClusterRoleBinding |
| `networking.k8s.io` | NetworkPolicy, Ingress, IngressClass |
| `storage.k8s.io` | StorageClass, CSIDriver, VolumeAttachment, CSINode |
| `apiextensions.k8s.io` | CustomResourceDefinition |
| `policy` | PodDisruptionBudget, PodSecurityPolicy (deprecated) |
| `admissionregistration.k8s.io` | MutatingWebhookConfiguration, ValidatingWebhookConfiguration |
| `events.k8s.io` | Event |
| `coordination.k8s.io` | Lease |
| `node.k8s.io` | RuntimeClass |
| `flowcontrol.apiserver.k8s.io` | FlowSchema, PriorityLevelConfiguration |
| `certificates.k8s.io` | CertificateSigningRequest |
| `authentication.k8s.io` | TokenReview, SubjectAccessReview |
| `authorization.k8s.io` | (in apiVersions) SubjectAccessReview |
| `autoscaling` | HorizontalPodAutoscaler, Scale |

For custom resources (CRDs), the API group is the CRD's `spec.group`.

Use `kubectl api-resources` to see the full list for your cluster.

## 5. The Verbs in Depth

| Verb | What it does | When you need it |
|---|---|---|
| `get` | Read a single resource (by name) | `kubectl get pod <name>` |
| `list` | Read multiple resources (by selector) | `kubectl get pods` |
| `watch` | Receive updates | controllers, `kubectl get -w` |
| `create` | Make a new one | controllers, kubectl apply (for new objects) |
| `update` | Replace entirely | `kubectl replace` |
| `patch` | Partial modify | `kubectl patch` |
| `delete` | Remove one | `kubectl delete pod <name>` |
| `deletecollection` | Remove all matching | garbage collection |
| `*` | All verbs | admin roles |

For **read**, you need `get` + `list` + `watch` (3 verbs). For **write**, add `create` + `update` + `patch` + `delete` (4 more).

### 5.1 Special verbs

Some resources have **special verbs** beyond the standard ones:

* **`bind`** — for `roles` and `clusterroles`. Allows creating a RoleBinding / ClusterRoleBinding that references this Role.
* **`escalate`** — for `roles` and `clusterroles`. Allows modifying a Role's rules to grant more permissions.
* **`approve`** / **`sign`** — for `certificatesigningrequests`. Allows approving or signing CSRs.
* **`use`** — for `subjectaccessreviews` and `tokenreviews`. Allows creating them.
* **`impersonate`** — for `users`, `groups`, `serviceaccounts`. Allows acting as another identity.
* **`create`** / **`patch`** / **`update`** on `pods/eviction` subresource. The eviction API.

The `bind` and `escalate` verbs are **sensitive** — they let a user modify RBAC. Don't grant them to untrusted users.

## 6. The `resourceNames` Field

```yaml
rules:
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["my-app-secret"]   # only this Secret
  verbs: ["get"]
```

`resourceNames` limits the rule to specific resource instances. It works for:

* **Most named resources** — `secrets`, `configmaps`, `pods`, `services`, etc.
* **Cluster-scoped resources** — `nodes`, `namespaces`, `persistentvolumes`, etc.

It does **NOT** work for:

* **Subresources** — `pods/log`, `pods/exec`, `deployments/scale`, `pods/eviction`.
* **Resources without names** — `bindings`, `componentstatuses` (very few).

The `resourceNames` field is the **right way to limit access to a specific Secret or ConfigMap**. A Role with `resourceNames: ["my-app-secret"]` and `verbs: ["get"]` only allows reading that one Secret.

## 7. Subresources

*"https://kubernetes.io/docs/reference/access-authn-authz/authorization/#referring-to-subresources"*

Some resources have **subresources**:

* `pods/log` — Pod logs.
* `pods/exec` — `kubectl exec`.
* `pods/portforward` — `kubectl port-forward`.
* `pods/eviction` — the eviction API.
* `pods/status` — Pod status updates (used by kubelet).
* `pods/proxy` — `kubectl proxy`.
* `deployments/scale` — `kubectl scale`.
* `deployments/status` — Deployment status.
* `replicasets/scale`, `statefulsets/scale`, etc.
* `nodes/status` — Node status updates.
* `nodes/metrics`, `nodes/proxy` — Node-level access.

Subresources are referenced in RBAC:

```yaml
rules:
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get"]
```

For `pods/log`, the standard pattern:

```yaml
# allow reading logs
- apiGroups: [""]
  resources: ["pods/log", "pods"]
  verbs: ["get", "list"]
```

`pods` (the parent) for `list`, `pods/log` (the subresource) for `get` on logs.

For `pods/eviction`:

```yaml
# allow eviction (used by drain, autoscaler, HPA scale-down)
- apiGroups: [""]
  resources: ["pods/eviction"]
  verbs: ["create"]
```

The `create` verb on `pods/eviction` is what allows calling the eviction API. This is what `kubectl drain`, Cluster Autoscaler, and HPA scale-down all do.

## 8. The Built-in ClusterRoles

k8s ships with these built-in ClusterRoles:

| ClusterRole | What it allows |
|---|---|
| `cluster-admin` | Everything. `*` on `*` for `*`. Use sparingly. |
| `admin` | Most things in a namespace. `*` on most resources. Doesn't allow Role / RoleBinding modification or custom resource access. |
| `edit` | Read/write most resources in a namespace. No Role / RoleBinding, no NetworkPolicy, no ResourceQuota, no CRD, no SecurityContext... wait, it allows SecurityContext. But not PSS / PSA. |
| `view` | Read most resources in a namespace. No Secrets (Secrets are sensitive), no write. |
| `system:masters` | Implicit. Anyone in this group is cluster-admin. |
| `system:node` | Used by kubelets (legacy, before Node authorizer). |
| `system:node-proxier` | For kube-proxy (update Services, Endpoints). |
| `system:kube-controller-manager` | For kube-controller-manager (bound to the system SA). |
| `system:kube-scheduler` | For kube-scheduler. |
| `system:kube-dns` | For kube-dns / CoreDNS. |
| `system:public-info-viewer` | Anonymous read access to non-sensitive info (ClusterInfo, etc.). |
| `system:discovery` | Read access for service discovery (used by all SAs by default, until k8s 1.16+). |
| `system:basic-user` | Read access to the user's own info. |
| `system:authenticated` | Implicit. Anyone authenticated is in this group. |
| `system:unauthenticated` | Implicit. Anonymous users. |
| `system:serviceaccounts` | All SAs cluster-wide. |
| `system:serviceaccounts:<ns>` | All SAs in a namespace. |
| `system:nodes` | All kubelets. |

The **standard pattern**:

* Bind `view` to read-only groups.
* Bind `edit` to developers in their namespace.
* Bind `admin` to namespace owners.
* Bind `cluster-admin` to operators (rarely).

The built-in `view` role does **NOT** include `watch` on Secrets. Secrets are sensitive. To allow reading a specific Secret, create a custom Role with `resourceNames`.

## 9. The Aggregation Rule (ClusterRole)

*"https://kubernetes.io/docs/reference/access-authn-authz/rbac/#aggregated-clusterroles"*

A ClusterRole can **aggregate** rules from other ClusterRoles. The `aggregationRule` defines a selector; all ClusterRoles that match the selector are **merged** into this one.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: monitoring
aggregationRule:
  clusterRoleSelectors:
  - matchLabels:
      rbac.example.com/aggregate-to-monitoring: "true"
rules: []   # the aggregated rules (filled in by the apiserver)
```

Any ClusterRole with the label `rbac.example.com/aggregate-to-monitoring: "true"` is included.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
  labels:
    rbac.example.com/aggregate-to-monitoring: "true"
rules:
- apiGroups: [""]
  resources: ["pods", "services", "endpoints"]
  verbs: ["get", "list", "watch"]
```

The `prometheus` ClusterRole is now part of the `monitoring` ClusterRole. **A user with `monitoring` gets `prometheus`'s rules.**

The aggregation is **automatic and dynamic**. Add a label to a ClusterRole, and the apiserver re-aggregates.

The built-in `admin`, `edit`, `view` use aggregation. Built-in ClusterRoles for system components have labels like `kubernetes.io/bootstrapping=rbac-defaults` and are aggregated into `system:public-info-viewer` etc.

## 10. The "Deny by Default" Rule

**No rule that matches = deny.** There's no "allow if not explicitly denied". Every verb on every resource needs an explicit allow.

```yaml
# alice has "get pods" but tries to "create pods"
kubectl auth can-i create pods --as=alice
# no — alice can only "get" pods, not "create"
```

This is the safe default. **The principle of least privilege** at the authz level.

## 11. The RoleBinding + ClusterRole Pattern

A RoleBinding can reference a ClusterRole, not just a Role. The result: the **ClusterRole's rules apply in the RoleBinding's namespace**.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: edit, namespace: team-a }
roleRef:
  kind: ClusterRole
  name: edit
subjects:
- kind: Group
  name: team-a
```

This gives "team-a" the `edit` ClusterRole's permissions in the `team-a` namespace. The `edit` ClusterRole itself is cluster-scoped, but the binding scopes it to a namespace.

This is the **standard pattern**: bind built-in ClusterRoles to groups in namespaces.

## 12. Subjects in Depth

A `RoleBinding`'s `subjects` can be:

* **`User`** — a username. `alice`, `alice@example.com`, `system:serviceaccount:default:my-sa`.
* **`Group`** — a group name. `developers`, `system:authenticated`, `system:masters`.
* **`ServiceAccount`** — a SA. Format: `kind: ServiceAccount, name: <sa>, namespace: <ns>`.

```yaml
subjects:
- kind: User
  name: alice
  apiGroup: rbac.authorization.k8s.io
- kind: Group
  name: developers
  apiGroup: rbac.authorization.k8s.io
- kind: ServiceAccount
  name: my-app
  namespace: default
```

The `apiGroup` is `rbac.authorization.k8s.io` for User and Group. For ServiceAccount, the `namespace` is required (and is **where the SA is**, not where the binding is).

### 12.1 The cross-namespace SA

A SA in one namespace can be a subject in a binding in another:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: ci-deploy, namespace: prod }
subjects:
- kind: ServiceAccount
  name: ci
  namespace: ci                # SA in ci namespace
roleRef:
  kind: Role
  name: deploy
  apiGroup: rbac.authorization.k8s.io
```

The `ci` SA in `ci` namespace can deploy in `prod` namespace. The binding's namespace is where the permissions apply.

## 13. The Impersonation Verbs

*"https://kubernetes.io/docs/reference/access-authn-authz/authentication/#user-impersonation"*

To allow a user to impersonate another, grant the `impersonate` verb:

```yaml
# allow alice to impersonate the SA my-app
rules:
- apiGroups: [""]
  resources: ["serviceaccounts"]
  name: "my-app"
  verbs: ["impersonate"]

# allow alice to impersonate any user
rules:
- apiGroups: ["authentication.k8s.io"]
  resources: ["uids"]
  verbs: ["impersonate"]
- apiGroups: [""]
  resources: ["users", "groups", "serviceaccounts"]
  verbs: ["impersonate"]
```

The user being impersonated becomes the new "user" in the apiserver. The original user is recorded as the `impersonator` (in `user.extra`).

`impersonate` is a powerful verb. It can be used to escalate (act as a more privileged user). **Don't grant it broadly.**

## 14. The Escalate and Bind Verbs

Two verbs that allow modifying RBAC:

* **`escalate`** — modify a Role's rules (escalate the permissions).
* **`bind`** — create a RoleBinding / ClusterRoleBinding that references a Role.

```yaml
# allow alice to escalate the "deploy" Role
rules:
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["roles"]
  resourceNames: ["deploy"]
  verbs: ["escalate"]
```

A user with `escalate` on a Role can **add more permissions to that Role**. If alice has `escalate` on `deploy`, alice can add `create secrets` to the `deploy` Role — and alice then has `create secrets` (via the binding to `deploy`).

This is **privilege escalation** in the RBAC sense. **Don't grant `escalate` or `bind` to untrusted users.**

The built-in `admin` and `edit` ClusterRoles **do not** include `escalate` or `bind` on Roles. Only `cluster-admin` has them.

## 15. Authorization for Kubelets

A special case: the **Node authorizer** is enabled by default and restricts what kubelets can do.

A kubelet (identified by `system:node:<node-name>`) can only:

* Read its own Node object.
* Read Pods assigned to it.
* Update the status of Pods assigned to it.
* Create Events related to its Pods.

It **cannot**:

* Read other Nodes' secrets.
* Modify Pods not assigned to it.
* Do anything outside its lane.

This is enforced by the Node authorizer and the NodeRestriction admission plugin. See [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/20-cluster-hardening|Cluster Hardening]] and [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/21-node-hardening|Node Hardening]] for details.

## 16. Authorization for System Components

The control plane components (`kube-controller-manager`, `kube-scheduler`, `cloud-controller-manager`) run as `system:serviceaccount:kube-system:<name>`. They have **cluster-scoped permissions** via built-in ClusterRoleBindings:

* `system:kube-controller-manager` is bound to `cluster-admin` (yes, full access — it needs to manage every resource).
* `system:kube-scheduler` is bound to `system:kube-scheduler` (its own custom ClusterRole).
* `cloud-controller-manager` is bound to `system:cloud-controller-manager`.

These are **system ClusterRoleBindings** — created by the apiserver at startup. **Don't modify them.**

The controller-manager runs with `--use-service-account-credentials=true` (k8s 1.14+) — each controller has its own SA with the minimum RBAC. The `--use-service-account-credentials=false` default (legacy) gives a single SA with cluster-admin, which is overly broad.

## 17. The SubjectAccessReview API

*"https://kubernetes.io/docs/reference/access-authn-authz/authorization/#checking-api-access"*

The `SubjectAccessReview` (SAR) API is a way to **check** whether a user can do an action. It's used by `kubectl auth can-i`:

```http
POST /apis/authorization.k8s.io/v1/subjectaccessreviews
{
  "apiVersion": "authorization.k8s.io/v1",
  "kind": "SubjectAccessReview",
  "spec": {
    "user": "alice",
    "group": ["developers"],
    "resourceAttributes": {
      "namespace": "default",
      "verb": "get",
      "resource": "pods"
    }
  }
}
```

The apiserver returns:

```json
{
  "apiVersion": "authorization.k8s.io/v1",
  "kind": "SubjectAccessReview",
  "status": {
    "allowed": true
  }
}
```

The SAR is checked against RBAC. The result is whether the user can do the action.

To allow a user to **create** SARs, grant the `create` verb on `subjectaccessreviews`:

```yaml
rules:
- apiGroups: ["authorization.k8s.io"]
  resources: ["subjectaccessreviews"]
  verbs: ["create"]
```

This is what `kubectl auth can-i` does — it uses the user's own credentials to create a SAR.

## 18. RBAC for Custom Resources

A CRD defines a new resource. RBAC for CRDs uses the CRD's `spec.group`:

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata: { name: compositions.apiextensions.crossplane.io }
spec:
  group: apiextensions.crossplane.io
  names: { plural: compositions, kind: Composition }
```

RBAC for the CRD's resources:

```yaml
rules:
- apiGroups: ["apiextensions.crossplane.io"]
  resources: ["compositions"]
  verbs: ["get", "list"]
```

The `apiGroup` is the CRD's group. The `resources` is the CRD's plural name.

**The CRD must exist** for the RBAC to be meaningful. Without the CRD, the apiGroup is unknown and the rule doesn't match anything.

For **subresources of a CRD** (e.g. `compositions/status`), use the subresource name:

```yaml
rules:
- apiGroups: ["apiextensions.crossplane.io"]
  resources: ["compositions", "compositions/status"]
  verbs: ["get", "update", "patch"]
```

## 19. The kubebuilder / controller-gen RBAC Markers

For controller authors using `kubebuilder` or `controller-gen`, the RBAC is **generated from Go markers**:

```go
//+kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=core,resources=pods,verbs=get;list;watch
//+kubebuilder:rbac:groups=core,resources=pods/status,verbs=get;update;patch
```

`controller-gen` reads these markers and generates a `role.yaml` (and `clusterrole.yaml`) with the RBAC.

The generated RBAC is what the controller's SA needs to operate. **Don't manually edit the generated file** — edit the markers and re-run `make manifests`.

## 20. Common Patterns

### 20.1 The CI service account

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: { name: ci, namespace: ci }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: deploy, namespace: app-prod }
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "update", "patch"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: ci, namespace: app-prod }
subjects:
- kind: ServiceAccount
  name: ci
  namespace: ci
roleRef:
  kind: Role
  name: deploy
  apiGroup: rbac.authorization.k8s.io
```

CI can deploy but can't delete or create new Deployments. Limited blast radius.

### 20.2 Read-only access to a namespace

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: view, namespace: production }
subjects:
- kind: Group
  name: production-readers
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: view
  apiGroup: rbac.authorization.k8s.io
```

The `view` ClusterRole gives read-only to most things.

### 20.3 Cluster-wide read for ops

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: { name: ops-read }
subjects:
- kind: Group
  name: ops
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: view
  apiGroup: rbac.authorization.k8s.io
```

The `ops` group gets read access cluster-wide.

### 20.4 The leader-election SA

Many controllers need to update their own status for leader election. The standard:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: leader-election, namespace: default }
rules:
- apiGroups: ["coordination.k8s.io"]
  resources: ["leases"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: leader-election, namespace: default }
subjects:
- kind: ServiceAccount
  name: my-controller
  namespace: default
roleRef:
  kind: Role
  name: leader-election
  apiGroup: rbac.authorization.k8s.io
```

The controller can create and update Leases for leader election. It can't touch other resources.

### 20.5 The "I need a specific Secret" pattern

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: read-app-secret, namespace: default }
rules:
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["app-secret"]
  verbs: ["get"]
```

The Role allows reading **only** the `app-secret` Secret. The user / SA can't read other Secrets.

## 21. Discovery and Debugging

```bash
# what can I do?
kubectl auth can-i --list

# can I do X?
kubectl auth can-i create deployments -n my-ns

# can a specific SA do X?
kubectl auth can-i list pods --as=system:serviceaccount:default:app -n default

# show the effective RBAC for a user
kubectl auth can-i --list --as=alice@example.com -n production

# see all roles in a namespace
kubectl get roles -n production
kubectl get rolebindings -n production

# see all cluster roles / bindings
kubectl get clusterroles
kubectl get clusterrolebindings

# see the rules in a Role
kubectl get role <name> -n <ns> -o yaml

# see who is bound to a Role
kubectl get rolebinding <name> -n <ns> -o yaml

# see all bindings for a specific user / SA
kubectl get rolebindings -A -o json | jq '.items[] | select(.subjects[]?.name == "alice")'
kubectl get clusterrolebindings -o json | jq '.items[] | select(.subjects[]?.name == "alice")'
```

## 22. Operations and Debugging

### 22.1 The "kubectl auth can-i returns false but it should be true" case

```bash
# 1. Is the user / SA correct?
kubectl auth can-i list pods --as=system:serviceaccount:default:my-app -n default
# check the user

# 2. Is the binding in the right namespace?
kubectl get rolebindings -A | grep my-app

# 3. Does the Role's rules match?
kubectl get role <name> -n <ns> -o yaml
# check rules

# 4. Is the binding referencing the right Role?
kubectl get rolebinding <name> -n <ns> -o yaml
# check roleRef

# 5. Is the apiGroup correct?
# "pods" is in apiGroup "" (empty), not "core"
# "deployments" is in apiGroup "apps"
# check the rule's apiGroups
```

### 22.2 The "I added a binding, but the user still gets 403" case

```bash
# RBAC changes are eventually consistent
# the apiserver's authz cache may take a few seconds to update
# wait 5-10s and retry

# or check:
kubectl get rolebinding -n <ns> -o yaml
# is the binding present?
```

### 22.3 The "RBAC for custom resource is broken" case

```bash
# 1. Is the CRD installed?
kubectl get crd | grep <crd-name>
# if not, RBAC for the CRD's resources doesn't apply

# 2. Is the apiGroup correct?
kubectl api-resources | grep <crd-name>
# the apiGroup is the CRD's spec.group

# 3. Is the plural correct?
# RBAC uses plural, not singular or short names
# "compositions", not "composition" or "comp"
```

## 23. Gotchas and Common Mistakes

### 23.1 The 30+ common mistakes

1. **No rule that matches = deny.** Every verb on every resource needs an explicit allow.

2. **`apiGroups: [""]` for core resources.** Pods, Services, ConfigMaps, Secrets, etc. are in the empty group. Not `"core"`, not `"v1"`.

3. **`apiGroups: ["apps"]` for Deployment / StatefulSet / DaemonSet.** Not `""`.

4. **`apiGroups: ["batch"]` for Job / CronJob.** Not `""`.

5. **RBAC uses plural names.** `pods`, `deployments`, `configmaps`. Not `pod`, `deployment`, `configmap`. Not short names like `po`.

6. **Missing `apiGroups` is a silent failure.** The Role is created but doesn't match anything. Always include `apiGroups`.

7. **`resourceNames` doesn't work on subresources.** `pods/log`, `pods/exec`, `deployments/scale` can't be filtered by name.

8. **`resourceNames` works on most named resources.** Secrets, ConfigMaps, Pods, Services, Nodes, Namespaces, etc.

9. **The `view` ClusterRole doesn't include Secrets.** Secrets are sensitive. To read a specific Secret, create a custom Role.

10. **The `edit` ClusterRole doesn't include `delete` for Namespaces.** Use `admin` to delete a Namespace.

11. **The `admin` ClusterRole doesn't include `*` on RoleBindings.** Wait — it does, but not on ClusterRoleBindings. Use `cluster-admin` for cluster-wide RBAC modification.

12. **A RoleBinding can reference a ClusterRole.** The ClusterRole's rules apply in the RoleBinding's namespace.

13. **A RoleBinding's `subjects[].namespace` is the SA's namespace, not the binding's namespace.** The binding's namespace is the `metadata.namespace`.

14. **A SA in one namespace can be a subject in a binding in another.** The binding's namespace is where the permissions apply.

15. **The Node authorizer restricts kubelets.** They can only update their own Node and Pod status. They can't read other Nodes' secrets.

16. **The system ClusterRoleBindings are created by the apiserver.** Don't modify `system:kube-controller-manager`, etc.

17. **`escalate` and `bind` are sensitive verbs.** A user with `escalate` on a Role can add permissions to that Role (and to themselves via the binding). Don't grant them to untrusted users.

18. **The `impersonate` verb allows acting as another user.** The original user is recorded as `impersonator`. Use carefully.

19. **The `pods/eviction` subresource is what `kubectl drain` uses.** Grant `create` on `pods/eviction` for the drain user.

20. **`pods/exec` and `pods/portforward` are subresources.** Grant `create` on them for the users that need them.

21. **`nonResourceURLs` are for non-resource URLs.** `/healthz`, `/metrics`, `/api`, `/apis`. For monitoring / debugging.

22. **Role aggregation can be unexpected.** A ClusterRole with `aggregationRule` collects rules from other ClusterRoles. Adding a label to a ClusterRole may aggregate it.

23. **The `system:serviceaccounts` group includes all SAs cluster-wide.** Don't grant it broad permissions.

24. **The `system:authenticated` group includes all authenticated users.** Don't grant it broad permissions.

25. **The `system:masters` group is cluster-admin.** Don't add users to it.

26. **The `system:node` group is for kubelets (legacy).** The modern way is the Node authorizer + NodeRestriction.

27. **The `system:public-info-viewer` is for anonymous read access.** Used by health checks, etc. Don't grant it Secrets.

28. **A wildcard (`*`) in `apiGroups` and `resources` is powerful but dangerous.** Use it for built-in admin roles, not for your team's day-to-day.

29. **RBAC changes are eventually consistent.** The apiserver's authz cache may take a few seconds to update.

30. **`kubectl auth can-i` requires the user's identity to be set.** With OIDC, you may need `--as=<user>` or impersonation.

## See also

* [[Kubernetes/concepts/L07-security/01-api-access/01-authentication-authorization|AuthN/AuthZ]] — the bigger picture
* [[Kubernetes/concepts/L07-security/01-api-access/02-service-accounts|ServiceAccounts]] — the in-cluster identity
* [[Kubernetes/concepts/L07-security/07-security|Security Overview]] — the security model end-to-end
* [[Kubernetes/concepts/L07-security/02-workload-sandboxing/06-pod-security-standards|PSS]] — the workload-side complement
* [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/20-cluster-hardening|Cluster Hardening]] — the apiserver flags
