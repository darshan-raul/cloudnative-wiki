---
title: IP Routing Fundamentals, BGP & ECMP Architecture
description: The mechanics of IP routing — Longest Prefix Match (LPM), routing tables, OSPF vs BGP, Autonomous Systems, and Equal-Cost Multi-Path (ECMP) load balancing
tags:
  - networking
  - routing
  - bgp
  - ospf
  - ecmp
  - infrastructure
date: 2026-01-30
---

# IP Routing Fundamentals, BGP & ECMP Architecture

**Routing** is the process of selecting paths across one or more networks to deliver Layer 3 IP packets from source to destination. Routers inspect the destination IP address of each incoming packet and consult their **Forwarding Information Base (FIB)** to choose the appropriate outbound interface and next-hop router.

---

## 1. The Core Principle: Longest Prefix Match (LPM)

When an IP packet arrives, multiple routes in the routing table may match the destination IP address. The router **always** selects the route with the **most specific subnet mask (longest prefix length)**.

### Example Routing Table:

```
1. 10.0.0.0/8     via 192.168.1.1  (Prefix length /8)
2. 10.20.0.0/16   via 192.168.1.2  (Prefix length /16)
3. 10.20.30.0/24  via 192.168.1.3  (Prefix length /24)
4. 0.0.0.0/0      via 192.168.1.254 (Default Route /0)
```

- If destination is `10.20.30.55`: Matches routes 1, 2, 3, and 4. **Route 3 (`/24`) wins** because 24 bits is the longest match.
- If destination is `10.20.99.1`: Matches routes 1, 2, and 4. **Route 2 (`/16`) wins**.
- If destination is `8.8.8.8`: Only matches route 4. **Default route (`0.0.0.0/0`) wins**.

---

## 2. Dynamic Routing: IGP vs EGP

Networks are divided into **Autonomous Systems (AS)**—collections of IP networks governed by a single administrative organization (e.g., Google is AS15169, Cloudflare is AS13335).

```
Autonomous System 100 (Internal DC)             Autonomous System 200 (Transit ISP)
┌─────────────────────────────────┐             ┌─────────────────────────────────┐
│ Router A <=== OSPF ===> Router B│ <== eBGP ==>│ Router C <=== OSPF ===> Router D│
└─────────────────────────────────┘             └─────────────────────────────────┘
```

| Dimension             | Interior Gateway Protocols (IGP)            | Exterior Gateway Protocols (EGP)                                  |
| :-------------------- | :------------------------------------------ | :---------------------------------------------------------------- |
| **Scope**             | Within a single datacenter or private WAN   | Between distinct companies and ISPs globally                      |
| **Dominant Protocol** | **OSPF** (Open Shortest Path First) / IS-IS | **BGP** (Border Gateway Protocol v4)                              |
| **Algorithm**         | Dijkstra Shortest Path First (Link-State)   | Path-Vector (AS Path, Local Preference, Multi-Exit Discriminator) |
| **Convergence Speed** | Sub-second (Milliseconds)                   | Seconds to Minutes                                                |
| **Routing Metric**    | Interface bandwidth / latency cost          | Business relationships, policy, AS hop count                      |

---

## 3. Border Gateway Protocol (BGP): The Glue of the Internet

BGP does not calculate the fastest physical path; it routes based on **policy, cost, and trust**:

- **iBGP (Internal BGP):** Synchronizes external routes between border routers within the same Autonomous System.
- **eBGP (External BGP):** Exchanges prefixes between distinct Autonomous Systems.
- **BGP Anycast:** Advertising the exact same IP prefix (e.g. `1.1.1.1` or `8.8.8.8`) from 300 data centers worldwide. Internet routers automatically deliver client packets to the nearest geographic PoP.

---

## 4. Equal-Cost Multi-Path (ECMP) Routing

When multiple equal-cost paths exist to the same destination CIDR, routers distribute packets across all paths simultaneously using **ECMP**.

### The Flow Hash Rule:

Routers compute a hash of the packet's 5-tuple:
$$\text{Hash} = \text{CRC32}(\text{src\_ip}, \text{dst\_ip}, \text{src\_port}, \text{dst\_port}, \text{protocol}) \pmod N$$

- **Per-Flow Consistency:** All packets belonging to the same TCP connection hash to the exact same physical link. This guarantees packets arrive **in order** and avoids TCP retransmissions.
- **Hash Polarization Pitfall:** If two consecutive tiers of network switches use the same hash algorithm and seed, traffic concentrates onto a single downstream link. Modern spine-leaf datacenter switches use randomized seeds per tier.

## Across the wiki

- [[Linux/networking/routing|Routing]] — packet path (Linux)
- [[Kubernetes/concepts/L04-services-networking/01-networking|Networking (L04 Overview)]] — packet path (Kubernetes)
- [[Linux/networking/tcp-ip-model|TCP/IP Model]] — packet path (Linux)
- [[Kubernetes/concepts/L04-services-networking/07-k8s-networking-deep-dive|Kubernetes Networking — Deep Dive]] — packet path (Kubernetes)
