# StatefulSets

*"https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/"*

A StatefulSet is a controller that manages a set of Pods with **stable, unique identities** and **persistent per-replica storage**. It's the right choice for stateful workloads — databases, message queues, key-value stores — where each replica has a role that's different from the others.

## The problem with Deployments for stateful apps

A Deployment's Pods are **interchangeable** — they're all replicas of the same service. When a Pod is replaced, it gets a new random name, a new random IP, and a new random identity.

For most apps, that's fine. The Service load-balances to whatever Pod is ready; clients don't care which one they hit.

For stateful apps, it's not fine:

* A Postgres **primary** is different from a **replica**. You don't load-balance to both; you route writes to the primary, reads to replicas.
* A Kafka **broker 0** is different from **broker 1**. The cluster needs to know which broker is which.
* A ZooKeeper **ensemble** member is different from another. The leader vs follower role matters.

These apps need:

* **Stable, predictable names** (`postgres-0`, `postgres-1`, `postgres-2`)
* **Stable, predictable network identities** (DNS that points to the right Pod)
* **Stable, per-replica storage** (data that survives Pod replacement)
* **Ordered deployment and scaling** (start 0, then 1, then 2)
* **Ordered termination** (kill 2, then 1, then 0)
* **Ordered rolling updates** (update 0, then 1, then 2 — and respect readiness)

StatefulSets provide all of this. Deployments don't.

## Basic example

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: postgres }
spec:
  serviceName: postgres            # the headless Service that gives the Pods DNS
  replicas: 3
  selector:
    matchLabels: { app: postgres }
  template:
    metadata:
      labels: { app: postgres }
    spec:
      containers:
      - name: postgres
        image: postgres:15
        ports:
        - containerPort: 5432
          name: postgres
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:             # per-replica PVC, created automatically
  - metadata: { name: data }
    spec:
      accessModes: [ReadWriteOnce]
      storageClassName: gp3
      resources:
        requests: { storage: 100Gi }
```

This creates:

* A StatefulSet `postgres` with 3 replicas
* 3 Pods: `postgres-0`, `postgres-1`, `postgres-2`
* 3 PVCs: `data-postgres-0`, `data-postgres-1`, `data-postgres-2`
* 3 PVs (dynamically provisioned by the `gp3` StorageClass)

The PVCs persist even if the StatefulSet is deleted. The Pods are recreated with the same names and mount the same PVCs.

## Stable identity

Each Pod in a StatefulSet has:

* **Stable name**: `postgres-0`, `postgres-1`, `postgres-2` (zero-indexed)
* **Stable hostname**: set to the Pod name (`postgres-0`)
* **Stable DNS**: a `Headless Service` (see below) provides DNS records

The Pod name is **deterministic** — `postgres-0` is always Pod 0 in the StatefulSet, no matter how many times it's recreated.

## Headless Service

A StatefulSet needs a **headless Service** to provide DNS for its Pods. The `clusterIP: None` setting means the Service has no virtual IP — DNS returns the Pods' IPs directly.

```yaml
apiVersion: v1
kind: Service
metadata: { name: postgres }
spec:
  clusterIP: None                  # headless
  selector: { app: postgres }
  ports:
  - port: 5432
    name: postgres
```

The StatefulSet spec says `serviceName: postgres`. This is the headless Service.

DNS records for the StatefulSet's Pods:

```
postgres-0.postgres.default.svc.cluster.local    → 10.244.1.5
postgres-1.postgres.default.svc.cluster.local    → 10.244.2.7
postgres-2.postgres.default.svc.cluster.local    → 10.244.3.9

postgres.default.svc.cluster.local                → all 3 IPs (in random order)
```

Clients can address individual Pods by name (`postgres-0.postgres.default.svc.cluster.local`) or the headless Service for all of them.

## Per-replica persistent storage

`volumeClaimTemplates` create a PVC per Pod. Each Pod mounts its own PVC.

```yaml
volumeClaimTemplates:
- metadata: { name: data }
  spec:
    accessModes: [ReadWriteOnce]
    storageClassName: gp3
    resources: { requests: { storage: 100Gi } }
