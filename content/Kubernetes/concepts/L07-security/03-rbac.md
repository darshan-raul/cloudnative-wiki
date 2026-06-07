# RBAC (Role-Based Access Control)

*"https://kubernetes.io/docs/reference/access-authn-authz/rbac/"*

RBAC is the **standard authorization model** in Kubernetes. It defines who can do what via four resource types: **Role**, **ClusterRole**, **RoleBinding**, **ClusterRoleBinding**. This is the L07 deep dive.

## The four objects

| Object | Scope | What it does |
|---|---|---|
| **Role** | Namespaced | Set of allowed verbs on resources, within one namespace |
| **ClusterRole** | Cluster-wide | Same, but cluster-wide (or for cluster-scoped resources) |
| **RoleBinding** | Namespaced | Assigns a Role to a User / Group / ServiceAccount, within one namespace |
| **ClusterRoleBinding** | Cluster-wide | Assigns a ClusterRole cluster-wide |

A **Role** is a set of allowed verbs. A **RoleBinding** is who gets that Role. The two are separate so you can reuse Roles across bindings (give the same Role to multiple users, or to SAs in different namespaces).

## The basic example

```yaml
# a Role: "this person can read pods in the default namespace"
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: default
rules:
- apiGroups: [""]                   # "" = core API group
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

## Role / ClusterRole fields

### `rules` — what this role allows

```yaml
rules:
- apiGroups: [""]                    # core group, includes Pod, Service, ConfigMap, ...
  resources: ["pods"]
  resourceNames: ["my-specific-pod"]  # optional, limit to specific instances
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]                 # apps group, includes Deployment, StatefulSet, ...
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "update", "patch"]
- apiGroups: ["batch"]
  resources: ["jobs"]
  verbs: ["*"]                        # all verbs
- nonResourceURLs: ["/healthz", "/readyz"]
  verbs: ["get"]
```

**`apiGroups`:**

* `""` (empty string) = core API group (Pod, Service, ConfigMap, Secret, Event, Namespace, Node, PV, ...)
* `"apps"` = Deployment, StatefulSet, DaemonSet, ReplicaSet, ControllerRevision
* `"batch"` = Job, CronJob
* `"rbac.authorization.k8s.io"` = Role, ClusterRole, RoleBinding, ClusterRoleBinding
* `"networking.k8s.io"` = NetworkPolicy, Ingress
* `"storage.k8s.io"` = StorageClass, CSIDriver, VolumeAttachment
* `"apiextensions.k8s.io"` = CustomResourceDefinition
* etc. Use `kubectl api-resources` to list.

**`resources`:**

* Plural names: `pods`, `deployments`, `configmaps`
* Some resources have short names too (e.g. `po` for `pods`), but those don't work in RBAC

**`resourceNames`:**

* Optional
* Limit the rule to specific resource instances
* Works for resources with a name (most do); doesn't work for resources that are subresources

**`verbs`:**

* `get` — read a single resource
* `list` — read multiple
* `watch` — receive updates
* `create` — create a new resource
* `update` — modify (full replace)
* `patch` — partial modify
* `delete` — delete a single resource
* `deletecollection` — delete multiple
* `*` — all verbs
* Custom verbs for some resources (e.g. `bind` for `roles` and `clusterroles`, `escalate` for `roles`)

**`nonResourceURLs`:**

* For URLs that aren't resources: `/healthz`, `/readyz`, `/metrics`, `/api`, `/apis`
* Mostly used by monitoring / debugging tools

### `aggregationRule` (ClusterRole only)

```yaml
aggregationRule:
  clusterRoleSelectors:
  - matchLabels:
      rbac.example.com/aggregate-to-monitoring: "true"
