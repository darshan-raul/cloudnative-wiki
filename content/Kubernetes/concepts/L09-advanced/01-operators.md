# Operators

*"https://kubernetes.io/docs/concepts/extend-kubernetes/operator/"*

An operator is a **method of packaging, deploying, and managing a Kubernetes application** that uses custom resources to manage applications and their components. It's a controller pattern (see L09-deep) applied to operational knowledge — the "operator" captures how a human SRE would manage a complex application, encoded as software that runs in the cluster.

## The problem operators solve

Some applications are **stateful and operationally complex**:

* A database (Postgres, MySQL) that needs a primary + replicas, with failover, backup, restore
* A message queue (Kafka, RabbitMQ) that needs a 3-broker cluster with replicated topics
* A search engine (Elasticsearch, Solr) that needs sharded indices and rolling restarts
* A monitoring system (Prometheus, Thanos) that needs a federation of instances

Without an operator, you'd:

1. Write YAML for each component
2. Manually upgrade each component, one at a time
3. Manually handle failover
4. Manually back up and restore
5. Manually rebalance shards
6. Hope nothing goes wrong

With an operator, you write **one custom resource** that says "I want a Postgres cluster with 3 replicas", and the operator:

* Creates the StatefulSet, Services, Secrets, ConfigMaps
* Manages failover when a node dies
* Performs backups on a schedule
* Handles version upgrades with the right ordering
* Exposes a status field that tells you "all 3 replicas are healthy, backup ran 4 hours ago"

The operator encodes **operational knowledge** that would otherwise live in runbooks.

## The pattern

```
┌─────────────────────────────────────────────────────┐
│                                                      │
│   You                                                 │
│    │                                                 │
│    │ kubectl apply                                   │
│    ▼                                                 │
│   ┌──────────┐                                       │
│   │ Postgres │ (a custom resource)                   │
│   │ Cluster  │   apiVersion: postgres.example.com/v1 │
│   │ CR       │   kind: PostgresCluster               │
│   └────┬─────┘   spec:                                │
│        │         replicas: 3                         │
│        │         version: "15"                        │
│        │         storage: 100Gi                       │
│        │                                              │
│        ▼                                              │
│   ┌──────────────────┐                               │
│   │  Postgres        │   (the operator)              │
│   │  Operator         │                               │
│   │  controller       │                               │
│   │                   │                               │
│   │  watches:         │                               │
│   │   - PostgresCluster CR                            │
│   │   - owned Pods    │                               │
│   │   - owned PVCs    │                               │
│   │                   │                               │
│   │  creates:         │                               │
│   │   - StatefulSet   │                               │
│   │   - Services      │                               │
│   │   - Secrets       │                               │
│   │   - ConfigMaps    │                               │
│   │   - CronJobs (for backup)                        │
│   │                   │                               │
│   │  reconciles:      │                               │
│   │   - spec.replicas → matches state                 │
│   │   - failover      → on node failure              │
│   │   - backup        → on schedule                  │
│   │   - upgrade       → on version change            │
│   │                   │                               │
│   │  updates:         │                               │
│   │   - .status       ← current state               │
│   │   - .status.conditions ← Ready, Replica, etc.    │
│   │                   │                               │
│   └──────────────────┘                               │
│                                                      │
└─────────────────────────────────────────────────────┘
```

The operator is a **custom controller** that:

* **Watches** the CR (and its owned objects)
* **Reconciles** the actual state toward the desired state
* **Updates** `.status` so users can see what's happening

## A real example: Cert-Manager

