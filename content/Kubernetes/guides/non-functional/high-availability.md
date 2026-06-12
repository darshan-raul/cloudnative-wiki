---
title: High Availability
tags:
  - Kubernetes
  - Non-Functional
  - High-Availability
  - Reliability
---

A HA cluster survives **node loss, zone loss, control plane failure, and partial network partitions** without dropping traffic. The 9s you achieve are a function of design choices, not luck.

## The layers of HA

```
┌────────────────────────────────────────────────────────────┐
│  Application layer                                         │
│  ├─ multiple replicas                                      │
│  ├─ PodDisruptionBudgets                                   │
│  ├─ anti-affinity / topology spread                        │
│  └─ graceful shutdown, health checks                       │
├────────────────────────────────────────────────────────────┤
│  Cluster layer                                             │
│  ├─ 3+ control plane nodes (HA control plane)              │
│  ├─ multiple worker nodes (no single point of failure)     │
│  ├─ multiple zones / regions                               │
│  └─ replicated etcd                                        │
├────────────────────────────────────────────────────────────┤
│  Network layer                                             │
│  ├─ multiple CNI paths                                     │
│  ├─ redundant ingress controllers (not just replicas)      │
│  └─ cross-zone traffic engineering                         │
├────────────────────────────────────────────────────────────┤
│  Data layer                                                │
│  ├─ replicated storage (no single PV)                      │
│  ├─ backup/restore (separate cluster / region)             │
│  └─ tested disaster recovery                               │
└────────────────────────────────────────────────────────────┘
```

Each layer has its own HA strategy. Failing any one layer can take down the system.

## The 9s and what they cost

| Target | Downtime/year | What it requires |
|--------|---------------|------------------|
| 99% (2 nines) | 3.65 days | Single node, single zone, single cluster. Cheap, fragile. |
| 99.9% (3 nines) | 8.77 hours | Multiple nodes, basic redundancy. Standard k8s. |
| 99.95% | 4.38 hours | Multi-zone, replicated data. Real engineering. |
| 99.99% (4 nines) | 52.6 minutes | Multi-region, tested DR, automation. Expensive. |
| 99.999% (5 nines) | 5.26 minutes | Multi-region active-active, automated failover, chaos-tested. Telco-grade. |

Most production k8s clusters aim for **3-4 nines**. 5 nines is rarely the actual requirement — measure first.

## Control plane HA

The control plane is the API server, scheduler, controller-manager, etcd. If it dies, the cluster doesn't accept new work.

**Single control plane = no HA.** A single etcd node or API server is a SPOF.

**HA control plane requires:**
- **3 or 5 etcd nodes** (odd number, quorum-based)
- **2+ API server instances** behind a load balancer
- **Multiple controller-manager / scheduler replicas** (only one is leader, others standby)
- **Cloud-managed** (EKS, GKE, AKS) handles this for you

**kubeadm HA pattern:**

```
┌─────────────────────────────────────────────────────────────┐
│  Load Balancer (cloud LB or HAProxy)                        │
│      ↓                                                      │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐               │
│  │ API Server │ │ API Server │ │ API Server │               │
│  │ master-1   │ │ master-2   │ │ master-3   │               │
│  └────────────┘ └────────────┘ └────────────┘               │
│       ↓             ↓              ↓                        │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐               │
│  │   etcd     │ │   etcd     │ │   etcd     │               │
│  │ master-1   │ │ master-2   │ │ master-3   │               │
│  └────────────┘ └────────────┘ └────────────┘               │
└─────────────────────────────────────────────────────────────┘
```

3 etcd nodes tolerate 1 failure. 5 etcd nodes tolerate 2. **Don't use 2 etcd nodes** — no quorum, you lose HA.

## Multi-AZ deployment

For real HA, deploy across **3 availability zones**. Two zones gives you 2-AZ failover; three zones gives you better fault tolerance and load distribution.

**Pod topology spread:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 6
  template:
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: web
      containers:
      - name: web
        image: myorg/web:v1
