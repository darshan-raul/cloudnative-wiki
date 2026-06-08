# CNI (Container Network Interface)

*"https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/"*

CNI is the **specification and plugin model** that connects Pod networking. Kubernetes doesn't ship a network implementation itself — it delegates to a CNI plugin that runs on every node. The kubelet calls the CNI when a Pod is created, and the CNI does the actual work of giving the Pod an IP and wiring it into the cluster's network.

### Table of Contents

1. [The CNI's Job](#1-the-cnis-job)
2. [The Kubernetes Network Model Contract](#2-the-kubernetes-network-model-contract)
3. [CNI Plugins: A Comparison](#3-cni-plugins-a-comparison)
4. [Overlay vs Underlay Networking](#4-overlay-vs-underlay-networking)
5. [eBPF-Based CNIs and the Datapath](#5-ebpf-based-cnis-and-the-datapath)
6. [IPAM (IP Address Management)](#6-ipam-ip-address-management)
7. [AWS VPC CNI and the IP Pressure Problem](#7-aws-vpc-cni-and-the-ip-pressure-problem)
8. [CNI Installation and the "Pick Wisely" Decision](#8-cni-installation-and-the-pick-wisely-decision)
9. [MTU, Encapsulation, and Performance](#9-mtu-encapsulation-and-performance)
10. [Dual-Stack (IPv4 + IPv6)](#10-dual-stack-ipv4--ipv6)
11. [NetworkPolicy and the CNI Dependency](#11-networkpolicy-and-the-cni-dependency)
12. [Operations and Debugging](#12-operations-and-debugging)
13. [Gotchas and Common Mistakes](#13-gotchas-and-common-mistakes)

---

## 1. The CNI's Job

When a Pod is scheduled on a node, the kubelet calls the CNI plugin to:

1. **Allocate an IP** for the Pod (from a node pool or cluster-wide).
2. **Create a network namespace** for the Pod and a virtual interface pair (veth).
3. **Wire the veth** into the node's network (bridge, route, or overlay).
4. **Set up routes** so Pods on different nodes can talk.

When the Pod is deleted, the CNI plugin tears it down: removes the veth, releases the IP, deletes routes.

```
       kubelet                              CNI plugin
          │                                       │
          │  CREATE: {                           │
          │    "name": "k8s-pod-network",        │
          │    "type": "calico",                 │
          │    "cniVersion": "0.3.1",            │
          │    "runtimeConfig": {                │
          │      "podIP": "10.244.1.5/32"        │
          │    },                                │
          │    "netns": "/var/run/netns/abc-123" │
          │  }                                   │
          │ ─────────────────────────────────►   │
          │                                       │  1. allocate IP
          │                                       │  2. create veth
          │                                       │  3. move veth into netns
          │                                       │  4. add route
          │                                       │
          │  RESULT: {                           │
          │    "ips": [{"version": "4",          │
          │             "address": "10.244.1.5/32",
          │             "interface": 0}],        │
          │    "dns": {}                          │
          │  }                                    │
          │ ◄─────────────────────────────────   │
          │                                       │
          │  (Pod's eth0 is now in its netns,     │
          │   with the IP 10.244.1.5)             │
```

The CNI plugin is a binary (`/opt/cni/bin/<plugin>`) and a config (`/etc/cni/net.d/<config>.conf`). The kubelet finds the binary, passes it the config, and the plugin does the rest.

### 1.1 The veth pair

A **veth pair** is a virtual cable — two ends of a virtual network interface. One end goes into the Pod's network namespace (becomes `eth0` inside the Pod). The other stays on the host (named something like `cali-abc123`).

```
Pod's network namespace              Host network namespace
┌──────────────────────┐             ┌──────────────────────────┐
│                      │             │                          │
│   eth0 (10.244.1.5)  │ ◄══veth══► │   cali-abc123            │
│                      │             │      │                   │
│   lo: 127.0.0.1      │             │      │                   │
│                      │             │      ▼                   │
│                      │             │   cbr0 (bridge)          │
│                      │             │      │                   │
│                      │             │      ▼                   │
│                      │             │   eth0 (node's NIC)      │
└──────────────────────┘             └──────────────────────────┘
```

Packets sent from the Pod's `eth0` come out the host-side veth, get bridged / routed, and head out the node's network interface. The reverse happens for incoming traffic.

## 2. The Kubernetes Network Model Contract

For k8s to consider the network "valid", the CNI must satisfy these rules (from the k8s design doc, 2014):

1. **Every Pod gets its own IP address.** No sharing, no NAT inside the cluster.
2. **Pods on any node can communicate with all other Pods on any other node without NAT.** Flat, routable.
3. **Agents on a node (kubelet, etc.) can communicate with all Pods on that node.**
4. **Pods in the host network can communicate with all other Pods without NAT.** (A consequence of 2.)

Anything that satisfies these is a valid CNI. The model is **deliberately simple** — it doesn't specify IP ranges, CIDR schemes, or any specific implementation. The CNI has freedom to choose how to implement it.

### 2.1 The IP-per-Pod corollary

A fundamental consequence: **IP-per-Pod is the unit of identity, not IP-per-container.**

A Pod's containers share a network namespace (one IP for the Pod). A Pod's IP is "as stable as the Pod is" — when the Pod is deleted and recreated, it gets a new IP. This is the basis for Services, DNS, and NetworkPolicy.

This is also why the IP-per-Pod model is so different from the VM model. In a VM world, you have a stable VM IP and stable service IPs on top. In a Pod world, the Pod IP is ephemeral; the Service IP is the stable thing.

## 3. CNI Plugins: A Comparison

| Plugin | Model | NetworkPolicy | L7 (L4) | Notes |
|---|---|---|---|---|
| **Flannel** | VXLAN / host-gw overlay | ❌ | ❌ | Easy to set up, no policy, no L7. Default in k3s. |
| **Calico** | BGP / VXLAN / IPIP / eBPF | ✅ | ❌ | Full policy, scalable, common in production. eBPF mode (Calico eBPF or Calico VPP). |
| **Cilium** | eBPF | ✅ | ✅ | L7 policy (HTTP/gRPC), can replace kube-proxy, Hubble for observability. |
| **Weave Net** | Overlay | ✅ | ❌ | Simple, less common now. |
| **AWS VPC CNI** | Native VPC ENIs | ❌ (unless paired with Calico) | ❌ | Pods get real VPC IPs. Default on EKS. |
| **Azure CNI** | Native Azure VNet | ❌ (unless paired with Calico) | ❌ | Default on AKS. |
| **GKE Dataplane V2** | eBPF (Cilium-based) | ✅ | ✅ | Default on GKE. |
| **Antrea** | eBPF | ✅ | ✅ | VMware-led, on-prem focused. |
| **Multus** | Meta-plugin | Depends on delegates | Depends | Multiple network interfaces per Pod. |

### 3.1 Flannel

The simplest. VXLAN or host-gw overlay between nodes. No NetworkPolicy (you'd need a separate plugin). Good for dev / test, less common in production.

**Strengths:** zero-config, works on any Linux, doesn't need a database.
**Weaknesses:** no policy, no observability, scales poorly at high throughput (CPU-bound VXLAN encap/decap).

### 3.2 Calico

The most common in production. Supports multiple modes:

* **BGP + IPIP** — Pod IPs are routable in your datacenter, advertised via BGP. No encapsulation overhead.
* **VXLAN** — Encapsulated overlay, like Flannel. Works without BGP-capable network equipment.
* **eBPF (datapath)** — eBPF programs replace iptables for the data plane. Faster than iptables.
* **VPP** — Vector Packet Processing. Less common.

Calico supports **NetworkPolicy** (the standard k8s API), plus its own `GlobalNetworkPolicy` and `NetworkSet` for cluster-wide rules. It also supports `BGP peer` and `BGPConfiguration` for advanced routing.

**Strengths:** full policy, multiple modes, scalable, mature.
**Weaknesses:** complex to set up if you want BGP. eBPF mode requires recent kernels.

### 3.3 Cilium

The modern choice. **eBPF-based** — most of the data plane is in eBPF programs in the kernel, not iptables.

Key features:

* **L3/L4 policy** (the standard k8s NetworkPolicy).
* **L7 policy** — `cilium.NetworkPolicy` can match on HTTP path, gRPC method, Kafka topic, etc.
* **Replaces kube-proxy** — Cilium's eBPF handles Service ClusterIP DNAT. No iptables rules.
* **Hubble** — observability for the data plane. Flow logs, DNS observability, metrics.
* **ClusterMesh** — multi-cluster connectivity.
* **Service mesh** — Cilium Service Mesh (beta) provides mTLS, L7 routing without sidecars.

**Strengths:** performance (no iptables), L7 policy, observability, multi-cluster, mesh.
**Weaknesses:** requires recent kernels (>= 5.4 for full features), more complex to operate, learning curve.

### 3.4 Weave Net

Older plugin, simple to set up. Less common now — Calico and Cilium have eaten its lunch.

### 3.5 AWS VPC CNI

The default on EKS. Each Pod gets a **real VPC IP** by attaching a secondary IP to the node's ENI (Elastic Network Interface).

**Pros:** no overlay, no encapsulation, no MTU issues. Pods are first-class VPC citizens (security groups, route tables, etc.).
**Cons:** **IP pressure** — the node subnet can run out of IPs. A `/24` node subnet supports ~250 Pods (limited by ENI density). Prefix delegation helps, but it's a real constraint.

**Pairing with Calico:** AWS VPC CNI alone doesn't do NetworkPolicy. Many teams install Calico in "policy-only" mode (Calico programs the policy, AWS VPC CNI programs the data plane).

### 3.6 Azure CNI / GKE Dataplane V2

Same idea as AWS VPC CNI, on their respective clouds. GKE Dataplane V2 is Cilium-based.

### 3.7 Multus

A **meta-plugin**. Attaches multiple network interfaces to a Pod. Used for:

* **Secondary networks** — a Pod with one interface for cluster traffic and another for a separate VLAN (e.g. legacy storage network).
* **SR-IOV** — direct hardware access for high-performance networking.
* **NFV** — network function virtualization, where a Pod acts as a router / firewall.

Multus delegates to other CNIs (Flannel, Calico, etc.) for the primary interface.

## 4. Overlay vs Underlay Networking

### 4.1 Overlay (Flannel, Calico VXLAN mode)

Pods get IPs from a **private range** (e.g. `10.244.0.0/16`). Packets are **encapsulated** (VXLAN / IPIP) to traverse the underlying network.

```
Node 1                                                  Node 2
┌────────────────────────────┐         ┌────────────────────────────┐
│  Pod A (10.244.1.5)        │         │  Pod C (10.244.2.7)        │
│       │                    │         │       │                    │
│       ▼                    │         │       ▼                    │
│   eth0 (veth)              │         │   eth0 (veth)              │
│       │                    │         │       │                    │
│   cbr0 / cali-bridge       │         │   cbr0 / cali-bridge       │
│       │                    │         │       │                    │
│   eth0 (node's NIC)        │         │   eth0 (node's NIC)        │
│       │                    │         │       │                    │
│   ── VXLAN encap ──────────┼────►────┼── VXLAN decap ──────      │
│   outer IP: <node1 IP>     │         │   outer IP: <node2 IP>     │
│   inner IP: 10.244.1.5     │         │   inner IP: 10.244.2.7     │
│   inner dest: 10.244.2.7   │         │                            │
└────────────────────────────┘         └────────────────────────────┘
```

**Pros:** no IP pressure on the node network. You can have 1000s of Pods per node regardless of the node subnet size. The node subnet only needs IPs for the nodes themselves.

**Cons:** encapsulation overhead (50-100 bytes per packet), MTU issues (effective MTU is 1400-1450 instead of 1500), CPU cost of encap/decap at high throughput.

### 4.2 Underlay / Native (AWS VPC CNI, Cilium in chaining mode)

Pods get **real network IPs** (VPC IPs, for example). No encapsulation.

**Pros:** no MTU issues, full network performance, Pods are first-class network citizens.
**Cons:** **IP pressure** — the node subnet must have enough IPs for all the Pods. This is the **#1 operational issue** with AWS VPC CNI.

### 4.3 BGP without encapsulation (Calico)

A middle ground. Pod IPs are routable in the datacenter, but the network equipment (ToR switches, etc.) must support BGP. The CNI just adds routes — no encapsulation.

**Pros:** no overhead, no IP pressure on the cluster (uses the same subnet).
**Cons:** requires BGP-capable network. Common in on-prem, rare in cloud.

## 5. eBPF-Based CNIs and the Datapath

eBPF (extended Berkeley Packet Filter) lets you run sandboxed programs in the Linux kernel. eBPF-based CNIs (Cilium, Calico eBPF) move the data plane from iptables to eBPF:

```
┌────────────────────────────────────────────────────────────┐
│  Traditional (iptables)                                     │
│  ┌──────────┐  ┌──────────┐  ┌────────────┐                 │
│  │  App     │──│  veth    │──│  netfilter │──►  NIC         │
│  │          │  │          │  │  (iptables)│                 │
│  └──────────┘  └──────────┘  └────────────┘                 │
│                            ↑                                │
│                       O(n) chain walk                        │
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│  eBPF (Cilium)                                             │
│  ┌──────────┐  ┌──────────┐  ┌────────────┐                 │
│  │  App     │──│  veth    │──│  eBPF      │──►  NIC         │
│  │          │  │          │  │  program   │                 │
│  └──────────┘  └──────────┘  └────────────┘                 │
│                            ↑                                │
│                       O(1) hash lookup                       │
└────────────────────────────────────────────────────────────┘
```

### 5.1 What eBPF gives you

* **Faster Service DNAT** — eBPF hash lookups are O(1), iptables is O(n) chain walk.
* **L7 visibility** — eBPF can parse HTTP / gRPC headers without a sidecar.
* **Lower CPU usage** — no copying packets through iptables rules.
* **Hubble integration** — flow logs from eBPF, not from packet sampling.

### 5.2 What eBPF costs you

* **Kernel version** — needs >= 5.4 for full features (5.10+ recommended). Older kernels fall back to a less featureful mode.
* **Debugging complexity** — eBPF programs are harder to inspect than iptables rules. You need `bpftool` and Cilium's own tools.
* **Smaller community** — fewer people know eBPF than iptables. Documentation is thinner.

### 5.3 Cilium's data plane in detail

Cilium's eBPF programs handle:

* **Service ClusterIP DNAT** — replaces kube-proxy's iptables rules.
* **NetworkPolicy** — enforced in the eBPF program, not iptables.
* **L7 policy** — can match HTTP paths, gRPC methods, Kafka topics, etc.
* **Conntrack** — connection tracking for stateful rules.
* **Load balancing** — multiple algorithms (random, maglev, etc.).
* **Host firewall** — Cilium's host firewall replaces or augments iptables for the host.

Cilium **replaces kube-proxy** when used in this mode. The cluster runs without kube-proxy entirely.

## 6. IPAM (IP Address Management)

The CNI needs to give each Pod an IP. The strategy depends on the plugin:

### 6.1 Host-local (Flannel default)

Each node has a **slice** of the cluster's Pod CIDR. A node with `10.244.1.0/24` gives out `10.244.1.0` - `10.244.1.255` to its Pods.

**Pros:** simple, no central coordination.
**Cons:** if a node's slice is small, it can run out. IP allocation is per-node, not cluster-wide.

### 6.2 Calico IPAM

Multiple modes:

* **Host-local** — same as Flannel.
* **Calico IPAM** — a central IP pool, but allocation is per-Pod (the IP is "reserved" before the Pod is scheduled).
* **Kubernetes IPAM** — uses the `v1.Node` spec's `podCIDR` field. Set by the apiserver or the controller-manager.

### 6.3 AWS VPC CNI IPAM

Each Pod gets a **secondary IP from the node's ENI**. The CNI manages a pool of secondary IPs per node.

**Limit:** the number of secondary IPs per ENI is bounded by the instance type. A `m5.large` has 10 secondary IPs per ENI. A `m5.4xlarge` has 234.

### 6.4 Prefix delegation (AWS VPC CNI, k8s 1.27+)

The CNI can request a **/28 prefix** (16 IPs) from the VPC and assign individual IPs to Pods. This multiplies the IP count per ENI by ~16x. **Massively reduces IP pressure.**

```yaml
# aws-node ConfigMap
spec:
  env:
  - name: ENABLE_PREFIX_DELEGATION
    value: "true"
  - name: WARM_PREFIX_TARGET
    value: "1"   # pre-allocate 1 prefix per node at startup
```

Prefix delegation requires **Amazon VPC CNI >= 1.9** and **subnet routing tables** that support /28 routes (most do, but on-prem doesn't apply).

## 7. AWS VPC CNI and the IP Pressure Problem

This is the **#1 operational concern** for AWS VPC CNI users.

### 7.1 The math

A `/24` subnet = 256 IPs.
A `m5.large` ENI supports ~10 secondary IPs.
A `m5.large` has 3 ENIs (1 primary + 2 secondary).
Total Pods per node: ~30.

To run 100 nodes with 30 Pods each = 3000 Pods, you need 3000 VPC IPs. That's a `/22` subnet. **Doable, but tight.**

For dense clusters (hundreds of Pods per node), you need:
* Larger instance types (more ENIs / more secondary IPs per ENI).
* Prefix delegation (multiplies the IP count).
* A `/19` or `/18` subnet for the nodes.

### 7.2 The trade-off

AWS VPC CNI is great for **most apps** (no MTU, no encapsulation, Pods are VPC citizens). But for **dense node pools** (e.g. a `c5.12xlarge` running 200 Pods), the IP math is hard.

Alternatives:
* **Calico on AWS** — overlay mode, no IP pressure, but adds encapsulation overhead.
* **EKS Auto Mode** — newer, abstracts the IPAM (still uses VPC IPs but managed).
* **Pod density limits** — limit Pods per node via `max-pods` on the kubelet.

## 8. CNI Installation and the "Pick Wisely" Decision

### 8.1 Installation patterns

* **Managed k8s (EKS, GKE, AKS)** — CNI comes pre-installed. EKS uses AWS VPC CNI. GKE uses GKE Dataplane V2 (Cilium-based). AKS uses Azure CNI. You can usually choose a different one (with caveats).
* **kubeadm** — you install the CNI yourself, usually via a manifest (DaemonSet, RBAC, etc.). Calico and Cilium both have documented install paths.
* **k3s, k0s, kind** — comes bundled with a default CNI (Flannel for k3s, Calico for k0s, kind's default CNI).

### 8.2 Picking a CNI

The decision tree:

```
What does your environment look like?
├── Cloud (EKS, GKE, AKS)
│   ├── Default is fine → use it (EKS: AWS VPC CNI, GKE: Dataplane V2, AKS: Azure CNI)
│   ├── Need L7 policy / observability → Cilium
│   └── IP pressure on AWS → Calico overlay or enable prefix delegation
│
├── On-prem with BGP-capable network
│   └── Calico BGP mode (no encapsulation, no IP pressure)
│
├── On-prem without BGP
│   └── Calico VXLAN or Flannel VXLAN
│
├── Dev / test
│   └── Flannel (or kind's default)
│
└── Need L7 / mesh features
    └── Cilium (or Calico eBPF)
```

### 8.3 The "one-way door" warning

Migrating CNIs is **non-trivial**. Pod IPs change (if you switch overlay ↔ underlay), routes change, NetworkPolicy semantics may differ, and the cluster is effectively down during the migration.

**Choose carefully before going to production.** Most teams stick with whatever the managed cluster provides, or pick Calico / Cilium once and stay with it for years.

## 9. MTU, Encapsulation, and Performance

### 9.1 The MTU problem with overlays

Ethernet's default MTU is 1500 bytes. VXLAN adds 50 bytes of overhead (24 bytes VXLAN + 8 bytes UDP + 14 bytes Ethernet + 4 bytes IP). IPIP adds 20 bytes. So the **inner** MTU is reduced to 1450 (VXLAN) or 1480 (IPIP).

If a Pod tries to send a 1500-byte packet over VXLAN, the kernel either fragments it (slow, sometimes blocked) or drops it (if `DF` is set and there's no PMTUD reply).

**Symptoms:** weird slowness, connections that hang at startup, large HTTP requests that fail.

**Fixes:**

* Set the Pod's MTU to 1450 (or the right value for your CNI).
* Enable PMTUD (Path MTU Discovery) on the kernel — usually default.
* Use jumbograms on the underlying network (MTU 9000) — common in on-prem, rare in cloud.

Calico and Cilium configure the MTU automatically when installed. **If you change the CNI or the underlying network's MTU, update the CNI config.**

### 9.2 CPU cost of encapsulation

VXLAN encap/decap is CPU work. At 10 Gbps, the overhead is measurable. Cilium and Calico eBPF modes push this into the kernel's eBPF program, which is faster than userspace encap.

For high-throughput workloads:
* Use **eBPF-based CNIs** (Cilium, Calico eBPF).
* Use **BGP mode** if you can (no encapsulation).
* Use **SR-IOV** (hardware offload) for extreme cases.

### 9.3 Pod-to-Pod latency

A rough comparison (same region, same zone):

| Mode | Typical p99 latency | Notes |
|---|---|---|
| VPC CNI (underlay) | ~0.5ms | Best |
| Calico BGP (underlay, on-prem) | ~0.3ms | Best, on-prem |
| Calico VXLAN (overlay) | ~0.7ms | Adds encap overhead |
| Cilium eBPF (overlay) | ~0.5ms | Faster than VXLAN encap in userspace |
| Cilium eBPF (chaining to VPC CNI) | ~0.5ms | Best of both worlds on AWS |

## 10. Dual-Stack (IPv4 + IPv6)

### 10.1 What's needed

* **apiserver** feature gate: `--feature-gates=IPv6DualStack=true` (default in 1.21+).
* **kubelet** flag: `--node-ip=<ipv4>,<ipv6>` — the node must have both addresses.
* **CNI** that supports it: Calico, Cilium, Antrea. Not all do.
* **Service CIDRs** for both families: `--service-cluster-ip-range=10.96.0.0/16,fd00::/108` on the apiserver.
* **Pod CIDRs** for both families.

### 10.2 What you get

* Every Pod gets an IPv4 and an IPv6 address.
* Every Service gets an IPv4 and an IPv6 ClusterIP.
* DNS returns both (A and AAAA records).

### 10.3 The reality

Most clusters are **still IPv4-only**. IPv6 is GA in k8s but adoption is slow because:
* Cloud VPCs don't always have IPv6 enabled.
* Most internal apps and services are IPv4.
* The operational complexity is real.

If you have a specific IPv6 requirement (e.g. carrier-grade NAT, huge address space, regulatory), go for it. Otherwise, IPv4 is fine.

## 11. NetworkPolicy and the CNI Dependency

**NetworkPolicy enforcement depends on the CNI.** If your CNI doesn't support it, the resource is a **no-op** — no error, just silence.

```bash
kubectl get networkpolicy -A
# shows policies

# but if the CNI doesn't support them, traffic flows as if the policies don't exist
# the only way to know is to test
```

**This is a major footgun.** A team writes a deny-all NetworkPolicy, deploys it, and assumes traffic is restricted. But if the CNI is Flannel (which doesn't support NetworkPolicy), the policy is silently ignored. **Verify with a test Pod, not just `kubectl get`.**

CNI compatibility for NetworkPolicy:

| CNI | NetworkPolicy | Notes |
|---|---|---|
| Flannel | ❌ | Use Calico or Cilium if you need policy |
| Calico | ✅ | Full support, plus `GlobalNetworkPolicy` |
| Cilium | ✅ | Full support, plus L7 policy |
| Weave | ✅ | Full support |
| AWS VPC CNI | ❌ alone, ✅ with Calico | Install Calico in "policy-only" mode |
| Azure CNI | ❌ alone, ✅ with Calico / Cilium | Same as AWS |
| GKE Dataplane V2 | ✅ | Built on Cilium |
| Antrea | ✅ | Full support |

## 12. Operations and Debugging

### 12.1 Common commands

```bash
# check the CNI on a node
ls /etc/cni/net.d/                  # the CNI configs
ls /opt/cni/bin/                    # the CNI binaries

# check the CNI pods
kubectl -n kube-system get pods -l k8s-app=<cni-name>
# e.g. k8s-app=calico-node, k8s-app=cilium

# check the data plane
ip link show                        # list interfaces (look for veth pairs, bridges)
ip route show                       # routes (look for Pod CIDR routes)
iptables-save | head                # iptables rules
ipvsadm -L -n                       # IPVS rules

# check Pod network
kubectl exec -it <pod> -- ip addr   # check the Pod's IP
kubectl exec -it <pod> -- ping <other-pod-ip>

# check the node's view
# (on the node)
ss -tnp | grep <pod-ip>             # see what the node sees
conntrack -L | grep <pod-ip>        # see conntrack entries
```

### 12.2 The "Pods can't talk to each other" checklist

```bash
# 1. Are the Pods in the same CNI's view?
kubectl get pods -o wide
# check IPs and nodes

# 2. Is there a NetworkPolicy blocking?
kubectl get networkpolicy -A
# and a default-deny in the namespace?

# 3. Can Pod A reach Pod B's IP directly?
kubectl exec -it <pod-a> -- ping <pod-b-ip>
# if no, the data plane is broken

# 4. Can Pod A reach Pod B by Service name?
kubectl exec -it <pod-a> -- nslookup <svc>
kubectl exec -it <pod-a> -- curl <svc>

# 5. Is kube-proxy running?
kubectl -n kube-system get pods -l k8s-app=kube-proxy

# 6. CNI logs?
kubectl -n kube-system logs -l k8s-app=<cni-name> --tail=100
```

### 12.3 CNI-specific debugging

**Calico:**

```bash
# check Felix (the Calico agent)
kubectl -n kube-system logs -l k8s-app=calico-node --tail=100
calicoctl get nodes
calicoctl get ipPools
calicoctl get bgpPeer

# check the BGP status (if using BGP mode)
calicoctl node status
```

**Cilium:**

```bash
# check Cilium agent
kubectl -n kube-system logs -l k8s-app=cilium --tail=100
cilium status
cilium endpoint list
cilium bpf lb list                # service LB map
cilium bpf ct list global         # conntrack

# Hubble (if installed)
hubble observe
hubble flow list
```

**Flannel:**

```bash
# check the flannel agent
kubectl -n kube-system logs -l app=flannel --tail=100

# check the routes
ip route show
```

## 13. Gotchas and Common Mistakes

### 13.1 The 30+ common mistakes

1. **Choosing Flannel in production because "it's simple".** Flannel has no NetworkPolicy. Your team will write NetworkPolicy resources and they'll be silently ignored.

2. **Picking a CNI without checking NetworkPolicy support.** This is the #1 footgun. Always check.

3. **Forgetting MTU when switching CNIs.** Different CNIs use different MTUs. Pods that worked on Flannel VXLAN (MTU 1450) may break on Calico IPIP (MTU 1480).

4. **AWS VPC CNI IP exhaustion.** A `/24` node subnet + 100 nodes + 30 Pods per node = 3000 IPs needed. Plan the subnet size accordingly.

5. **Cilium requires kernel 5.4+.** Older kernels fall back to a less featureful mode. Check `uname -r` before installing.

6. **Calico BGP mode requires BGP-capable network equipment.** Cloud VPCs usually don't speak BGP to the nodes. Use Calico VXLAN / IPIP on cloud.

7. **The CNI's pods run in `kube-system`.** Deleting them breaks the cluster. **Don't clean up `kube-system` blindly.**

8. **Calico's `calicoctl` is a separate binary.** Not installed by default. Download from GitHub releases.

9. **Cilium's Hubble is a separate install.** The Cilium agent and Hubble UI are different components.

10. **Calico's IPIP mode is not the same as VXLAN mode.** IPIP adds 20 bytes of overhead, VXLAN adds 50. Pick based on your MTU budget.

11. **Multus requires a "primary" CNI.** You can't run Multus alone. It delegates to other CNIs.

12. **Switching CNIs in place is very hard.** Pod IPs change, NetworkPolicy semantics differ, downtime is required. Don't switch in production unless you really need to.

13. **The CNI's data plane vs control plane.** Cilium's agent is the data plane. Calico has Felix (data plane) + Typha (control plane) + confd / BGP speaker. Different components, different failure modes.

14. **`NetworkPolicy` is enforced by the CNI, not the apiserver.** The apiserver just stores the resource. The CNI watches it and programs the data plane.

15. **A Pod's `dnsPolicy: ClusterFirst` requires the CNI to be working.** If the CNI is broken, DNS doesn't work, even though CoreDNS is up.

16. **The CNI's MTU must be set in the CNI config, not on the Pod.** The kubelet doesn't set Pod MTU. The CNI configures the veth MTU when creating the interface.

17. **Calico eBPF mode requires `--kube-proxyReplacement=strict` for some features.** Default mode (`strict`) replaces kube-proxy entirely.

18. **Calico's `GlobalNetworkPolicy` is non-standard.** Only Calico understands it. Don't use it if you want to be CNI-agnostic.

19. **Cilium's L7 policy is non-standard.** `CiliumNetworkPolicy` extends NetworkPolicy with L7 fields. Same caveat.

20. **AWS VPC CNI prefix delegation requires Amazon VPC CNI >= 1.9** and `aws-node` config. Older versions don't support it.

21. **CNI plugins don't survive kubelet restarts gracefully.** When the kubelet restarts, it re-runs the CNI for every running Pod. Most CNIs handle this idempotently, but some don't.

22. **Calico's VXLAN mode uses UDP port 4789.** Flannel's uses 8472. Different defaults. If you're switching CNIs, update firewall rules.

23. **The CNI is on every node.** A misbehaving CNI pod on one node doesn't affect other nodes, but the affected node is down.

24. **NetworkPolicy egress rules can block the CNI itself.** The CNI agent (e.g. calico-node) needs to reach the apiserver. If you write a default-deny egress policy in `kube-system`, the CNI agent may be blocked.

25. **Cilium's eBPF maps consume kernel memory.** At 100,000s of connections, the conntrack map can grow large. Monitor it.

26. **The CNI is unaware of `NetworkPolicy` for the host itself.** NetworkPolicy applies to Pods, not to host services. Use a host firewall (iptables, nftables) for that.

27. **The kube-proxy mode (`iptables` vs `IPVS` vs `eBPF`) is independent of the CNI.** You can run iptables kube-proxy with Cilium (for Service scaling) or IPVS kube-proxy with Calico.

28. **`NetworkPolicy` selectors are exact match.** `matchLabels` is exact match on labels. `matchExpressions` allows set-based selectors (In, NotIn, Exists). Both work; combine for complex rules.

29. **The CNI's data plane is on the **node**, not in the cluster.** When you `kubectl drain` a node, the CNI pods on that node are evicted. The node's data plane is gone, but the cluster is fine (other nodes' data planes are unaffected).

30. **CNI upgrades can break running Pods.** Most CNIs handle this carefully, but a buggy upgrade can break networking for in-flight Pods. Always test in staging first.

31. **`Pod-to-Pod` encryption (WireGuard, IPsec) requires the CNI to support it.** Calico has Felix + WireGuard. Cilium has its own encryption. Flannel doesn't.

32. **The CNI's logs are in `kube-system` but may not show in `kubectl logs` by default.** Use `-n kube-system` and the right label selector.

## See also

* [[Kubernetes/concepts/L04-services-networking/01-networking|Networking]] — the L04 mental model
* [[Kubernetes/concepts/L04-services-networking/02-services|Services]] — what the CNI supports
* [[Kubernetes/concepts/L04-services-networking/05-network-policy|NetworkPolicy]] — needs a CNI that supports it
* [[Kubernetes/concepts/L04-services-networking/07-k8s-networking-deep-dive|Networking Deep Dive]] — packet walkthroughs
* [[Kubernetes/concepts/L09-advanced/08-ipvs|IPVS]] — kube-proxy mode that some CNIs replace