```

For 3 replicas, k8s creates 3 PVCs:

* `data-postgres-0`
* `data-postgres-1`
* `data-postgres-2`

Each Pod mounts the PVC with its index. When the Pod is replaced, the new Pod mounts the same PVC, and the data is there.

The PVCs are **not deleted when the StatefulSet is deleted** (default `persistentVolumeReclaimPolicy: Retain`). You have to delete them manually if you want to free the storage.

## Ordered operations

StatefulSets have **strict ordering** for several operations:

### Scaling up

When scaling from 3 to 5 replicas:

1. `postgres-3` is created
2. Wait for `postgres-3` to be Ready
3. `postgres-4` is created
4. Wait for `postgres-4` to be Ready

`postgres-3` must be Ready before `postgres-4` starts. If `postgres-3` fails, `postgres-4` is never created.

### Scaling down

When scaling from 5 to 3:

1. `postgres-4` is terminated (gracefully)
2. Wait for `postgres-4` to be fully terminated
3. `postgres-3` is terminated
4. Wait for `postgres-3` to be fully terminated

`postgres-4` is killed before `postgres-3`. The reverse of scale-up.

### Rolling update

When you change the Pod template:

1. `postgres-0` is updated
2. Wait for `postgres-0` to be Ready
3. `postgres-1` is updated
4. Wait for `postgres-1` to be Ready
5. ... etc.

Each replica is updated in order, waiting for Readiness before moving on.

The default update strategy is `RollingUpdate` with `partition: 0` (update all). You can set `partition: 2` to only update Pods with index ≥ 2 (canary).

## The "broken" Pod behavior

StatefulSets have a `podManagementPolicy` that controls what happens when a Pod is "broken" (failed, can't become Ready).

### `OrderedReady` (default)

* Operations are strictly ordered
* A broken Pod **blocks the next one** — the StatefulSet doesn't move on
* If `postgres-2` fails, no subsequent Pods are updated

This is the safe default. If something's wrong, you find out fast.

### `Parallel`

* All Pods are created/updated/deleted in parallel
* No ordering
* Faster, but you can have multiple broken Pods

Use this when:

* The app doesn't depend on ordinals
* You want fast rollouts
- You're OK with a brief inconsistency window

## Update strategies

### `RollingUpdate` (default)

Updates Pods one at a time, in order, waiting for Readiness.

```yaml
spec:
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 0                  # update all Pods with index >= 0
      maxUnavailable: 1             # allow 1 Pod to be down during update
```

`partition: N` means: only update Pods with index ≥ N. Use for **canary rollouts**:

```bash
# canary: update only Pods with index >= 2
kubectl patch statefulset postgres -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":2}}}}'

# change the template
kubectl set image statefulset postgres postgres=postgres:16

# only postgres-2 gets updated; postgres-0 and postgres-1 stay on the old version

# if canary looks good, update everyone
kubectl patch statefulset postgres -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'
```

### `OnDelete`

Old Pods are kept until you manually delete them. The StatefulSet doesn't recreate them.

Useful for manual upgrade procedures (e.g. you have a custom script that drains a Postgres replica, runs the migration, then deletes the Pod so the StatefulSet recreates it).

## The Pod identity, in detail

A Pod in a StatefulSet has:

* **Name**: `<statefulset-name>-<ordinal>` (e.g. `postgres-0`)
* **Hostname**: same as the name
* **Subdomain**: `<pod-name>.<service-name>.<namespace>.svc.cluster.local` (e.g. `postgres-0.postgres.default.svc.cluster.local`)
* **Stable storage**: the PVC from `volumeClaimTemplates`
* **Ordinal**: 0, 1, 2, ... (assigned by the StatefulSet)

The ordinal is part of the **Pod's name** but also implicit in the StatefulSet's tracking. If you delete `postgres-0` and the StatefulSet recreates it, the new Pod is `postgres-0` (same name, same ordinal, different UID).

The Pod's name is also a label:

```
statefulset.kubernetes.io/pod-name: postgres-0
```

## The headless Service DNS, in detail

For a StatefulSet `postgres` with 3 replicas in namespace `default`, the headless Service provides:

```
# for each Pod
postgres-0.postgres.default.svc.cluster.local.   A  10.244.1.5
postgres-1.postgres.default.svc.cluster.local.   A  10.244.2.7
postgres-2.postgres.default.svc.cluster.local.   A  10.244.3.9

# for the Service
postgres.default.svc.cluster.local.              A  10.244.1.5
                                                 A  10.244.2.7
                                                 A  10.244.3.9
