# IPVS (kube-proxy mode)

*"https://kubernetes.io/docs/reference/networking/virtual-ips/"*

IPVS (IP Virtual Server) is one of the modes **kube-proxy can use to implement Service virtual IPs**. It's a Linux kernel feature that does L4 load balancing more efficiently than iptables for large clusters.

## The problem with iptables

The default kube-proxy mode is **iptables**. For each Service, kube-proxy installs iptables rules that DNAT traffic from the Service ClusterIP to a backend Pod IP. The rules look like:

```
-A KUBE-SERVICES -d 10.96.0.42/32 -p tcp --dport 80 -j KUBE-SVC-XXX
-A KUBE-SVC-XXX -m statistic --mode random --prob 0.333 -j KUBE-SEP-AAA   # backend 1
-A KUBE-SVC-XXX -m statistic --mode random --prob 0.500 -j KUBE-SEP-BBB   # backend 2
-A KUBE-SVC-XXX                              -j KUBE-SEP-CCC            # backend 3
```

These rules work, but:

* **Rules are linear.** Each new Service / endpoint adds a chain. With 10,000 Services, you have 10,000 chains. Each packet traverse walks the entire chain.
* **Updates are O(n).** Adding or removing an endpoint touches many rules. The update happens on the **hot path** — every packet goes through these rules.
* **The kernel's netfilter becomes the bottleneck.** At 100,000+ Services, CPU spent in iptables goes up.
* **Hashing is statistical, not consistent.** Random-with-probability, so the same client may hit different backends for the same connection (no session affinity by default).

## The IPVS approach

IPVS is a Linux kernel L4 load balancer. It uses **hash tables** (not linear chains) to look up virtual services, and supports multiple **scheduling algorithms** (round-robin, least-connection, source-hash, etc.).

```
Service: 10.96.0.42:80
  │
  ▼
IPVS virtual server
  │
  ├─ backend 1: 10.244.1.5:80    weight=1
  ├─ backend 2: 10.244.2.7:80    weight=1
  └─ backend 3: 10.244.3.9:80    weight=1
```

The IPVS implementation is **O(1) lookup** (hash table), supports thousands of virtual services with no measurable CPU cost, and provides better load balancing algorithms.

## How kube-proxy uses IPVS

When kube-proxy is started with `--proxy-mode=ipvs`, it:

1. Creates a **dummy interface** (`kube-ipvs0`) on the node
2. **Binds Service ClusterIPs to the dummy interface** (so the IPs are local)
3. Creates an **IPVS virtual server** for each Service (ClusterIP:Port)
4. Adds the Service's endpoints as **IPVS real servers**
5. Configures the IPVS scheduler (round-robin by default, but configurable)

When a packet arrives at the node destined for the Service ClusterIP, IPVS intercepts it, picks a backend (based on the scheduler), and DNATs the packet to the backend's IP. The packet then goes through the normal Linux networking stack to the Pod.

## Enabling IPVS

```bash
# check the current mode
kubectl get --raw /api/v1/nodes/<node> | jq '.status.nodeInfo.kubeProxyVersion'
# (kube-proxy version)

# on a kubeadm cluster, set the proxy mode in the kubeadm config
# /etc/kubernetes/kubeadm-config.yaml or via init
kubeadm init --skip-phases=... --config=...
# in the config:
# ---
# apiVersion: kubeadm.k8s.io/v1beta3
# kind: InitConfiguration
# ...
# ---
# apiVersion: kubeadm.k8s.io/v1beta3
# kind: ClusterConfiguration
# ...
# networking:
#   proxyMode: ipvs

# for an existing cluster, edit the kube-proxy ConfigMap
kubectl edit configmap kube-proxy -n kube-system
# set:
#   mode: ipvs
# then restart kube-proxy:
kubectl rollout restart daemonset kube-proxy -n kube-system
```

The DaemonSet restarts, and each Pod reconfigures IPVS.

## Prerequisites for IPVS

IPVS requires the kernel modules:

```bash
# check that the modules are loaded
lsmod | grep ip_vs
# ip_vs                 147456  0
# ip_vs_rr               16384  0
# ip_vs_wrr              16384  0
# ip_vs_sh               16384  0
# nf_conntrack           139264  1 ip_vs

# if not loaded, load them
modprobe ip_vs
modprobe ip_vs_rr
modprobe ip_vs_wrr
modprobe ip_vs_sh

# on most distros, these are loaded by default
```

kube-proxy will fall back to iptables if IPVS isn't available, with a log warning.

## IPVS schedulers

kube-proxy can use any IPVS scheduler. Configurable in the kube-proxy ConfigMap:

| Scheduler | Description | Use case |
|---|---|---|
| `rr` (round-robin) | Distribute evenly | Default. Most cases. |
| `wrr` (weighted round-robin) | Distribute by weight | Used with `service.beta.kubernetes.io/aws-load-balancer-type` or similar |
| `lc` (least connection) | Pick the least busy | Long-lived connections |
| `dh` (destination hashing) | Hash destination | Sticky to a backend |
| `sh` (source hashing) | Hash source IP | Sticky to client |
| `sed` (shortest expected delay) | Minimize expected delay | Specialized |
| `nq` (never queue) | Like sed, no queueing | Specialized |

