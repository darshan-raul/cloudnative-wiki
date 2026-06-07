# High Availability

*"https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/"*

HA in Kubernetes means **no single point of failure** in the control plane and **redundancy for workloads**. The control plane runs on multiple nodes; workloads use PodDisruptionBudgets, replicas, and spread across failure domains.

## Control plane HA

The kube-apiserver is the piece that must not go down. Everything else (scheduler, controller-manager) can lose one instance without breaking workloads — but no apiserver means no API, which means nothing works.

```
                 ┌──────────────────────────────────────┐
                 │          load balancer                │
                 │  (cloud LB or keepalived + haproxy)   │
                 └──────────┬──────────┬───────────────┘
                            │          │
                   ┌────────▼──┐ ┌─────▼──────┐ ┌──────▼─────┐
                   │ kube-     │ │ kube-      │ │ kube-      │
                   │ apiserver │ │ apiserver  │ │ apiserver  │
                   │ (node 1)  │ │ (node 2)   │ │ (node 3)   │
                   └─────┬─────┘ └─────┬──────┘ └──────┬────┘
                         │             │              │
                         ▼             ▼              ▼
                 ┌──────────────────────────────────────────┐
                 │                   etcd                    │
                 │          (3 or 5 node cluster)           │
                 │  ┌─────┐  ┌─────┐  ┌─────┐              │
                 │  │  0  │  │  1  │  │  2  │              │
                 │  └─────┘  └─────┘  └─────┘              │
                 └──────────────────────────────────────────┘
```

### Two HA topologies

**Stacked etcd** (easier, more common):

* etcd runs on the same nodes as the control plane
* Fewer machines, but correlated failures — if a control plane node goes down, you lose both an apiserver and an etcd member
* Suitable for: 3-node clusters, managed k8s (EKS, GKE, AKS)

**External etcd** (more resilient):

* etcd runs on separate nodes from the control plane
* More machines, but independent failure domains
* Suitable for: 5+ node control planes, ultra-high-availability requirements

### What the load balancer does

The LB sits in front of the apiserver instances:

```bash
# what nodes join the cluster
kubeadm join --control-plane \
  --server https://lb.example.com:6443 \
  --certificate-key <key>

# on each apiserver node
# the LB health check:
#   https://<apiserver>:6443/healthz
# If an apiserver fails the health check, the LB stops routing to it
```

The LB must:

* Terminate TLS (or pass it through, but then clients need the certs of all apiservers)
* Do TCP health checks on port 6443
* Distribute traffic to all healthy apiservers
* Support long-lived connections (apiserver watches are long-lived HTTP/2)

In cloud environments, use the cloud's managed LB (AWS NLB, GCP TCP LB, Azure LB). On-prem, use keepalived + haproxy or a hardware load balancer.

### etcd quorum

etcd requires a quorum to work: **majority of members must be available**.

| etcd members | Quorum | Tolerates failures |
|---|---|---|
| 1 | 1 | 0 |
| 3 | 2 | 1 |
| 5 | 3 | 2 |
| 7 | 4 | 3 |

With 3 members, you can lose 1. With 5, you can lose 2. Beyond 5, adding more members makes cluster changes slower without meaningfully improving availability.

**Always use 3 or 5 etcd members.** Never 2 (you can't tolerate any failure with 2 — losing one member leaves you with 1 of 2, which is not a majority).

## Workload HA

HA for workloads means **no single point of failure** at the application layer.

### PodDisruptionBudgets

A PDB limits how many Pods of a given app can be down simultaneously due to voluntary disruption:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: web-pdb }
spec:
  minAvailable: 2       # always keep at least 2 Pods
  # OR
  maxUnavailable: 1     # never have more than 1 Pod down
  selector:
    matchLabels:
      app: web
```

During a `kubectl drain` or a Deployment rollout, the PDB is respected. If `minAvailable: 2` and you have 3 replicas, only 1 Pod is evicted at a time.

### Replicas

The simplest HA: run multiple replicas.

```yaml
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0    # zero downtime
      maxSurge: 1          # one extra during rollout
```

With `maxUnavailable: 0`, the Deployment never drops below 3 Pods. If you lose one, you're still at 3 until a new one starts.

### Multi-zone/node spread

Spread Pods across failure domains so a single zone or node failure doesn't take down the app.

```yaml
spec:
  topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: web
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: web
```

This says: spread across zones (maxSkew: 1 means at most 1 Pod more in any zone than the minimum), and also across nodes. If a zone goes down, only Pods in that zone are affected.

### Anti-affinity

Keep Pods away from each other (or co-locate them):

```yaml
spec:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app: web
          topologyKey: kubernetes.io/hostname
