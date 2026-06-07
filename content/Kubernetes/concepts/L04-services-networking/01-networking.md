# Networking (L04 Overview)

*"https://kubernetes.io/docs/concepts/cluster-administration/networking/"*

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
│  Application (Pod)                                    │
│  ┌──────────┐  ┌──────────┐                          │
│  │  app     │  │  sidecar │  ← Pod's network ns      │
│  └────┬─────┘  └────┬─────┘                          │
│       │             │                                 │
│       └──────┬──────┘  ← localhost on Pod IP         │
│              │                                        │
│  ──────────── │ ─────────────────────────────         │
│              ▼                                        │
│        eth0 (veth)                                    │
│              │                                        │
│  ════════════ │ ════════════════════════════         │
│              │                                        │
│   veth (host side) ──── bridge / route table          │
│              │                                        │
│         node's network interface                      │
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

## The "Service mesh" question

If you have a lot of microservices, you eventually want:

* mTLS between services
* Retries and circuit breaking
* Distributed tracing
* L7 routing (e.g. route 10% of `/checkout` traffic to v2)

These are **L7 features** that a plain ClusterIP Service doesn't give you. A **service mesh** (Istio, Linkerd, Cilium's service mesh features) is the typical answer: a sidecar proxy in every Pod that handles these features.

Service mesh is a different layer than what's in L04. It's covered separately — see [[Kubernetes/concepts/guides/service-mesh|service-mesh]].

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

## Gotchas (cross-cutting, L04)

* **"Why is my Service unreachable?"** — the most common network problem. Check (1) is the Pod `Ready`? (2) are the Endpoints populated? (3) is kube-proxy running on the node? (4) is there a NetworkPolicy blocking it?
* **DNS resolution inside Pods is `ndots:5` by default.** This means lookups for short names try 4 search domains before failing. For external services, this is slow. Set `dnsConfig.options` to lower `ndots`.
* **kube-proxy and CNI are not the same thing.** A node needs both. Forgetting one leaves the cluster non-functional.
* **iptables rules scale linearly with Services and Pods.** A cluster with 10,000 Services and 100,000 Pods can have millions of iptables rules, which slows down the kernel's netfilter. IPVS or eBPF scale better.
* **NetworkPolicy is enforced by the CNI.** If your CNI doesn't support it (e.g. basic Flannel), the policies are no-ops. **Always use Calico, Cilium, or a CNI that supports NetworkPolicy in production.**
* **MTU mismatches break things silently.** An overlay (VXLAN) typically has 50-100 bytes of overhead. If the underlying network has MTU 1500, the overlay's effective MTU is 1400-1450. Mismatched MTUs cause mysterious packet loss and slow connections.
* **Dual-stack IPv4/IPv6 requires both the apiserver and the CNI to support it.** And the nodes need routable IPv6 addresses. Not all clouds do this well.
* **Service ClusterIPs are not routable from outside the cluster.** Even if you can ping them, you can't actually reach them from outside. NodePort / LoadBalancer / Ingress are the only ways in.

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