```

This ensures that pods are spread across zones as evenly as possible, with no zone having more than 1 pod above the average.

**Pod anti-affinity** for nodes:

```yaml
spec:
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app: web
        topologyKey: kubernetes.io/hostname   # don't put two web pods on the same node
```

Combined: `topologySpreadConstraints` for zones, `podAntiAffinity` for nodes.

**Storage:** zone-bound volumes are the gotcha. An EBS volume is in zone A. If the pod scheduled in zone B tries to use it, it can't.

**Solutions:**

1. **Pod topology + node topology constraint** — schedule the pod in the same zone as its PVC.
2. **Replicated storage** — Ceph, Rook, EFS, S3 — works across zones.
3. **StorageClass with `WaitForFirstConsumer`** — defers binding until the pod is scheduled, so the PV provisions in the right zone.

## PodDisruptionBudgets (PDBs)

The most overlooked HA control. PDBs tell Kubernetes: "during voluntary disruption, keep at least N pods running."

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-pdb
spec:
  minAvailable: 2
  # or
  maxUnavailable: 1
  selector:
    matchLabels:
      app: web
```

**Without PDBs, any voluntary disruption can take down all your pods at once:**
- Karpenter consolidation
- Cluster autoscaler scale-down
- Node drain for maintenance
- Helm uninstall
- Argo CD sync

**With PDBs, the disruption is rate-limited.** `kubectl drain` will wait for pods to finish gracefully, but the scheduler won't schedule new pods to replace them if the PDB would be violated.

```bash
# verify PDBs
kubectl get pdb -A
# NAME       MIN-AVAILABLE   MAX-UNAVAILABLE   ALLOWED-DISRUPTIONS   AGE
# web-pdb    2                                1                     5d
# the "ALLOWED-DISRUPTIONS" column tells you how many pods can be down
```

**Setting PDB values:**

| Workload | minAvailable | maxUnavailable |
|----------|--------------|----------------|
| Stateless web (5 replicas) | 3 | 2 |
| Stateful DB (3 replicas) | 2 | 1 |
| Critical service (10 replicas) | 5 | 5 |
| Best-effort (1 replica) | 0 | 1 (or no PDB) |

**Common mistake:** `minAvailable: 100%`. If you have 3 replicas and want 100% available, the PDB will block all voluntary disruption. This can deadlock drain operations.

## Anti-affinity vs topology spread

These are different, and you usually want both:

| | Anti-affinity | Topology spread |
|--|---|---|
| **Purpose** | Don't put same-kind pods on the same node/zone | Spread pods evenly across topology |
| **Constraint type** | Hard (required) or soft (preferred) | Hard (required) or soft (preferred) |
| **Use case** | Avoid node failure taking all replicas | Even distribution |

```yaml
# good: combine both
spec:
  affinity:
    podAntiAffinity:                          # don't put two web pods on same node
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app: web
          topologyKey: kubernetes.io/hostname
  topologySpreadConstraints:                  # spread across zones
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app: web
```

## Graceful shutdown

When a pod is deleted (scaled down, drained, etc.), it should:

1. **Stop accepting new requests** (remove from Service endpoints, or signal the load balancer)
2. **Finish in-flight requests** (within the grace period)
3. **Exit cleanly** (return 0, or whatever the platform expects)

**Configure properly:**

```yaml
spec:
  terminationGracePeriodSeconds: 60     # give 60s to finish in-flight
  containers:
  - name: web
    lifecycle:
      preStop:
        exec:
          command:
          - /bin/sh
          - -c
          - "sleep 5 && kill -SIGTERM 1"  # small delay to let Service remove pod
    ports:
    - name: http
      containerPort: 8080
  readinessProbe:                          # fails during shutdown = removed from Service
    httpGet:
      path: /health
      port: 8080
```

**The `preStop` sleep is a well-known workaround for the race condition** where the kubelet sends SIGTERM before the pod is removed from the Service endpoints. The sleep gives kube-proxy time to update iptables rules. Without it, you may see brief 502s during rollouts.

## Liveness, readiness, and startup probes

The three probes each have a different role:

