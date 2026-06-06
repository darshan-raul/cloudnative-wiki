---
title: Linux Networking
description: Linux networking — TCP/IP model, routing, DNS, iptables, firewalld, network namespaces, netplan, network performance tuning
tags:
  - linux
  - networking
---

# Linux Networking

Linux's networking stack is deep and capable. This section covers everything from the TCP/IP four-layer model up through firewall rules, DNS resolution, network performance tuning, and network namespaces for container isolation.

Start with [[tcp-ip-model]] if you want the big-picture foundation. The rest can be read in any order based on what you need.

## Foundation

**[[tcp-ip-model|TCP/IP Model]]** — The four-layer model (link, internet, transport, application) that underpins all IP networking. How encapsulation works: an HTTP response becomes a TCP segment, then an IP packet, then an Ethernet frame. How this differs from the OSI seven-layer model and why the TCP/IP model is what actually matters on Linux.

**[[ip-command|ip command]]** — The modern replacement for `ifconfig`, `route`, and `arp`. `ip addr` for addressing, `ip link` for interface state, `ip route` for routing tables, `ip neigh` for ARP/ND tables. Also covers `ss` for socket statistics (replacing `netstat`).

## DNS

**[[dns-resolution|DNS Resolution]]** — How Linux resolves hostnames to IP addresses. `/etc/resolv.conf`, the `nsswitch.conf` lookup order, systemd-resolved, and how `getent` queries the system resolver. Tools: `dig`, `host`, `nslookup`. Common issues: stale DNS caches, wrong search domain, and resolv.conf being overwritten by NetworkManager.

## Routing and Connectivity

**[[routing|Routing]]** — How the kernel routes packets. The routing table (`ip route`), default gateways, static routes, and policy routing (multiple routing tables). How NAT works at the kernel level, and how packets decide which interface to leave on.

**[[dhcp|DHCP]]** — How machines automatically get IP addresses. The DORA process (Discover, Offer, Request, Acknowledge). How systemd-networkd and NetworkManager handle DHCP leases, and how to debug DHCP when nothing connects.

## Firewalls

**[[iptables|iptables]]** — The legacy Linux firewall. Tables (`filter`, `nat`, `mangle`), chains (INPUT, OUTPUT, FORWARD, PREROUTING, POSTROUTING), targets (ACCEPT, DROP, REJECT, MASQUERADE, DNAT, SNAT). How NAT works with the NAT table. Common patterns: blocking an IP, opening a port, forwarding for a NAT'd server, Docker's interaction with iptables.

**[[firewalld|firewalld]]** — The modern firewall manager on CentOS/RHEL/Fedora. Zones and services as abstractions over iptables/nftables. Rich rules for complex scenarios (port forwarding, rate limiting). How firewalld integrates with Docker and podman.

## Network Configuration

**[[netplan|Netplan]]** — Ubuntu's YAML-based network configuration. Describes interfaces in `/etc/netplan/*.yaml` and renders to either systemd-networkd or NetworkManager. The declarative model and why it reduces config errors on servers.

**[[network-performance-tuning|Network Performance Tuning]]** — `sysctl` parameters for TCP (timestamps, SACK, congestion control, keepalive). BBR vs cubic. `ethtool` for ring buffers and offload features. IRQ affinity and `irqbalance`. NIC bonding. `tc` for traffic control (qdiscs, shaping, priority).

## Container Networking

**[[network-namespace|Network Namespaces]]** — How containers get isolated network stacks. `ip netns`, veth pairs, the bridge driver, and how Docker's `bridge` network actually works. How NAT enables containers to reach the outside world. The `--network=host` and `--publish` flags explained through namespace behavior.