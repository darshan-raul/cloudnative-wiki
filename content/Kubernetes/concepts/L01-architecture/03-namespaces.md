# Namespaces

*"https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/"*

A namespace is a **scope for names** — resource names must be unique within a namespace, but the same name can be used in different namespaces. Namespaces are how you partition a single cluster into multiple virtual clusters.

## What they actually do

* **Provide a scope for names** — two Deployments with the same name can coexist if they're in different namespaces
* **Provide a scope for RBAC** — you can grant a user access to one namespace and not another
* **Provide a scope for policies** — ResourceQuotas, LimitRanges, NetworkPolicies, PodSecurity, etc. all apply per-namespace
* **Provide a scope for service DNS** — `my-svc.my-ns.svc.cluster.local`

Namespaces do **not** provide:

* **Hard isolation** — by default, all Pods in all namespaces can talk to each other
* **Resource isolation** — a namespace can request more resources than the node has; quotas enforce limits, not guarantees
* **Network segmentation** — without NetworkPolicy, namespaces are just label prefixes

## The default namespaces

When a cluster is created, four namespaces exist:

* `default` — for objects without a namespace. The cluster-admin puts things here when they're being lazy.
* `kube-system` — for the control plane and add-ons (CoreDNS, kube-proxy, CNI). **Do not deploy your apps here.**
* `kube-public` — readable by all users (including unauthenticated). Usually just holds a `cluster-info` ConfigMap.
* `kube-node-lease` — for the NodeLease objects, used to determine node health. Lightweight heartbeat.

```bash
kubectl get ns
# NAME              STATUS   AGE
# default           Active   30d
# kube-node-lease   Active   30d
# kube-public       Active   30d
# kube-system       Active   30d
```

## Creating namespaces

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    purpose: production
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

The Pod Security labels are applied at namespace creation so any Pod in this namespace is automatically gated by PSS.

```bash
kubectl create ns production
kubectl get ns production
```

**Always label namespaces with purpose / owner / environment / PSS profile.** Unlabeled namespaces are an operational mess.

## Namespaced vs cluster-scoped resources

**Most resources are namespaced:**

```bash
kubectl api-resources --namespaced=true
# NAME                              SHORTNAMES   APIVERSION                       NAMESPACED   KIND
# bindings                                                  v1                             true         Binding
# configmaps                       cm           v1                               true         ConfigMap
# endpoints                        ep           v1                               true         Endpoints
# events                           ev           v1                               true         Event
# limitranges                      limits       v1                               true         LimitRange
# persistentvolumeclaims           pvc          v1                               true         PersistentVolumeClaim
# pods                             po           v1                               true         Pod
# podtemplates                                                 v1                             true         PodTemplate
# replicationcontrollers           rc           v1                               true         ReplicationController
# resourcequotas                   quota        v1                               true         ResourceQuota
# secrets                                      v1                               true         Secret
# serviceaccounts                  sa           v1                               true         ServiceAccount
# services                         svc          v1                               true         Service
# controllerrevisions                           apps/v1                          true         ControllerRevision
# daemonsets                       ds           apps/v1                          true         DaemonSet
# deployments                      deploy       apps/v1                          true         Deployment
# replicasets                      rs           apps/v1                          true         ReplicaSet
# statefulsets                     sts          apps/v1                          true         StatefulSet
# ... etc
```

**Some resources are cluster-scoped (not in any namespace):**

```bash
kubectl api-resources --namespaced=false
# NAME                              SHORTNAMES   APIVERSION                       NAMESPACED   KIND
# componentstatuses                cs           v1                               false        ComponentStatus
# namespaces                       ns           v1                               false        Namespace
# nodes                            no           v1                               false        Node
# persistentvolumes                pv           v1                               false        PersistentVolume
# mutatingwebhookconfigurations                 admissionregistration.k8s.io/v1  false        MutatingWebhookConfiguration
# validatingwebhookconfigurations               admissionregistration.k8s.io/v1  false        ValidatingWebhookConfiguration
# customresourcedefinitions         crd,crds     apiextensions.k8s.io/v1          false        CustomResourceDefinition
# apiservices                                   apiregistration.k8s.io/v1        false        APIService
# clusterrolebindings                            rbac.authorization.k8s.io/v1     false        ClusterRoleBinding
# clusterroles                                   rbac.authorization.k8s.io/v1     false        ClusterRole
# ... etc
```

The mental model:

