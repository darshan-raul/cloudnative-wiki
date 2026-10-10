---
title: "TCP"
tags: [architecture, networking, tcp]
date: 2026-10-10
description: "TCP (Transmission Control Protocol)"
---

# TCP

"https://www.youtube.com/watch?v=JWUsO1vmPcE"

**TCP (Transmission Control Protocol)**

- **Reliability:** TCP is a connection-oriented protocol, meaning it establishes a virtual circuit before sending any data. It guarantees delivery and maintains the order of data packets.
- **Flow Control:** TCP prevents the sender from overwhelming the receiver by implementing a dynamic window size. If the receiver is slower, it communicates to the sender to slow down the transmission rate.
- **Congestion Control:** TCP uses mechanisms like slow start and congestion avoidance algorithms to regulate traffic on the network, preventing collapse under heavy loads.
- **Three-way Handshake (SYN, SYN-ACK, ACK):** This is how TCP initiates reliable connections and synchronizes sequence numbers.
- **FIN-ACK Sequence:** TCP uses a graceful four-step process to terminate connections, ensuring all data is transferred and acknowledged.

## Across the wiki

- [[Linux/networking/routing|Routing]] — packet path (Linux)
- [[Kubernetes/concepts/L04-services-networking/01-networking|Networking (L04 Overview)]] — packet path (Kubernetes)
- [[Linux/networking/tcp-ip-model|TCP/IP Model]] — packet path (Linux)
- [[Kubernetes/concepts/L04-services-networking/07-k8s-networking-deep-dive|Kubernetes Networking — Deep Dive]] — packet path (Kubernetes)