cert-manager is one of the most-used operators. It manages TLS certificates in k8s.

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: { name: my-cert, namespace: default }
spec:
  secretName: my-tls
  dnsNames:
  - app.example.com
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
```

The cert-manager operator:

1. Sees the Certificate
2. Creates an Order (CR) with the ACME server (Let's Encrypt)
3. Creates a Challenge (CR) to prove domain ownership
4. Once the Order is fulfilled, stores the cert in the `my-tls` Secret
5. Renews the cert before it expires
6. Updates the Certificate's `.status` with the current state

You didn't write any of that. The operator handles it.

## What's in an operator

Three things:

1. **Custom Resource Definitions (CRDs)** — the schema for the new object types
2. **Controllers** — the reconcilers that watch CRs and create / update / delete resources
3. **Operational knowledge** — the SRE-encoded-in-software part (failover, backup, upgrade, etc.)

Sometimes there's a fourth: **admission webhooks** to validate or mutate the CRs at admission time (e.g. reject an invalid version).

## When to use an operator

* **You have a stateful application** with operational complexity (databases, queues, search engines)
* **You want to manage many instances** of the same thing (50 Kafka clusters, 100 Postgres instances)
* **You want GitOps for a complex app** — declare the desired state, the operator makes it so
* **You want self-healing** for an app that doesn't have it (e.g. a legacy statefulset that doesn't handle failover)

## When NOT to use an operator

* **Stateless applications** — a Deployment is enough
* **Simple stateful apps** — a StatefulSet might be enough
* **One-off applications** — operators shine when there are many; for one instance, the overhead doesn't pay off
* **You don't have the operational knowledge** — if no one on the team knows how to operate Postgres, building a Postgres operator is not the right first step
* **The upstream project provides one** — Kafka has Strimzi, Postgres has CloudNativePG, Redis has Redis Operator. **Use the upstream operator if it exists.** Don't write your own.

## How operators are written

The most common way: **Go, with kubebuilder or operator-sdk**. The two frameworks generate most of the boilerplate:

* CRD definition (with OpenAPI schema)
* Controller skeleton (informer, workqueue, reconcile loop)
* RBAC needed to watch / create the CRs and resources

The pattern in Go:

```go
// The reconcile loop
func (r *PostgresReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    // 1. Fetch the CR
    pg := &postgresqlv1.PostgresCluster{}
    if err := r.Get(ctx, req.NamespacedName, pg); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)
    }

    // 2. Reconcile the StatefulSet
    if err := r.reconcileStatefulSet(ctx, pg); err != nil {
        return ctrl.Result{}, err
    }

    // 3. Reconcile the Services
    if err := r.reconcileServices(ctx, pg); err != nil {
        return ctrl.Result{}, err
    }

    // 4. Reconcile the backup CronJob
    if err := r.reconcileBackup(ctx, pg); err != nil {
        return ctrl.Result{}, err
    }

    // 5. Update status
    pg.Status.Ready = true
    pg.Status.Replicas = 3
    if err := r.Status().Update(ctx, pg); err != nil {
        return ctrl.Result{}, err
    }

    // 6. Requeue if needed
    return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
}
```

The framework handles the rest: informers, work queues, leader election, RBAC, metrics.

### Other languages

* **Python** with [`kopf`](https://kopf.readthedocs.io/) (Kubernetes Operator Pythonic Framework) or [`operator-sdk`](https://sdk.operatorframework.io/) for Python
* **Java** with the Java Operator SDK
* **Helm + a sidecar** — not really an operator, but a popular middle ground
* **Ansible** — Ansible Operator SDK wraps Ansible playbooks as a controller

For most teams, **Go + kubebuilder is the standard**. The other languages are for when you have a specific reason (existing expertise, language requirements).

## Operator maturity levels

The [Operator Capability Levels](https://operatorframework.io/operator-capabilities/) define how mature an operator is:

| Level | What it does |
|---|---|
| **Level 1: Basic install** | Can install / uninstall the app |
| **Level 2: Seamless upgrades** | Can upgrade the app with the right ordering |
| **Level 3: Full lifecycle** | Backup, restore, scaling, reconfiguration |
| **Level 4: Deep insights** | Metrics, alerts, log streaming, workload recommendations |
| **Level 5: Auto-pilot** | Auto-scaling, auto-tuning, auto-remediation |

Most production operators aim for Level 3 or 4. Level 5 is rare and complex.

## OperatorHub

[OperatorHub.io](https://operatorhub.io/) is a catalog of operators. **Before writing one, check if it's already there.** Categories include:

* **Database** — Postgres, MySQL, MongoDB, Redis, Cassandra, ScyllaDB
* **Messaging** — Kafka (Strimzi), RabbitMQ, NATS, Pulsar
* **Storage** — MinIO, Rook (Ceph), OpenEBS
* **Monitoring** — Prometheus, Grafana
* **Security** — cert-manager, Vault
* **Networking** — various ingress controllers, service meshes
* **Big data** — Spark, Flink
* **AI/ML** — Kubeflow, KServe

## The "is it a real operator?" check

A few heuristics:

* **Has a CRD** (or multiple) for the resource being managed
* **Has a controller** that watches the CR and creates / updates resources
* **Updates `.status`** so users can see what's happening
* **Has owned resources** (StatefulSets, Services, etc.) with proper owner references
* **Handles deletion** with finalizers (so cleanup happens)
* **Is documented** with installation, usage, and operational guides
* **Has tests** — at minimum, unit tests of the reconcile logic; ideally end-to-end envtest

If a tool is "a Helm chart" with no controller, it's not an operator — it's a Helm chart. Both are useful.

## Operator anti-patterns

### 1. The "Helm chart pretending to be an operator"

A Helm chart that installs a Deployment is not an operator. It doesn't reconcile, it doesn't handle drift, it doesn't update status.

### 2. The "CRD with no controller"

You can create a CRD and have a CR instance exist, but if nothing watches it and reconciles, it's just data in etcd.

### 3. The "controller that ignores errors"

```go
// DON'T
if err := r.reconcileBackup(ctx, pg); err != nil {
    log.Error(err, "backup failed")
    // continue anyway
}
```

Errors should propagate. The reconcile loop will requeue. Failing silently is a debugging nightmare.

### 4. The "controller that owns the world"

```go
// DON'T create Pods, Services, Deployments across namespaces
// DON'T use cluster-scoped permissions for namespaced operations
```

The blast radius of an operator is its RBAC. Keep it tight.

### 5. The "controller with no finalizers"

```go
// DON'T skip the finalizer
// when the CR is deleted, the operator's cleanup logic doesn't run
```

Finalizers are how controllers do cleanup. Without them, deleting a CR leaves orphaned resources.

### 6. The "controller that doesn't update status"

```go
// DON'T forget to update the CR's .status
// users can't tell if the app is healthy
```

`.status` is the user-facing view. Always update it.

## Real-world operator examples

* **Argo CD** (GitOps) — `Application` CR, reconciles to desired Git state
* **cert-manager** (TLS) — `Certificate`, `Issuer`, `ClusterIssuer` CRs
* **Strimzi** (Kafka) — `Kafka`, `KafkaTopic`, `KafkaUser` CRs
* **CloudNativePG** (Postgres) — `Cluster` CR
* **Redis Operator** — `RedisCluster`, `RedisSentinel` CRs
* **Rook** (Ceph storage) — `CephCluster` CR
* **Keda** (event-driven autoscaling) — `ScaledObject` CR
* **Crossplane** (cloud resources) — `Composition`, `Composite` CRs

## See also

* [[Kubernetes/concepts/L09-advanced/02-custom-controllers|Custom Controllers]] — the pattern operators are built on
* [[Kubernetes/concepts/L09-advanced/03-customresourcedefinitions|CRDs]] — the API extension mechanism
* [[Kubernetes/concepts/L09-advanced/04-admission-controllers|Admission Controllers & Webhooks]] — for validating / mutating CRs
* [[Kubernetes/concepts/L09-advanced/05-finalizers|Finalizers]] — for cleanup
