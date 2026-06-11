---
title: Networking (L04 Overview)
tags:
  - Kubernetes
  - Networking
  - L04
date: 2024-02-10
---

*Sources: [k8s networking docs](https://kubernetes.io/docs/concepts/cluster-administration/networking/), [CNI spec](https://github.com/containernetworking/cni/blob/master/SPEC.md), [kube-proxy doc](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-proxy/)*

This note is the **mental model** for L04 — a frame to hang the deeper notes on. It covers the k8s network model, the four questions you have to answer for any cluster, and the relationship between Services, DNS, Ingress, NetworkPolicy, and the CNI.

## The k8s network model

In its 2014 design, Kubernetes committed to a **simple** network model. Every cluster, regardless of size, must satisfy four rules:

1. **Every Pod gets its own IP address.**
2. **Pods on any node can communicate with all other Pods on any other node without NAT.**
3. **Agents on a node (kubelet, etc.) can communicate with all Pods on that node.**
4. **Pods in the host network can communicate with all other Pods without NAT.** (This is a consequence of 2, but worth being explicit about.)

The model is **deliberately simple**: it doesn't specify IP ranges, CIDR schemes, or any specific implementation. It says: "your cluster network must be flat, no NAT, and routable end-to-end." The implementation is the CNI's job.

A corollary of rule 2: **IP-per-Pod is the unit of identity, not IP-per-container.** A Pod's containers share a network namespace (one IP for the Pod). A Pod's IP is "as stable as the Pod is" — when the Pod is deleted and recreated, it gets a new IP. This is fundamental to how Services and DNS work.

## The four questions

To understand any cluster's networking, ask:

1. **How do Pods get IPs?** (CNI plugin)
2. **How do Pods on different nodes reach each other?** (overlay vs underlay, routing)
3. **How do Services provide stable virtual IPs?** (kube-proxy, iptables / IPVS / eBPF)
4. **How do Pods reach the outside world?** (NAT, SNAT, IP masquerading)

Every note in L04 answers one or more of these.

## The layers

```
┌──────────────────────────────────────────────────────┐
│  Application (Pod)                                  │
│  ┌──────────┐  ┌──────────┐                          │
│  │  app     │  │  sidecar │  ← Pod's network ns     │
│  └────┬─────┘  └────┬─────┘                          │
│       │             │                                │
│       └──────┬──────┘  ← localhost on Pod IP        │
│              │                                       │
│  ──────────── │ ─────────────────────────────        │
│              ▼                                       │
│        eth0 (veth)                                   │
│              │                                       │
│  ════════════ │ ════════════════════════════        │
│              │                                       │
│   veth (host side) ──── bridge / route table        │
│              │                                       │
│         node's network interface                     │
└──────────────────────────────────────────────────────┘
                │
                │   ← the CNI's domain ends here
                │
   ──── node-to-node network (overlay or underlay) ────
                │
   ──── Pod-to-Pod (any node to any node) ────
                │
   ──── kube-proxy on each node programs ────
   ──── iptables / IPVS for Service VIPs ────
                │
   ──── egress SNAT for outbound traffic ────
                │
   ──── ingress (Ingress controller, load balancer) ────
```

## The k8s networking stack, top to bottom

### Layer 7: Ingress / Gateway API

How **external traffic** reaches Services. An Ingress resource is the k8s-native way to say "route requests for `app.example.com` to the `frontend` Service, and `api.example.com` to the `api` Service". An **Ingress controller** (nginx, Traefik, etc.) is the implementation that reads Ingress resources and configures a real reverse proxy.

→ [[Kubernetes/concepts/L04-services-networking/04-ingress|Ingress]]

### Layer 4: Services

A **stable virtual IP** for a set of Pods. Pods come and go, but the Service's ClusterIP stays. `kube-proxy` on every node programs iptables / IPVS / eBPF rules that DNAT traffic from the Service IP to a backend Pod IP.

→ [[Kubernetes/concepts/L04-services-networking/02-services|Services]]

### Layer 3: Pod-to-Pod

The CNI plugin's job. **Pod A on node 1 sends a packet to Pod B on node 2.** This works because:

* The CNI gives Pod A an IP from a known range
* A route on node 1 says "the range that contains Pod B is reachable via node 2"
* A tunnel (overlay) or direct routing (underlay) carries the packet
* The CNI on node 2 has the route back

### Layer 2: Node networking

The node's interface, the bridges, the veth pairs. Each Pod's `eth0` is a **veth pair** — one end in the Pod's network namespace, the other on the host. Packets from the Pod come out the host-side veth, get bridged or routed, and head out the node's network interface.

### The CNI

The plugin that does all of layer 2 and 3 setup. **CNI** stands for Container Network Interface — it's a spec, not a product. Implementations include Calico, Cilium, Flannel, Weave, AWS VPC CNI, Azure CNI, GKE Dataplane V2.

→ [[Kubernetes/concepts/L04-services-networking/06-cni|CNI]]

## How a packet flows

Let's trace `curl http://frontend:80` from a Pod.

1. **Pod A's container** resolves `frontend` via the cluster DNS (CoreDNS) and gets the Service's ClusterIP (say `10.96.0.42`).
2. **Pod A's container** opens a TCP connection to `10.96.0.42:80`.
3. **The kernel** sees `10.96.0.42` matches the Service's iptables rule (programmed by `kube-proxy` on the node).
4. **DNAT happens** — the kernel rewrites the destination to a Pod IP (say `10.244.1.5` — a backend Pod of the Service).
5. **The packet leaves Pod A** via its veth, hits the host's bridge / routing table.
6. **The packet goes out the node's interface** and traverses the node-to-node network.
7. **It arrives at the destination node** (where `10.244.1.5` lives). The CNI on that node delivers it to the Pod's veth.
8. **The destination Pod's container** receives the packet on its `eth0` (which is the other end of the veth).
9. **The container's app** processes the request and sends a response.
10. **The response goes back** through the same path in reverse.

If `kube-proxy` is using **IPVS** instead of iptables, the DNAT happens via an IPVS virtual server, not an iptables rule. Same end result.

If the CNI is using **eBPF** (Cilium), the entire datapath can be in eBPF programs in the kernel, with no iptables rules at all. Faster, but more complex.

## Services, DNS, and Ingress — what each does

* **Service** — stable IP for a dynamic set of Pods. Layer 4 (TCP/UDP). Pod-to-pod.
* **DNS** — resolves Service names to ClusterIPs. Done by CoreDNS.
* **Ingress** — L7 (HTTP) routing from outside the cluster. Done by an Ingress controller.
* **NetworkPolicy** — firewall rules for Pods. Requires a CNI that supports it.

A common mental mistake: thinking an Ingress is "a public Service". It's not. A Service is layer 4. An Ingress is layer 7. An Ingress is for HTTP routing, terminating TLS, name-based virtual hosting. A LoadBalancer Service is for raw TCP/UDP.

## Egress: how a Pod reaches the internet

By default, a Pod can reach the internet. The CNI / kube-proxy handles this via **SNAT** (source NAT): the packet leaves the node with the node's IP as the source, not the Pod's IP. The return packet comes back to the node, which de-SNATs and forwards to the Pod.

This has a few consequences:

* **External services see the node's IP, not the Pod's IP.** For HTTP logs / analytics, this is unhelpful. Some CNIs have a "preserve source IP" mode.
* **A single Pod making many requests shares a SNAT port.** If you have a NodePort Service, the SNAT port can collide. Some clouds have SNAT port exhaustion issues.
* **You can block egress with NetworkPolicy.** A `policyTypes: [Egress]` rule with no `to:` clauses denies all egress.

## kube-proxy: the three modes

Every node runs a `kube-proxy` pod that programs packet forwarding rules. Three modes:

### iptables mode (default)

kube-proxy writes iptables NAT rules for every Service. On a cluster with 5,000 Services, this means hundreds of thousands of iptables rules in the kernel's netfilter pipeline.

**Pros:** Universal, works everywhere, simple.
**Cons:** Linear scan through rules — O(n) where n = number of Services + Pods. Slows down as the cluster grows. Rule updates are atomic but slow (reload whole ruleset).

```bash
# see the iptables rules kube-proxy creates for a Service
iptables -t nat -L KUBE-SERVICES | grep <service-name>
iptables -t nat -L KUBE-NEWPORTS | grep <service-name>
```

### IPVS mode (recommended for large clusters)

kube-proxy uses the Linux kernel's IPVS (IP Virtual Server) subsystem. IPVS is a hash-table-based Layer 4 load balancer — O(1) lookups regardless of how many Services exist.

**Pros:** Scales to thousands of Services without packet-loss slowdown. Supports richer load-balancing algorithms (round-robin, least-conn, source-hash).
**Cons:** Requires the `ip_vs` kernel modules loaded. Slightly more complex to debug.

```bash
# verify IPVS is active
lsmod | grep ip_vs
# see IPVS virtual servers
ipvsadm -L -n
```

To enable IPVS, set the kube-proxy config:

```yaml
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "ipvs"
ipvs:
  scheduler: "least-conn"  # or "round-robin", "sourcehash"
```

### eBPF mode (modern, Cilium/ingkube-native)

kube-proxy is replaced by eBPF programs attached to network interfaces. The kernel itself handles Service NAT — no iptables, no IPVS, just the kernel's fast path.

**Pros:** Near-line-rate performance, per-connection tracking, built-in observability (Cilium).
**Cons:** Requires a CNI that supports it (Cilium, aws-cni with eBPF mode). Kernel version >= 4.19 for most features.

```
┌─────────────────────────────────────────┐
│  Pod sends to ClusterIP                 │
│         ↓                               │
│  eBPF program on veth interface         │
│  (kernel, no userspace routing)          │
│         ↓                               │
│  NAT happens in kernel netfilter        │
│         ↓                               │
│  Packet forwarded to backend Pod IP     │
└─────────────────────────────────────────┘
```

## CNI: what it actually does

The CNI is called by the container runtime (containerd, CRI-O) at two moments: when a Pod is created (ADD) and when it's deleted (DEL). The CNI's job:

1. **Allocate an IP** for the Pod's network namespace from the cluster's Pod CIDR
2. **Create a veth pair** — one end in the Pod, one on the host
3. **Bridge or route** — attach the host-side veth to a bridge or wire it into the routing table
4. **Program routes** — tell the node how to reach the Pod CIDR (via overlay or underlay)
5. **Set up egress** — NAT rules for outbound traffic

The CNI spec is just JSON over stdin/stdout. A CNI plugin is any executable that speaks that protocol.

```json
# CNI ADD call (simplified)
{
  "cniVersion": "1.0.0",
  "name": "k8s-pod-network",
  "netns": "/var/run/netns/...",
  "ifInterfaces": [{"name": "eth0", "sandbox": "..."}],
  "prevResult": {...}
}
```

## CNI implementations compared

| CNI | Overlay/Underlay | NetworkPolicy | Performance | Best for |
|-----|-----------------|---------------|-------------|----------|
| **Calico** | BGP (underlay) or VXLAN (overlay) | Yes (rich) | High (BGP) | On-prem, multi-node, policy-heavy |
| **Cilium** | eBPF-based | Yes (L7) | Highest | Cloud-native, observability-first |
| **Flannel** | VXLAN (overlay) | No | Medium | Simple clusters, quick setup |
| **Weave** | sleeve (overlay) | Yes | Medium | Multi-cloud, simple operational model |
| **AWS VPC CNI** | Underlay (ENI) | Yes (native) | Highest | EKS, AWS-native |
| **Azure CNI** | Overlay/underlay hybrid | Yes | High | AKS |
| **GKE Dataplane V2** | eBPF (GKE-native) | Yes (L7) | Highest | GKE, Google-native |

**The rule:** never use a CNI without NetworkPolicy support in production. Flannel is great for dev/minikube but insufficient for anything with security requirements.

## DNS: how names resolve to IPs

Kubernetes runs **CoreDNS** as the cluster DNS. Every Pod automatically gets DNS config pointing to `kube-dns.kube-system.svc.cluster.local`.

### What CoreDNS resolves

```
# standard Service
web.default.svc.cluster.local → 10.96.0.100

# short name (from within default namespace)
web → 10.96.0.100

# headless Service (no ClusterIP)
web.default.svc.cluster.local → pod1-ip, pod2-ip, pod3-ip
# client picks one (client-side load balancing)

# StatefulSet headless
mysql-0.mysql.default.svc.cluster.local → <pod-ip>
```

### The `ndots` problem

By default, Pods try 5 search domains before giving up on a name. If you query `mysql`, it tries:

```
mysql.default.svc.cluster.local
mysql.svc.cluster.local
mysql.cluster.local
mysql (with ndots=5 → tries external DNS last)
```

For a busy app making many external calls, this adds 4 failed lookups per request. Fix:

```yaml
# in your Pod spec
dnsConfig:
  options:
    - name: ndots
      value: "2"    # only append search domains when name has <2 dots
```

### CoreDNS tuning

```yaml
# ConfigMap for CoreDNS
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
      forward . 8.8.8.8  # upstream resolvers
      cache 30           # cache TTL
      loadbalance        # round-robin A records
    }
```

## Service types: a quick decision guide

```
┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  ClusterIP   │  │  NodePort    │  │ LoadBalancer │  │ ExternalName │
│  (internal)  │  │  (fixed port)│  │  (cloud LB)  │  │  (CNAME)     │
└──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘
```

| Type | External access | Use when |
|------|----------------|---------|
| **ClusterIP** | No | Internal-only services |
| **NodePort** | `<node-ip>:<port>` | Dev, on-prem, simple external access |
| **LoadBalancer** | Cloud LB provisioned | Cloud-hosted k8s (AWS/GCP/Azure) |
| **ExternalName** | CNAME to external name | Migration, aliasing external services |

Headless Services (`clusterIP: None`) give you direct Pod IPs — no load balancing, no ClusterIP. Useful for:

* StatefulSets where clients need to discover individual Pods
* Custom client-side load balancing
* Running your own service discovery

## When the model breaks

The k8s network model assumes a **flat, routable** network between all Pods. This works for:

* Most clouds (overlay networks)
* Most on-prem setups (Calico with BGP)
* Most single-cluster deployments

It gets harder when:

* **Multi-cluster** — Pods in different clusters have non-routable IPs. You need Submariner, Skupper, Cilium ClusterMesh, or a cloud's multi-cluster service mesh.
* **Hybrid cloud** — Pods in on-prem and cloud. Same as above.
* **Strict network isolation** — some compliance regimes (PCI-DSS, certain DoD configurations) require **no flat network** between tenants. Default-deny NetworkPolicy is the standard approach.
* **IPv4 address exhaustion** — a `/16` is 65k Pods, which sounds like a lot until you have a busy cluster. Some clusters use IPv6, dual-stack, or aggressive CIDR design.

## The "Service mesh" question

If you have a lot of microservices, you eventually want:

* mTLS between services
* Retries and circuit breaking
* Distributed tracing
* L7 routing (e.g. route 10% of `/checkout` traffic to v2)

These are **L7 features** that a plain ClusterIP Service doesn't give you. A **service mesh** (Istio, Linkerd, Cilium's service mesh features) is the typical answer: a sidecar proxy in every Pod that handles these features.

