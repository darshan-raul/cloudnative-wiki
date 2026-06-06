---
title: Network Namespaces
description: Linux network namespaces — ip netns, veth pairs, bridge, NAT, isolated network stacks
tags:
  - linux
  - namespaces
  - networking
  - containers
---

# Network Namespaces

Network namespaces isolate the entire **network stack** — interfaces, routing tables, firewall rules, ports — so that processes in one namespace can't see or affect the network of another. This is how containers get their own IP addresses and network stack.

## The Core Concept

Without network namespaces:
- All processes share `eth0`, `lo`, routing table, iptables rules
- One process binding port 80 blocks everyone else from binding 80
- There's one `/proc/sys/net/` for the whole system

With network namespaces:
```
Host namespace:
  eth0 (physical)
  docker0 (bridge)
  routing table A

Container namespace (isolated):
  eth0@if5 (veth, one end of pair)
  lo
  routing table B (different!)
  iptables rules (different!)
  can bind port 80 independently of host
```

## Creating and Using Network Namespaces

```bash
# Create a network namespace
ip netns add myns

# Run a command inside it
ip netns exec myns ip addr
ip netns exec myns ip link
ip netns exec myns ss -tlnp       # listening ports in this namespace

# Delete it
ip netns del myns

# List all namespaces
ip netns list
```

## veth Pairs: Connecting Namespaces

A **veth pair** is a virtual ethernet cable — two interfaces that pipe packets between each other. To connect a namespace to the host, you use a veth pair with one end in the namespace and one end on the host bridge:

```
┌─────────────────────────────────────────────────────────┐
│ Host network namespace                                  │
│                                                         │
│   eth0 ─────────────────────────────────────────────►   │
│                                                         │
│   veth-host ◄─────────────────────────────────► veth-ns │
│   (bridge port)                         (in container)  │
│                                                         │
│   docker0 (bridge)                                       │
└─────────────────────────────────────────────────────────┘
```

### Setting Up a veth pair manually

```bash
# 1. Create namespace
ip netns add container1

# 2. Create veth pair
ip link add veth-ns type veth peer name veth-host

# 3. Move one end into the namespace
ip link set veth-ns netns container1

# 4. Assign IPs
ip addr add 172.18.0.2/24 dev veth-host
ip link set veth-host up

ip netns exec container1 ip addr add 172.18.0.3/24 dev veth-ns
ip netns exec container1 ip link set veth-ns up
ip netns exec container1 ip link set lo up

# 5. Bridge it (optional — or just route between namespaces)
ip link set veth-host master docker0   # add to bridge

# 6. Enable forwarding and NAT on host
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -s 172.18.0.0/24 ! -d 172.18.0.0/24 -j MASQUERADE
```

## How Docker Does It

Docker automates the above with its bridge network:

```bash
# Docker creates a bridge named docker0 (172.17.0.0/16)
ip link show docker0

# Each container gets a veth pair:
# vethXXXXX on host (attached to docker0)
# eth0 in container (gets 172.17.0.x via DHCP/dockerd)

# Docker's iptables rules:
# - MASQUERADE for outbound NAT
# - FORWARD rules to allow container-to-container traffic
# - DROP or ACCEPT depending on --icc flag
```

## Network Namespace Isolation Properties

Each namespace has its own:

| Resource            | Isolated? | Notes                                          |
|--------------------|-----------|------------------------------------------------|
| Network interfaces | Yes       | `lo`, `eth0`, etc. are per-namespace          |
| IP addresses       | Yes       | Each interface has its own addr                |
| Routing table      | Yes       | `ip route` output differs per namespace       |
| iptables rules     | Yes       | NAT, filter, mangle tables are per-namespace  |
| `/proc/sys/net/`  | Yes       | TCP/UDP tuning parameters                     |
| Port bindings      | Yes       | Port 80 can be bound in host and container simultaneously |
| ARP table          | Yes       | Separate neighbor table per namespace          |

## The Loopback Device

`lo` exists in every namespace. By default it is DOWN inside new namespaces:

```bash
# Must be brought up manually in container
ip netns exec container1 ip link set lo up

# Without this, 127.0.0.1 doesn't work inside the container
```

## Port Binding and `ss`

```bash
# Host view: what's listening?
ss -tlnp
# LISTEN 0 128 *:80 *:* users:(("nginx",pid=1234,fd=4))

# Inside container: same port 80, different PID
ip netns exec container1 ss -tlnp
# LISTEN 0 128 *:80 *:* users:(("nginx",pid=1,fd=4))
```

Both show port 80 in use, independently. No conflict because they're in different network namespaces.

## Network Namespaces and Kubernetes

In Kubernetes, each pod gets its own network namespace:

```
┌─────────────────────────────────────────┐
│ Pod "web-1"                             │
│                                         │
│   eth0@if5 ◄──── veth pair ────► host  │
│   (pod's view)       (host side)        │
│                                         │
│   Network NS: "cni-pod-12345"           │
│   Routing table, iptables: pod-scoped    │
│   ARP table: pod-specific               │
└─────────────────────────────────────────┘
```

CNI plugins (flannel, calico, vpc-cni) handle the veth pair setup and routing.

## Inspecting Network Namespaces

```bash
# List all network namespaces
ip netns list

# Show interfaces in a namespace
ip netns exec myns ip link

# Show routes in a namespace
ip netns exec myns ip route

# Show iptables in a namespace (if iptables is ns-aware)
ip netns exec myns iptables -t nat -L -n

# See which namespace a process is in
ip netns identify $(pgrep -f nginx)

# Show ARP table
ip netns exec myns ip neigh
```

## The `netns` Link in /proc

```bash
# Each namespace has a device at /var/run/netns/<name>
# Bind-mounting lets you keep a namespace "alive" without a process in it
touch /var/run/netns/myns
mount --bind /proc/$$/ns/net /var/run/netns/myns

# Now you can enter it even after the creating process exits
ip netns exec myns bash
```