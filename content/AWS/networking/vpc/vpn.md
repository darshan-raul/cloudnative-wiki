---
title: AWS Site-to-Site VPN & Client VPN
description: Connecting on-premises networks and remote users to AWS VPCs via IPsec Site-to-Site VPN and AWS Client VPN
tags:
  - aws
  - networking
  - vpc
  - vpn
  - ipsec
---

# AWS Site-to-Site VPN & Client VPN

AWS provides managed VPN solutions to connect remote networks (on-premises data centers, branch offices) and remote users securely to your Amazon VPCs over encrypted IPsec and OpenVPN tunnels.

---

## 1. AWS Site-to-Site VPN Architecture

An AWS Site-to-Site VPN creates an encrypted IPsec tunnel over the public internet between your on-premises network and AWS.

```
On-Premises Data Center                     AWS Cloud
┌─────────────────────────┐                ┌─────────────────────────┐
│ Customer Gateway (CGW)  │                │ Virtual Private Gateway │
│ Physical Appliance / IP │                │ (VGW) or Transit Gateway│
└───────────┬─────────────┘                └────────────┬────────────┘
            │                                           │
            │==== IPsec Tunnel 1 (Active) ==============│
            │                                           │
            │==== IPsec Tunnel 2 (Standby / ECMP) ======│
            └───────────────────────────────────────────┘
```

### Core Components:

1. **Virtual Private Gateway (VGW):** The VPN concentrator attached to a single VPC.
2. **Transit Gateway (TGW) Attachment:** For multi-VPC topologies, attach the VPN to an AWS Transit Gateway. Supports Equal-Cost Multi-Path (ECMP) routing across multiple tunnels to exceed the 1.25 Gbps per-tunnel bandwidth limit.
3. **Customer Gateway (CGW):** The AWS resource representing your on-premises router/firewall appliance (requires a public static IPv4 address).
4. **Dual Tunnels:** AWS automatically provisions **two redundant IPsec tunnels** per VPN connection terminating in different Availability Zones. Always configure both tunnels on your CGW for high availability.

---

## 2. Routing: Dynamic (BGP) vs Static

| Feature            | Dynamic Routing (BGP)                             | Static Routing                            |
| :----------------- | :------------------------------------------------ | :---------------------------------------- |
| **Protocol**       | Border Gateway Protocol (ASN 64512-65534)         | Static CIDR routes entered in route table |
| **Failover**       | **Automatic sub-second failover** between tunnels | Manual route updates or health probes     |
| **ECMP Scaling**   | Supported (up to ~5 Gbps aggregate throughput)    | Not supported                             |
| **Recommendation** | **Best Practice for all production networks**     | Legacy firewalls without BGP support      |

---

## 3. AWS Client VPN

For individual remote workers (laptops/workstations):

- Managed client-based VPN service based on **OpenVPN**.
- Integrates with corporate identity providers via **Active Directory (SAML 2.0 / OIDC)** or mutual certificate authentication.
- Elastic and serverless: scales connection capacity automatically.