Service mesh is a different layer than what's in L04. It's covered separately — see [[Kubernetes/concepts/guides/service-mesh|service-mesh]].

## Real packet walkthrough: Service to Pod

Let's go layer by layer for `curl http://api-svc:8080/api/users` from `client` Pod to `api` Pod:

```
┌─ client pod namespace ──────────────────────────────────┐
│  ┌──────────────┐    eth0 (veth pair)                   │
│  │ curl process │ ──→ 10.244.1.15:random-port          │
│  └──────────────┘                                       │
└────────────────────│────────────────────────────────────┘
                     │ packet: src=10.244.1.15, dst=10.96.0.42
                     ▼
┌─ node-1 (host) ──────────────────────────────────────────┐
│  veth-xxx (host side)                                   │
│        ↓                                                │
│  bridge (cbr0 or similar)                               │
│        ↓                                                │
│  iptables PREROUTING / FORWARD                          │
│        ↓  ← DNAT: 10.96.0.42 → 10.244.2.30            │
│  routing table                                          │
│        ↓  ← dst 10.244.2.30 via node-2                 │
│  eth0 (node-1)                                          │
└────────────────────│────────────────────────────────────┘
                     │ VXLAN or direct route to node-2
                     ▼
┌─ node-2 (host) ──────────────────────────────────────────┐
│  eth0 (node-2)                                          │
│        ↓                                                │
│  routing: 10.244.2.30 → veth-yyy (host side)           │
│        ↓                                                │
│  veth-yyy (host side)                                   │
└────────────────────│────────────────────────────────────┘
                     │ packet: src=10.244.1.15, dst=10.244.2.30
                     ▼
┌─ api pod namespace ─────────────────────────────────────┐
│  veth-yyy (pod side) = eth0                             │
│        ↓                                                │
│  ┌──────────────────────────────┐                       │
│  │ nginx / go process on :8080 │  ← application layer  │
│  └──────────────────────────────┘                       │
└─────────────────────────────────────────────────────────┘
```

