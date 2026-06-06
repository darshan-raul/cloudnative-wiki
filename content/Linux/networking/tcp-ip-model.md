---
title: TCP/IP Model
description: TCP/IP 4-layer model — application, transport, internet, link layer, encapsulation, OSI comparison, key protocols
tags:
  - linux
  - networking
---

# TCP/IP Model

The TCP/IP model describes how internet traffic works. It's a 4-layer model that maps directly to Linux's kernel network stack. Understanding it makes troubleshooting, firewall rules, and container networking intuitive.

## The 4 Layers

```
┌─────────────────────────────────────────────────────────┐
│  Layer 4: Application    — HTTP, DNS, SSH, SMTP        │
│  Your program: curl, nginx, postgresql                  │
├─────────────────────────────────────────────────────────┤
│  Layer 3: Transport      — TCP, UDP, SCTP               │
│  Connection: reliable stream vs fire-and-forget datagram│
├─────────────────────────────────────────────────────────┤
│  Layer 2: Internet       — IP (IPv4, IPv6), ICMP, routing│
│  Addressing: IP addresses, routing between networks     │
├─────────────────────────────────────────────────────────┤
│  Layer 1: Link/Access   — Ethernet, WiFi, ARP          │
│  Frames: MAC addresses, switch forwarding              │
└─────────────────────────────────────────────────────────┘
```

## Encapsulation: How Data Moves Down

```
Application:  "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
              ↓
Transport:    [TCP header | Payload]  (segment)
              ↓
Internet:     [IP header | TCP segment]  (packet/datagram)
              ↓
Link:         [Ethernet header | IP packet | Ethernet trailer]  (frame)
              ↓
Physical:     111010101... (bits on wire)
```

Each layer adds its own header. The peer layer at the destination strips it and passes up.

## Layer 1: Link/Access Layer

**Ethernet** is the dominant link protocol. It uses MAC (Media Access Control) addresses:

```
MAC address:  52:54:00:12:34:56
Format:       6 bytes, colon-separated (or dash-separated)
First 3 bytes: OUI (manufacturer, e.g., 52:54:00 = QEMU)
Last 3 bytes:  device-specific assigned by NIC
```

Linux shows MAC in `/sys/class/net/eth0/address`.

**ARP** (Address Resolution Protocol) maps IP → MAC:

```
Host wants to send to 192.168.1.1
  ↓
ARP broadcast: "Who has 192.168.1.1? Tell 192.168.1.100"
  ↓
192.168.1.1 replies: "192.168.1.1 is at aa:bb:cc:dd:ee:ff"
  ↓
ARP cache updated
```

```bash
# View ARP cache
ip neigh show
# 192.168.1.1 dev eth0 lladdr aa:bb:cc:dd:ee:ff REACHABLE

# See ARP table
arp -n

# Flush ARP cache (when MAC changes)
ip neigh flush all
```

## Layer 2: Internet Layer

### IP (Internet Protocol)

**IPv4** — 32-bit addresses, written as 4 decimal octets:

```
10.0.0.1        — private (RFC 1918)
172.16.0.0/12   — private (RFC 1918)
192.168.0.0/16  — private (RFC 1918)
169.254.0.0/16  — link-local (no DHCP, e.g. eth0)
8.8.8.8         — public
```

**IPv6** — 128-bit addresses, written in hex groups:

```
fe80::1                — link-local
2001:db8::1            — documentation prefix
2a00:1450:4001:820e::  — public (Google DNS)
```

```bash
# View IP addresses
ip addr show
# 2: eth0: <BROADCAST,MULTICAST,UP> mtu 1500 qdisc fq_codel state UP
#     inet 192.168.1.100/24 brd 192.168.1.255 scope global eth0
#     inet6 fe80::a00:27ff:fe8e:8aa8/64 scope link

# CIDR notation: /24 means 24 bits of network = 256 addresses
#   192.168.1.0/24 → network: 192.168.1.0, broadcast: 192.168.1.255
#   usable: 192.168.1.1 – 192.168.1.254 (254 hosts)
```

### Routing

IP's job is to move packets between networks. A **route** says: "to reach this destination, send packets via this gateway":

```
# Routing table
ip route show
# default via 192.168.1.1 dev eth0 proto dhcp
# 192.168.1.0/24 dev eth0 proto kernel scope link src 192.168.1.100
```

- **default route** (0.0.0.0/0): catch-all, send to gateway
- **link-local route**: directly reachable hosts on the same network (no gateway)
- **gateway**: the next-hop router

```
To reach 8.8.8.8:
  1. Check route table for 8.8.8.8
  2. No specific match → use default route
  3. Send packet to 192.168.1.1 (gateway)
  4. Gateway has its own routing table
  5. Process repeats until packet arrives
```