```yaml
# in kube-proxy ConfigMap
data:
  config.conf: |
    apiVersion: kubeproxy.config.k8s.io/v1alpha1
    kind: KubeProxyConfiguration
    mode: ipvs
    ipvs:
      scheduler: rr
      strictARP: false              # if true, only ARP for Service IPs (advanced)
      minSyncPeriod: 1s
      syncPeriod: 15s
```

## When to use IPVS

* **Large clusters** (1000+ Services) — iptables starts to choke
* **Clusters with many endpoints per Service** — IPVS's O(1) lookup shines
* **You need consistent hashing** — IPVS supports `sh` (source-hash) and `dh` (destination-hash), iptables doesn't
* **Latency-sensitive workloads** — IPVS has lower per-packet overhead

## When NOT to use IPVS

* **Small clusters** — iptables is fine, and more familiar
* **You need iptables-specific features** — some CNIs (e.g. Calico with iptables mode) interact with iptables directly; switching to IPVS can break them
* **You're using a userspace iptables implementation** — unusual, but some old CNIs do this
* **The kernel modules aren't available** — and you can't load them

## Comparison: iptables vs IPVS

| | iptables | IPVS |
|---|---|---|
| Lookup | O(n) chain | O(1) hash |
| Algorithms | Random probability | rr, wrr, lc, dh, sh, sed, nq |
| Update cost | High (rewrites chains) | Low (hash table mutation) |
| CPU at scale | High (linear) | Low (constant) |
| Setup | Always works | Needs kernel modules |
| Conntrack | Required | Required |
| Compatibility | Universal | Mostly universal |

## Performance numbers

Rough numbers for a kube-proxy at scale:

| Services | Endpoints | iptables CPU | IPVS CPU |
|---|---|---|---|
| 100 | 1,000 | low | low |
| 1,000 | 10,000 | medium | low |
| 10,000 | 100,000 | high | low-medium |
| 50,000 | 500,000 | very high | medium |

The crossover where IPVS becomes worth it is around 1,000-5,000 Services.

## IPVS and Conntrack

Both iptables and IPVS modes use **conntrack** (the kernel's connection tracker) for:

* Tracking established connections
* Service session affinity (client IP sticky)
* Hairpin NAT (a Pod reaching its own Service ClusterIP)

If you see "conntrack table full" errors, the table is too small for your traffic. Tune:

```bash
# check current size
sysctl net.netfilter.nf_conntrack_max
# typically 262144 by default

# increase
sysctl -w net.netfilter.nf_conntrack_max=1048576
```

## strictARP

The `strictARP` setting (kube-proxy ConfigMap) makes the node **only respond to ARP for Service IPs**, not for Pod IPs. This is needed when you're using BGP for Pod IP advertisement (e.g. Calico's BGP mode) and want to avoid the kernel answering ARP for Pod IPs that aren't on the node.

```yaml
ipvs:
  strictARP: true
```

This is an **advanced setting**. Most clusters don't need it.

## Gotchas

* **IPVS is on the Linux kernel side; iptables is userspace.** With IPVS, kube-proxy installs fewer userspace rules and uses kernel-side IPVS instead. This is good for performance, but debugging requires `ipvsadm` instead of `iptables`.
* **IPVS dummy interface (`kube-ipvs0`) is the local endpoint for ClusterIPs.** If the interface is missing, the ClusterIP isn't routable. Check with `ip addr show kube-ipvs0`.
* **The `iptables-save` output is mostly empty in IPVS mode.** kube-proxy doesn't install Service rules in iptables anymore. If you're looking for "where are my Service rules?", they're in IPVS, not iptables.
* **Some CNIs conflict with IPVS.** Calico with iptables mode, for example, may interact with iptables rules kube-proxy installs. Most modern CNIs (Calico eBPF, Cilium) work fine with IPVS.
* **IPVS uses conntrack.** Tune `nf_conntrack_max` for high-traffic clusters.
* **Rolling back from IPVS to iptables** requires deleting the IPVS rules and re-installing iptables rules. The rollback path is just `kubectl edit configmap kube-proxy` + restart.
* **IPVS scheduler choice matters.** `rr` is fine for most. `lc` for long-lived connections. `sh` for sticky-by-source. Default `rr` is rarely wrong.
* **IPVS doesn't replace kube-proxy.** It's a mode of kube-proxy. The other responsibilities (watching Services, EndpointSlices, etc.) are unchanged.
* **IPVS and IPv6 dual-stack** — works, but verify your kernel modules include IPv6 conntrack (`nf_conntrack_ipv6`).

## How to debug

```bash
# list IPVS virtual services
ipvsadm -L -n
# IP Virtual Server version 1.2.1 (size=4096)
# Prot LocalAddress:Port    Scheduler
#   -> RemoteAddress:Port     Forward Weight ActiveConn InActConn
# TCP  10.96.0.42:80         rr
#   -> 10.244.1.5:80         Masq    1      0          0
#   -> 10.244.2.7:80         Masq    1      0          0
#   -> 10.244.3.9:80         Masq    1      0          0
# TCP  10.96.10.55:443       rr
#   ...

# look at a specific service
ipvsadm -L -n -t 10.96.0.42:80

# look at statistics
ipvsadm -L -n --stats

# look at connection state
ipvsadm -L -n --connection

# reset IPVS (dangerous, will disrupt traffic briefly)
ipvsadm -C
```

## See also

* [[Kubernetes/concepts/L04-services-networking/02-services|Services]] — what IPVS is implementing
* [[Kubernetes/concepts/L04-services-networking/06-cni|CNI]] — the network layer below
