# Kubernetes Networking — Deep Dive

A comprehensive technical guide to networking in Kubernetes — from the three independent IP spaces, through pod network namespaces, veth pairs, CNI plugins, kube-proxy, CoreDNS, and Ingress. Written as detailed explanatory prose to accompany the interactive visualization at `k8s-networking.html`.

---

# Part 1: The Three Independent IP Ranges

Every Kubernetes cluster requires the operator to plan and configure **three completely separate, non-overlapping IP address ranges**. This is one of the most commonly misunderstood aspects of k8s networking, and getting it wrong causes subtle, hard-to-debug connectivity failures.

## 1.1 Why Three Separate Ranges?

The fundamental guarantee Kubernetes makes is that **every pod can communicate with every other pod directly, without NAT, anywhere in the cluster**. To make this possible across heterogeneous infrastructure (cloud VMs, bare metal, on-prem) and across network boundaries, Kubernetes deliberately keeps three distinct IP spaces that serve different purposes and are managed by different components.

These three ranges must not overlap. If the pod CIDR overlaps with the node network, or the service CIDR overlaps with either, packets will be misrouted and connectivity will fail in ways that are difficult to diagnose because the symptoms appear unrelated to IP planning.

## 1.2 The Node Network (Host IPs)

The **node network** is the physical (or virtual) network that the Kubernetes nodes themselves use for communication. This is the network your nodes get their IP addresses from — typically via DHCP or static assignment by your infrastructure team.

This network handles:
- Node-to-node communication (control plane to worker, etcd traffic)
- Node-to-API-server communication
- Node-to-external-storage communication
- Any traffic that originates or terminates outside the cluster

Examples:
- AWS VPC subnet: `10.0.0.0/24` — nodes get IPs like `10.0.0.10`, `10.0.0.11`
- On-prem: `192.168.1.0/24`
- GCE: `10.142.0.0/20`

Nodes use these IPs for their control plane communication. The API server listens on a port (default 6443) bound to the node's IP (or a dedicated control plane network interface). kubelet communicates with the API server using the node's IP. etcd cluster members communicate using node IPs on the node network.

**Critical constraint**: Nodes must be able to reach each other on this network for the cluster to function. If nodes are on overlapping or misconfigured subnets, the control plane components won't be able to communicate.

## 1.3 The Pod CIDR (CNI IP Space)

The **pod CIDR** is the IP range from which pod IP addresses are allocated. This is the range you specify when initializing the cluster with kubeadm (`--pod-network-cidr`) or when configuring your CNI plugin.

Each **node** receives a **subnet** carved out of the cluster-wide pod CIDR. For example, with a cluster pod CIDR of `10.244.0.0/16`:
- Node A receives `10.244.0.0/24` (256 pod IPs: `10.244.0.1` through `10.244.0.254`)
- Node B receives `10.244.1.0/24`
- Node C receives `10.244.2.0/24`

The CNI plugin is responsible for carving up the cluster CIDR into per-node subnets and tracking which IPs are in use on each node. This prevents two pods on different nodes from getting the same IP — a problem that would cause traffic to be delivered to the wrong pod.

Pods get their IP from this range when they are scheduled. The IP is assigned by the CNI plugin's IPAM (IP Address Management) component during the `CNI ADD` call.

**Critical constraint**: The pod CIDR must not overlap with the node network or the service CIDR. Many misconfigurations happen when a cloud VPC already uses `10.0.0.0/8` and the operator picks `10.0.0.0/16` as the pod CIDR, not realizing it overlaps with the VPC's addressing.

## 1.4 The Service CIDR (Virtual Cluster IPs)

The **service CIDR** is the IP range from which Kubernetes **Services** get their virtual ClusterIP addresses. This range is configured via the kube-apiserver flag `--service-cluster-ip-range` (default: `10.96.0.0/12`).

**Crucially, service IPs are purely virtual.** No network interface in the cluster ever has a service IP. There is no device with address `10.96.0.1` — instead, the kube-proxy running on every node creates iptables (or IPVS) rules that intercept traffic destined for `10.96.0.1` and redirect it to the backing pods. The service IP exists only as a rule in the kernel's netfilter tables.

When you create a Service with the default ClusterIP type:
1. The API server picks the next available IP from the service CIDR
2. It stores that mapping in etcd
3. Every node's kube-proxy sees the update and programs rules
4. Traffic to that IP hits kube-proxy's interception and gets DNAT'd to a backing pod

The first IP in the service CIDR is always reserved — `10.96.0.1` by default resolves to `kubernetes.default.svc.cluster.local`, the service that exposes the API server itself. You cannot assign a Service ClusterIP of `10.96.0.1` to any other service.

**Key insight**: Because service IPs are purely virtual and managed entirely by iptables/IPVS, you can use almost any IP in the service CIDR, even IPs that are unreachable on the physical network. This is very different from pod IPs, which need to be routable within the cluster's overlay. The service CIDR just needs to be non-overlapping with the other two ranges — it doesn't need to be reachable from anywhere.

## 1.5 Non-Overlapping Requirement and CIDR Planning

When planning a cluster, you must choose three non-overlapping CIDR ranges. Here's a common and correct example:

| Range | Example | Size | Used For |
|-------|---------|------|----------|
| Node Network | `192.168.1.0/24` | 254 nodes max | Physical/Virtual machine IPs |
| Pod CIDR | `10.244.0.0/16` | 65,536 pods | Container IPs via CNI |
| Service CIDR | `10.96.0.0/12` | 65,536 services | Virtual service IPs |

The three ranges are completely independent:
- `192.168.1.0/24` lives on physical network interfaces — nodes use these IPs for external communication
- `10.244.0.0/16` lives inside the cluster's CNI overlay — pod IPs exist only within k8s
- `10.96.0.0/12` exists only as iptables rules on each node

**Common mistake**: Operators sometimes pick a node network like `10.0.0.0/8` (common in AWS VPCs) and then accidentally use `10.0.0.0/16` as the pod CIDR. The result is that node IPs and pod IPs overlap, causing routing confusion.

You can verify a node's IP with `kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'` and check the configured CIDRs on each kubelet.

---

# Part 2: Pod as Network Namespace

## 2.1 Linux Network Namespaces

A **network namespace** is a Linux kernel feature that provides an isolated view of the network stack. A network namespace has its own:
- Network interfaces (eth0, lo, veth pairs)
- Routing tables
- ARP tables
- Firewall rules (iptables)
- `/proc/sys/net` settings

Linux creates one network namespace per pod in Kubernetes. Every container inside the pod shares that namespace. This is fundamentally different from Docker's default behavior where each container has its own network namespace — in k8s, containers within a pod co-own a single namespace.

You can explore network namespaces on a node with:
```bash
# List all network namespaces on the host
ip netns list

