---
title: "WebRTC Architecture: Signaling, NAT Traversal (ICE/STUN/TURN) & SFU Media Servers"
description: Deep dive into WebRTC — SDP offer/answer signaling, NAT traversal with STUN and TURN, DTLS/SRTP encryption, and media server topologies (Mesh vs SFU vs MCU)
tags:
  - protocols
  - webrtc
  - real-time
  - media
  - video
date: 2026-01-30
---

# WebRTC Architecture: Signaling, NAT Traversal (ICE/STUN/TURN) & SFU Media Servers

**WebRTC (Web Real-Time Communication)** is an open standard and browser API enabling peer-to-peer, sub-500ms audio, video, and arbitrary data exchange directly between browsers and native clients without third-party plugins.

```mermaid
sequenceDiagram
    autonumber
    actor PeerA as Peer A (Browser)
    participant Signal as Signaling Server (WebSocket)
    participant STUN as STUN / TURN Server
    actor PeerB as Peer B (Browser)

    PeerA->>STUN: Discover Public IP & Port (STUN Binding Request)
    STUN-->>PeerA: Public Reflexive IP:Port
    PeerA->>Signal: Send SDP Offer (Codecs, Encryption, ICE Candidates)
    Signal->>PeerB: Forward SDP Offer
    PeerB->>STUN: Discover Public IP & Port
    STUN-->>PeerB: Public Reflexive IP:Port
    PeerB->>Signal: Send SDP Answer
    Signal->>PeerA: Forward SDP Answer
    Note over PeerA,PeerB: Direct P2P Media Stream Established via SRTP / UDP!
    PeerA<-->>PeerB: Encrypted Audio/Video (SRTP) + Data (SCTP/DTLS)
```

---

## 1. The Signaling Phase & SDP

WebRTC **does not define a signaling protocol**. Developers use WebSockets, gRPC, or HTTP to exchange metadata out-of-band:

- **Session Description Protocol (SDP):** A text format describing media capabilities (video resolution, supported codecs like VP8, VP9, H.264, Opus, and encryption keys).
- **Offer / Answer Model:** Peer A generates an `offer` SDP, sends it over the signaling channel to Peer B. Peer B responds with an `answer` SDP.

---

## 2. NAT Traversal: ICE, STUN, and TURN

Modern clients sit behind home routers, carrier-grade NATs (CGNAT), and corporate firewalls. Direct IP-to-IP connectivity fails without NAT traversal.

### 1. STUN (Session Traversal Utilities for NAT - RFC 5389)

- Client sends a UDP packet to a public STUN server (e.g. `stun:stun.l.google.com:19302`).
- The STUN server inspects the packet header and replies: _"You sent this from public IP `203.0.113.4` and port `54120`"_.
- Works for ~80% of consumer residential NATs (Full Cone, Restricted Cone).

### 2. Symmetric NATs & TURN (Traversal Using Relays around NAT - RFC 5766)

- In symmetric corporate NATs, the router assigns a _different_ port for every distinct destination IP. Direct P2P fails.
- **TURN Server:** Acts as an encrypted relay proxy in the public cloud. Both peers stream UDP/TCP traffic directly through the TURN server.
- **Bandwidth Impact:** TURN consumes significant server bandwidth (~1.5 Mbps per HD video stream).

### 3. ICE (Interactive Connectivity Establishment - RFC 5245)

- Gathers all potential connection addresses (**ICE Candidates**): Host (local LAN IP), Server Reflexive (STUN IP), and Relay (TURN IP).
- Concurrently probes candidate pairs and locks onto the lowest-latency, most direct path available.

---

## 3. Media Server Architectures: Mesh vs SFU vs MCU

When scaling a video call beyond two participants (e.g. Google Meet or Zoom):

```
1. Mesh (Full P2P):
   Every peer uploads to every other peer.
   Bandwidth: N * (N - 1) streams. Collapses on > 4 participants!

2. SFU (Selective Forwarding Unit):
   Every peer uploads 1 stream to SFU server. SFU forwards packets without decoding.
   Bandwidth: 1 upload, N - 1 downloads. The modern enterprise standard (LiveKit, Janus).

3. MCU (Multipoint Control Unit):
   Server decodes, composites, and re-encodes all video into a single video tile grid.
   Extremely high CPU cost; high latency. Used in legacy hardware telepresence.
```

---

## 4. Encryption & Security

WebRTC mandates end-to-end encryption at all times:

- **DTLS (Datagram Transport Layer Security):** Negotiates encryption keys and authenticates the peer connection over UDP.
- **SRTP (Secure Real-time Transport Protocol):** Encrypts voice and video payloads with AES-GCM.
- **Data Channels:** Arbitrary peer-to-peer binary/text data runs over **SCTP (Stream Control Transmission Protocol)** encapsulated inside DTLS.