| Probe | Question | Failure action |
|-------|----------|----------------|
| **Liveness** | Is the app still working? | Restart the container |
| **Readiness** | Is the app ready to serve traffic? | Remove from Service endpoints |
| **Startup** | Is the app still starting up? | Wait, don't run liveness yet |

**Best practices:**

```yaml
livenessProbe:
  httpGet:
    path: /alive
    port: 8080
  initialDelaySeconds: 0          # startup probe handles initial delay
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 3             # 3 consecutive failures = restart
  successThreshold: 1

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 2             # 2 failures = remove from Service
  successThreshold: 1

startupProbe:
  httpGet:
    path: /alive
    port: 8080
  periodSeconds: 5
  failureThreshold: 30            # 30*5 = 150s for slow apps to start
```

**Why separate `/alive` and `/ready`?**

- `/alive` should be permissive — it should fail only if the app is genuinely broken. Restart the container only if it's stuck.
- `/ready` should be strict — it should fail if the app can't serve traffic right now (e.g., dependency down). Remove from Service so traffic goes elsewhere.

A bad pattern: a single `/health` endpoint that returns 200 only when fully functional. Then a transient dependency failure removes all pods from the Service, causing a full outage. Use separate endpoints.

## Rate limiting and circuit breakers

For application-level HA:

- **Client-side rate limiting** — your service should back off when a downstream is slow
- **Circuit breakers** — if a downstream fails N times, stop calling it for a while
- **Retries with exponential backoff** — and jitter

Tools: Istio, Linkerd, Resilience4j, Polly, etc.

## Health checks at every layer

| Layer | Health check |
|-------|--------------|
| Node | kubelet heartbeat to apiserver |
| Pod | Liveness, readiness, startup probes |
| Service | Endpoints populated only with Ready pods |
| Ingress | Backend health check, TLS verification |
| Cloud LB | Target group health checks |
| App | Internal health endpoints |

When debugging "why is X down?", walk up the layers — if the app's health check is fine but the LB says unhealthy, it's the LB's check failing, not the app.

## Application patterns for HA

### Idempotency

Make your services **idempotent**. Retries are inevitable; if a request is non-idempotent, retries cause duplicate work.

- Use idempotency keys for write operations
- Database transactions with unique constraints
- Message deduplication for async workloads

### Backpressure

When downstream is slow, **don't keep accepting work**. Reject early. Patterns:

