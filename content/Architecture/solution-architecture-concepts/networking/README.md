---
title: Cloud-Native Networking Architecture Guide
description: Curated architectural guide to cloud-native networking — packet lifecycles, TCP/IP, OSI layers, routing protocols, and Kubernetes cluster networking
tags:
  - networking
  - architecture
  - guides
  - tcp
  - ip
date: 2026-01-30
---

# Cloud-Native Networking Architecture Guide

Understanding how packets traverse physical cables, operating system kernels, virtual network interfaces, overlay networks, and reverse proxies is the most fundamental diagnostic skill in cloud-native infrastructure engineering.

```mermaid
flowchart LR
    Client([Client Browser]) --> L7[Layer 7: HTTP/2 / TLS 1.3]
    L7 --> L4[Layer 4: TCP Handshake / Flow Control]
    L4 --> L3[Layer 3: IP Routing / Next-Hop / BGP]
    L3 --> Overlay[Overlay CNI: VXLAN / Geneve / WireGuard]
    Overlay --> Pod[Target Kubernetes Container]
```

---

## 1. Core Curriculum & Modules

### Foundations & Protocols

- [[Architecture/solution-architecture-concepts/networking/osi-model|OSI 7-Layer Model]]: Protocol Data Units (PDUs), packet encapsulation, and layer-by-layer troubleshooting.
- [[Architecture/solution-architecture-concepts/networking/tcpip|TCP/IP Architecture]]: 3-way handshake, 4-way close, `TIME_WAIT` vs `CLOSE_WAIT`, sliding window flow control, and BBR vs CUBIC congestion algorithms.
- [[Architecture/solution-architecture-concepts/networking/routing|IP Routing & BGP]]: Longest Prefix Match (LPM), routing tables, OSPF link-state vs BGP path-vector, and ECMP hash polarization.

### Real-Time & Streaming Protocols

- [[Architecture/solution-architecture-concepts/protocols/webrtc|WebRTC Architecture]]: Peer-to-peer audio/video streaming, SDP signaling, and NAT traversal via STUN/TURN.
- [[Architecture/solution-architecture-concepts/protocols/server-sent-events|Server-Sent Events (SSE)]]: Lightweight HTTP streaming for LLM token-by-token generation.

### Cloud & Kubernetes Networking

- [[AWS/networking/README|AWS VPC Networking]]: Subnets, Route Tables, Internet Gateways, NAT Gateways, Transit Gateway, and PrivateLink.
- [[Kubernetes/concepts/L04-services-networking/00-README|Kubernetes Networking]]: Pod-to-Pod communication, ClusterIP/NodePort Services, CNI plugins (Cilium, Calico), and Ingress controllers.

## More in this section

- [[Architecture/solution-architecture-concepts/networking/dns-over-https|dns over https]] — DNS over HTTPS (DoH) works by taking the traditional process of looking up a website's IP address and wrapping it in the same…
- [[Architecture/solution-architecture-concepts/networking/packet-flow|Packet flow]] — 1. TCP SYN-ACK Handshake.
- [[Architecture/solution-architecture-concepts/networking/tcp|TCP]] — TCP (Transmission Control Protocol)

## Further reading

- [Ipv6: why we need ipv6 (video)](https://youtu.be/42Hy4JtBeQA)
- [Ipv6: indepth into ipv6 ( and ipv4) (video)](https://youtu.be/6Lh8wpqJ0Oc)
- [Ipv6: aws (video)](https://youtu.be/bJK5R_dJCBY)

## Across the wiki

- [[AWS/networking/vpc/README|Amazon VPC]] — virtual networks (AWS)
- [[Azure/networking/vnet|Azure Virtual Network (VNet) & Hybrid Routing]] — virtual networks (Azure)
- [[GCP/networking/vpc|GCP Virtual Private Cloud (VPC) & Networking]] — virtual networks (GCP)
- [[Linux/networking/README|Linux Networking]] — virtual networks (Linux)