* **Namespaced** resources describe things that "live" in a tenant (your app, your team's data)
* **Cluster-scoped** resources describe cluster-wide things (Nodes, PVs, CRDs, ClusterRoles)

## The "default" namespace problem

A common anti-pattern: deploying to `default`. Why it's bad:

* **No PSS** — `default` doesn't have Pod Security labels, so it gets the cluster default (usually `privileged` = no enforcement)
* **No quota** — you can use unlimited resources
* **No ownership** — anyone can deploy here, no one owns it
* **Mixes everything** — test apps, prod apps, scratch apps all in one place

```bash
# check what's in default
kubectl get all -n default
# you might see a lot more than you expect
```

**Don't deploy to `default`.** Create a namespace per environment, team, or app:

```bash
kubectl create ns app-prod
kubectl create ns app-staging
kubectl create ns app-dev
kubectl create ns team-a
kubectl create ns team-b
```

## Cross-namespace references

A few resources let you reference across namespaces:

* **NetworkPolicy** with `namespaceSelector` — "Pods in any namespace with this label can be ingress"
* **RoleBinding** with a subject from another namespace — rare, but possible
* **Service DNS** — `my-svc.other-ns.svc.cluster.local` from any namespace
* **Ingress** to Services in other namespaces — depends on the controller
* **Gateway API** — `backendRefs` can target a Service in another namespace (with explicit `namespace:`)

But the **default is single-namespace**:

* A Pod in `default` can only mount a ConfigMap in `default`
* A PVC in `team-a` is invisible to a Pod in `team-b`
* A Service in `team-a` is accessible by DNS from any namespace, but you must use the FQDN or set up search paths

This is intentional: **namespaces are isolation boundaries by default.**

## Namespaces and DNS

The cluster's DNS has a search path. From a Pod, you can refer to a Service by:

* `my-svc` — same namespace as the Pod
* `my-svc.my-ns` — explicit namespace
* `my-svc.my-ns.svc.cluster.local` — FQDN

The `/etc/resolv.conf` inside a Pod:

```
nameserver 10.96.0.10        # CoreDNS service IP
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

So from a Pod in the `default` namespace, `my-svc` resolves to `my-svc.default.svc.cluster.local`. From a Pod in `team-a`, `my-svc` resolves to `my-svc.team-a.svc.cluster.local`.

To reach a Service in another namespace, use the FQDN or set up a custom search domain.

## Namespaces and resource quotas

A `ResourceQuota` is a namespaced object that caps total resource usage in that namespace:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-a-quota
  namespace: team-a
spec:
  hard:
    requests.cpu: "100"
    requests.memory: 200Gi
    limits.cpu: "200"
    limits.memory: 400Gi
    persistentvolumeclaims: "50"
    services: "100"
    secrets: "200"
    configmaps: "200"
```

If a Pod in `team-a` would exceed the quota, it's **rejected at admission**. Existing Pods keep running. The quota is enforced by the `ResourceQuota` admission controller.

```bash
kubectl describe quota -n team-a
# Name:       team-a-quota
# Namespace:  team-a
# Resource    Used   Hard
# --------    ----   ----
# cpu         45     100
# memory      80Gi   200Gi
# ...
```

## LimitRange — per-container defaults

A `LimitRange` sets defaults and limits at the **container** level. A namespace can have one LimitRange that applies to all Pods in it.

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: defaults
  namespace: team-a
spec:
  limits:
  - type: Container
    default:                  # these are applied if not specified
      cpu: 500m
      memory: 512Mi
    defaultRequest:           # the default request
      cpu: 100m
      memory: 128Mi
    max:                      # hard cap
      cpu: "2"
      memory: 4Gi
    min:                      # minimum required
      cpu: 50m
      memory: 64Mi
  - type: PersistentVolumeClaim
    max:
      storage: 100Gi
    min:
      storage: 1Gi
```

Without a LimitRange, a Pod with no `resources:` set is `BestEffort` and gets the lowest eviction priority. With a LimitRange, every container has at least a default.

## The "namespace as tenant" pattern

A common pattern for multi-tenant clusters:

```yaml
# One namespace per team
apiVersion: v1
kind: Namespace
metadata:
  name: team-a
  labels:
    team: alpha
    pod-security.kubernetes.io/enforce: restricted
---
# Each team gets a quota
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-a
  namespace: team-a
spec:
  hard: { ... }
---
# Each team gets a NetworkPolicy
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: team-a
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```

This gives you:

* Resource limits (Quota)
* Security baseline (PSS)
* Network isolation (default-deny + allow rules)
* No cross-team access (RBAC scoped to the namespace)

This is "soft multi-tenancy" — strong isolation but still a single cluster.

## Namespaces and kubelet / control plane

Namespaces are a **logical** concept. The kubelet, the apiserver, the scheduler don't know about them as a thing — they just see objects with a `namespace` field.

You cannot "namespace" a Node or a PV. You cannot "namespace" a CRD (the CRD is cluster-scoped, but its instances can be namespaced or cluster-scoped).

## When to create a new namespace

| Scenario | New namespace? |
|---|---|
| Different environment (dev, staging, prod) | **Yes** |
| Different team | **Yes** |
| Different app with its own RBAC / quotas | **Yes** |
| Different customer (multi-tenant SaaS) | **Yes** |
| Different lifecycle (app + its jobs) | Maybe — depends on the team |
| Different version of the same app (v1, v2) | Maybe — but labels usually suffice |
| Random new feature being developed | **No** — use the dev namespace |

The rule of thumb: **if you'd want different RBAC, quotas, or PSS profiles, you want a different namespace.** If you wouldn't, you don't.

## How many namespaces is too many?

There's no hard limit, but practical advice:

* **10-50** — easy, recommended
* **100-500** — fine, but consider using a tool (e.g. [namespace-operator](https://github.com/kubernetes-sigs/multi-tenancy), [hierarchical namespaces](https://github.com/kubernetes-sigs/hierarchical-namespaces)) to manage them
* **1000+** — you're probably doing something wrong. Use labels, not namespaces.

The apiserver's `namespace` field is indexed, so 1000s of namespaces don't cause performance issues. But managing them does.

## Namespace lifecycle

When you delete a namespace:

1. The apiserver marks the namespace as `Terminating`
2. All objects in the namespace are deleted (in parallel, by default)
3. The apiserver waits for all objects to be gone
4. The namespace is removed from etcd

**Deleting a namespace deletes EVERYTHING in it.** This includes:

* Deployments, StatefulSets, DaemonSets
* Pods (and their volumes if the StorageClass has the right policy)
* Services
* ConfigMaps and Secrets
* ServiceAccounts
* CRs of all types

The deletion is **cascading and irreversible**. Be careful.

```bash
# delete a namespace, wait for completion
kubectl delete ns <name> --wait=true
# or async
kubectl delete ns <name> &
```

The `NamespaceLifecycle` admission controller prevents creating new objects in a namespace that's terminating. So you can't "rescue" data by creating new objects in a deleting namespace.

## Gotchas

* **You can't `kubectl get pods` across namespaces by default.** Use `-A` or `--all-namespaces`.
* **The `default` namespace is a trap.** Never deploy to it. Don't even create objects there manually.
* **Deleting a namespace is permanent.** There's no "soft delete". If you need staging, snapshot, or backup semantics, use a backup tool (Velero).
* **Namespaces are not security boundaries by themselves.** Add NetworkPolicy + RBAC + PSS + quotas to make them so.
* **Cross-namespace DNS works, but cross-namespace mounts do not.** A Pod in `team-a` can resolve `db.team-b` but can't mount a PVC from `team-b`.
* **The `kube-system` namespace is special.** Don't deploy there. Don't apply PSS labels there (system Pods need privileged).
* **Namespaces can't be renamed.** You can `kubectl create ns new-name` and migrate, but you can't rename in place.
* **Annotations on namespaces are the standard for tooling.** ArgoCD, cert-manager, ExternalDNS, etc. all use namespace annotations for their config.
* **ServiceAccount tokens are per-namespace.** A `default` ServiceAccount in `team-a` is a different identity than in `team-b`.
* **The kubelet doesn't see namespaces.** It only sees Pods assigned to it, regardless of namespace. The kubelet enforces Pod limits (memory, CPU) but not namespace quotas.

## The full lifecycle in one diagram

```
kubectl create ns production
    ↓
Namespace object stored in etcd
    ↓
Default ServiceAccount created
    ↓
PSS labels, quotas, NetworkPolicies applied (separately)
    ↓
Users / CI / GitOps deploy to it
    ↓
    ... time passes ...
    ↓
kubectl delete ns production
    ↓
All objects cascade-deleted
    ↓
NamespaceLifecycle admission blocks new objects
    ↓
Namespace object deleted from etcd
```