```

This prefers (but doesn't require — `preferred`) scheduling Pods on different nodes. If you want a hard requirement, use `requiredDuringSchedulingIgnoredDuringExecution`.

## Node HA

### Node lifecycle management

If a node is unresponsive:

* The **node controller** marks it `NotReady` after `node-monitor-grace-period` (default 40s)
* Pods on that node are evicted after `pod-eviction-timeout` (default 5m)
* New Pods are not scheduled to it

The window between node failure and Pods being rescheduled is **voluntary disruption** — the app is degraded but still running on the dead node until the PDB allows eviction.

### cordon / drain / delete

```bash
# cordon: stop scheduling new Pods to this node
kubectl cordon node-3

# drain: evict all Pods (respecting PDBs), then mark as unschedulable
kubectl drain node-3 --ignore-daemonsets --delete-emptydir-data

# delete: remove the node object from the API
# (the node is already gone, just clean up)
kubectl delete node node-3
```

For routine maintenance (kernel update, kubelet restart), `cordon` + `drain` is the right sequence. For a dead node, just delete it.

### Taints and tolerations for critical nodes

```bash
# taint a node so only critical pods schedule there
kubectl taint node node-3 dedicated=true:NoSchedule

# pods must have the matching toleration to be scheduled
kubectl label namespace kube-system pod-role=critical
```

The `node.kubernetes.io/not-ready:NoExecute` taint is automatically applied to nodes that are `NotReady`. Pods without a matching toleration are evicted after the tolerationSeconds (default 300s).

## Application-level HA

The cluster can keep your Pods running, but your app needs to handle:

* **Graceful shutdown**: catch SIGTERM, stop accepting new connections, finish in-flight requests, exit within `terminationGracePeriodSeconds`
* **Connection draining**: if you're behind a Service, the Service stops routing to a Pod that's terminating — but existing connections need to drain
* **Readiness probing**: don't receive traffic until you're ready (otherwise you get 503s during startup)
* **Idempotency**: retries are safe (GET is idempotent; POST might not be — design for it)
* **Leader election**: if you have a single active process (not a replicated app), use leader election so another instance takes over when the leader dies

## Managed k8s HA

If you're on EKS, GKE, or AKS, the control plane is managed for you:

| | EKS | GKE | AKS |
|---|---|---|---|
| Control plane | Managed (multi-AZ) | Managed (multi-AZ) | Managed (single-region) |
| etcd | Managed | Managed | Managed |
| API server | Managed | Managed | Managed |
| Node pools | Your responsibility | Your responsibility | Your responsibility |
| Add-ons | EKS addons | GKE addons | Azure addons |

On managed k8s, the main HA work is:

* **Multi-AZ node pools** (spread nodes across AZs)
* **PodDisruptionBudgets** on every production app
* **topologySpreadConstraints** for zone-level resilience
* **Cluster autoscaler** so nodes scale with demand
* **HPA** so Pods scale with demand

## What "five 9s" means in practice

99.999% uptime = ~5 minutes of downtime per year. For most applications, this is unrealistic. The realistic targets:

| Target | Downtime/year | What it requires |
|---|---|---|
| 99% | 3.7 days | Basic HA, no single points of failure |
| 99.9% | 8.7 hours | Multi-AZ, PDBs, HPA, decent monitoring |
| 99.99% | 52 minutes | All of the above + runbooks, alerts, fast recovery |
| 99.999% | 5 minutes | Everything + automated failover, chaos engineering, very fast MTTR |

For infrastructure like k8s control planes, 99.99% is achievable. For applications, 99.9% is the typical target.

## Common HA mistakes

* **No PodDisruptionBudgets** — a `kubectl drain` takes down all Pods simultaneously
* **Single-replica Deployments** — one node failure takes down the app
* **All Pods in one zone** — a zone outage takes down the app
* **`maxUnavailable: 1` on a Deployment with 1 replica** — this means 0 Pods during rollout
* **No readiness probe** — traffic is sent to Pods that aren't ready, causing 503s
* **`terminationGracePeriodSeconds: 30`** with a startup that takes 60s — the Pod is killed before it starts
* **Not testing chaos** — HA setup that hasn't been tested is not HA. Run chaos experiments (kill nodes, kill Pods, kill API servers).
* **etcd on 2 nodes** — you can't tolerate any failure with 2 etcd members. Use 1, 3, or 5.

## See also

* [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget|PodDisruptionBudget]] — protecting voluntary disruptions
* [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits|Resource Requests & Limits]] — for proper scheduling
* [[Kubernetes/concepts/L03-workloads/03-deployments|Deployments]] — rolling updates
* [[Kubernetes/concepts/L03-workloads/04-statefulsets|StatefulSets]] — for stateful HA