```

The ClusterRole's permissions are the **union** of all ClusterRoles that match the selector. Used for building modular role hierarchies (e.g. "all roles with this label get aggregated into `monitoring`").

## The built-in ClusterRoles

k8s ships with several built-in ClusterRoles that you should know:

| ClusterRole | What it does |
|---|---|
| `cluster-admin` | Everything. Use sparingly. |
| `admin` | Most things in a namespace, but not cluster-scoped |
| `edit` | Read/write most resources in a namespace |
| `view` | Read most resources in a namespace |

```bash
kubectl get clusterrole cluster-admin -o yaml
# rules:
# - apiGroups: ["*"]
#   resources: ["*"]
#   verbs: ["*"]
# - nonResourceURLs: ["*"]
#   verbs: ["*"]
```

`view` and `edit` are commonly bound to groups via RoleBinding for namespace access.

## The "deny by default" rule

**No rule that matches = deny.** There's no "allow if not explicitly denied". Every verb on every resource needs an explicit allow.

```yaml
# alice has "get pods" but tries to "create pods"
kubectl auth can-i create pods --as=alice
# no — alice can only "get" pods, not "create"
```

## The aggregation / inheritance model

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

This is the standard pattern: **bind built-in ClusterRoles to groups in namespaces.**

## The verbs to know

* **`get`** — read a specific resource (e.g. `kubectl get pod web-abc`)
* **`list`** — read a collection (e.g. `kubectl get pods`)
* **`watch`** — receive updates
* **`create`** — make a new one
* **`update`** — replace entirely
* **`patch`** — modify a part
* **`delete`** — remove
* **`deletecollection`** — remove all matching a selector

For most things, you need `get` + `list` + `watch` (read), or `get` + `list` + `watch` + `create` + `update` + `patch` + `delete` (write).

## Common patterns

### The CI service account

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
  verbs: ["get", "list", "watch"]    # so CI can check rollout status
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

### Read-only access to a namespace

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

### Cluster-wide read for ops

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

### Node tainting / privileged workloads

A Pod that needs to taint a node (for cluster autoscaler) needs:

```yaml
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list", "watch", "update", "patch"]
```

This is `cluster-admin`-ish; restrict it.

## The ServiceAccount pattern

By default, every Pod's ServiceAccount has no permissions. To let a Pod do anything, you bind a Role to it:

```yaml
# the SA
apiVersion: v1
kind: ServiceAccount
metadata: { name: app, namespace: default }
---
# the role
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: read-config, namespace: default }
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  resourceNames: ["app-config"]
  verbs: ["get"]
---
# the binding
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: app, namespace: default }
subjects:
- kind: ServiceAccount
  name: app
  namespace: default
roleRef:
  kind: Role
  name: read-config
  apiGroup: rbac.authorization.k8s.io
```

Now the Pod's `app` SA can `get configmap/app-config`. Nothing else.

## Discovery

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
```

## The most common mistakes

### 1. Granting `*` to a namespace

```yaml
# DON'T
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
```

This is "namespace admin". Fine for the team that owns the namespace, terrible if scoped wrong. If a user has this in `kube-system`, they can break the cluster.

### 2. ClusterRoleBinding when RoleBinding would do

```yaml
# DON'T bind cluster-admin cluster-wide
kind: ClusterRoleBinding
roleRef: { kind: ClusterRole, name: cluster-admin }
```

Use a `RoleBinding` in a specific namespace, with the `edit` or `admin` ClusterRole. Limit the blast radius.

### 3. Forgetting the `apiGroups` field

```yaml
# WRONG — this is a syntax error
rules:
- resources: ["pods"]
  verbs: ["get"]

# RIGHT
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get"]
```

A missing `apiGroups` is a silent failure — the role is created but doesn't match anything.

### 4. Using `resourceNames` on resources that don't support it

```yaml
# resourceNames doesn't work on subresources
- apiGroups: [""]
  resources: ["pods/log"]
  resourceNames: ["my-pod"]
  verbs: ["get"]
```

`resourceNames` works on most named resources but not on subresources like `pods/log` or `pods/exec`. The rule will be created but won't match.

### 5. Confusing RoleBinding and ClusterRoleBinding

A RoleBinding + Role gives permissions in one namespace. A ClusterRoleBinding + ClusterRole gives permissions cluster-wide. **A RoleBinding + ClusterRole gives permissions in the RoleBinding's namespace using the ClusterRole's rules** — this is the most useful and most often confused.