# Show interfaces inside a pod's namespace (using the pod's PID)
nsenter -t <pod-pid> --net ip addr
nsenter -t <pod-pid> --net ip route
```

## 2.2 The Pause Container (Sandbox Container)

When kubelet creates a pod, the first thing it does is create a **pause container**. The pause container (also called the sandbox container) is a tiny, static image (`k8s.gcr.io/pause:3.x`, less than 1MB) whose only purpose is to hold the network namespace.

The pause container:
1. Starts with a new network namespace (created by the container runtime, typically containerd or CRI-O)
2. Runs a single `pause` process that simply blocks forever
3. Holds the network namespace open as long as the pod exists
4. Does essentially nothing else — no application code runs in it

**Why does this matter?** Because containers in a pod can crash and restart without the network namespace being destroyed. If you had no pause container and your nginx container crashed, the network namespace would be reclaimed and the pod's IP would be lost. With the pause container holding the namespace, the IP persists across container restarts — the pause container itself never restarts (it's designed to be immortal).

All application containers in the pod share the network namespace that the pause container owns. This means:
- Container A and Container B both see `eth0` as the same interface (pointing to the pod's veth pair on the host)
- Both containers share the same IP address
- Both containers share the same port space (nginx on port 80 and redis on port 6379 can coexist without conflict because there's only one network namespace)
- Both containers share the same `lo` (loopback) interface, so `localhost` resolves to the same stack within the pod

## 2.3 Shared Network Stack

Within a pod, all containers share the network namespace. This has practical implications:

**Loopback is shared**: The `lo` interface inside the pod is shared. A request to `127.0.0.1:8080` by Container A can be received by Container B if Container B is listening on port 8080. This enables patterns like a sidecar proxy handling traffic for the main application container.

**Port conflicts are impossible (within a pod)**: If you want nginx to serve port 80 and your sidecar to also bind port 80, they can do so inside the pod — because they share the same network namespace. If you tried this in separate pods, one would fail to start because port 80 would already be taken.

**Signals are shared**: When kubelet sends SIGTERM to terminate a pod, the signal is delivered to the pause container's main process, which then propagates it to all child processes (the application containers). This ensures graceful shutdown of all containers in a pod simultaneously.

**DNS configuration is shared**: The pod's `/etc/resolv.conf`, `hostname`, and DNS settings are shared across all containers. The kubelet generates `/etc/resolv.conf` once (for the pause container's namespace) and all containers in the pod see the same file.

## 2.4 Pod Networking Lifecycle (kubelet → CRI → CNI)

The complete flow from pod creation to network setup involves three distinct layers working together:

1. **kubelet** decides to create a pod → calls the **CRI** (Container Runtime Interface) to create containers
2. **CRI** (containerd, CRI-O) creates the pause container first, which creates and holds the network namespace
3. **kubelet** receives the pause container's handle (including the network namespace path) → calls the **CNI** plugin to configure networking
4. **CNI** runs `ADD` with the container ID, network namespace path, and interface name → configures veth pairs, bridge, routes → returns the pod's IP
5. **kubelet** stores the pod IP in pod status, and the pod is considered ready

The CRI interface (defined in `runtime/v1alpha2.proto` and later versions) uses the concept of a **PodSandbox** — an abstract representation of the pause container and its network namespace. CNI operates on the sandbox's network namespace path.

On pod deletion:
1. kubelet calls CNI `DEL` with the container ID
2. CNI removes the veth pair, releases the IP back to IPAM
3. CRI removes the pause container and its network namespace

---

# Part 3: veth Pairs & The Linux Bridge

## 3.1 Virtual Ethernet Pairs (veth)

A **veth pair** is a virtual ethernet cable — two virtual network interfaces connected to each other. Anything written to one end appears at the other end, exactly like a physical cable connecting two devices. In Linux, you create one with:

```bash
ip link add veth0 type veth peer name veth1
```

In Kubernetes networking, every pod gets one veth pair:
- **Pod side** (inside the pod's network namespace): renamed to `eth0` — the pod's primary network interface
- **Host side** (on the node): kept as `veth{unique-id}` (e.g., `veth-abc123`, `cali123456`)

The pod has no visibility into the host-side name. Inside the pod, the interface is always called `eth0` — this is a CNI convention that all plugins follow. The host-side naming varies by plugin (bridge plugin uses `veth{hash}`, calico uses `cali{hash}`, etc.).

When a packet leaves the pod via `eth0`, it enters the host-side veth. When a packet is sent into the host-side veth, it appears at the pod's `eth0`.

## 3.2 The CNI Bridge (cni0)

The **bridge** is a software switch running in the Linux kernel. When using the bridge CNI plugin (or when the bridge is the first-hop for an overlay), the host-side veth of every pod plugs into a bridge called `cni0`.

```bash
# Attach host-side veth to the bridge
ip link set veth-abc123 master cni0

