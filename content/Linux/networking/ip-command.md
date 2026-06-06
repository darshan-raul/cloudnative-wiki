---
title: ip Command
description: Linux ip command — ip addr, ip link, ip route, ip neigh, ip netns, managing interfaces, addresses, routes
tags:
  - linux
  - networking
---

# ip Command

`ip` is the modern replacement for `ifconfig`, `route`, `arp`, and `netstat`. It's part of `iproute2` and provides a consistent interface to all Linux networking configuration.

## ip addr — Interface Addresses

```bash
ip addr show                     # show all interfaces
ip addr show eth0               # show specific interface
ip addr add 192.168.1.100/24 dev eth0    # add IP
ip addr del 192.168.1.100/24 dev eth0    # remove IP
ip addr flush dev eth0           # remove all IPs
```

### Output Explained

```
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP qlen 1000
    link/ether 52:54:00:12:34:56 brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.100/24 brd 192.168.1.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::5054:ff:fe12:3456/64 scope link
       valid_lft forever preferred_lft forever
```

- `<BROADCAST,MULTICAST,UP,LOWER_UP>`: flags (UP means interface is admin-up)
- `mtu 1500`: Maximum Transmission Unit (Ethernet default)
- `qdisc fq_codel`: queueing discipline (traffic scheduler)
- `state UP`: operational state (UP, DOWN, UNKNOWN)
- `inet 192.168.1.100/24`: IPv4 address with CIDR prefix
- `brd 192.168.1.255`: broadcast address
- `scope global`: globally routable vs `scope link` (local-only)

## ip link — Interface Configuration

```bash
ip link show                     # show all links
ip link set eth0 up             # bring interface up
ip link set eth0 down           # bring interface down
ip link set eth0 mtu 9000       # set MTU (jumbo frames)
ip link set eth0 promisc on     # enable promiscuous mode
ip link set eth0 name wan       # rename interface
ip link delete eth0             # delete a virtual interface
```

### Create Virtual Interfaces

```bash
# Create a VLAN interface (802.1q)
ip link add link eth0 name eth0.100 type vlan id 100
ip addr add 10.0.100.1/24 dev eth0.100
ip link set eth0.100 up

# Create a dummy interface (for testing, loopback-like)
ip link add dummy0 type dummy
ip addr add 10.255.255.1/32 dev dummy0
ip link set dummy0 up

# Create a macvlan interface (shares host's MAC, separate IP)
ip link add link eth0 name macvlan0 type macvlan mode bridge
ip addr add 192.168.200.1/24 dev macvlan0
ip link set macvlan0 up
```

## ip route — Routing Table

```bash
ip route show                    # show routing table
ip route add default via 192.168.1.1 dev eth0     # default route
ip route add 10.0.0.0/16 via 192.168.1.254 dev eth0  # static route
ip route add blackhole 10.0.0.0/8                 # drop traffic
ip route del 10.0.0.0/16                           # remove route
ip route get 8.8.8.8                    # which route for this IP?

# Change metrics (lower = preferred)
ip route add default via 192.168.1.1 dev eth0 metric 100
```

## ip neigh — ARP/Neighbor Table

```bash
ip neigh show                    # show ARP cache
ip neigh add 192.168.1.1 lladdr aa:bb:cc:dd:ee:ff dev eth0 nud permanent  # static ARP entry
ip neigh del 192.168.1.1 dev eth0  # remove ARP entry
ip neigh flush all               # clear ARP cache
```

NUD states (Neighbour Unreachability Detection):
- `REACHABLE`: confirmed working
- `STALE`: valid but untested (will be verified lazily)
- `PERMANENT`: static entry, never expires
- `FAILED`: resolution failed

## ip netns — Network Namespaces

```bash
# Create a network namespace
ip netns add myns

# List namespaces
ip netns list

# Run command in namespace
ip netns exec myns ip addr
ip netns exec myns ping 8.8.8.8

# Create veth pair and move one end to namespace
ip link add veth0 type veth peer name veth0ns
ip link set veth0ns netns myns
ip addr add 10.0.0.1/24 dev veth0
ip link set veth0 up
ip netns exec myns ip addr add 10.0.0.2/24 dev veth0ns
ip netns exec myns ip link set veth0ns up

# Delete namespace
ip netns del myns
```

## ip maddr — Multicast Addresses

```bash
ip maddr show                    # show multicast memberships
ip maddr add 01:00:5e:00:00:01 dev eth0   # join IGMP group (for 224.0.0.1 all-hosts)
```

## ip monitor — Watch for Changes

```bash
ip monitor all                   # watch all changes live
ip monitor route                # watch route changes
ip monitor neigh                 # watch ARP changes
```

## Complete Workflow: Set Up a Static IP

```bash
# 1. Bring interface up
ip link set eth0 up

# 2. Set IP address
ip addr add 192.168.1.100/24 dev eth0

# 3. Set default gateway
ip route add default via 192.168.1.1

# 4. Verify
ip addr show eth0
ip route show
ping -c 1 192.168.1.1
```

## Complete Workflow: Bridge with VETH for Containers

```bash
# 1. Create bridge
ip link add br0 type bridge
ip addr add 10.244.0.1/24 dev br0
ip link set br0 up

# 2. Create veth pair
ip link add veth0 type veth peer name veth1

# 3. Move one end to namespace (container)
ip link set veth1 netns container1
ip netns exec container1 ip addr add 10.244.0.10/24 dev veth1
ip netns exec container1 ip link set veth1 up
ip netns exec container1 ip link set lo up
ip netns exec container1 ip route add default via 10.244.0.1

# 4. Connect other end to bridge
ip link set veth0 master br0
ip link set veth0 up

# 5. Enable forwarding on bridge
iptables -A FORWARD -i br0 -o br0 -j ACCEPT
```