```

(The Service's A records are all the backing Pods. The headless service doesn't load-balance — it just returns all the IPs.)

This DNS setup is what makes stable identities useful: a client can connect to `postgres-0.postgres.default.svc.cluster.local:5432` and always reach the same Pod (until the Pod is rescheduled).

## PVC lifecycle

PVCs created from `volumeClaimTemplates` follow this lifecycle:

1. **StatefulSet is created with 3 replicas** → 3 PVCs (`data-postgres-0`, `data-postgres-1`, `data-postgres-2`) are created
2. **A Pod is replaced** (rescheduled, restarted, etc.) → it mounts the same PVC, the data is there
3. **StatefulSet is scaled down** (3 → 1) → the Pods `postgres-2` and `postgres-1` are deleted, but their PVCs are **retained**
4. **StatefulSet is scaled up again** (1 → 3) → Pods `postgres-1` and `postgres-2` are recreated, mounting the same PVCs — **data is preserved**
5. **StatefulSet is deleted** → the Pods are deleted, **but the PVCs are not** (the StatefulSet's `persistentVolumeClaimRetentionPolicy` defaults to `Retain`)

To delete the PVCs, you have to do it manually:

```bash
kubectl delete pvc data-postgres-0 data-postgres-1 data-postgres-2
```

This is a **feature**, not a bug. The data outlives the StatefulSet.

## PVC retention policy

You can control this:

```yaml
spec:
  persistentVolumeClaimRetentionPolicy:
    whenScaled: Retain             # PVCs survive scale-down
    whenDeleted: Retain            # PVCs survive StatefulSet deletion
```

`whenScaled: Delete` would delete PVCs when the StatefulSet is scaled down. **Almost never what you want** — you'd lose data.

`whenDeleted: Delete` is also rarely correct. The whole point of StatefulSets is that data outlives Pods.

## Headless Service vs regular Service

You can have **both** a headless Service (for Pod-to-Pod addressing) and a regular Service (for client access):

```yaml
# headless Service: for direct Pod addressing
apiVersion: v1
kind: Service
metadata: { name: postgres }
spec:
  clusterIP: None
  selector: { app: postgres }
  ports:
  - port: 5432
    name: postgres
---
# regular Service: for client load balancing
apiVersion: v1
kind: Service
metadata: { name: postgres-lb }
spec:
  selector: { app: postgres }
  ports:
  - port: 5432
    name: postgres
```

In-cluster clients can use:

* `postgres-lb.default.svc.cluster.local:5432` — load-balanced (random Pod)
* `postgres-0.postgres.default.svc.cluster.local:5432` — specific Pod 0

## Init containers in StatefulSets

Init containers run per-Pod, like in Deployments. They run before the main container starts.

```yaml
spec:
  template:
    spec:
      initContainers:
      - name: init-replica
        image: postgres:15
        command:
        - sh
        - -c
        - |
          # wait for previous replica to be reachable, then run init
          until pg_isready -h postgres-$((ORDINAL - 1)) -p 5432; do
            sleep 2
          done
          # initialize this replica
        env:
        - name: ORDINAL
          valueFrom:
            fieldRef:
              fieldPath: metadata.name      # e.g. "postgres-0"
                # extract "0" with a script
```

This is the kind of thing you need to set up **replica chains** for Postgres or MySQL — replica N waits for replica N-1 to be ready.

## Use cases

StatefulSets are for stateful apps. Some examples:

* **Databases**: Postgres, MySQL, MongoDB, Cassandra, ScyllaDB, CockroachDB
* **Message queues**: Kafka, RabbitMQ, NATS
* **Coordination**: ZooKeeper, etcd
* **Search**: Elasticsearch, Solr, OpenSearch
* **Custom**: any app that has per-replica identity and state

For all of these, you also typically need an **operator** to handle the operational complexity (failover, backup, scaling, etc.). A bare StatefulSet doesn't do that.

## When NOT to use a StatefulSet

* **Stateless apps** — use a Deployment
* **One Pod per node** — use a DaemonSet
* **Run-to-completion tasks** — use a Job
* **The app doesn't need stable identity** — use a Deployment

If you can replace a Pod with another random Pod and nothing breaks, you don't need a StatefulSet.

## The "Pod stuck Pending" debugging

A common StatefulSet issue: a Pod is `Pending` because its PVC is `Pending`. This usually means the storage class can't provision a volume. The PVC is waiting for a PV that matches.

```bash
kubectl get pvc -l app=postgres
# NAME              STATUS    VOLUME   CAPACITY   ACCESS MODES
# data-postgres-0   Pending                                      # waiting for PV