# The bridge itself
ip link show cni0
# cni0: <BROADCAST,MULTICAST,UP> mtu 1400 qdisc noqueue master docker0 state UP
```

The bridge functions as a learning switch:
- It maintains a **MAC address table** mapping MAC addresses to bridge ports
- When it receives a frame, it looks up the destination MAC
- If the MAC is known → forwards to the corresponding port
- If unknown → floods to all ports (except source)

You can inspect the MAC table with `bridge fdb show`.

The bridge also acts as the gateway for pods. When a pod tries to reach an IP outside its local subnet, it sends the packet to its gateway (the bridge), which then routes appropriately based on the host's routing table.

## 3.3 Same-Node Packet Flow

When Pod A (on Node 1) sends a packet to Pod B (also on Node 1), here's exactly what happens:

```
Pod A (10.244.0.2)
  └─> eth0 (inside pod A's netns)
      └─> exits via veth pair (host side: veth-xxx)
          └─> arrives at cni0 bridge
              └─> Bridge looks up MAC of 10.244.0.3 (Pod B)
                  └─> MAC found on port 3 (veth-yyy)
                      └─> forwards frame to veth-yyy
                          └─> enters Pod B's netns via eth0
```

Step by step:

1. **Inside Pod A's namespace**: Pod A wants to send to `10.244.0.3`. The routing table says `10.244.0.0/24` is directly reachable via `eth0`. Pod A's kernel ARPs for `10.244.0.3` (asking "who has this IP?").

2. **Bridge receives the ARP**: The bridge has ports for both veth-xxx (Pod A) and veth-yyy (Pod B). It broadcasts the ARP to all ports except the source.

3. **Pod B's veth responds**: "I have `10.244.0.3`, here's my MAC." The bridge records this MAC mapping.

4. **Frame is forwarded**: Pod A's kernel sends the actual data frame. The bridge looks up the destination MAC, finds it on port 3, and forwards the frame to veth-yyy.

5. **Delivery**: The frame appears inside Pod B's namespace at `eth0`. Pod B's kernel processes it.

The key insight: all of this happens in the kernel — no userspace context switches, no encapsulation. This is why same-node pod-to-pod networking has very low overhead.

## 3.4 ARP Resolution and MAC Learning

The bridge's MAC learning is what makes this efficient. On first boot of the bridge, the MAC table is empty. As packets flow and ARPs are resolved, the bridge learns which MAC addresses are on which ports.

If a MAC address hasn't been learned, the bridge floods the frame to all ports (flooding). Once learned, frames are forwarded only to the correct port. MAC entries expire after a timeout (typically 5 minutes) and are refreshed on traffic.

This means the first packet between two pods always has slightly higher latency (flooding + learning), but subsequent packets are directly forwarded.

## 3.5 External Traffic and Masquerading

When a pod sends traffic to an IP **outside** the cluster's pod CIDR (e.g., to `8.8.8.8`), the bridge doesn't have that IP in its table. The bridge forwards it to the bridge's parent interface (the node's physical interface), which then uses the host's default route.

However, the return traffic needs to find its way back. Because the pod IP is not routable on the physical network, the host performs **Source NAT (masquerading)** — it replaces the pod's source IP with the node's IP for outbound traffic, and then tracks the connection so return traffic can be DNAT'd back to the original pod.

```
Pod A (10.244.0.2) → wants to reach 8.8.8.8
  └─> Packet: src=10.244.0.2, dst=8.8.8.8
      └─> Node's iptables performs SNAT → src becomes NODE_IP
          └─> Packet leaves node: src=NODE_IP, dst=8.8.8.8
              └─> Response returns to NODE_IP
                  └─> iptables tracks connection, DNAT's back to 10.244.0.2
```

This is why pods can reach the internet, but external systems cannot initiate connections to pods directly (they don't know the pod IP).

---

# Part 4: CNI — The Plugin Interface

## 4.1 CNI Specification

The **Container Network Interface (CNI)** is a specification and a set of libraries for configuring network interfaces in containers. It was developed by CoreOS (now Red Hat) and is maintained by the CNCF. The specification defines how a container runtime should interact with a network plugin to set up and tear down networking for containers.

The key design goal of CNI is **plugin interoperability**: any CNI plugin can work with any CNI-compliant container runtime. This means you can swap flannel for calico without changing anything in the container runtime or in your pod specifications.

The specification defines:
- A JSON schema for network configuration files
- A set of operations: ADD, DEL, CHECK, VERSION
- The contract between the container runtime (caller) and the CNI plugin (callee)

Reference implementations exist in `github.com/containernetworking/cni`. Kubernetes uses the CNI specification to integrate with network plugins.

## 4.2 CNI Operations

The CNI plugin must implement four operations:

**ADD (CNI_ADD)**: Called when kubelet needs to set up networking for a container. Kubelet passes:
- `container_id`: unique identifier for the container
- `netns`: filesystem path to the container's network namespace (e.g., `/var/run/netns/cni-xxxx`)
- `ifname`: the interface name to create inside the container (always `eth0` by convention)
- `network_name`: which network from the CNI config to use

The plugin should:
1. Read the network configuration from `/etc/cni/net.d/`
2. Allocate an IP address (using its IPAM)
3. Set up the veth pair (one end inside netns as `ifname`, one on host)
4. Configure routes inside the container
5. Return the assigned IP, gateway, and any DNS configuration to kubelet

**DEL (CNI_DEL)**: Called when a container is being deleted. The plugin should:
1. Remove the veth pair
2. Release the IP address back to the IPAM pool
3. Clean up any routes or rules it created

**CHECK (CNI_CHECK)**: Called to verify that the network is still correctly configured. Added in CNI v0.4.0. This is important for detecting configuration drift or stale rules.

**VERSION (CNI_VERSION)**: Returns the plugin's supported CNI spec versions.

## 4.3 CNI Configuration Files

CNI configuration files live in `/etc/cni/net.d/`. Multiple plugins can be installed; kubelet reads all files in alphabetical order and uses the configuration from the first plugin that successfully provides a network configuration.

```bash
# Example: flannel stores its config here
ls /etc/cni/net.d/
# 10-containerd-net.conflist  (containerd's CNI config, uses flannel as backend)
# 100-cilium.conflist         (cilium CNI config)
# 99-loopback.conflist        (loopback plugin — does nothing, always last)
```

The configuration file format is typically JSON (`.conflist` for plugins that support network lists, `.conf` for basic plugins). The file specifies:
- The plugin binary to invoke
- The plugin's configuration options (e.g., bridge name, CNI subnet, IPAM settings)

## 4.4 CNI Plugin Types

CNI plugins can be categorized by their function:

**Bridge Plugin**: Creates a Linux bridge (`cni0`) on the host and plugs one end of a veth pair into it. The other end is moved into the container's namespace as `eth0`. Sets up routes so the bridge is the default gateway. Most basic plugin, works everywhere.

**host-device Plugin**: Moves an existing physical device (e.g., `eth0` of the host) into the container's namespace. Used for SR-IOV or DPDK scenarios where containers get direct access to hardware.

**vlan Plugin**: Creates a VLAN sub-interface on the host and moves it into the container. Allows network isolation at layer 2 (like a separate broadcast domain).

**ipvlan Plugin**: Creates an ipvlan interface inside the container that shares the same MAC address as the host's interface but has its own IP addressing. Unlike macvlan, ipvlan operates at layer 2 (L2 mode) or layer 3 (L3 mode) without creating a new MAC address. Lower overhead than veth but less flexibility.

**macvlan Plugin**: Creates a virtual MAC address for each pod, making the pod appear as a physical device on the network. The pod's MAC is distinct from the host's MAC. High performance but requires the network infrastructure to allow MAC spoofing.

**ptp (Point-to-Point) Plugin**: Creates a veth pair but doesn't attach either end to a bridge. Instead, it sets up routes so one end can reach the other. Simpler than bridge, but only useful for specific topologies.

**portmap Plugin**: Sets up port mappings (hostPort). Achieves this by adding iptables DNAT rules that forward traffic from a host port to the container's IP:port.

**bandwidth Plugin**: Enforces traffic shaping using Linux `tc` (traffic control). Works by creating `htb` (hierarchical token bucket) qdiscs and classes on the veth interface.

**tuning Plugin**: Adjusts sysctl parameters (e.g., `net.ipv4.conf.eth0.forwarding`) on the container's interface after it's created.

**sbr (Source-Based Routing) Plugin**: Configures source-based routing so return traffic uses the same interface the request arrived on. Used for complex routing scenarios.

## 4.5 Full CNI Solutions

The plugins above are building blocks. Full CNI solutions combine one or more of these with their own IPAM, overlay encapsulation, and policy enforcement:

**Flannel**: Simple and widely used. Backend can be:
- `vxlan`: uses VXLAN encapsulation to tunnel pod traffic between nodes. Works everywhere (doesn't require L2 adjacency). Performance: moderate (kernel-level, but UDP overhead).
- `host-gw`: directly routes traffic by setting up a per-node subnet. No encapsulation. Requires nodes to be layer-2 adjacent or have BGP. Highest performance.
- `wireguard`: encrypted tunnel (alpha as of recent versions).

**Calico**: Powerful and flexible. Modes:
- **BGP mode** (calico node): no encapsulation. Nodes exchange routes via BGP. Pods are reachable via node IPs, with routes for pod CIDRs. Highest performance, but requires nodes be reachable (L2 or BGP-peered).
- **IPIP mode**: encapsulates pod traffic in IP-in-IP tunnels. Single mode (IPIP only) or double mode (IPIP + BGP fallback). Works over any network.
- **eBPF mode** ( Cilium backend): attaches eBPF programs to kernel hooks for very high performance, bypassing iptables entirely. Cilium is the reference implementation.

**Cilium**: eBPF-native. Attaches eBPF programs to network interface hooks, allowing per-pod enforcement of network policy, transparent encryption (WireGuard), and observability without iptables overhead. Hubble provides built-in flow visualization.

**Antrea**: Built on Open vSwitch (OVS). Supports VXLAN and Geneve encapsulation. Integrates with NSX-T. Good for hybrid-cloud scenarios.

**Weave**: Mesh networking. Each node forms encrypted connections to peers (sleeve mode: UDP encapsulation, fastdp mode: kernel WireGuard). Self-healing topology.

**Multus**: Meta-plugin. Chains multiple CNI plugins so a pod can have multiple network interfaces. Useful for pods that need both a primary network and an out-of-band storage/network interface.

## 4.6 CNI Config JSON Example

Here's a typical bridge plugin configuration:

```json
{
  "cniVersion": "0.4.0",
  "name": "k8s-pod-network",
  "type": "bridge",
  "bridge": "cni0",
  "isGateway": true,
  "isDefaultGateway": true,
  "ipMasq": true,
  "mtu": 1400,
  "ipam": {
    "type": "host-local",
    "subnet": "10.244.0.0/16",
    "routes": [
      { "dst": "0.0.0.0/0" }
    ]
  }
}
```

Breaking this down:
- `cniVersion`: which CNI spec version this config uses
- `name`: arbitrary name for this network (kubelet can reference it from `k8s.v1.cni.cncf.io/networks` annotation)
- `type`: which binary to invoke (`bridge`)
- `bridge`: the bridge device name to use (`cni0`)
- `isGateway`: whether the bridge should be assigned an IP and serve as the gateway
- `ipMasq`: whether to masquerade (SNAT) outbound traffic that goes through this bridge (prevents pod IPs from leaking onto the physical network)
- `mtu`: set MTU on the bridge (usually 1400 for VXLAN overhead accommodation)
- `ipam`: which IPAM plugin to use and its configuration

---

# Part 5: CNI IPAM — IP Address Management

## 5.1 What IPAM Does

IPAM (IP Address Management) is the component within a CNI plugin responsible for **allocating** IP addresses to containers and **tracking** which IPs are currently in use so they aren't double-assigned. When a pod is created, the CNI plugin asks its IPAM for an IP. When a pod is deleted, the IP is returned to the IPAM pool.

IPAM is pluggable — different plugins use different strategies:
- **host-local**: allocates from a per-node file-based pool
- **DHCP**: requests IPs from an external DHCP server
- **static**: manually assigned, no dynamic allocation
- **whereabouts**: a CNI IPAM plugin that supports multi-node clusters without a central server (uses CRDs in Kubernetes)

The IPAM plugin used must match the CNI plugin. You cannot use the calico IPAM with the flannel plugin, for example, because each IPAM stores state in a format that only its corresponding CNI plugin understands.

## 5.2 host-local IPAM

The **host-local** IPAM is the default IPAM for the bridge plugin and is the simplest to understand. It works entirely on the local node, storing its state in the filesystem.

State is stored in `/var/lib/cni/networks/`. For each subnet the node manages, there's a directory:

```bash
ls /var/lib/cni/networks/
# 10.244.0.0_24  10.244.1.0_24
```

Inside each directory, there's one file per allocated IP, named by the IP address:

```bash
ls /var/lib/cni/networks/10.244.0.0_24/
# 10.244.0.2  10.244.0.3  10.244.0.4  10.244.0.5  ...
```

Each file contains the container ID (the CNI container ID passed during ADD) — this is how host-local knows who owns which IP. When CNI DEL is called, it reads the container ID from the file to confirm it matches before releasing the IP.

**On node reboot**: All state is preserved on disk, so IPs survive kubelet restarts. When containerd restarts, it reconnects to the same pods and the CNI state is still valid.

**On IP exhaustion**: If a node runs out of IPs in its subnet (e.g., all 256 IPs in a /24 are used), new pods cannot be scheduled to that node until some IPs are released. This is why choosing the right per-node subnet size matters.

## 5.3 Node Subnet Allocation

When a cluster is initialized, the **cluster-wide pod CIDR** (e.g., `10.244.0.0/16`) is split into per-node subnets. How this happens depends on the CNI plugin:

**Flannel**: The flannel daemon (running as a DaemonSet) reads the node's pod CIDR from the node spec (`node.spec.podCIDR`) and writes it to `/run/flannel/subnet.env`. The flannel CNI plugin reads this file to know which subnet to manage.

**Calico**: Calico's CNI plugin uses the node's `podCIDR` annotation set by the IPAM plugin (calico-node). Calico's IPAM carves up the cluster CIDR and distributes ranges to nodes, storing state in etcd (not local files).

**Manual**: With the raw bridge plugin, you configure each node's subnet explicitly in the CNI config, or use a tool like `host-local` that reads `node.spec.podCIDR` from the Kubernetes API.

The node subnet size is typically a `/24` (256 IPs), which is enough for most nodes. Some operators use `/25` or `/26` for very large clusters to fit more nodes into the CIDR space, but this reduces the number of pods per node.

## 5.4 IP Allocation Flow on Pod Create

Here's the complete sequence when a pod gets an IP:

1. **Scheduler** places the pod on Node A
2. **kubelet** calls the container runtime (containerd) to create the pause container
3. **containerd** creates the pause container and its network namespace, reports back to kubelet with the container ID and namespace path
4. **kubelet** constructs a CNI configuration and calls the CNI plugin's `ADD` operation with:
   - `container_id`: e.g., `9b9b4b8b4b4b`
   - `netns`: e.g., `/var/run/netns/cni-9b9b4b8b`
   - `ifname`: `eth0`
5. **CNI plugin** (bridge) receives the ADD call
6. **bridge plugin** asks its IPAM (host-local) to allocate an IP from Node A's subnet (`10.244.0.0/24`)
7. **host-local IPAM**:
   - Reads the list of already-allocated IPs from `/var/lib/cni/networks/10.244.0.0_24/`
   - Picks the first available IP (`.2`, if `.2` is not in the directory)
   - Writes `container_id` to a file named `10.244.0.2`
   - Returns `{ ip: "10.244.0.2", gateway: "10.244.0.1" }`
8. **bridge plugin**:
   - Creates a veth pair (`veth-xxx` on host, `eth0` in netns)
   - Moves the host end to the bridge (`ip link set veth-xxx master cni0`)
   - Assigns the gateway IP (`10.244.0.1`) to the bridge interface
   - Sets `eth0` inside the container to `10.244.0.2` with mask `/24`
   - Adds a default route via the gateway
   - Writes state so DEL knows what to clean up
9. **bridge plugin** returns to kubelet with the assigned IP, gateway, routes, and DNS config
10. **kubelet** stores the pod's IP in `pod.status.podIP`, and the pod is marked as having an IP assigned

The entire process takes tens of milliseconds on a typical node. The bottleneck is usually the kernel calls for network namespace manipulation and veth pair creation.

---

# Part 6: Multi-Node Networking — Overlay

## 6.1 Why Overlay Is Needed

Pod IP addresses are not assigned to physical network interfaces on the nodes — they're assigned to veth pairs inside the node's kernel. The physical network the nodes run on knows nothing about pod IP addresses. When a packet from Pod A (on Node 1) needs to reach Pod B (on Node 2), the physical network can't deliver it because it doesn't know how to route `10.244.1.3` (Pod B's IP, from the `10.244.0.0/16` range) to Node 2's physical interface.

The **overlay** solves this by encapsulating packets. Before a pod packet leaves its node, it's wrapped in an outer packet with the **node's physical IP** as the source and destination. The physical network sees only the outer IP (node-to-node communication) and delivers it to Node 2. Node 2 then decapsulates and delivers the inner packet to Pod B.

This means the overlay is effectively a **virtual network on top of the physical network**. Pods communicate as if every other pod is on the same switch (which is why k8s calls it a "flat network") — even when they're on opposite sides of the data center, in different availability zones, or on different physical hosts.

## 6.2 VXLAN (Virtual Extensible LAN)

**VXLAN** is the most common overlay protocol used in Kubernetes. It's a UDP-based encapsulation protocol (port 4789) that creates virtual layer 2 networks on top of layer 3 infrastructure.

Key concepts:
- **VTEP** (VXLAN Tunnel Endpoint): the component that encapsulates and decapsulates packets. In k8s, the VTEP runs on each node (part of the CNI plugin's network stack).
- **VNI** (VXLAN Network Identifier): a 24-bit identifier (16 million possible values) that distinguishes one VXLAN virtual network from another. Most k8s CNI plugins use VNI 1 for the default network.
- **UDP 4789**: the destination port for VXLAN packets. Firewalls must allow this port between nodes.

VXLAN works by:
1. **Encapsulation**: When Node 1 needs to send a packet to Pod B on Node 2, it wraps the original packet (src=pod IP, dst=pod IP) inside a new VXLAN header (with VNI) and a UDP/IP header (src=Node1 IP, dst=Node2 IP).
2. **Transport**: The outer packet travels over the physical network using normal IP routing. Any IP router between Node 1 and Node 2 can forward it — they only see the outer IP, not the pod IPs inside.
3. **Decapsulation**: Node 2 receives the VXLAN packet, strips the outer headers, and delivers the original pod packet to Pod B.

The VNI allows multiple virtual networks to coexist on the same physical infrastructure — useful for multi-tenancy or isolating different clusters.

## 6.3 Cross-Node Packet Journey (Pod A → Pod B, different nodes)

Let's trace a packet from Pod A (10.244.0.2 on Node 1) to Pod B (10.244.1.3 on Node 2):

```
Step 1: Pod A sends to Pod B's IP (10.244.1.3)
   Pod A's kernel: routing decision — 10.244.1.0/24 not local → use default gateway

Step 2: Packet reaches the bridge (cni0)
   Bridge knows 10.244.1.3 is not on its local ports
   Bridge forwards to the node's routing table

Step 3: Node 1's routing table
   ip route show | grep 10.244.1
   # 10.244.1.0/24 via <VTEP for Node 2> dev flannel.1
   # or via cni0 if using host-gw mode

Step 4: VTEP encapsulation (if VXLAN)
   VTEP on Node 1 wraps the packet:
     Outer: src=NODE1_IP, dst=NODE2_IP, protocol=UDP, dport=4789
     Inner: src=10.244.0.2, dst=10.244.1.3, protocol=TCP

Step 5: Packet travels over physical network
   Routed hop-by-hop using NODE IPs only
   No node knows about pod IPs — only outer header matters

Step 6: Node 2 receives the VXLAN packet
   VTEP on Node 2 sees it's a VXLAN packet (UDP 4789)
   VTEP decapsulates: strips outer UDP/IP header
   VTEP recovers the original pod packet (src=10.244.0.2, dst=10.244.1.3)

Step 7: Node 2 delivers to Pod B
   Packet enters cni0 bridge on Node 2
   Bridge forwards to veth pair for Pod B
   Delivered to Pod B's eth0
```

The key insight is that the overlay makes the physical network irrelevant to pod-to-pod communication. Nodes just need to be able to reach each other's IPs (the node network). The overlay handles everything else.

## 6.4 Flannel Modes

Flannel supports several backends, selectable at cluster setup time:

**VXLAN backend** (`--backend-type=vxlan`):
- Encapsulates pod traffic in VXLAN packets
- Works over any network infrastructure
- Performance: moderate (kernel-level VXLAN is efficient, but UDP encapsulation adds overhead)
- Use case: general purpose, works in cloud and on-prem

**host-gw backend** (`--backend-type=host-gw`):
- No encapsulation — directly routes traffic using the physical network
- Requires nodes to be on the same L2 broadcast domain (or have BGP peering)
- Performance: best — pure L3 routing, no encapsulation overhead
- Use case: performance-critical workloads on flat networks, bare metal

**wireguard backend** (`--backend-type=wireguard`, alpha):
- Encrypted tunnel using WireGuard
- Performance: very good (WireGuard is highly optimized)
- Use case: security-sensitive workloads requiring in-transit encryption

## 6.5 Calico Modes

Calico is more flexible than Flannel, offering several modes:

**BGP mode** (no encapsulation):
- Nodes run a BGP daemon (bird) that announces pod CIDR routes to peers
- Other nodes install these routes in their kernel routing tables
- Pod traffic goes over the physical network using pod IPs as source/destination
- Highest performance (no encapsulation), but requires BGP-capable network infrastructure or dedicated BGP peering between nodes
- Doesn't work across NAT or over the internet

**IPIP mode**:
- Encapsulates pod traffic inside IP-in-IP tunnels (protocol 4)
- Works over any network (nodes just need IP reachability)
- Single mode: always uses IPIP
- Double mode: falls back to IPIP when BGP peering fails
- Lower overhead than VXLAN (IP header only, no UDP), but still encapsulation

**eBPF mode** (via Cilium):
- Uses eBPF programs attached to network interfaces
- Can implement encapsulation (VXLAN) or direct routing (no encapsulation)
- Bypasses iptables for routing and policy enforcement
- WireGuard encryption support
- Highest performance and best observability
- Cilium is the reference implementation; Calico's eBPF mode shares some infrastructure

## 6.6 Cilium

Cilium is the reference implementation for eBPF-based networking in Kubernetes. Rather than using iptables rules or overlay tunnels, Cilium attaches **eBPF programs** directly to kernel hooks on network interfaces (including `eth0`, `cilium_host`, veth pairs, etc.).

When a packet arrives:
1. The kernel passes it through eBPF programs
2. Cilium's eBPF program can inspect, modify, redirect, or drop the packet
3. Policy enforcement happens at the kernel level — no userspace context switch

Benefits:
- **Performance**: No iptables chain traversal, no userspace encapsulation. Packets are processed in the kernel.
- **Observability**: Hubble provides per-pod flow visualization without sidecars or service meshes
- **Security**: Per-pod network policy enforcement at L7 in some cases, not just L3/L4
- **Encryption**: WireGuard integration for transparent pod-to-pod encryption
- **Scalability**: Doesn't degrade as cluster size grows (no iptables scaling issues)

Cilium can operate in:
- **Overlay mode** (VXLAN or Geneve): encapsulation, works anywhere
- **Native routing mode** (no encapsulation): direct routing, requires L2 or BGP, highest performance

## 6.7 Overlay Comparison Table

| Solution | Encapsulation | Data Path | Performance | Encryption | Notes |
|---|---|---|---|---|---|
| Flannel VXLAN | VXLAN (UDP 4789) | kernel | medium | none | Simplest overlay, works everywhere |
| Flannel host-gw | none | kernel | highest | none | Requires L2 adjency |
| Calico BGP | none | kernel | highest | none | Requires BGP infrastructure |
| Calico IPIP | IP-in-IP | kernel | medium | none | Falls back when BGP fails |
| Cilium eBPF + VXLAN | VXLAN | kernel | high | WireGuard (optional) | Best observability |
| Cilium eBPF (native) | none | kernel | highest | WireGuard (optional) | Requires L2 or BGP |
| Antrea | VXLAN / Geneve | kernel | high | IPsec (optional) | OVS-based |
| Weave sleeve | UDP encapsulation | userspace | low | optional | Self-healing mesh |
| Weave fastdp | WireGuard | kernel | medium-high | built-in | Better performance |

---

# Part 7: kube-proxy & Services

## 7.1 What Is a Service?

A Kubernetes **Service** is an abstraction that provides a stable virtual IP (ClusterIP) and DNS name for a set of backing pods. The key problem it solves is that **pod IPs are ephemeral** — when a pod restarts, it gets a new IP. Without a Service, every consumer would need to track pod IPs manually and update their configuration whenever a pod was rescheduled.

Services work through label selectors:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-svc
spec:
  selector:
    app: nginx
  ports:
  - port: 80        # Service port (ClusterIP port)
    targetPort: 80  # Container port
```

The selector `app: nginx` matches all pods with label `app: nginx`. The Kubernetes **endpoint controller** automatically creates and maintains an **Endpoints** object containing the IP:port of every matching pod.

## 7.2 kube-proxy

**kube-proxy** is a DaemonSet deployed to every node in the cluster (`kube-system/kube-proxy`). Its job is to watch the Kubernetes API for Service and Endpoint changes, and to program the node's network rules so that traffic to a Service's ClusterIP is correctly forwarded to backing pods.

kube-proxy does not route traffic itself — it programs the Linux kernel's **netfilter** (iptables or IPVS) subsystem. The actual packet interception and forwarding happens in the kernel, which is why kube-proxy has minimal CPU overhead.

Modes of operation:
- **iptables mode** (default, legacy): Programs iptables NAT rules
- **IPVS mode** (opt-in): Programs IPVS load-balancing rules
- **kernelspace mode** (Windows only): Uses the Windows kernel's routing stack
- **userspace mode** (deprecated): Proxies in userspace, no longer recommended

## 7.3 iptables Mode (Default)

In iptables mode, kube-proxy creates a hierarchy of chains in the **NAT table** to intercept Service traffic and DNAT it to backing pod IPs.

The chain structure:
- `KUBE-SERVICES`: The entry point. Matches destination IP:port against all Service ClusterIPs.
- `KUBE-SVC-XXXXX`: Per-Service dispatcher chain. Uses `statistic mode random probability` to select one of the service's endpoints.
- `KUBE-SEP-XXXXX`: Per-endpoint chain. Performs the actual DNAT to the pod IP:port.

A simplified example for a Service `10.96.0.1:80` with two backing pods (10.244.0.2:80 and 10.244.0.3:80):

```
# KUBE-SERVICES chain
-A KUBE-SERVICES -d 10.96.0.1/32 -p tcp --dport 80 -j KUBE-SVC-NWDN6VOCZNGJSPJK

# Per-service dispatcher (round-robin via probability)
-A KUBE-SVC-NWDN6VOCZNGJSPJK -m statistic --mode random --probability 0.33333333 -j KUBE-SEP-AAABBB
-A KUBE-SVC-NWDN6VOCZNGJSPJK -m statistic --mode random --probability 0.50000000 -j KUBE-SEP-CCCDDD
-A KUBE-SVC-NWDN6VOCZNGJSPJK -j KUBE-SEP-EEEFFF

# Per-endpoint chains (DNAT to actual pod)
-A KUBE-SEP-AAABBB -s 10.244.0.2/32 -j DNAT --to-destination 10.244.0.2:80
-A KUBE-SEP-CCCDDD -s 10.244.0.3/32 -j DNAT --to-destination 10.244.0.3:80
-A KUBE-SEP-EEEFFF -s 10.244.0.5/32 -j DNAT --to-destination 10.244.0.5:80
```

The `statistic --mode random --probability` trick is how iptables implements load balancing: the first rule matches with 33.3% probability, the second (from remaining 66.6%) matches with 50% probability, and the third catches the rest. This is effectively weighted round-robin.

The `-s 10.244.0.2/32` match ensures the DNAT only applies to return traffic (prevents forwarding loops).

## 7.4 IPVS Mode

IPVS (IP Virtual Server) is a kernel feature that implements layer 4 load balancing in the kernel. kube-proxy can use IPVS instead of iptables, providing better performance at scale.

IPVS uses a **hash table** for destination lookups — O(1) lookup regardless of the number of services or endpoints. In contrast, iptables does O(n) chain traversal for every packet (where n is the number of services/endpoints).

kube-proxy creates IPVS virtual servers (one per Service) and real servers (one per Endpoint):

```bash
ipvsadm -ln
# Proto VirtualAddress   Weight RR
# TCP  10.96.0.1:80       rr, 2 backends
#   -> 10.244.0.2:80      weight 1
#   -> 10.244.0.3:80      weight 1
```

Supported load balancing algorithms in IPVS:
- **round-robin (rr)**: each connection goes to the next endpoint
- **weighted round-robin (wrr)**: like rr but respects weights
- **least connections (lc)**: sends to endpoint with fewest active connections
- **weighted least connections (wlc)**: like lc but weighted
- **source hash (sh)**: consistent hashing based on source IP (for session affinity)
- **destination hash (dh)**: consistent hashing based on destination IP

To enable IPVS mode:
```yaml
# kube-proxy ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-proxy
  namespace: kube-system
data:
  config.conf: |
    mode: "ipvs"
    ipvs:
      scheduler: "rr"
```

## 7.5 Comparison: iptables vs IPVS

| | iptables | IPVS |
|---|---|---|
| Data structure | Chain traversal | Hash table |
| Lookup complexity | O(n) per packet | O(1) per packet |
| Load balancing algorithms | Random only (probability chains) | RR, WRR, LC, WLC, SH, DH |
| Connection tracking | Full connection tracking | Can be stateless or stateful |
| Scale | Degrades with many services | O(1) regardless of scale |
| Default | Yes (legacy) | No (opt-in) |
| Session affinity | No (each packet independently routed) | Yes (with SH/DH) |
| Graceful handle endpoint changes | Full conntrack migration | Requires new connection |
| Minimum kernel | Any | 4.1+ for full feature set |

For small clusters (< 1000 services), iptables is fine. At scale, IPVS provides significantly better performance.

## 7.6 Service Types Deep Dive

**ClusterIP** (default):
- Virtual IP from service CIDR, only reachable within the cluster
- Most common type for internal-only services
- No external access

**NodePort**:
- Exposes the service on each node's IP at a static port (30000-32767)
- `my-svc.default.svc:80` → `<node-ip>:30080`
- External traffic hits any node (which forwards to the service via kube-proxy)
- Useful for development or simple exposures without a cloud LB

**LoadBalancer**:
- Provisions an external load balancer (cloud provider: AWS ELB, GCP LB, Azure LB; bare metal: MetalLB)
- Traffic from external LB → NodePort → kube-proxy → pods
- Cloud controllers auto-configure the LB to point to the NodePort

**ExternalName**:
- Maps the service to an external DNS name (CNAME)
- `my-svc.default.svc.cluster.local` → `api.external.com`
- Used for importing external services into k8s DNS namespace

## 7.7 External Traffic Policy

When external traffic enters via NodePort or LoadBalancer, kube-proxy has two options for which pods to forward to:

**`externalTrafficPolicy: Cluster`** (default):
- kube-proxy can forward to any pod, anywhere in the cluster
- Causes an extra network hop if the selected pod is on a different node (SNAT preserves source IP, but latency increases)
- Preserves source IP (with SNAT)

**`externalTrafficPolicy: Local`**:
- kube-proxy only selects pods running on the same node as the ingress node
- No extra hop, optimal routing
- Client IP is preserved (no SNAT needed)
- If no local pod exists, the connection is dropped (no fallback to remote nodes)
- Best for latency-sensitive or IP-sensitive workloads

---

# Part 8: Service IP Allocation — How ClusterIPs Are Assigned

## 8.1 Service CIDR

The service CIDR is configured at cluster creation time via the kube-apiserver flag `--service-cluster-ip-range`. The default is `10.96.0.0/12`, which provides over 65,000 service IPs — sufficient for virtually any deployment.

The API server reserves the first IP (`10.96.0.1`) for `kubernetes.default.svc.cluster.local` (the API server's own service). You cannot create a service with ClusterIP `10.96.0.1`.

## 8.2 ClusterIP Assignment Process

When you create a Service without specifying a ClusterIP:

1. `kubectl apply -f svc.yaml` sends the Service spec to the API server
2. API server validates the spec (namespace exists, port is valid, etc.)
3. If `spec.clusterIP` is unset, the API server scans the service CIDR for the next available IP
4. It checks against a bitmap of allocated IPs in etcd — skips any IP already assigned to another service
5. The chosen IP is written to etcd as part of the Service object
6. All kube-proxy instances (watching via informers) see the new Service and create their iptables/IPVS rules

The allocation is deterministic — the same Service created twice in the same cluster will get the same ClusterIP (because allocation scans in order), but different clusters will get different IPs based on the order of operations.

## 8.3 Specifying a Custom ClusterIP

You can manually specify a ClusterIP in the Service spec:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-fixed-svc
spec:
  clusterIP: 10.96.0.200
  selector:
    app: my-app
  ports:
  - port: 80
```

This must be:
- Within the service CIDR
- Not already allocated to another service
- Not the reserved IP (`10.96.0.1`)

This is useful when migrating from one service to another, or when an application has a hardcoded dependency on a specific IP.

## 8.4 ClusterIP Is Virtual — No Interface

This is the most important mental model to internalize: **Service ClusterIPs do not correspond to any network interface**. Running `ip addr show` on any node will not reveal any service IP. The IP exists only in:
- The Kubernetes API server's etcd database
- The iptables or IPVS rules on every node

When a packet is sent to a ClusterIP:
1. `PREROUTING` chain in the NAT table intercepts it (for service-to-service)
2. `INPUT` chain also intercepts it (for local processes sending to ClusterIP)
3. The iptables rule matches on destination IP and rewrites (DNATs) the destination to a backing pod IP
4. The original destination IP is replaced; the packet is forwarded as if it was destined for the pod

This is why you can use a ClusterIP that doesn't exist on any network — the iptables rules intercept and redirect before the packet reaches the network stack's routing decision.

---

# Part 9: Endpoints & EndpointSlices

## 9.1 What Are Endpoints?

An **Endpoints** object is a Kubernetes resource that tracks the IP addresses and ports of all pods that back a service. It exists because Services need to know which pods to send traffic to.

The endpoint controller (running in kube-controller-manager) continuously reconciles the Endpoints object for each Service:
- When a pod with matching labels is created → its IP:port is added to Endpoints
- When a matching pod is deleted → its IP:port is removed from Endpoints
- When a pod's IP changes → the Endpoints entry is updated

```bash
kubectl get endpoints nginx-svc
# NAME        ENDPOINTS                    AGE
# nginx-svc   10.244.0.2:80,10.244.0.5:80   5d
```

## 9.2 EndpointSlices (Kubernetes 1.16+)

Before EndpointSlices, all endpoints for a Service were stored in a single Endpoints object. For large Services with hundreds of pods, this caused:
- Large etcd objects (slow reads/writes)
- Large API responses (watch bandwidth)
- High memory usage in kube-proxy (storing all rules)

**EndpointSlices** solve this by grouping endpoints into multiple objects of ~100 endpoints each. A Service with 500 pods would have ~5 EndpointSlice objects.

```bash
kubectl get endpointslices -l kubernetes.io/service-name=nginx-svc
# NAME                            ADDRESSES   PORTS   AGE
# nginx-svc-7x                     10.244.0.2   80      5d
# nginx-svc-8y                     10.244.0.5   80      5d
```

EndpointSlices are indexed by `kubernetes.io/service-name` label so kube-proxy can watch only the slices for a given service.

## 9.3 Endpoint Lifecycle

The full lifecycle of an endpoint:

```
Pod Created → kubelet assigns IP → endpoint controller sees new pod
→ creates Endpoint record → kube-proxy sees Endpoint change
→ adds iptables/IPVS rule → traffic now forwarded to new pod

Pod Terminating → kubelet sends SIGTERM → pod stops receiving new traffic
→ endpoint controller removes Endpoint → kube-proxy removes rule
→ connection draining completes → IP returned to pool on pod delete
```

The `endpointslice.kubernetes.io/managed-by` label identifies which controller manages each slice.

## 9.4 Headless Services

A **headless Service** is declared with `spec.clusterIP: "None"`. In this case:
- No ClusterIP is allocated from the service CIDR
- No kube-proxy rules are created
- DNS returns **A records for all backing pod IPs** directly

```yaml
apiVersion: v1
kind: Service
metadata:
  name: headless-svc
spec:
  clusterIP: "None"
  selector:
    app: database
  ports:
  - port: 5432
```

Querying DNS for `headless-svc.default.svc.cluster.local` returns all three pod IPs:
```
10.244.0.2
10.244.0.5
10.244.1.3
```

Clients must implement their own load balancing or pick a specific IP. Headless Services are used for:
- **StatefulSets** (etcd, Cassandra, Kafka) where pods need to discover each other's IPs directly
- **Database clusters** where the application manages replication
- **Custom service meshes** where the sidecar handles discovery and load balancing

---

# Part 10: CoreDNS — Service Discovery

## 10.1 Evolution: kube-dns to CoreDNS

Before Kubernetes 1.12, DNS was provided by **kube-dns**, which consisted of three components:
- **SkyDNS**: the DNS server
- **kube2sky**: a bridge that watched the Kubernetes API and updated SkyDNS
- **dnsmasq**: a caching DNS proxy on each node

This stack was fragile and hard to configure. In Kubernetes 1.12, **CoreDNS** became the default DNS provider. CoreDNS is:
- A single binary (no sidecars)
- Configured entirely via a ConfigMap
- Performs DNS resolution for cluster-local names and forwards everything else to upstream DNS
- Auto-reloads configuration on ConfigMap changes

CoreDNS runs as a Deployment (typically 2 replicas for HA) in the `kube-system` namespace, exposed by a Service called `kube-dns`:

```bash
kubectl get svc kube-dns -n kube-system
# NAME       TYPE        CLUSTER-IP    PORT(S)   AGE
# kube-dns   ClusterIP   100.64.0.10   53/UDP    30d
```

The ClusterIP `100.64.0.10` is in the service CIDR but, like all ClusterIPs, is purely virtual — managed by iptables rules on each node.

## 10.2 How Pods Get DNS Configuration

kubelet injects DNS configuration into every pod at startup. The pod's `/etc/resolv.conf` is generated by kubelet based on the cluster's DNS configuration:

```bash
# Inside a pod
cat /etc/resolv.conf
nameserver 100.64.0.10
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

- `nameserver`: points to the `kube-dns` service IP
- `search`: appends domain suffixes so short names resolve
- `ndots:5`: controls how many dots are required before treating a name as fully qualified (to avoid unnecessary upstream queries for short names within the cluster)

## 10.3 CoreDNS Plugins

CoreDNS uses a plugin-based architecture. Each plugin handles a specific type of DNS request:

- **kubernetes**: Handles cluster-local DNS (Service A records, headless Service A records, pod DNS). Enabled by default.
- **forward**: Passes non-matched queries to `/etc/resolv.conf` on the host (the node's upstream DNS)
- **errors**: Logs DNS errors
- **health**: Exposes a health endpoint at `:8080/health`
- **prometheus**: Exposes metrics at `:9153/metrics` (for Prometheus scraping)
- **cache**: Caches DNS responses with TTL-based expiry
- **reload**: Watches the Corefile ConfigMap and reloads on changes (without restart)
- **loop**: Detects and halts infinite DNS resolution loops

## 10.4 Corefile (CoreDNS Configuration)

The CoreDNS configuration lives in a ConfigMap called `coredns` in `kube-system`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :9153
        forward . /etc/resolv.conf {
           max_concurrent 1000
        }
        cache 30
        reload
    }
```

Key parts:
- `kubernetes cluster.local`: answers queries for the cluster domain
- `pods insecure`: enables pod A record lookups (can also use `pods verified` for stricter validation against actual pod IPs)
- `fallthrough in-addr.arpa ip6.arpa`: for reverse DNS lookups, falls through to next plugin
- `forward . /etc/resolv.conf`: forwards all other queries to the node's upstream DNS servers

## 10.5 DNS Query Resolution Flow

When a pod runs `nslookup nginx-svc.default.svc.cluster.local`:

1. **Pod's resolver** (glibc): The query goes to `100.64.0.10` (kube-dns)
2. **kube-dns service IP**: The service IP is virtual — iptables on the node intercepts it and redirects to a CoreDNS pod's UDP port 53
3. **CoreDNS pod**: Receives the query for `nginx-svc.default.svc.cluster.local`
4. **kubernetes plugin**: Checks if it matches `cluster.local` → yes
5. **Service lookup**: Looks up `nginx-svc` in the `default` namespace → finds ClusterIP `10.96.0.5`
6. **Response**: Returns A record: `nginx-svc.default.svc.cluster.local → 10.96.0.5`

For a headless service:
- CoreDNS finds no ClusterIP (clusterIP is "None")
- CoreDNS looks up the Endpoints for the service
- Returns A records for all pod IPs directly

## 10.6 DNS Record Types

**A records** (standard Service):
```
nginx-svc.default.svc.cluster.local. 30 IN A 10.96.0.5
```

**A records** (headless Service — multiple):
```
headless-svc.default.svc.cluster.local. 30 IN A 10.244.0.2
headless-svc.default.svc.cluster.local. 30 IN A 10.244.0.5
```

**A records** (Pod FQDN — when `pods verified` mode):
```
pod-ip.default.pod.svc.cluster.local → single A record
```
For a pod `nginx-abc123` in `default` namespace with IP `10.244.0.7`:
```
nginx-abc123.default.pod.svc.cluster.local. 300 IN A 10.244.0.7
```
This requires `pods verified` mode in CoreDNS, which validates the pod exists by querying the Kubernetes API before returning the record.

**SRV records** (named ports):
```
_http._tcp.nginx-svc.default.svc.cluster.local. 30 IN SRV 0 100 80 nginx-svc.default.svc.cluster.local.
```

**CNAME records** (ExternalName Service):
```
external-svc.default.svc.cluster.local. 30 IN CNAME api.external.com.
```

## 10.7 Pod Hostname and Subdomain

A pod's hostname is its `metadata.name`. If a pod also has `metadata.subdomain` set (pointing to the name of a headless Service in the same namespace), it gets a fully qualified domain name:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-0
  namespace: default
  subdomain: my-headless-svc  # points to headless service "my-headless-svc"
spec:
  hostname: nginx-0
  subdomain: my-headless-svc
```

The pod's FQDN: `nginx-0.my-headless-svc.default.svc.cluster.local`

The headless Service `my-headless-svc` must exist in the same namespace. The Service's selector must include a label that this pod has, otherwise the subdomain won't resolve.

Pods without a subdomain still get a DNS name, but it uses the `pod.svc.cluster.local` suffix:
`nginx-abc123.default.pod.svc.cluster.local` (no subdomain)

## 10.8 Headless Service DNS in Detail

With a headless Service, the DNS query returns all pod IPs:

```bash
# nslookup in a pod for a headless service
nslookup headless-svc.default.svc.cluster.local
# Name:   headless-svc.default.svc.cluster.local
# Address: 10.244.0.2
# Name:   headless-svc.default.svc.cluster.local
# Address: 10.244.0.5
# Name:   headless-svc.default.svc.cluster.local
# Address: 10.244.1.3
```

The client receives all IPs and can choose which to connect to. This is how StatefulSets achieve stable pod identity — each pod's hostname always resolves to its own IP, even across rescheduling.

## 10.9 DNS TTL Behavior

- **Services**: CoreDNS returns a TTL of 30 seconds by default (configurable). Short TTL allows fast failover when pod IPs change.
- **Pods (insecure mode)**: TTL is typically 5 minutes. Pod IPs change on restart, so caching longer would cause stale lookups.
- **Negative caching**: If a query returns NXDOMAIN (no such domain), CoreDNS caches the negative result for up to 5 minutes. This prevents repeated failed queries from hitting the DNS server.

## 10.10 Stub Domains and External DNS

CoreDNS can forward queries for specific domains to different upstream servers (stub domains):

```yaml
cluster.local:53 {
    kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods verified
        fallthrough in-addr.arpa ip6.arpa
    }
}
company.internal:53 {
    forward . 10.0.0.1     # forward .company.internal to internal DNS server
}
. {
    forward . /etc/resolv.conf   # all other queries go to node's upstream
}
```

This enables corporate DNS integration: queries for `*.company.internal` go to the internal DNS server, while everything else goes to the node's upstream DNS (typically the cloud provider's DNS or on-premises DNS server).

---

# Part 11: Ingress — External Access

## 11.1 What Is Ingress?

**Ingress** is a Kubernetes API object (stable since Kubernetes 1.19) that provides HTTP/HTTPS routing from outside the cluster to Services inside the cluster. It supports:
- Path-based routing (e.g., `/api` → Service A, `/admin` → Service B)
- Host-based routing (e.g., `api.example.com` → Service A, `dashboard.example.com` → Service B)
- TLS termination (HTTPS traffic is decrypted at the Ingress controller, then forwarded to backends)
- Load balancing configuration

Ingress is not a built-in controller — it's just a spec. You need an **Ingress controller** to implement it. The controller watches Ingress resources and configures itself accordingly.

## 11.2 Ingress Resource

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - api.example.com
    secretName: api-tls
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-svc
            port:
              number: 80
```

Key fields:
- `ingressClassName`: which IngressClass (controller) handles this Ingress (replaces the deprecated `kubernetes.io/ingress.class` annotation)
- `spec.tls`: TLS certificates and keys stored as Secrets, referenced by name
- `spec.rules`: host-based routing rules
- `spec.rules[].http.paths`: path-based routing within a host
- `pathType`: `Prefix` (most common), `Exact`, or `ImplementationSpecific`

## 11.3 Ingress Controller

The Ingress spec is just an API object. The actual HTTP server that handles traffic is the **Ingress controller**. Several controllers exist:

**nginx-ingress-controller** (NGINX Inc.):
- The most widely used Ingress controller
- Implements load balancing, TLS termination, rewrite rules, rate limiting
- Configured via Ingress annotations and ConfigMaps

**Contour** (Envoy-based, Heptio/VMware):
- Envoy proxy as the data plane
- Supports Ingress, Gateway API, and CRDs for advanced routing
- Good for multi-team ingress delegation

**Traefik** (Containous):
- Reverse proxy and load balancer
- Native support for Let's Encrypt, canary deployments, A/B testing
- Configuration via Ingress annotations or separate CRDs

**GKE Ingress Controller** (Google Cloud):
- Provisions Google Cloud Load Balancers automatically
- Manages SSL certificates via Google Certificate Manager
- Cloud-native integration

**Ambassador** / **Emissary-ingress** (Datawire):
- Envoy-based, API gateway capabilities
- Supports REST and gRPC, rate limiting, authentication

## 11.4 IngressClass

`IngressClass` (introduced in Kubernetes 1.18) replaces the older annotation-based approach for specifying which controller handles an Ingress:

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
spec:
  controller: k8s.io/nginx-ingress-controller
```

The `spec.controller` field specifies which controller implementation handles this class. Ingress resources then reference the class by name:

```yaml
spec:
  ingressClassName: nginx
```

Multiple IngressClasses can coexist in a cluster, each managed by a different controller.

## 11.5 Path-Based and Host-Based Routing

**Path-based routing** uses the URL path to select the backend service:

```
api.example.com/api → Service: api-svc (port 8080)
api.example.com/static → Service: static-svc (port 8081)
api.example.com/ → Service: fallback-svc (port 8082)
```

The `pathType: Prefix` matching means `/api` matches `/api`, `/api/v2`, `/api/anything`. For exact matching, use `pathType: Exact`.

**Host-based routing** uses the HTTP `Host` header:

```
api.example.com → Service: api-svc
cdn.example.com → Service: cdn-svc
dashboard.example.com → Service: dashboard-svc
```

This allows multiple sites to be served by a single Ingress controller and a single external load balancer IP.

## 11.6 TLS Termination

TLS termination happens at the Ingress controller, not at the Service:

1. Client sends HTTPS request to `api.example.com`
2. External load balancer routes to the Ingress controller
3. Controller decrypts the request using the Secret's certificate and key
4. Controller forwards the decrypted HTTP request to the backend Service
5. Response travels back through the controller, which re-encrypts it if the client used HTTPS

```
Client --HTTPS--> External LB --HTTP--> Ingress Controller --HTTP--> api-svc --TCP--> pod nginx
                  (TLS terminates)      (forwards)           (receives)
```

The backend pod sees requests as plain HTTP — the controller handles all TLS complexity.

## 11.7 Gateway API (Successor to Ingress)

The **Gateway API** (stable in Kubernetes 1.19 as `gateway.networking.k8s.io/v1`) is the successor to Ingress. It introduces a more flexible, role-based model for ingress management:

- **GatewayClass**: describes the controller implementation (like IngressClass)
- **Gateway**: the actual load balancer instance (replaces Ingress resource)
- **HTTPRoute**, **TCPRoute**, **UDPRoute**, **GRPCRoute**: route resources that attach to a Gateway

Key improvements:
- Route resources can be managed by different teams than the Gateway owner
- Multiple route types beyond HTTP
- Better semantics for traffic splitting, retries, and timeouts
- Built for multi-tenancy

Example HTTPRoute:
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-route
spec:
  parentRefs:
  - name: my-gateway
    namespace: ingress
  hostnames:
  - api.example.com
  rules:
  - backendRefs:
    - name: api-svc
      port: 80
```

---

# Part 12: Network Policies

## 12.1 What Are Network Policies?

A **NetworkPolicy** is a Kubernetes API object that acts as a **pod-level firewall**. By default, all pods in a Kubernetes cluster can communicate with all other pods (flat network). NetworkPolicy lets you restrict this by defining which pods can talk to which other pods, on which ports.

NetworkPolicy is **namespaced** and selects pods via labels. Policies are additive (deny wins if no allow matches). A pod that has no NetworkPolicy applied to it is **unrestricted** (all traffic allowed).

**Critical requirement**: The CNI plugin in use must support NetworkPolicy. Flannel by itself doesn't support NetworkPolicy — you need a plugin like Calico, Cilium, Antrea, or Weave that implements the policy enforcement. Using Flannel with NetworkPolicy resources will have no effect.

## 12.2 Policy Structure

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-netpol
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - protocol: TCP
      port: 5432
```

- `podSelector`: which pods this policy applies to
- `policyTypes`: explicitly declare both Ingress and Egress (if you only want one, list only one)
- `ingress[].from[]`: whitelist of allowed inbound sources (pods with specific labels)
- `ingress[].ports[]`: allowed destination ports on selected pods
- `egress[].to[]`: whitelist of allowed outbound destinations
- `egress[].ports[]`: allowed source ports for outbound traffic

## 12.3 Implicit Default Deny

When a NetworkPolicy with `policyTypes` is applied to a namespace, any pod not matched by an `ingress` rule has all ingress blocked, and any pod not matched by an `egress` rule has all egress blocked.

This means you must explicitly allow:
- DNS egress (to `kube-dns` service IP, port 53) — otherwise pods can't resolve names
- API server egress (to `kubernetes.default.svc`, port 443) — otherwise pods can't talk to the API

## 12.4 DNS Egress Requirement

A common mistake when applying NetworkPolicies is forgetting that pods need to reach the DNS service:

```yaml
# This policy blocks all egress — including DNS
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: restrictive
spec:
  podSelector:
    matchLabels:
      app: my-app
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - protocol: TCP
      port: 5432
# ❌ DNS is blocked — pod can't resolve names
```

A corrected policy must allow DNS:
```yaml
egress:
- to:
  - namespaceSelector: {}   # all namespaces (including kube-system)
  - podSelector:
      matchLabels:
        k8s-app: kube-dns
  ports:
  - protocol: UDP
    port: 53
  - protocol: TCP
    port: 53
```

## 12.5 CNI Plugin Support

| Plugin | NetworkPolicy Support | Implementation |
|---|---|---|
| Calico | Yes | Per-pod eBPF or iptables rules |
| Cilium | Yes | eBPF-based L7 policy |
| Antrea | Yes | OVS ACLs |
| Weave | Yes | Network policy rules in weave daemon |
| Flannel | No | Requires additional plugin (e.g., Calico for policy) |
| Multus | Depends on attached plugin | Policy handled by whichever CNI is active |

When evaluating CNI plugins for a security-sensitive cluster, verify that NetworkPolicy is fully supported and tested.

---

# Appendix: Quick Reference

## IP Ranges in a Default Cluster

| Range | Example | Used By |
|---|---|---|
| Node Network | (infrastructure-dependent) | kubelet, API server, etcd |
| Pod CIDR | `10.244.0.0/16` (flannel default) | Pod IPs via CNI |
| Service CIDR | `10.96.0.0/12` (default) | Service ClusterIPs |
| kube-dns | `100.64.0.10` (default) | CoreDNS service |

## Key Commands

```bash
# Check node IPs
kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'

# Check pod IPs
kubectl get pods -o wide

# Check service ClusterIPs
kubectl get svc

# Check endpoints (backing pod IPs for a service)
kubectl get endpoints <service-name>

# Check DNS pod FQDN
kubectl exec -it <pod-name> -- hostname -f

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns

# Check iptables rules (on node)
sudo iptables -t nat -L KUBE-SERVICES -n | grep <service-name>

# Check IPVS rules (on node)
sudo ipvsadm -ln | grep <service-ip>

# Inspect CNI config
cat /etc/cni/net.d/10-kubernetes.conf

# List network namespaces
ip netns list

# Show veth pairs
ip link show | grep veth
```

## Key Ports

| Port | Protocol | Used By |
|---|---|---|
| 4789 | UDP | VXLAN overlay |
| 8472 | UDP | Flannel VXLAN (old port) |
| 6443 | TCP | Kubernetes API server |
| 2379 | TCP | etcd client |
| 2380 | TCP | etcd peer-to-peer |
| 10250 | TCP | kubelet API (authenticated) |
| 10251 | TCP | kube-scheduler |
| 10252 | TCP | kube-controller-manager |
| 9153 | TCP | CoreDNS metrics |
| 30000-32767 | TCP | NodePort range |

---

*This document accompanies `k8s-networking.html` — the interactive visualization. See the HTML file for visual diagrams and animations of the concepts described here.*