- Queue depth monitoring (e.g., Kafka lag, SQS depth)
- Pod-level concurrency limits
- Rate limiters (token bucket, leaky bucket)
- Adaptive concurrency (e.g., Netflix's concurrency limits library)

### Bulkheading

Isolate failures to one component. If your checkout service is down, the rest of the site should still work.

- Separate Deployments per service
- Resource isolation (resource quotas, separate nodes)
- Per-user rate limits (so one noisy customer doesn't starve others)

## Database HA

K8s doesn't manage your data tier directly. But HA of the data tier is essential.

**Patterns:**

1. **Managed database** (RDS, Cloud SQL, Azure Database) — HA built-in, failover managed by the cloud.
2. **Operator-managed** (e.g., CloudNativePG, Percona, MongoDB operator) — runs in k8s, handles replication, failover, backups.
3. **Self-managed** — you handle replication, failover, backups. Don't do this unless you have to.

**For stateful workloads on k8s:**

- Use StatefulSets (not Deployments) for stable network identity
- Use `volumeClaimTemplates` for per-pod storage
- Set `podManagementPolicy: OrderedReady` to ensure replica order
- Use the operator's own failover mechanism (not k8s)

## Ingress HA

A single ingress controller is a SPOF. Run **at least 2 replicas**, ideally across zones.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ingress-nginx
spec:
  replicas: 2
  template:
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        # ...
```

The cloud LB in front of the ingress will route to healthy pods. If a zone dies, the LB removes the failed pods and routes to the remaining ones.

## Cross-region HA

Beyond multi-AZ, multi-region:

```
us-east-1 (primary)        us-west-2 (standby)
  ┌─────────────┐           ┌─────────────┐
  │   Cluster   │           │   Cluster   │
  │             │           │             │
  │  App pods   │           │  App pods   │
  │             │           │  (warm)     │
  └──────┬──────┘           └──────┬──────┘
         │                         │
         └─── data replication ───┘
              (DB, object storage)
```

Patterns:

- **Active-passive** — one region active, the other on standby. Failover is manual or scripted.
- **Active-active** — both regions serve traffic. Requires global load balancer + cross-region data sync.
- **Backup-and-restore** — simplest. Restore from backups in another region. Highest RTO.

Tools: Cluster API for cluster lifecycle, Submariner/Cilium ClusterMesh for cross-cluster networking, Velero for backup.

## Failure mode testing

You don't have HA until you've tested it. Common failure mode tests:

| Test | What it exercises |
|------|-------------------|
| Kill a node | Pod rescheduling, anti-affinity |
| Drain a node | PDBs, graceful shutdown |
| Kill a zone | Multi-AZ failover, topology spread |
| Kill the apiserver | etcd quorum, control plane HA |
| Network partition | Service failover, client retry |
| Kill the database | Failover, replica promotion |
| Spike load | Auto-scaling, resource limits |
| Bad rollout | Rollback, readiness gates |

Run these regularly, not just once. See [[Kubernetes/guides/non-functional/chaos-engineering|chaos-engineering]] for the practice.

## Common gotchas

* **PDBs without enough headroom** can deadlock `kubectl drain`. Always test.
* **Topology spread with `whenUnsatisfiable: DoNotSchedule`** prevents scheduling if constraints can't be met. Use `ScheduleAnyway` for soft constraints.
* **Single-pod Deployments** are not HA. Always run >= 2 replicas for stateless services.
* **PodDisruptionBudgets don't protect against involuntary disruption** (node crash, OOM). For that, you need multiple replicas across failure domains.
* **`maxSkew: 1` is strict.** A cluster with 3 zones and 5 pods means 2/2/1, which fails `maxSkew: 1`. Use `ScheduleAnyway` or accept unevenness.
* **Graceful shutdown without a `preStop` sleep** can cause 502s during rollouts. The 5-10s sleep is the standard fix.
* **Liveness probes that check downstream health** are wrong. Liveness should only fail if the app itself is broken; downstream checks belong in readiness.
* **Don't run ingress as a single replica** to save cost. It's a SPOF.
* **Storage is the silent failure mode.** A 99% HA setup with EBS volumes in one zone isn't 99% HA.
* **Cloud-managed control plane is HA by default** but the data plane (worker nodes) is your problem.
* **Don't set HPA `minReplicas: 1`** for critical services. Scale to 0/1 is not HA.
* **`topology.kubernetes.io/zone` may be missing on some nodes** (especially self-managed). Always verify.
* **DaemonSet pods run on every node.** If a DaemonSet is critical, set its tolerations carefully so it can run on tainted nodes.

## The HA checklist

For production:

- [ ] Control plane: 3+ nodes, 3+ etcd (or managed)
- [ ] Workers: 3+ nodes, ideally across 3 zones
- [ ] Each Deployment: replicas >= 2, anti-affinity, topology spread
- [ ] Each Deployment: PDB with appropriate minAvailable
- [ ] Each Deployment: liveness, readiness, startup probes
- [ ] Each Deployment: graceful shutdown (preStop, terminationGracePeriodSeconds)
- [ ] Ingress: >= 2 replicas, across zones
- [ ] Storage: replicated, or zone-bound with topology constraints
- [ ] Network: multiple CNI paths, cross-zone aware
- [ ] Data: managed database or operator, with backups
- [ ] Tested: node failure, zone failure, network partition, bad rollout
- [ ] Monitored: latency, error rate, pod restarts, node health
- [ ] Documented: RTO, RPO, runbooks

## Per-service HA profiles

Not every service needs the same HA bar. Define profiles:

| Profile | Targets | Patterns | Cost |
|---------|---------|----------|------|
| **Tier 0** (Tier-1 critical) | 99.99%, RPO seconds | Multi-region active-active, multi-AZ, multi-replica, full DR | $$$$ |
| **Tier 1** (production) | 99.95%, RPO minutes | Multi-AZ, multi-replica, PDBs, backups, runbooks | $$$ |
| **Tier 2** (internal) | 99.9%, RPO 1 hour | Multi-AZ, 2+ replicas, backups | $$ |
| **Tier 3** (dev/test) | 99%, no RPO target | Single AZ, 1 replica, no backups | $ |

```yaml
# tier annotation on the workload
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payments
  annotations:
    ha-tier: "0"   # critical
spec:
  replicas: 6
  # ... multi-AZ, anti-affinity
```

```yaml
# tier-2 deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: admin-tool
  annotations:
    ha-tier: "2"   # internal
spec:
  replicas: 2
  # single AZ OK
```

## The "blast radius" calculator

When designing HA, the key question is: "what's the worst-case impact of a failure?"

```
Single pod failure       → 1/N capacity loss
Node failure            → all pods on that node lost
Zone failure            → all pods in that zone lost
Region failure          → all pods in that region lost
Control plane failure   → no new scheduling, existing pods run
etcd quorum loss        → cluster is read-only, then dead
```

Each level needs different mitigations:

- Pod → replicas
- Node → anti-affinity, multi-node
- Zone → topology spread, multi-AZ
- Region → multi-region DR
- Control plane → 3+ masters, managed
- etcd → 3+ etcd nodes, encrypted backups

**Design for the failure mode you're trying to survive.** Don't over-engineer for "single pod" if your real risk is "zone failure."

## Regional patterns

For multi-region, three main patterns:

### Active-passive (cost-effective)

- Primary region: full production
- Secondary region: warm standby (data replicated, compute idle)
- Failover: scripted or manual, takes minutes
- Cost: 1.5-2x single region

```
us-east-1 (primary)        us-west-2 (standby)
  App: 100% traffic        App: 0% traffic, scaled to 0
  DB: primary              DB: read replica, can promote
  Storage: primary         Storage: replicated
```

### Active-active (best availability)

- Both regions serve traffic
- Data replicated synchronously (or near-sync)
- DNS-based routing (Route53, Cloud DNS)
- Cost: 2-3x single region

```
us-east-1                  us-west-2
  50% traffic                50% traffic
  DB: bidirectional          DB: bidirectional
  Storage: replicated        Storage: replicated
```

### Backup-and-restore (cheapest)

- Primary region: full production
- Secondary: just backups (S3 cross-region replication)
- Failover: provision new cluster, restore data
- Cost: 1.05-1.1x single region

### The "right" pattern

| Use case | Pattern |
|----------|---------|
| Internal tools | Backup-and-restore |
| Standard production | Active-passive |
| Critical production | Active-active |
| Compliance mandates | Active-active (geo-redundant) |

## Capacity planning for HA

Don't just make the cluster HA; make the **team** HA.

- **Document runbooks** for common failures
- **Cross-train** the on-call rotation
- **Test failover** quarterly
- **Have backups** of runbooks, configs, and code in git
- **Run incident simulations** (game days)
- **Blameless postmortems** — focus on systems, not individuals

## Regional failover with Route53 / Cloud DNS

DNS-based failover is the common pattern for multi-region.

```
Route53 health check → healthy endpoint (us-east-1) → traffic
                     → unhealthy                  → traffic to us-west-2
```

```yaml
# AWS Route53 health check
Type: HTTP
URL: https://api.example.com/healthz
Interval: 30s
Failure threshold: 3
```

**Gotcha:** DNS TTL matters. Long TTLs (1 hour) = slow failover. Short TTLs (60s) = fast failover, but more DNS queries.

**For HTTP failover:** use a global load balancer (AWS Global Accelerator, GCP Cloud Load Balancing) instead of DNS. Faster, more reliable.

## The "blast radius" of cluster lifecycle

The cluster itself fails. Be ready:

- **Cluster provisioning is in git** (Cluster API, Terraform, kOps)
- **Cluster add-ons are in git** (Argo CD, Flux)
- **Application manifests are in git**
- **Secrets are in an external store** (Vault, AWS SM)
- **Backups are automated** (Velero, cloud-native)

**Then: rebuild the cluster from git.** Cluster should be re-creatable in <1 hour.

## Multi-cluster service discovery

If you have multiple clusters and want a Service to span them:

- **Submariner** — L3 VPN between clusters, services work across
- **Cilium ClusterMesh** — eBPF-based, faster than Submariner
- **Istio multi-cluster** — mesh-aware
- **Linkerd multi-cluster** — simpler than Istio
- **Clusterpedia** — federated read

**Tradeoff:** multi-cluster networking is complex. Most teams don't need it; they need regional DR with separate clusters and DNS failover.

## Storage HA patterns

Storage is the hard part. Block storage is zone-bound.

| Storage | Zone-bound? | Multi-AZ? | Cross-region? |
|---------|-------------|------------|---------------|
| **EBS** | Yes | No (replicated) | Snapshots only |
| **EFS** | No | Yes | Replication |
| **GCE PD** | Yes | No | Snapshots only |
| **Filestore** | No | Yes | No (snapshots) |
| **Ceph / Rook** | No | Yes | Yes |
| **S3 / GCS** | No | Yes | Yes (built-in) |

**For multi-AZ, multi-replica storage:** EFS, Filestore, or Ceph.
**For cross-region:** replication or object storage (S3, GCS).

## The HA observability layer

You can't be HA if you can't see what's happening.

- **Multi-cluster observability** — central Prometheus / Grafana for all clusters
- **Health endpoints at every level** — app, Service, Ingress, LB
- **Alerting on symptoms** — error rate, latency, not just node CPU
- **Synthetic monitoring** — periodically test the full path from outside
- **Real user monitoring (RUM)** — see what users see

## Common HA anti-patterns

- **Single AZ for "production."** Even if you have multiple clusters, one AZ is still a SPOF.
- **No runbooks for the HA failures.** "We have HA" is meaningless if no one knows how to use it.
- **PDBs with `minAvailable: 100%`.** Locks the system during drain.
- **Topology spread with `DoNotSchedule` and `maxSkew: 0`.** Impossible constraints.
- **Single ingress controller replica.** A SPOF.
- **Default ServiceAccount with cluster-admin in some namespace.** Most security incidents start with over-permissioned SAs.
- **No tested failover.** "DR works" until you try it.

## HA in managed vs self-managed

| Aspect | Managed (EKS/GKE/AKS) | Self-managed (kubeadm) |
|--------|----------------------|-------------------------|
| Control plane | Managed by cloud | You manage (3+ nodes) |
| etcd | Managed | You manage (3+ nodes) |
| Node upgrades | Partial (managed node groups) | You manage |
| Add-ons | You manage | You manage |
| Networking | Cloud-integrated | You configure |

**The 80/20:** managed control plane handles most HA. You handle data plane (nodes, add-ons, workloads).

## The HA project plan

A 90-day plan to get to production-grade HA:

**Days 1-30: foundations**
- Multiple replicas per workload (anti-affinity, topology spread)
- PodDisruptionBudgets on critical services
- Liveness, readiness, startup probes on every workload
- Graceful shutdown (preStop, terminationGracePeriod)

**Days 31-60: infrastructure HA**
- Multi-AZ deployment (3 AZs)
- 3+ control plane nodes (or use managed)
- 3+ etcd nodes (or use managed)
- Ingress controller with 2+ replicas across zones
- Replicated storage (EFS, Ceph, etc.)

**Days 61-90: operations HA**
- Documented runbooks
- Tested failover (node, zone)
- Monitoring and alerting
- Cross-trained on-call
- Game day exercise

After 90 days: you have a cluster that survives most failures.

## See also

* [[Kubernetes/guides/non-functional/auto-scaling|auto-scaling]] — HPA for replicas
* [[Kubernetes/guides/non-functional/chaos-engineering|chaos-engineering]] — testing HA
* [[Kubernetes/guides/non-functional/disaster-recovery|disaster-recovery]] — beyond HA, full failover
* [[Kubernetes/guides/non-functional/backup-restore|backup-restore]] — data protection
* [[Kubernetes/guides/troubleshooting/node-not-ready|node-not-ready]] — when nodes fail
