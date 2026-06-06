---
title: Routing
description: Linux routing — routing tables, ip route, default gateway, static routes, policy routing, routing protocols
tags:
  - linux
  - networking
---

# Routing

Routing is the process of forwarding IP packets toward their destination. The Linux kernel maintains a **routing table** that it consults for every outgoing packet. Understanding routing is essential for troubleshooting connectivity, setting up firewalls, and running containers.

## The Routing Table

```bash
ip route show
# default via 192.168.1.1 dev eth0 proto dhcp src 192.168.1.100
# 192.168.1.0/24 dev eth0 proto kernel scope link src 192.168.1.100
```

Each line is a **route entry**:

| Field | Meaning |
|-------|---------|
| `default` | Destination network (0.0.0.0/0 = any) |
| `via 192.168.1.1` | Next hop gateway IP |
| `dev eth0` | Outgoing interface |
| `proto dhcp` | How route was learned (dhcp, kernel, static) |
| `scope link` | Scope: link-local (direct), global (routable) |

## Routing Decision

When sending a packet to `8.8.8.8`:

```
1. Check route table for longest prefix match
   0.0.0.0/0 (default) matches → gateway is 192.168.1.1
   (but 192.168.1.0/24 also matches — longer match wins)
   ↓
2. Longer match: 192.168.1.0/24 (direct, no gateway needed)
   Send directly to MAC of 8.8.8.8 (via ARP)
```

**Longest prefix match wins.** A /24 is more specific than a /16, which is more specific than 0.0.0.0/0.

## Default Gateway

The default gateway is the router that handles traffic not matching any other route:

```
ip route add default via 192.168.1.1
# Equivalent to:
ip route add 0.0.0.0/0 via 192.168.1.1
```

Without a default route, the host can only talk to hosts on directly connected networks.

## Static Routes

```bash
# Add a static route to 10.0.0.0/16 via 192.168.1.254
ip route add 10.0.0.0/16 via 192.168.1.254 dev eth0

# Add route to a specific host (single IP = /32)
ip route add 10.0.1.50/32 via 192.168.1.254 dev eth0

# Blackhole route (drop traffic to this destination)
ip route add 10.0.0.0/8 blackhole
# Useful for suppressing spam from a net block

# Reject route (better than blackhole for some tools)
ip route add 10.0.0.0/8 reject
```

## Multi-homed Routing (Multiple NICs)

When a host has multiple NICs on different networks:

```
eth0: 192.168.1.100/24  (gateway: 192.168.1.1)
eth1: 10.0.0.50/24      (gateway: 10.0.0.1)
```

```bash
ip route show
# default via 192.168.1.1 dev eth0 proto dhcp
# 10.0.0.0/24 dev eth1 proto kernel scope link src 10.0.0.50
# 192.168.1.0/24 dev eth0 proto kernel scope link src 192.168.1.100
```

Traffic to 10.0.0.0/24 uses eth1 directly (scope link, no gateway). Traffic to everywhere else uses eth0 via the default gateway.

## Policy Routing (Advanced)

Normal routing uses only the destination IP. **Policy routing** lets you route based on source IP, fwmark, or interface:

```bash
# Use a separate routing table for traffic from 10.0.0.0/24
ip route add 0.0.0.0/0 via 10.0.0.1 dev eth1 table 100
ip rule add from 10.0.0.0/24 lookup 100

# Check routing tables
ip route show table all
ip rule show
```

This is how Docker and Kubernetes route pod traffic — they add rules that force container traffic through specific interfaces or tables.

## Viewing Routes

```bash
ip route                         # main table
ip route show table 100         # specific table
ip route show table all         # all tables

# Legacy:
route -n
# Kernel IP routing table
# Destination     Gateway         Genmask         Flags Metric Ref  Use Iface
# 0.0.0.0         192.168.1.1    0.0.0.0         UG    600    0      0 eth0
# 192.168.1.0     0.0.0.0         255.255.255.0   U     600    0      0 eth0
```

## Container Networking and Routes

Containers have their own network namespace with their own routing table:

```bash
# From inside a Docker container:
ip route
# default via 172.17.0.1 dev eth0
# 172.17.0.0/16 dev eth0 proto kernel scope link src 172.17.0.2

# Host's view of docker0 bridge:
ip route show | grep 172.17
# 172.17.0.0/16 dev docker0 proto kernel scope link src 172.17.0.1
```

Kubernetes pods on a CNI bridge have similar routes:
```
10.244.0.0/24 dev cni0 proto kernel scope link src 10.244.0.1
default via 10.244.0.1 dev cni0    (traffic to external networks)
```

## Debugging Routing Issues

```bash
# 1. Is the destination reachable?
ping -c 1 8.8.8.8

# 2. Where does routing fail?
tracepath 8.8.8.8
traceroute 8.8.8.8

# 3. Which route is used?
ip route get 8.8.8.8
# 8.8.8.8 via 192.168.1.1 dev eth0 src 192.168.1.100 uid 1000

# 4. Check for ARP issues
ip neigh show
# Should show gateway MAC

# 5. Is forwarding enabled?
cat /proc/sys/net/ipv4/ip_forward
# 0 = not a router, 1 = can forward packets between interfaces

# 6. Check firewall FORWARD chain
iptables -L FORWARD -n -v
```

## Common Routing Scenarios

### Scenario: Host can't reach the internet

```bash
# Check default route
ip route | grep default
# Nothing → no default gateway set
# Add one:
ip route add default via 192.168.1.1

# Or gateway unreachable:
ping 192.168.1.1   # is gateway up?
arp 192.168.1.1    # can we resolve gateway MAC?
```

### Scenario: Two NICs, traffic not going out right interface

```bash
# Force traffic to a specific interface:
ip route get 10.0.0.5
# 10.0.0.5 via 192.168.1.254 dev eth0   ← wrong interface!

# Use policy routing:
ip rule add to 10.0.0.0/24 dev eth1 lookup 100
ip route add 0.0.0.0/0 via 10.0.0.1 dev eth1 table 100
```

### Scenario: Host is a router

```bash
# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1

# NAT/masquerade (so internal hosts look like the router's IP)
iptables -t nat -A POSTROUTING -s 192.168.1.0/24 ! -o eth0 -j MASQUERADE

# Then hosts on 192.168.1.0/24 set this Linux box as their default gateway
```