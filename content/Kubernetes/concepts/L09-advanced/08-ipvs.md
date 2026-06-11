# IPVS (kube-proxy mode)

>*"https://kubernetes.io/docs/reference/networking/virtual-ips/"*

IPVS (IP Virtual Server) is one of the modes **kube-proxy can use to implement Service virtual IPs**. It's a Linux kernel feature that does L4 load balancing more efficiently than iptables for large clusters.

## Table of Contents

1. [Why iptables breaks at scale](#1-why-iptables-breaks-at-scale)
2. [How IPVS works differently](#2-how-ipvs-works-differently)
3. [The dummy interface trick](#3-the-dummy-interface-trick)
4. [Packet walkthrough: Service ClusterIP](#4-packet-walkthrough-service-clusterip)
5. [Enabling IPVS](#5-enabling-ipvs)
6. [IPVS schedulers](#6-ipvs-schedulers)
7. [IPVS and conntrack](#7-ipvs-and-conntrack)
8. [strictARP explained](#8-strictarp-explained)
9. [Comparison: iptables vs IPVS vs IPVS+Firecracker](#9-comparison-iptables-vs-ipvs-vs-ipvsfirecracker)
10. [Performance numbers at scale](#10-performance-numbers-at-scale)
11. [Debugging with ipvsadm](#11-debugging-with-ipvsadm)
12. [kube-proxy ConfigMap reference](#12-kube-proxy-configmap-reference)
13. [Prerequisites and kernel modules](#13-prerequisites-and-kernel-modules)
14. [CNI compatibility](#14-cni-compatibility)
15. [Rollback from IPVS to iptables](#15-rollback-from-ipvs-to-iptables)
16. [When to use each mode](#16-when-to-use-each-mode)
17. [Gotchas](#17-gotchas)

---

### 1. Why iptables breaks at scale

The default kube-proxy mode is **iptables**. For each Service, kube-proxy installs iptables rules:

```
# kube-proxy iptables rules (simplified)
-A KUBE-SERVICES -d 10.96.0.42/32 -p tcp --dport 80 -j KUBE-SVC-XXX
-A KUBE-SVC-XXX -m statistic --mode random --probability 0.333333 -j KUBE-SEP-AAA
-A KUBE-SVC-XXX -m statistic --mode random --probability 0.500000 -j KUBE-SEP-BBB
-A KUBE-SVC-XXX -j KUBE-SEP-CCC
```

Problems at scale:

| Problem | Symptom |
|---------|---------|
| **Linear chain traversal** | Each packet for Service X walks the full KUBE-SVC chain, then KUBE-SEP chain |
| **O(n) updates** | Adding/removing an endpoint rewrites the chain — on the hot path |
| **CPU overhead** | At 10,000+ Services, CPU spent in netfilter/iptables is measurable |
| **No consistent hashing** | `random --probability` is statistical, not deterministic |
| **Memory pressure** | Large iptables rulesets use significant kernel memory |

The breaking point is roughly **1,000–5,000 Services**. Below that, iptables is fine.

---

### 2. How IPVS works differently

IPVS uses **kernel hash tables** instead of linear chains. Service lookups are **O(1)**:

```
                    ┌─────────────────────────────────┐
                    │     IPVS hash table             │
                    │                                 │
Service ClusterIP ─►│  key: 10.96.0.42:80             │
                    │  entries: [backend1, backend2]   │
                    │  scheduler: rr                  │
                    └─────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────────────────────┐
                    │   Selected backend:             │
                    │   10.244.1.5:80 (DNAT)          │
                    └─────────────────────────────────┘
```

IPVS is a **Linux kernel L4 load balancer**. It's part of the `ip_vs` kernel module and runs entirely in kernel space — no userspace round-trips per packet.

```
kube-proxy (userspace)
  │
  │ configures
  ▼
IPVS (kernel space)
  │
  │ DNATs packets
  ▼
Backend Pod
```

---

### 3. The dummy interface trick

kube-proxy in IPVS mode creates a **dummy interface** called `kube-ipvs0`:

```bash
ip addr show kube-ipvs0
# 5: kube-ipvs0: <BROADCAST,NOARP>  mtu 1500 qdisc noop
#     inet 10.96.0.1/32 scope global kube-ipvs0
#     valid_lft forever preferred_lft forever

# All ClusterIPs are assigned to this dummy interface
ip addr show kube-ipvs0
# inet 10.96.0.42/32 scope global kube-ipvs0
# inet 10.96.0.55/32 scope global kube-ipvs0
```

Why a dummy interface? So the node **answers ARP for the ClusterIP** even though no physical interface has that IP. The dummy interface holds the IP, and the kernel's IPVS intercepts packets destined for it before they reach the routing stage.

---

### 4. Packet walkthrough: Service ClusterIP

```
1. App in Pod A sends: tcp 10.96.0.42:80 → Pod B
2. Pod A's namespace: routing decision → route to node's eth0
3. Node eth0 receives packet
4. IPVS intercepts: dest = 10.96.0.42:80
5. IPVS applies scheduler (e.g., round-robin)
6. IPVS DNATs: 10.96.0.42:80 → 10.244.2.7:80
7. Packet forwarded to Pod B's veth pair
8. Pod B receives packet (src = Pod A IP, dst = 10.244.2.7:80)
```

For return traffic, conntrack reverses the DNAT transparently.

---

### 5. Enabling IPVS

#### Via kubeadm config (at cluster init)

```yaml
# kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
networking:
  serviceSubnet: 10.96.0.0/12
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: ipvs
ipvs:
  scheduler: rr
  strictARP: false
  minSyncPeriod: 1s
  syncPeriod: 15s
```

```bash
kubeadm init --config=kubeadm-config.yaml
```

#### On an existing cluster

```bash
# 1. Edit the kube-proxy ConfigMap
kubectl edit configmap kube-proxy -n kube-system

# 2. Add or change the mode
data:
  config.conf: |
    apiVersion: kubeproxy.config.k8s.io/v1alpha1
    kind: KubeProxyConfiguration
    mode: ipvs
    ipvs:
      scheduler: rr
      strictARP: false

# 3. Restart kube-proxy to pick up the change
kubectl rollout restart daemonset kube-proxy -n kube-system

# 4. Verify the mode changed
kubectl get pods -n kube-system -l k8s-app=kube-proxy -o jsonpath='{.items[*].spec.containers[*].command}' \
  | grep -oP 'mode=\K[^ ]+'

# 5. Verify ipvs entries exist
ipvsadm -L -n
```

---

### 6. IPVS schedulers

| Scheduler | Name | Description | Best for |
|-----------|------|-------------|----------|
| Round-robin | `rr` | Distributes evenly in turn | Default, most cases |
| Weighted round-robin | `wrr` | Distributes by weight | Heterogeneous backends |
| Least connection | `lc` | Picks least busy backend | Long-lived connections (HTTP keepalive) |
| Weighted least connection | `lblc` | LC + virtual server weight | |
| Destination hashing | `dh` | Hashes destination IP | Sticky to a specific backend |
| Source hashing | `sh` | Hashes source IP | Client stickiness |
| Shortest expected delay | `sed` | Minimizes (active_conns+1)/weight | |
| Never queue | `nq` | Never queue — assign idle backend first | Latency-sensitive |

```yaml
# Set scheduler in kube-proxy ConfigMap
ipvs:
  scheduler: sh      # source-hashing for client stickiness
```

For session affinity (`sh` or `dh`), the same client always hits the same backend — useful when the backend maintains local state.

---

### 7. IPVS and conntrack

IPVS and conntrack work **together**:

```
Client → IPVS (DNAT) → Backend → conntrack (reverse DNAT) → Client
```

IPVS handles the load-balancing decision. **conntrack** tracks the connection state so return traffic is correctly reverse-DNATTed without going through IPVS again.

```
┌──────────────────────────────────────────────────────────┐
│ Connection tracked by conntrack                          │
│                                                          │
│  Flow: 10.244.1.5:80 → 10.244.2.7:8080                  │
│  NAT:  src 10.244.1.5:80  → dst 10.244.2.7:8080        │
│  Reply: src 10.244.2.7:8080 → dst <original-client>    │
│  conntrack reverse-NATs automatically                    │
└──────────────────────────────────────────────────────────┘
```

For **hairpin mode** (Pod reaching its own Service ClusterIP), conntrack is essential:

```bash
# Pod A → Service ClusterIP → IPVS → Backend (could be Pod A itself)
# Hairpin: return traffic must go back through IPVS
# conntrack tracks the flow so reply reaches the right place
```

**Tuning conntrack** for high-traffic clusters:

```bash
# Check current conntrack table size
sysctl net.netfilter.nf_conntrack_max

# Check current usage
cat /proc/sys/net/netfilter/nf_conntrack_count

# Increase if needed
sysctl -w net.netfilter.nf_conntrack_max=1048576

# For faster conntrack lookup (if kernel supports it)
sysctl -w net.netfilter.nf_conntrack_hashsize=262144
```

Add to `/etc/sysctl.d/99-kubernetes.conf` to persist.

---

### 8. strictARP explained

`strictARP: true` tells the node to **only respond to ARP requests for IPs assigned to its interfaces** — specifically, the dummy `kube-ipvs0` interface's ClusterIPs.

Why this matters: In BGP-based networking (e.g., Calico in BGP mode), each node advertises its own Pod CIDRs. The node shouldn't respond to ARP for Pod IPs that belong to other nodes. Without `strictARP: true`, the kernel might answer ARP for a Pod IP that belongs to a different node, causing routing issues.

```bash
# Without strictARP:
# Node receives ARP for 10.244.2.0/26 (a Pod CIDR on another node)
# Kernel answers ARP (wrong!) → traffic goes to wrong node

# With strictARP:
# Node only ARPs for IPs on kube-ipvs0 (ClusterIPs) and its own interfaces
# Pod CIDRs from other nodes are ignored
```

For most clusters (not using BGP Pod routing), `strictARP: false` is fine.

---

### 9. Comparison: iptables vs IPVS vs IPVS+Firecracker

| | iptables | IPVS | Notes |
|---|---|---|---|
| **Lookup** | O(n) chain | O(1) hash | |
| **Setup** | Always works | Needs kernel modules | |
| **Algorithms** | Random/probability | rr, wrr, lc, dh, sh, sed, nq | |
| **Update cost** | High (rewrite chains) | Low (hash update) | |
| **CPU at scale** | High | Low | |
| **Conntrack** | Required | Required | Both use it |
| **Session affinity** | Limited (probability) | Deterministic (sh/dh) | |
| **L7 proxy** | No | No | For L7, use a service mesh |
| **Debugging** | `iptables -L -n -v` | `ipvsadm -L -n` | |

IPVS is the right choice for large clusters (1000+ Services) or when you need deterministic session affinity.

---

### 10. Performance numbers at scale

Rough CPU impact of kube-proxy at scale (measured on a 3-node cluster with 50/50 split between data and control plane):

| Services | Endpoints | iptables CPU (extra) | IPVS CPU (extra) |
|----------|-----------|---------------------|-----------------|
| 100 | 1,000 | ~0.5% per node | ~0.5% |
| 1,000 | 10,000 | ~3-5% per node | ~0.5% |
| 5,000 | 50,000 | ~15-20% per node | ~1% |
| 10,000 | 100,000 | ~30%+ per node | ~2% |
| 50,000 | 500,000 | Kernel OOM possible | ~5-10% |

The crossover point where IPVS clearly wins is **1,000–5,000 Services**.

---

### 11. Debugging with ipvsadm

```bash
# List all virtual services
ipvsadm -L -n

# TCP  10.96.0.42:80 rr
#   -> 10.244.1.5:80         Masq  1      0          0
#   -> 10.244.2.7:80         Masq  1      0          0
#   -> 10.244.3.9:80         Masq  1      0          0

# List with connection info
ipvsadm -L -n --connection

# List a specific virtual service
ipvsadm -L -n -t 10.96.0.42:80

# Show statistics
ipvsadm -L -n --stats
# TCP connections: how many flows went through

# Show rates
ipvsadm -L -n --rate
# InPkt/s, OutPkt/s, InBytes/s, OutBytes/s

# Check the dummy interface
ip addr show kube-ipvs0

# All ClusterIPs should be here
ip addr show kube-ipvs0 | grep inet

# Clear all IPVS rules (dangerous — will break Service routing!)
ipvsadm -C

# Add a rule manually (for testing)
ipvsadm -A -t 10.96.0.99:80 -s rr
ipvsadm -a -t 10.96.0.99:80 -r 10.244.1.5:80 -m

# Check if IPVS kernel module is loaded
lsmod | grep ip_vs
# ip_vs_rr               16384  1
# ip_vs                  147456  6 ip_vs_rr,ip_vs_wrr,ip_vs_sh,ip_vs_lc,ip_vs_dh,ip_vs_sed
```

---

### 12. kube-proxy ConfigMap reference

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-proxy
  namespace: kube-system
data:
  config.conf: |
    apiVersion: kubeproxy.config.k8s.io/v1alpha1
    kind: KubeProxyConfiguration

    # Mode: iptables, ipvs, userspace, nftables (k8s 1.27+)
    mode: "ipvs"

    # ipvs-specific config
    ipvs:
      scheduler: "rr"           # load balancing algorithm
      strictARP: false          # whether to use strict ARP
      excludeCIDRs: []          # CIDRs to exclude from IPVS
      minSyncPeriod: 1s         # minimum time between syncs
      syncPeriod: 15s           # full sync interval
      TCPTimeout: 900s          # TCP connection timeout
      TCPFinTimeout: 15s        # TCP FIN timeout
      UDPTimeout: 300s          # UDP packet timeout

    # iptables config (still used for some things even in IPVS mode)
    iptables:
      masqueradeAll: false
      masqueradeBit: 14
      localIPv4CIDRs: []
      ownerSyncSeconds: 30
      syncPeriod: 15s
      minSyncPeriod: 1s

    # Node port ranges
    nodePortAddresses: null     # or ["10.0.0.0/8"]

    # Logging
    logging:
      format: text              # or json
      verbosity: 2              # 0-4
```

---

### 13. Prerequisites and kernel modules

```bash
# Check if IPVS modules are loaded
lsmod | grep ip_vs
# Should show: ip_vs, ip_vs_rr, ip_vs_wrr, ip_vs_sh, ip_vs_lc, ip_vs_dh, ip_vs_sed, ip_vs_nq

# Load manually
modprobe ip_vs
modprobe ip_vs_rr
modprobe ip_vs_wrr
modprobe ip_vs_sh
modprobe ip_vs_lc
modprobe ip_vs_dh
modprobe ip_vs_sed
modprobe ip_vs_nq

# Most production distros load these automatically when kube-proxy starts
# On some systems (especially container-optimized), you may need to load explicitly

# Check module is available
modinfo ip_vs
```

---

### 14. CNI compatibility

| CNI | Works with IPVS? | Notes |
|-----|-----------------|-------|
| Calico (BGP) | ✅ Yes | Set `strictARP: true` on nodes |
| Calico (eBPF) | ✅ Yes | Calico's eBPF dataplane replaces kube-proxy entirely |
| Cilium | ✅ Yes | Cilium replaces kube-proxy in IPVS mode |
| Flannel | ✅ Yes | |
| Weave | ✅ Yes | |
| AWS VPC CNI | ✅ Yes | EKS uses this by default |
| GKE VPC CNI | ✅ Yes | |

CNIs that **don't need kube-proxy at all**:
- Cilium (replaces kube-proxy entirely with eBPF)
- Calico with eBPF mode

For these, kube-proxy can be disabled entirely, or run in `iptables` mode alongside the CNI's dataplane.

---

### 15. Rollback from IPVS to iptables

```bash
# 1. Edit the ConfigMap
kubectl edit configmap kube-proxy -n kube-system

# Change mode to iptables
mode: iptables

# 2. Restart kube-proxy
kubectl rollout restart daemonset kube-proxy -n kube-system

# 3. Verify
kubectl get pods -n kube-system -l k8s-app=kube-proxy
# Wait for rollout to complete

# 4. Verify IPVS is gone
ipvsadm -L -n
# Should show nothing (or only manually added rules)

# 5. Verify iptables rules are back
iptables -L KUBE-SERVICES -n -v | head -20
```

IPVS rules persist until the next kube-proxy sync or node reboot. The rollback is clean — no disruption.

---

### 16. When to use each mode

| Use case | Mode |
|----------|------|
| < 1,000 Services, simple cluster | iptables (default) |
| > 1,000 Services | IPVS |
| Need deterministic session affinity | IPVS (`sh` or `dh` scheduler) |
| Long-lived connections (gRPC, websockets) | IPVS (`lc` scheduler) |
| Using Cilium or Calico eBPF | eBPF replaces kube-proxy entirely |
| Embedded/home-lab cluster | iptables |
| Multi-tenant with many NodePort services | IPVS |

---

### 17. Gotchas

* **`kube-ipvs0` dummy interface is the key.** If it's missing, ClusterIPs aren't routable. Check with `ip addr show kube-ipvs0`.
* **The iptables rules are mostly empty in IPVS mode.** kube-proxy doesn't install Service rules in iptables — they're in IPVS. `iptables -L KUBE-SERVICES` will be sparse.
* **IPVS uses conntrack.** Don't disable conntrack — it's required for hairpin mode and return traffic handling.
* **The kernel modules must be loaded.** Some container-optimized OS images don't load them by default. Add to `/etc/modules-load.d/` to persist.
* **`strictARP: true` is needed for BGP-mode CNIs.** Without it, nodes may answer ARP for Pod IPs that belong to other nodes.
* **Rolling back to iptables is safe** — but old IPVS rules linger until kube-proxy restarts or syncs. They won't cause conflicts.
* **IPVS doesn't do health checking of backends** — that's still kube-proxy's job. If a Pod becomes unready, kube-proxy removes it from the IPVS real server list.
* **`ipvsadm -C` clears all rules** and will break cluster networking. Never run it in production without a rollback plan.
* **IPVS and IPv6 dual-stack** works, but ensure `nf_conntrack_ipv6` is loaded alongside the IPv4 modules.
* **`scheduler: rr` is the default and rarely wrong.** Changing schedulers is an optimization — measure before changing.

---

## See also

* [[Kubernetes/concepts/L04-services-networking/02-services|Services]] — what IPVS implements
* [[Kubernetes/concepts/L04-services-networking/06-cni|CNI]] — the network layer below
* [[Kubernetes/concepts/L06-scheduling-scaling/02-scheduling|Scheduling]] — how Pods land on nodes