Return packet reverses the path, with SNAT applied at node egress.

## Gotchas (cross-cutting, L04)

* **"Why is my Service unreachable?"** — the most common network problem. Check (1) is the Pod `Ready`? (2) are the Endpoints populated? (3) is kube-proxy running on the node? (4) is there a NetworkPolicy blocking it?
* **DNS resolution inside Pods is `ndots:5` by default.** This means lookups for short names try 4 search domains before failing. For external services, this is slow. Set `dnsConfig.options` to lower `ndots`.
* **kube-proxy and CNI are not the same thing.** A node needs both. Forgetting one leaves the cluster non-functional.
* **iptables rules scale linearly with Services and Pods.** A cluster with 10,000 Services and 100,000 Pods can have millions of iptables rules, which slows down the kernel's netfilter. IPVS or eBPF scale better.
* **NetworkPolicy is enforced by the CNI.** If your CNI doesn't support it (e.g. basic Flannel), the policies are no-ops. **Always use Calico, Cilium, or a CNI that supports NetworkPolicy in production.**
* **MTU mismatches break things silently.** An overlay (VXLAN) typically has 50-100 bytes of overhead. If the underlying network has MTU 1500, the overlay's effective MTU is 1400-1450. Mismatched MTUs cause mysterious packet loss and slow connections.
* **Dual-stack IPv4/IPv6 requires both the apiserver and the CNI to support it.** And the nodes need routable IPv6 addresses. Not all clouds do this well.
* **Service ClusterIPs are not routable from outside the cluster.** Even if you can ping them, you can't actually reach them from outside. NodePort / LoadBalancer / Ingress are the only ways in.
* **kube-proxy runs as a DaemonSet** — one pod per node. If it's not running, that node can't route Service traffic.
* **The node's kernel `ip_forward` must be enabled** — the CNI sets this, but double-check if Pod-to-Pod traffic is broken.
* **Pod CIDR allocation is per-node.** The CNI allocates a slice of the Pod CIDR to each node. If a node runs out of its slice, no new Pods can be scheduled there until you adjust CIDR ranges.