## Gotchas

* **RBAC changes are eventually consistent.** When you change a Role or RoleBinding, the apiserver's authz cache may take a few seconds to update. `kubectl auth can-i` after a change might show old results briefly.
* **`kubectl auth can-i` requires the user's identity to be set.** If you're using a kubeconfig with an OIDC token, `kubectl auth can-i --as=alice` impersonates alice; `--as=system:serviceaccount:default:app` impersonates the SA.
* **The `system:masters` group is cluster-admin.** You can't undo this — anyone in the group has full access, including the ability to grant themselves more access.
* **ServiceAccount token review is RBAC-controlled.** The `authentication.k8s.io` API has its own RBAC for `TokenReview` and `SubjectAccessReview`. If those aren't granted, webhook authn and "can I" impersonation break.
* **Wildcards in `apiGroups` and `resources` are powerful but dangerous.** Use them for built-in admin roles, not for your team's day-to-day.
* **`escalate` and `bind` verbs on `roles` and `clusterroles`** are how you can modify RBAC. Don't grant them to untrusted users.
* **The `edit` ClusterRole doesn't include `delete` for everything.** Specifically, you can't delete a Namespace or a few other sensitive resources with `edit`. Use `admin` for that.
* **`view` doesn't include `watch` on Secrets by default.** Secrets are sensitive; the built-in `view` role omits them. You need to grant it explicitly.
* **Role aggregation can be unexpected.** A ClusterRole with an `aggregationRule` collects rules from other ClusterRoles. If you add a label to a ClusterRole and the selector matches, your rules get included.
* **ServiceAccount tokens cache in the kubelet for ~1 minute.** After revoking a SA's permissions, in-flight requests from that SA might still succeed briefly.

## Authorization for kubelets

A special case: the **Node authorizer** is enabled by default and restricts what kubelets can do.

Kubelets can only:

* Read their own Node object
* Read Pods assigned to them
* Update the status of Pods assigned to them
* Create Events related to their Pods

They **cannot** read other Nodes' secrets, modify Pods not assigned to them, or do anything outside their lane. This is enforced by the Node authorizer and NodeRestriction admission.

## Authorization for system components

kube-controller-manager, kube-scheduler, cloud-controller-manager run as the `system:serviceaccount:kube-system:<name>` ServiceAccount. They have **cluster-scoped permissions** via built-in ClusterRoleBindings:

* `system:kube-controller-manager` is bound to `cluster-admin` (yes, full access)
* `system:kube-scheduler` is bound to `system:kube-scheduler`
* `cloud-controller-manager` is bound to `system:cloud-controller-manager`

These are **system ClusterRoleBindings** — they're created by the apiserver at startup, not by users. Don't modify them.

## When to use which

| Scenario | Role type | Binding type |
|---|---|---|
| User can deploy to their team's namespace | ClusterRole `edit` | RoleBinding in the namespace |
| CI can deploy to a specific namespace | Role or ClusterRole | RoleBinding in the namespace |
| User can read everything in a namespace | ClusterRole `view` | RoleBinding in the namespace |
| User can read cluster-wide | ClusterRole `view` | ClusterRoleBinding |
| Pod needs to read a specific ConfigMap | Role | RoleBinding in the namespace |
| Pod needs to update its own status (e.g. leader election) | ClusterRole `system:leader-election` | RoleBinding in the namespace |
| Full cluster admin | ClusterRole `cluster-admin` | ClusterRoleBinding (rare) |
| Read all Pods cluster-wide | Custom ClusterRole | ClusterRoleBinding |

## See also

* [[Kubernetes/concepts/L07-security/01-authentication-authorization|Authentication vs Authorization]] — the bigger picture
* [[Kubernetes/concepts/L07-security/02-service-accounts|ServiceAccounts]] — the in-cluster identity
* [[Kubernetes/concepts/L07-security/07-security|Security Overview]] — the security model end-to-end
* [[Kubernetes/concepts/L07-security/06-pod-security-standards|Pod Security Standards]] — the workload-side complement to RBAC