kubectl describe pvc data-postgres-0
# Events:
#   ProvisioningFailed: storageclass "gp3" not found
#   (or similar)
```

The fix is usually:

* Make sure the storage class exists
* Make sure the cluster can provision volumes
* Check for quota issues

## The "Pod stuck terminating" debugging

When you delete a StatefulSet, the Pods are terminated in order. If one is stuck terminating:

```bash
kubectl get pods -l app=postgres
# NAME          READY   STATUS        RESTARTS   AGE
# postgres-2    1/1     Terminating   0          5m
# postgres-1    1/1     Terminating   0          6m
# postgres-0    1/1     Terminating   0          7m
```

A Pod is "stuck terminating" usually because:

* The container isn't responding to SIGTERM (no graceful shutdown)
* A `preStop` hook is hanging
* A volume is stuck unmounting

```bash
# force-delete (last resort)
kubectl delete pod postgres-0 --force --grace-period=0
```

This skips the graceful termination. The Pod's PVC might be left in a weird state.

## The "init container in wrong order" issue

If you have multiple StatefulSets with init containers that depend on each other, ordering can be tricky. The StatefulSet doesn't know about other StatefulSets.

For example, if `postgres-0`'s init container waits for `kafka-0`, but the StatefulSets are created in the wrong order, the init container times out.

Solutions:

* Use a Job to wait for dependencies
* Use an operator to manage ordering
- Use init containers with longer timeouts and good error messages

## Gotchas

* **A StatefulSet without a headless Service doesn't work.** The `serviceName` field requires a Service with `clusterIP: None`. If the Service doesn't exist, the StatefulSet's Pods can't be created (they fail DNS validation).
* **`volumeClaimTemplates` cannot be changed** once the StatefulSet is created. You can change `spec.template.spec.containers`, but adding a new `volumeClaimTemplate` requires a new StatefulSet.
* **A StatefulSet with a headless Service and a regular Service** is a common pattern. Make sure they have different names (or one selector excludes the other).
* **The `partition` field in `updateStrategy`** is per-StatefulSet, not per-Pod. A value of 2 means "update Pods with index ≥ 2" — so `postgres-0` and `postgres-1` stay on the old version.
* **Scaling down doesn't delete PVCs** (by default). If you re-scale up, the data is there. If you want a clean slate, delete the PVCs manually.
* **A StatefulSet that owns a `Headless Service`** doesn't manage the Service. You create the Service separately. The StatefulSet just uses the name in DNS.
* **`podManagementPolicy: Parallel` is faster but riskier.** With `OrderedReady`, a broken Pod blocks the update. With `Parallel`, all Pods are updated, even if some are broken.
* **A `StatefulSet`'s Pod template cannot use `hostPath`.** Some teams try to use `hostPath` for stateful data; the StatefulSet will reject it. Use PVCs.
* **The StatefulSet's `replicas` field is required.** Unlike a Deployment, you can't omit it.
* **Rolling update of a StatefulSet is per-Pod and sequential.** For 10 replicas, the update takes 10 * (startup time + ready time). For a slow-starting app, this can be hours.
* **Init containers can't use the PVCs of previous ordinals.** Each Pod only sees its own PVC. You have to coordinate across Pods via the headless Service.
* **The `serviceName` is required, not optional.** Some tools assume it can be derived. It's not.

## StatefulSet + operator

For real production, **don't run a StatefulSet alone** for databases. Use an operator:

* **Postgres**: CloudNativePG, Zalando
* **MySQL**: MySQL Operator (Oracle), Percona
* **MongoDB**: MongoDB Operator
* **Kafka**: Strimzi
* **Cassandra**: Cass Operator
* **Elasticsearch**: ECK (Elastic Cloud on Kubernetes)

These operators wrap a StatefulSet (or set of StatefulSets) and add:

* **Automated failover** (when a primary dies, promote a replica)
* **Backup and restore**
* **Scaling** (with the right ordering)
* **Version upgrades** (with the right procedure)
* **Monitoring** (Prometheus metrics)

A bare StatefulSet gives you **stable identity and per-replica storage**, but the operational stuff is up to you.

## See also

* [[Kubernetes/concepts/L03-workloads/03-deployments|Deployments]] — the alternative for stateless apps
* [[Kubernetes/concepts/L05-config-storage/05-persistentvolumeclaim|PersistentVolumeClaim]] — what StatefulSets use for storage
* [[Kubernetes/concepts/L09-advanced/01-operators|Operators]] — for real database management
* [[Kubernetes/concepts/L04-services-networking/02-services|Services]] — headless Services
