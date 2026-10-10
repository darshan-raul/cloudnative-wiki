---
title: The OSI 7-Layer Model in Modern Systems Engineering
description: Complete architectural breakdown of the Open Systems Interconnection (OSI) 7-layer model — PDUs, encapsulation, protocols, and debugging workflows
tags:
  - networking
  - architecture
  - osi
  - protocols
date: 2026-01-30
---

# The OSI 7-Layer Model in Modern Systems Engineering

The **Open Systems Interconnection (OSI)** model is a conceptual framework standardized by ISO (ISO/IEC 7498-1) that characterizes and standardizes the communication functions of telecommunication or computing systems without regard to their underlying internal structure and technology.

```mermaid
flowchart TD
    subgraph Host Layers (End-to-End)
        L7[Layer 7: Application — HTTP, gRPC, DNS, SSH, TLS]
        L6[Layer 6: Presentation — Serialization, Compression, Encryption]
        L5[Layer 5: Session — RPC, Sockets, Session Management]
        L4[Layer 4: Transport — TCP, UDP, QUIC, SCTP]
    end

    subgraph Media Layers (Hop-by-Hop)
        L3[Layer 3: Network — IP, ICMP, BGP, OSPF, Routers]
        L2[Layer 2: Data Link — Ethernet, MAC, ARP, VLANs, Switches]
        L1[Layer 1: Physical — Fiber, Copper, Radio, Bits]
    end

    L7 --> L6 --> L5 --> L4 --> L3 --> L2 --> L1
```

---

## 1. The 7 Layers Breakdown & Protocol Data Units (PDUs)

| Layer  | Name             | Protocol Data Unit (PDU)               | Core Responsibility                                         | Key Protocols / Standards                            | Hardware / Devices                      |
| :----- | :--------------- | :------------------------------------- | :---------------------------------------------------------- | :--------------------------------------------------- | :-------------------------------------- |
| **L7** | **Application**  | Data                                   | Direct application interaction, APIs, web traffic           | HTTP/1.1, HTTP/2, HTTP/3, gRPC, DNS, SMTP            | L7 Load Balancers (ALB, Envoy, Traefik) |
| **L6** | **Presentation** | Data                                   | Syntax translation, serialization, SSL/TLS negotiation      | JSON, Protobuf, gRPC, TLS 1.3, gzip, zstd            | Web Servers, Gateways                   |
| **L5** | **Session**      | Data                                   | Inter-host dialogue control, session checkpoints            | NetBIOS, RPC, SOCKS5                                 | OS Socket APIs                          |
| **L4** | **Transport**    | **Segment** (TCP) / **Datagram** (UDP) | Port addressing, reliable delivery, flow/congestion control | TCP, UDP, QUIC, SCTP                                 | L4 Load Balancers (NLB, IPVS, HAProxy)  |
| **L3** | **Network**      | **Packet**                             | Logical addressing (IP), route discovery, packet forwarding | IPv4, IPv6, ICMP, BGP, OSPF, IPsec                   | Routers, L3 Switches                    |
| **L2** | **Data Link**    | **Frame**                              | Physical addressing (MAC), framing, error detection (CRC)   | Ethernet (802.3), Wi-Fi (802.11), VLAN (802.1Q), ARP | L2 Network Switches, Bridges, NICs      |
| **L1** | **Physical**     | **Bit**                                | Transmission of raw unstructured bitstreams over media      | 1000BASE-T, Fiber (100GbE), SFP+, Radio RF           | Transceivers, Fiber cables, Hubs        |

---

## 2. Packet Encapsulation & Decapsulation

When a client sends an HTTP request:

```
Sender (Encapsulation):
[ HTTP Request Data ]                                          (L7 Data)
[ TCP Header | HTTP Request Data ]                             (L4 Segment)
[ IP Header | TCP Header | HTTP Data ]                         (L3 Packet)
[ Ethernet Header | IP Header | TCP Header | HTTP Data | FCS ] (L2 Frame)
010101101010101010101001010101010110...                        (L1 Bits on wire)
```

At the receiver, the network interface card (NIC) and kernel execute the inverse **decapsulation** pipeline, stripping headers layer by layer until the pure application payload reaches the socket buffer.

---

## 3. The DevOps / SRE Debugging Matrix

When an outage occurs, follow the OSI stack from Layer 1 up to Layer 7:

```
L1/L2 Check: Is the link up?
  $ ip link show eth0
  $ ethtool eth0
  $ arp -an

L3 Check: Can we route to the IP address?
  $ ping -c 3 10.0.1.50
  $ traceroute -n 10.0.1.50
  $ ip route get 10.0.1.50

L4 Check: Is the port listening and TCP handshake completing?
  $ nc -zv 10.0.1.50 443
  $ ss -tulpn | grep 443
  $ tcpdump -nn -i any port 443

L7 Check: Does the application respond with valid HTTP status?
  $ curl -Iv https://10.0.1.50/healthz
```

## Across the wiki

- [[Linux/networking/routing|Routing]] — packet path (Linux)
- [[Kubernetes/concepts/L04-services-networking/01-networking|Networking (L04 Overview)]] — packet path (Kubernetes)
- [[Linux/networking/tcp-ip-model|TCP/IP Model]] — packet path (Linux)
- [[Kubernetes/concepts/L04-services-networking/07-k8s-networking-deep-dive|Kubernetes Networking — Deep Dive]] — packet path (Kubernetes)