### ICMP

ICMP (Internet Control Message Protocol) is IP's error reporting and diagnostic system:

```
ping 8.8.8.8
  ↓
ICMP Echo Request (type 8) → IP header protocol=1
  ↓
ICMP Echo Reply (type 0) ← IP header protocol=1
```

Important ICMP types:
| Type | Name | Use |
|------|------|-----|
| 0 | Echo Reply | ping response |
| 3 | Destination Unreachable | firewall block, no route |
| 5 | Redirect | gateway tells host to use better route |
| 8 | Echo Request | ping |
| 11 | Time Exceeded | traceroute |

```bash
# ping
ping -c 3 8.8.8.8

# traceroute (UDP on Linux, ICMP on macOS)
traceroute 8.8.8.8
tracepath 8.8.8.8      # no root needed

# ICMP rate limiting (sysctl)
sysctl -w net.ipv4.icmp_ratelimit=1000
```

## Layer 3: Transport Layer

### TCP — Transmission Control Protocol

TCP provides **reliable, ordered, connection-oriented** byte streams:

```
Connection setup (3-way handshake):
  Client                Server
    │──── SYN ──────────────────▶│  seq=c_isn
    │◀─── SYN-ACK ──────────────│  seq=s_isn ack=c_isn+1
    │──── ACK ──────────────────▶│  seq=c_isn+1 ack=s_isn+1

Data transfer:
    │─────── DATA (seq) ────────▶│
    │◀─────── ACK (ack) ─────────│

Connection teardown (4-way):
    │──── FIN ──────────────────▶│
    │◀──── ACK ──────────────────│
    │◀──── FIN ──────────────────│
    │──── ACK ──────────────────▶│
```

**Key TCP concepts:**
- **Sequence numbers**: every byte is numbered (prevents gaps, enables ordering)
- **ACK**: receiver acknowledges receipt (cumulative)
- **Window size**: how much data can be sent before waiting for ACK (flow control)
- **Congestion window**: how much TCP sends before ACK (slow start + congestion avoidance)

```bash
# TCP stats
ss -tlnp                  # listening TCP sockets
ss -tn                    # established connections
ss -ti                    # TCP info (snd-cwnd, rtt, etc.)
```

### UDP — User Datagram Protocol

UDP provides **best-effort datagrams** — no connection, no ordering, no reliability:

```
No handshake:
  Client                Server
    │─────── DATAGRAM ──────────▶│  (fire and forget)
    │─────── DATAGRAM ──────────▶│

No guarantee of delivery or order.
Applications: DNS (single request/response), QUIC, video streaming, VoIP
```

### TCP vs UDP Quick Comparison

| Property | TCP | UDP |
|---------|-----|-----|
| Connection | Connected (handshake) | Connectionless |
| Reliability | Reliable (ACK, retransmit) | None |
| Ordering | Ordered (sequence numbers) | None |
| Overhead | 20 bytes + options | 8 bytes |
| Speed | Slower (handshake + ACK) | Faster (no overhead) |
| Use cases | HTTP, SSH, PostgreSQL | DNS, DHCP, VoIP, QUIC |

## Key Ports (Well-Known)

```bash
# /etc/services — port → service name mapping
cat /etc/services | grep -E "(http|ssh|dns|smtp|ntp)"
# http             80/tcp
# https            443/tcp
# ssh              22/tcp
# domain           53/udp         # DNS
# sntp             123/udp        # NTP
```

Common listening ports on a Linux server:

```bash
ss -tlnp | awk '{print $4}' | grep -oE ':[0-9]+' | sort | uniq -c | sort -rn | head
#      2 :22      (ssh)
#      1 :80      (http)
#      1 :443     (https)
#      1 :53      (dns)
```

## Linux Network Stack Flow

```
NIC receives frame
  → DMA to kernel ring buffer
  → netfilter (iptables PREROUTING)
  → routing decision (is it for local? forward?)
      ↓ local delivery
      IP layer → TCP/UDP layer → socket buffer → application
      ↓ forwarding
      netfilter (iptables FORWARD)
      → routing lookup → NIC egress
```

```bash
# See packet counters at each netfilter hook
cat /proc/net/stat/nf_conntrack
```

## /proc/sys/net

```bash
# TCP tuning
sysctl -a --pattern tcp | head -20
# net.ipv4.tcp_timestamps = 1
# net.ipv4.tcp_sack = 1
# net.ipv4.tcp_window_scaling = 1
# net.ipv4.tcp_congestion_control = cubic

# Buffer sizes
sysctl net.core.rmem_max
sysctl net.core.wmem_max
sysctl net.ipv4.tcp_rmem
sysctl net.ipv4.tcp_wmem
```