## The bigger picture

L04 covers a lot. The hierarchy of decisions:

1. **Pick a CNI.** This shapes everything else — networking model, NetworkPolicy support, performance.
2. **Pick a Service IP range.** The Service's ClusterIP CIDR (default `10.96.0.0/16` on kubeadm). Must not overlap with anything else.
3. **Pick a Pod IP range.** The CIDR that the CNI gives Pods. Must not overlap with anything else.
4. **Set up DNS.** Usually CoreDNS, which comes with kubeadm. Tune `ndots` and forwarders as needed.
5. **Set up Ingress.** Pick a controller. nginx is the most common; Traefik is popular for simplicity.
6. **Set up NetworkPolicy.** Default-deny + allow rules. Use the CNI that supports it.
7. **Test it.** Spin up a Pod, make a Service, hit the Service from another Pod, hit the Ingress from outside.

## The notes in this level

→ [[Kubernetes/concepts/L04-services-networking/02-services|Services]] — the foundational object after a Pod
→ [[Kubernetes/concepts/L04-services-networking/03-dns|DNS]] — how clients find Services
→ [[Kubernetes/concepts/L04-services-networking/04-ingress|Ingress]] — when you need HTTP routing from outside
→ [[Kubernetes/concepts/L04-services-networking/05-network-policy|NetworkPolicy]] — when you start designing multi-tenant or hardened clusters
→ [[Kubernetes/concepts/L04-services-networking/06-cni|CNI]] — understand the layer below all of this
→ [[Kubernetes/concepts/L04-services-networking/08-endpoint-slices|EndpointSlices]] — the scalable version of Endpoints
→ [[Kubernetes/concepts/L04-services-networking/07-k8s-networking-deep-dive|Networking Deep Dive]] — packet-level walkthroughs