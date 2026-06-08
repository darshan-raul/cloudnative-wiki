# Services

*"https://kubernetes.io/docs/concepts/services-networking/service/"*

A Service is a **stable virtual IP + DNS name** that fronts a dynamic set of Pods. Pods come and go, their IPs change, but a Service IP stays put. It's the foundational object in L04 — every other networking primitive (Ingress, Gateway, NetworkPolicy) is built on top of the Service abstraction.

### Table of Contents

1. [The Problem Services Solve](#1-the-problem-services-solve)
2. [The Four Service Types](#2-the-four-service-types)
3. [How a Service Gets Its IP — The kube-proxy Pipeline](#3-how-a-service-gets-its-ip--the-kube-proxy-pipeline)
4. [Selectors, Endpoints, and EndpointSlices](#4-selectors-endpoints-and-endpointslices)
5. [Headless Services](#5-headless-services)
6. [Multi-Port Services](#6-multi-port-services)
7. [Session Affinity and Traffic Policies](#7-session-affinity-and-traffic-policies)
8. [External Traffic and the NodePort / LoadBalancer Spectrum](#8-external-traffic-and-the-nodeport--loadbalancer-spectrum)
9. [publishNotReadyAddresses and the "ready" Boundary](#9-publishnotreadyaddresses-and-the-ready-boundary)
10. [Cross-Namespace and External Services](#10-cross-namespace-and-external-services)
11. [Service Mesh and "Do I Still Need a Service?"](#11-service-mesh-and-do-i-still-need-a-service)
12. [Gotchas and Common Mistakes](#12-gotchas-and-common-mistakes)
13. [Operations and Debugging](#13-operations-and-debugging)
14. [When to Use What — Decision Tree](#14-when-to-use-what--decision-tree)

---

## 1. The Problem Services Solve

Pod IPs are **fundamentally unstable**. When a Pod is rescheduled, it gets a new IP. The IP isn't tied to the workload — it's tied to the lifecycle of the Pod object.

Three things break if you try to talk to Pods by IP:

* **Rescheduling** — a node dies, Pods get evicted, new Pods get new IPs.
* **Scaling** — a Deployment with 5 replicas has 5 IPs. Which one does the client hit?
* **Rolling updates** — old Pods are killed, new Pods are created. The set of IPs is constantly shifting.

A Service solves this with **a stable virtual IP** (the ClusterIP) backed by a **dynamic set of backend Pods**. The kube-proxy on every node watches Services and Programs the data plane (iptables / IPVS / eBPF) so that traffic sent to the ClusterIP gets DNAT'd to a real backend Pod IP.

```
Client (Pod A)              kube-proxy on node 1              kube-proxy on node 2
       │                            │                                │
       │  GET 10.96.0.42:80         │                                │
       │ ──────────────────────►    │                                │
       │                            │  "10.96.0.42:80 is my Service, │
       │                            │   backends are 10.244.1.5,      │
       │                            │   10.244.2.7, 10.244.3.9"       │
       │                            │                                │
       │                            │  pick one (round-robin /       │
       │                            │  random) → 10.244.2.7           │
       │                            │                                │
       │  ← DNAT: src=10.244.1.5    │                                │
       │     dst=10.244.2.7:80       │                                │
       │                            │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ►│
       │                            │         (CNI delivers)          │
       │                            │                                ▼
       │                            │                          Pod B (10.244.2.7)
```

The client doesn't know about backend Pods. It talks to a stable IP, and kube-proxy handles the rest.

## 2. The Four Service Types

| Type | ClusterIP | External exposure | Typical use case |
|---|---|---|---|
| `ClusterIP` | Yes (auto-assigned) | None — internal only | Pod-to-pod, app-to-DB within the cluster |
| `NodePort` | Yes | `<NodeIP>:<NodePort>` (30000-32767 default) | Dev, on-prem, when you don't have a load balancer |
| `LoadBalancer` | Yes | Cloud LB (NLB / ELB / GLB) | Production external traffic on a cloud |
| `ExternalName` | None (no selector) | CNAME alias to external DNS | Migration to a service living outside the cluster |

There's also a 5th: **`Headless Service`** (`clusterIP: None`). It's not a "type" — it's a ClusterIP Service with `clusterIP: None`. It returns A records for each backing Pod, not a single virtual IP. Covered in section 5.

### 2.1 ClusterIP (default)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: prod
spec:
  type: ClusterIP    # default, can be omitted
  selector:
    app: backend
  ports:
  - name: http
    port: 80             # Service port
    targetPort: 8080     # container port on the Pod
    protocol: TCP
```

Reachable from within the cluster at `backend.prod.svc.cluster.local:80`. From inside the same namespace: just `backend`. From a different namespace: `backend.prod` or the full FQDN.

The `selector` is what binds the Service to a dynamic set of Pods. Every Pod with `app=backend` is a backend. As Pods come and go, the set updates.

### 2.2 NodePort

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  type: NodePort
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 8080
    nodePort: 30080     # optional, 30000-32767 by default
```

Every node listens on port 30080. From outside: `http://<any-node-ip>:30080`. The Service is **also** a ClusterIP — the NodePort is layered on top.

`NodePort` is useful for:

* **On-prem** — when there's no cloud LB, but you have a stable set of node IPs behind a hardware LB.
* **Dev / bare-metal** — kind, k3d, minikube with `minikube tunnel`.
* **SSH-style** — sometimes you want to expose a port that's not HTTP (e.g. a database) and there's no Ingress controller handy.

**Cost:** every node is open on the port. Security groups / firewall rules must allow it.

### 2.3 LoadBalancer

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
    service.beta.kubernetes.io/aws-load-balancer-scheme: internal
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
  - port: 443
    targetPort: 8080
    protocol: TCP
```

Provisions a **cloud load balancer** (NLB on AWS by default, internal-NLB with the `internal` annotation). The LB has the cluster's nodes as targets and forwards to the NodePort.

Cloud-specific annotations shape behavior:

* AWS: `aws-load-balancer-type` (nlb / alb), `aws-load-balancer-scheme` (internal / internet-facing), `aws-load-balancer-cross-zone-load-balancing-enabled`
* GCP: `cloud.google.com/neg` (Network Endpoint Groups)
* Azure: `service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path`

**Cost:** one LB per Service. For 30 services, that's 30 LBs. Most teams use **Ingress** (one LB, many Services) for HTTP, and LoadBalancer Service only for raw TCP/UDP (e.g. Postgres).

### 2.4 ExternalName

```yaml
apiVersion: v1
kind: Service
metadata:
  name: legacy-api
spec:
  type: ExternalName
  externalName: api.legacy.example.com
```

No selector, no ports. Just a **CNAME** — DNS queries for `legacy-api` (or its FQDN) return a CNAME pointing at `api.legacy.example.com`.

Useful for:

* **Migration** — moving a service out of the cluster without changing client code.
* **Aliasing to a managed service** — pointing to an RDS endpoint, a third-party API, etc.

**Gotcha:** ExternalName Services can't be backed by Endpoints. There's no backend. The CNAME is resolved by the resolver, and the resulting IP is whatever the external name points to.

## 3. How a Service Gets Its IP — The kube-proxy Pipeline

The Service's ClusterIP comes from the **cluster's Service CIDR** (default `10.96.0.0/16` on kubeadm, set by `--service-cluster-ip-range` on the apiserver). The apiserver allocates an IP from this range when the Service is created.

Once allocated:

1. **apiserver** creates the Service object with `.spec.clusterIP` set.
2. **Endpoints / EndpointSlices controller** (in kube-controller-manager) watches the Service and resolves the `selector` to a list of `<ip:port>` pairs.
3. **kube-proxy** on every node watches Services and Endpoints/EndpointSlices. It programs the local data plane:
   * **iptables mode** (default): installs iptables chains that DNAT ClusterIP traffic.
   * **IPVS mode**: creates an IPVS virtual server with hash-table lookup.
   * **eBPF mode** (Cilium): programs eBPF maps and a TC program for the DNAT.

The choice of mode is set by the kube-proxy ConfigMap (or the `--proxy-mode` flag). Most managed clusters use iptables by default. Larger clusters move to IPVS. Cilium replaces kube-proxy entirely with eBPF.

**Deep dive on IPVS:** see `L09-advanced/08-ipvs.md`.

The key invariant: **the ClusterIP is not a routable IP**. It's a marker that kube-proxy looks for. Packets to the ClusterIP hit the node's network stack, kube-proxy (or its data plane) catches them, and DNATs them to a Pod IP. From outside the node, the ClusterIP is unreachable.

### 3.1 iptables rules — what kube-proxy actually programs

For a Service with 3 backends, kube-proxy installs rules like:

```
-A KUBE-SERVICES -d 10.96.0.42/32 -p tcp --dport 80 -j KUBE-SVC-XXX
-A KUBE-SVC-XXX -m statistic --mode random --prob 0.333 -j KUBE-SEP-AAA   # backend 1
-A KUBE-SVC-XXX -m statistic --mode random --prob 0.500 -j KUBE-SEP-BBB   # backend 2
-A KUBE-SVC-XXX                              -j KUBE-SEP-CCC            # backend 3 (fallthrough)
```

The first matching rule wins. The probabilities are calculated so that each backend gets an equal share.

This works but doesn't scale linearly — every Service + every endpoint adds rules. At 10,000 Services, the iptables chains are huge and every packet does a long linear scan. **IPVS avoids this with O(1) hash-table lookup.**

## 4. Selectors, Endpoints, and EndpointSlices

### 4.1 The selector

```yaml
spec:
  selector:
    app: backend
    tier: api
```

A `matchLabels`-style selector. Every Pod with both labels becomes a backend.

* **No selector = no Endpoints** — the Service has no backends. Common with ExternalName and `headless` Services that target manual Endpoints.
* **Empty selector (`{}`)** — matches nothing. Backends must be added manually via an Endpoints object.

### 4.2 Endpoints (legacy)

For a Service `backend` in namespace `prod`, kube-controller-manager creates an `Endpoints` object `backend` in `prod`:

```
endpoints:
  - addresses:
    - ip: 10.244.1.5
      targetRef: { kind: Pod, name: backend-abc, namespace: prod }
    - ip: 10.244.2.7
      targetRef: { kind: Pod, name: backend-def, namespace: prod }
    ports:
    - port: 8080
      protocol: TCP
```

The Endpoints object is what kube-proxy consumes to program the data plane.

**Limitation:** one Endpoints object per Service. For a Service with 10,000 backends, that's a single object that can be hundreds of KB. Updates are atomic — every change rewrites the whole object. This was a real bottleneck for large Services.

### 4.3 EndpointSlices (modern, default since 1.21)

The same data, **sharded**. Instead of one Endpoints object, a Service has many EndpointSlices (default: 100 endpoints per slice).

```yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: backend-abc
  namespace: prod
  labels:
    kubernetes.io/service-name: backend
addressType: IPv4
endpoints:
- addresses: [10.244.1.5]
  conditions:
    ready: true
  targetRef: { kind: Pod, name: backend-abc, namespace: prod }
ports:
- port: 8080
  protocol: TCP
```

Benefits:

* **Smaller updates** — adding one backend updates one slice, not the whole Endpoints object.
* **Topology fields** — `zone`, `nodeName` for topology-aware routing.
* **Per-endpoint conditions** — `ready`, `serving`, `terminating` are tracked per endpoint, not per Service.

**Deep dive:** see `L04-services-networking/08-endpoint-slices.md`.

### 4.4 Manual Endpoints (no selector)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: external-db
spec:
  # no selector
  ports:
  - port: 5432
---
apiVersion: v1
kind: Endpoints
metadata:
  name: external-db
subsets:
- addresses:
  - ip: 10.20.30.40     # IP of an external DB
  ports:
  - port: 5432
```

This is the **pre-EndpointSlices way** to point a Service at external IPs. With EndpointSlices, you can do the same — create a Service with no selector and write the EndpointSlices by hand (or have a controller do it).

## 5. Headless Services

Set `clusterIP: None`. The Service **gets no virtual IP** — DNS returns the Pod IPs directly.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: db
spec:
  clusterIP: None
  selector:
    app: db
  ports:
  - port: 5432
```

DNS query for `db.prod.svc.cluster.local` returns **A records for each backing Pod**, not a single ClusterIP. The client picks which Pod to talk to (or uses the records in round-robin order).

### 5.1 When to use headless

* **StatefulSets** — you want to discover each Pod by stable name (`mongo-0`, `mongo-1`, ...). See `L03-workloads/04-statefulsets.md`.
* **Client-side load balancing** — the client (e.g. gRPC, Kafka client) does its own load balancing and wants the full set of Pod IPs.
* **Peer-to-peer discovery** — Cassandra, Elasticsearch, Consul, etcd all need direct Pod-to-Pod communication.

### 5.2 Headless + StatefulSet = per-Pod DNS

A StatefulSet with a headless Service and `serviceName: db` gives you:

```
db-0.db.prod.svc.cluster.local  →  10.244.1.5   (Pod 0)
db-1.db.prod.svc.cluster.local  →  10.244.2.7   (Pod 1)
db-2.db.prod.svc.cluster.local  →  10.244.3.9   (Pod 2)
```

This is the **canonical way to address individual replicas** for stateful workloads.

### 5.3 Headless gotchas

* **No ClusterIP** — anything that does a name → IP lookup gets multiple records. Some clients assume a single record and break.
* **No kube-proxy DNAT** — kube-proxy doesn't install iptables rules for headless Services. The traffic goes straight from the client Pod to the Pod IP, which means the **client Pod's network stack must be able to reach the Pod IP directly**. On any well-configured CNI, this works.
* **Service discovery is "stale" until DNS TTL expires** — the client caches the IPs. With Kubernetes DNS, the default TTL is 30s. A Pod that gets recreated may keep being hit until the cache refreshes.
* **`publishNotReadyAddresses: true` is common on headless StatefulSets** — so that clients can find Pods that aren't Ready yet (e.g. for a join operation).

## 6. Multi-Port Services

```yaml
apiVersion: v1
kind: Service
metadata:
  name: app
spec:
  selector:
    app: app
  ports:
  - name: http
    port: 80
    targetPort: 8080
    protocol: TCP
  - name: metrics
    port: 9090
    targetPort: 9090
    protocol: TCP
  - name: grpc
    port: 50051
    targetPort: 50051
    protocol: TCP
```

Each port has a name. **The name is required** when you have more than one port (this was added in v1.0 to disambiguate; some legacy Services with single ports still work without names).

You can also mix protocols:

```yaml
ports:
- name: http
  port: 80
  targetPort: 8080
  protocol: TCP
- name: dns-udp
  port: 53
  targetPort: 53
  protocol: UDP
```

**Note:** ClusterIP Services are **per-protocol** — TCP traffic and UDP traffic don't share a Service. A Service can't have both a TCP port 80 and a UDP port 80.

## 7. Session Affinity and Traffic Policies

### 7.1 Session affinity

By default, every connection is a fresh load balancing decision. Set `sessionAffinity: ClientIP` to make it sticky:

```yaml
spec:
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 10800   # 3 hours, max value
```

With this, all connections from the same client IP go to the same backend. Useful for:

* Apps with in-memory state (legacy session storage)
* WebSocket connections
* Long-lived TCP connections where you don't want reconnect overhead

**Limitations:**

* The "client IP" is the **source IP as seen by the Service**. With `externalTrafficPolicy: Cluster` (default for NodePort / LoadBalancer), the source is the **node IP**, not the original client. So all clients hitting a given node go to the same backend, which is a worse affinity than you'd want. Use `externalTrafficPolicy: Local` to preserve the original client IP (see 7.2).
* The default timeout is 10800s (3 hours), the max. There's no way to make it shorter per Service.
* Headless Services have **no session affinity** — they're not kube-proxy-backed.

### 7.2 externalTrafficPolicy

For NodePort and LoadBalancer Services, the source IP of incoming traffic matters. Two modes:

**`Cluster` (default):** kube-proxy on any node can DNAT the traffic to any backend Pod. Source IP is the **node IP**, not the client IP. Two consequences:

* **Source IP is lost** — the backend Pod sees the node as the client. Logging, geo-IP, rate-limiting all see the node's IP.
* **Asymmetric routing** — packets come in via node A (because that's where the LB sent them), get DNAT'd to a Pod on node B, and the response goes back through node B. Sometimes this works, sometimes the LB gets confused.

**`Local`:** only kube-proxy on a node that **runs a backend Pod** can accept the traffic. The LB is configured to send traffic only to nodes that run backends. Source IP is preserved (the original client IP), but the LB health check is more complex (each node reports health only if it has a local backend).

```yaml
spec:
  type: LoadBalancer
  externalTrafficPolicy: Local
```

**`Local` is almost always what you want for production**, despite the LB complexity. Source IP preservation is worth it. The `Cluster` mode is the legacy default because it was simpler; modern LBs handle `Local` fine.

### 7.3 internalTrafficPolicy

For ClusterIP Services, controls whether kube-proxy on a node can DNAT to a Pod on a different node:

* `Cluster` (default) — any node, any Pod.
* `Local` — only Pods on the same node. Useful for keeping traffic local for cost / latency reasons.

```yaml
spec:
  internalTrafficPolicy: Local
```

This is the "ClusterIP-local" pattern — used to keep pod-to-pod traffic on the same node when you have a lot of east-west traffic.

### 7.4 Topology-aware routing

Newer k8s (1.27+) supports **topology-aware routing** via EndpointSlices:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: app
  annotations:
    service.kubernetes.io/topology-mode: Auto
spec:
  # ... normal Service spec
```

`Auto` mode tells kube-proxy to prefer endpoints in the same zone as the source. `Disabled` falls back to the old random behavior. This requires EndpointSlices with topology hints to be populated — the EndpointSlice controller does this based on `trafficDistribution`.

## 8. External Traffic and the NodePort / LoadBalancer Spectrum

```
                    External Client
                          │
                          ▼
                  Cloud Load Balancer
                  (provisioned by Service.beta.kubernetes.io/...)
                          │
              ┌───────────┼───────────┐
              ▼           ▼           ▼
           Node 1      Node 2      Node 3   (all on NodePort 30080)
              │           │           │
              ▼           ▼           ▼
            kube-proxy  kube-proxy  kube-proxy
              │           │           │
              ▼           ▼           ▼
            Pod A       Pod B       Pod C  (DNAT'd)
```

### 8.1 NodePort port range

Default: 30000-32767. Configurable via `--service-node-port-range` on the apiserver. Some teams narrow this to 30000-30999 for security (smaller attack surface, easier firewall rules).

### 8.2 LoadBalancer provisioning time

Cloud LBs take 30s-2min to provision. The Service's `status.loadBalancer.ingress` field shows the LB's IP/DNS once ready.

```bash
kubectl get svc web -o jsonpath='{.status.loadBalancer.ingress}'
# [{"hostname": "abc123.elb.us-east-1.amazonaws.com"}]
```

### 8.3 The cost of one-LB-per-Service

A naive setup with 30 microservices and 30 LoadBalancer Services = 30 LBs. At AWS NLB pricing, that's $20-30/day just for the LBs. The fix is **Ingress** (L7, one LB, many Services) for HTTP, and NodePort / shared LoadBalancer for everything else.

For non-HTTP traffic that genuinely needs a LB, consider:

* **A single shared NLB** that fans out to NodePort Services behind it.
* **Gateway API** (the future) — same idea as Ingress but for non-HTTP too.

## 9. publishNotReadyAddresses and the "ready" Boundary

By default, a Pod is added to a Service's Endpoints **only when its readiness probe passes** (or it has no readiness probe, which counts as "always ready").

A Pod that is **not ready** (readiness probe failing, still starting up) is **excluded from Endpoints**. Traffic is not sent to it. This is the "grace period" mechanism.

```yaml
spec:
  publishNotReadyAddresses: true
```

With this set, the Pod is added to Endpoints **as soon as it exists**, regardless of readiness. Used for:

* **StatefulSet joins** — a new Pod needs to be reachable for the cluster join handshake, even if its readiness probe hasn't passed yet.
* **Headless services for stateful apps** — the new replica needs to accept bootstrap traffic.

**Don't set this on stateless services** — it routes traffic to a Pod that isn't ready, which causes user-facing failures.

## 10. Cross-Namespace and External Services

### 10.1 Cross-namespace

A Service in namespace `prod` is normally reachable as `backend.prod.svc.cluster.local`. To reach it from another namespace, use the FQDN or `<name>.<namespace>`:

```
backend.prod                  # short form (must be from inside a Pod with the right search path)
backend.prod.svc              # namespace + service
backend.prod.svc.cluster.local  # full FQDN
```

**Can a Service in `ns-a` route to a Pod in `ns-b`?** Yes, by setting the Service's selector to match labels on Pods in `ns-b`. The Service is namespaced, but the Endpoints it points at can be in any namespace.

**Should it?** Usually no. Cross-namespace Service selectors are a code smell — they couple namespaces that should be isolated. If you need to share, use:

* A separate Service in `ns-b` (the right way)
* A `kubernetes.io/metadata.name` selector with the target namespace
- **Never** do this with a `prod` → `dev` selector; it's a common path for privilege escalation.

### 10.2 External services

Three patterns for pointing a Service at an external system:

**(a) ExternalName:** simplest, just a CNAME.

```yaml
spec:
  type: ExternalName
  externalName: rds.example.com
```

**(b) Service without selector + manual Endpoints:**

```yaml
spec:
  ports:
  - port: 5432
---
# Endpoints object
subsets:
- addresses:
  - ip: 10.20.30.40
  ports:
  - port: 5432
```

**(c) EndpointSlice (modern):**

```yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: external-db-1
  labels:
    kubernetes.io/service-name: external-db
addressType: IPv4
endpoints:
- addresses: [10.20.30.40]
ports:
- port: 5432
```

For **(b)** and **(c)**, the Service behaves like a ClusterIP — it gets a ClusterIP, kube-proxy DNATs traffic to the external IP. The client doesn't know the backend is external.

## 11. Service Mesh and "Do I Still Need a Service?"

A service mesh (Istio, Linkerd, Cilium) doesn't replace Services. It adds **sidecar proxies** that handle mTLS, retries, traffic splitting, L7 routing.

Even with a mesh:

* **You still create a Service** for every workload. The mesh uses the Service for discovery.
* **The Service's ClusterIP is still the entry point** — the sidecar intercepts it on the way through.
* **Headless Services are still needed** for stateful workloads (Envoy uses the Pod IPs for the load balancing).

A common mistake: thinking the mesh is "instead of" Services. The mesh is "in addition to" Services. They're orthogonal.

**When you actually need a service mesh:**

* mTLS between services
* Traffic splitting (canary, A/B)
* Retries with circuit breaking
* L7 routing by header
* Distributed tracing woven into the proxy

If you don't need those, you don't need a mesh. A plain ClusterIP is fine.

## 12. Gotchas and Common Mistakes

### 12.1 The 30+ common mistakes

1. **Forgetting the `port` and `targetPort` distinction.** They're different numbers — the Service port is what clients connect to, the targetPort is what the Pod listens on. `port: 80, targetPort: 8080` is normal.

2. **Putting ClusterIP in external DNS.** The ClusterIP is **not routable from outside the cluster**. Don't put `10.96.0.42` in a public DNS record. It's a marker, not a destination.

3. **Empty selector on a regular Service.** A Service with no selector and no manual Endpoints has **no backends**. Traffic to the ClusterIP gets blackholed.

4. **Session affinity on a LoadBalancer with `externalTrafficPolicy: Cluster`.** All clients hitting the same node go to the same backend. The affinity is by node IP, not client IP. Use `Local` to preserve client IP.

5. **The `name` field on a multi-port Service is required.** Skipping it is silently allowed for single-port Services but breaks multi-port.

6. **Same port, different protocol.** A Service can't have TCP:80 and UDP:80. They're separate Services (or different ports).

7. **Headless Service with regular selector.** `clusterIP: None` + selector = fine, but you don't get kube-proxy DNAT. The client must be able to reach Pod IPs directly. Usually fine, but not always (e.g. some NetworkPolicy setups).

8. **Cross-namespace Service selectors.** Coupling namespaces via selectors is a security smell. Don't do it for `prod → dev` or `prod → kube-system`.

9. **`publishNotReadyAddresses: true` on a stateless Service.** Routes traffic to unready Pods. Causes 502s. Use only for stateful workloads that need the bootstrap path.

10. **`sessionAffinity: ClientIP` timeout is the wrong value.** The default (10800) is the max. You can't go higher. Going lower is fine, but you have to set it explicitly.

11. **The `nodePort` field is admin-only on a node-port range.** You can put anything in `spec.ports[].nodePort`, but if it's outside the apiserver's `--service-node-port-range`, the apiserver rejects it.

12. **A Service with `type: LoadBalancer` on a non-cloud cluster.** The Service is created, but the cloud-controller-manager doesn't exist to provision the LB. `status.loadBalancer.ingress` is empty forever. You need a cloud integration (or MetalLB for on-prem).

13. **The Service and Pod are in different namespaces.** A Service in `ns-a` with `selector: { app: x }` only matches Pods **in `ns-a`** with `app=x`. Pods in `ns-b` with the same labels are ignored.

14. **Renaming the Service doesn't update DNS clients.** The Service's DNS name is stable as long as the Service exists. But if you delete and recreate, the new Service might have a different ClusterIP (though usually not — the apiserver reuses IPs).

15. **`--service-cluster-ip-range` overlaps with `--pod-network-cidr`.** If your Service CIDR and Pod CIDR overlap, you get weird issues — a Pod IP could be confused with a Service IP. Don't overlap them.

16. **Readiness probe on the wrong port.** If `readinessProbe.httpGet.port: 8080` but the container listens on 80, every Pod is "not ready" forever. The Service has zero backends.

17. **Forgetting `protocol: UDP` for DNS.** A Service exposing CoreDNS on port 53 must be `protocol: UDP`. Default is TCP, which silently works for TCP DNS but breaks UDP.

18. **The `Endpoints` object is still there for backwards compat.** If you have automation that creates Endpoints, it works, but new code should use EndpointSlices.

19. **The Service's `status.loadBalancer.ingress` doesn't update immediately.** Cloud LBs take time. `kubectl get svc` may show `<pending>` for 30s-2min after creation.

20. **The ClusterIP is "stuck" in the cluster IP range after deletion.** The apiserver doesn't immediately reclaim ClusterIPs — they linger in the range for a while. If you're running out of Service IPs, this can be a real issue at scale.

21. **A Service with `selector: {}` matches nothing.** Same as no selector. You need to write the Endpoints manually.

22. **Two Services with the same name in the same namespace.** The apiserver rejects the second. The error is non-obvious if you don't know to look at the namespace.

23. **ExternalName with a CNAME chain.** Some clients don't follow long CNAME chains. Use an A record if your client is finicky.

24. **A Service with `type: LoadBalancer` on AWS + `aws-load-balancer-type: nlb` doesn't preserve source IP by default.** You need to also set `externalTrafficPolicy: Local` and the LB target group settings.

25. **The Service DNS is not resolvable from outside the cluster's network.** The CoreDNS Service IP is only routable inside the cluster. From your laptop, you can't `dig backend.prod.svc.cluster.local` (unless you've set up forwarding).

26. **The default LoadBalancer type on AWS is NLB (network), not ALB (application).** For L7 routing, use Ingress with the AWS Load Balancer Controller.

27. **EndpointSlice label `kubernetes.io/service-name` is required for the slice to be picked up by the Service's controller.** Forgetting it means the slice is orphaned.

28. **Headless Service with `publishNotReadyAddresses: true` and StatefulSet ordering.** The Pod is added to DNS even before it's ready, but the StatefulSet's `podManagementPolicy: OrderedReady` ensures only one Pod is created at a time. Don't switch to `Parallel` without thinking through the join semantics.

29. **Service mesh sidecars and headless Services.** Some meshes don't handle headless services well — they expect a single ClusterIP to intercept. Cilium and Linkerd handle it; Istio needs a `ServiceEntry`.

30. **`sessionAffinity: ClientIP` with hash-based load balancing (IPVS).** IPVS uses source hash by default for session affinity. The hash is stable across connections from the same source. Different from iptables mode (which uses conntrack).

### 12.2 The "my Service is unreachable" checklist

Run these in order:

1. **Are there backends?** `kubectl get endpoints <svc>` — does the `endpoints` list have IPs?
2. **Are the Pods Ready?** `kubectl get pods -l <selector>` — are they `1/1 Running`? Readyz?
3. **Is kube-proxy running?** `kubectl -n kube-system get ds kube-proxy` — are the Pods Running?
4. **NetworkPolicy?** `kubectl get networkpolicy -A` — is something blocking the traffic?
5. **DNS?** `kubectl exec -it <pod> -- nslookup <svc>` — does it resolve?
6. **Direct IP?** `kubectl exec -it <pod> -- curl <cluster-ip>` — does it connect? If yes, DNS is the issue. If no, the data plane is.
7. **Node port?** `curl <node-ip>:<nodeport>` from a node — does it connect? If yes, kube-proxy is fine. If no, the cloud LB is the issue (for LoadBalancer Services).
8. **iptables / IPVS rules?** `iptables-save | grep <cluster-ip>` or `ipvsadm -L | grep <cluster-ip>` — are the rules there?

## 13. Operations and Debugging

### 13.1 Common commands

```bash
# describe
kubectl describe svc backend
# shows endpoints, selector, ports, events

# check endpoints
kubectl get endpoints backend -o yaml
kubectl get endpointslice -l kubernetes.io/service-name=backend

# test from inside the cluster
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- bash
# inside the debug pod:
nslookup backend
curl -v http://backend:80
nc -zv backend 80

# check kube-proxy
kubectl -n kube-system logs -l k8s-app=kube-proxy --tail=100
kubectl -n kube-system get ds kube-proxy

# check the data plane on a node
iptables-save | grep -A 5 "10.96.0.42"
ipvsadm -L -n -t 10.96.0.42:80
```

### 13.2 Debugging flow

```
Service unreachable
       │
       ├── Endpoints empty? ─────── selector mismatch, no Pods match, readiness failing
       │
       ├── Endpoints present, Pods Ready, but unreachable?
       │       │
       │       ├── From same Pod: nslookup works, curl fails ── iptables/IPVS rules issue
       │       ├── From same Pod: nslookup fails ──── CoreDNS issue
       │       └── From outside the cluster: doesn't reach the Service ── externalTrafficPolicy / LB issue
       │
       └── Random / intermittent failures ──── kube-proxy not running, NetworkPolicy blocking, 
                                                 MTU issues, conntrack exhaustion
```

## 14. When to Use What — Decision Tree

```
Need to expose a workload to other Pods?
├── Yes (HTTP, within cluster)         → ClusterIP Service
├── Yes (TCP/UDP, raw, within cluster) → ClusterIP Service with targetPort
├── Yes (specific Pod identity)        → Headless Service (with StatefulSet)
│
Need to expose to the outside world?
├── HTTP / HTTPS, with hostname routing → Ingress (one LB, many Services)
├── HTTP / HTTPS, simple               → LoadBalancer Service (one LB per Service)
├── TCP/UDP, raw                       → LoadBalancer Service (with externalTrafficPolicy: Local)
├── On-prem, no cloud LB                → NodePort + hardware LB
├── Dev / local                         → NodePort, kind, minikube tunnel
│
Need to alias an external service?
└── Just DNS, no traffic                → ExternalName Service
```

## See also

* [[Kubernetes/concepts/L04-services-networking/01-networking|Networking]] — the L04 mental model
* [[Kubernetes/concepts/L04-services-networking/03-dns|DNS]] — how clients find Services
* [[Kubernetes/concepts/L04-services-networking/04-ingress|Ingress]] — L7 routing from outside
* [[Kubernetes/concepts/L04-services-networking/05-network-policy|NetworkPolicy]] — firewall for Pods
* [[Kubernetes/concepts/L04-services-networking/06-cni|CNI]] — the layer below
* [[Kubernetes/concepts/L04-services-networking/08-endpoint-slices|EndpointSlices]] — scalable Endpoints
* [[Kubernetes/concepts/L04-services-networking/07-k8s-networking-deep-dive|Networking Deep Dive]] — packet walkthroughs
* [[Kubernetes/concepts/L09-advanced/08-ipvs|IPVS]] — kube-proxy mode deep-dive
