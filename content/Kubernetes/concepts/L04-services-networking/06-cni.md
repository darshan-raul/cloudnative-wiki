# CNI (Container Network Interface)

*"https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/"*

CNI is the **specification and plugin model** that connects Pod networking. Kubernetes doesn't ship a network implementation itself — it delegates to a CNI plugin that you install on every node.

## What the CNI plugin does

When a Pod is scheduled on a node, the kubelet calls the CNI plugin to:

1. **Allocate an IP** for the Pod (from a node pool or cluster-wide)
2. **Create a network namespace** and a virtual interface pair (veth)
3. **Wire the veth** into the node's network (bridge, route, or overlay)
4. **Set up routes** so Pods on different nodes can talk

When the Pod is deleted, the CNI plugin tears it down.

```
┌────────── Node 1 ──────────┐         ┌────────── Node 2 ──────────┐
│                            │         │                            │
│  ┌──── Pod A ─────┐        │         │  ┌──── Pod C ─────┐        │
│  │  eth0 (veth)   │        │         │  │  eth0 (veth)   │        │
│  │  10.0.1.5      │        │         │  │  10.0.2.7      │        │
│  └────────┬───────┘        │         │  └────────┬───────┘        │
│           │                │         │           │                │
│       cbr0 (bridge)        │         │       cbr0 (bridge)        │
│           │                │         │           │                │
│       eth0 (node)          │         │       eth0 (node)          │
└───────────┼────────────────┘         └───────────┼────────────────┘
            │                                      │
            └────  overlay / underlay network  ────┘
```

## Common CNI plugins

| Plugin | Model | Notes |
|---|---|---|
| **Flannel** | Simple overlay (VXLAN/host-gw) | Easy to set up, no NetworkPolicy, no L7 |
| **Calico** | BGP / VXLAN / IPIP | Full NetworkPolicy, scalable, common in production |
| **Cilium** | eBPF-based | NetworkPolicy + L7 (HTTP/gRPC) policies, replaces kube-proxy |
| **Weave Net** | Overlay | Simple, full NetworkPolicy, less common now |
| **AWS VPC CNI** | Native AWS VPC ENIs | Pods get real VPC IPs, no overlay, less IP pressure on the node |
| **Azure CNI** | Native Azure VNet | Same idea as AWS VPC CNI |
| **GKE Dataplane V2** | eBPF, based on Cilium | Default on GKE |

## IP allocation

Two approaches:

### Overlay (Flannel, Calico VXLAN mode)

* Pods get IPs from a **private range** (e.g. `10.244.0.0/16`)
* Packets are encapsulated (VXLAN) to traverse the underlying network
* **No IP pressure on the node network** — you can have 1000s of Pods per node
* MTU overhead from encapsulation (usually 1500 → 1450 or so)

### Native / underlay (AWS VPC CNI, Cilium in chaining mode)

* Pods get **real VPC IPs**
* No encapsulation, full network performance
* **Limited by node IP availability** — a `/24` node subnet can host ~250 Pods (ENI + secondary IPs), or much more with prefix delegation
* AWS EKS lives here by default

## CNI requirements (the k8s model contract)

For k8s to consider the network "valid":

1. **Every Pod gets its own IP** (no NAT between Pods)
2. **Pods on any node can reach any other Pod** without NAT
3. **Agents on a node (kubelet, etc.) can talk to Pods on that node**

These three rules are the "k8s network model". Anything that satisfies them is a valid CNI.

## How the CNI is installed

* **Managed k8s** (EKS, GKE, AKS) — comes pre-installed, you select or it's chosen for you
* **kubeadm / k8s-the-hard-way** — you install it yourself (most often with a DaemonSet, like Calico)
* **k3s, k0s** — comes bundled with a default CNI

You can't change a CNI in place — switching from Flannel to Calico usually means a cluster rebuild or careful migration.

## Gotchas

* **The CNI you choose shapes what you can do.** Flannel = no NetworkPolicy. Calico/Cilium = full policy. AWS VPC CNI = real VPC IPs but IP accounting.
* **MTU matters on overlay networks.** A Pod sending 1500-byte packets over VXLAN gets fragmentation. Set the Pod's `interface MTU` correctly or live with the perf cost.
* **CNI choice is a one-way door.** Migrating CNIs is non-trivial — Pod IPs change, routes change, all networking has to be redone.
* **Dual-stack (IPv4 + IPv6) requires a CNI that supports it** and cluster config (`--feature-gates=IPv6DualStack=true` on the apiserver, and `--node-ip` from both families). Calico, Cilium, and Antrea all support it.
* **NetworkPolicy enforcement depends on the CNI.** If your CNI doesn't support it, the resource is a no-op (no error). This is a footgun.
* **Cilium replaces kube-proxy** in some configurations — it implements the Service virtual IP / iptables rules in eBPF. You get huge scale and L7 features, but it changes the operational model.
* **MTU discovery** is hard. If you have weird connectivity issues between Pods and not from Pods, check `ip route` and MTU.
