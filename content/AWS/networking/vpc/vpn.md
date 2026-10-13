---
title: "AWS VPN"
description: "Distinguish Site-to-Site routing and tunnel resilience from Client VPN workforce authentication and access."
tags:
  - cloud/aws/networking/hybrid
date: 2026-10-12
---

# AWS VPN

Site-to-Site VPN connects supported networks through encrypted tunnels; Client VPN connects individual clients. Start with [[AWS/networking/hybrid/README|hybrid topology]], [[AWS/networking/vpc/README|routes]] and [[AWS/security/iam/identity-center|workforce identity]].

## Site-to-Site

A customer gateway resource represents the supported customer endpoint; the AWS termination can use a VGW or TGW design. Configure both tunnels and verify actual failover. Static and dynamic BGP routing are supported with different operational implications.

BGP/ECMP, tunnel bandwidth, acceleration and endpoint address options are mode-specific. Do not universalize one bandwidth/default ASN/IPv4 requirement to all VPN variants. A quota increase is not a throughput guarantee.

## Client VPN

Authentication options include Active Directory, mutual certificates and SAML federation. OIDC is not a documented direct Client VPN authentication option; Active Directory is not the same mechanism as SAML federation.

Target-network associations, endpoint routes, authorization rules and SGs are separate. Authentication success alone does not authorize every destination. Split/full tunnel decisions affect routing, DNS and egress.

## Sandbox access drill

Prerequisites: approved test VPN endpoint and a nonsensitive private server, scoped administration and an independent management path. Tunnel/endpoint/connection charges may apply.

1. Record client/source identity, authorized destination and expected route.
2. Connect and test only the allowed service.
3. Attempt an excluded destination; expect failure despite successful authentication.
4. For Site-to-Site, test an approved single-tunnel failure and observe route/client recovery.
5. Restore the original configuration; verify both tunnels/routes or intended client associations.
6. Remove dedicated endpoints/connections/associations, customer-gateway resources and logs only after confirming no shared dependency.

Collect client/server logs, route tables and connection status; distinguish credentials, certificate validity, DNS, routes and SG failures. Measure failover rather than quoting a fixed application recovery time.

## Routing and access comparison

| Question        | Site-to-Site VPN                                | Client VPN                                              |
| --------------- | ----------------------------------------------- | ------------------------------------------------------- |
| Who connects?   | Customer network gateway to AWS gateway         | Individual client to endpoint                           |
| Routing         | Static or BGP with tunnel routes                | Endpoint route table plus target network association    |
| Access boundary | Prefixes, SGs/NACLs and customer firewall       | Authentication, authorization rules, routes and SGs     |
| Resilience test | Both tunnels and customer/AWS route convergence | Endpoint association, client reconnect and DNS behavior |

```text
on-prem router → tunnel A/B → VGW or TGW → VPC subnet → private service
user device → Client VPN endpoint → target association → authorized route → service
```

For BGP Site-to-Site VPN, record advertised/accepted prefixes and route priority; for static routing, maintain the explicit prefixes on both ends. In both cases, confirm return routing and MTU-sensitive application behavior. For Client VPN, a successful authentication result only establishes identity; the destination also needs an authorization rule, endpoint route, associated target network and matching SG. Split-tunnel clients may retain local routes that affect which resolver or path handles a request.

## References

- [Site-to-Site routing types](https://docs.aws.amazon.com/vpn/latest/s2svpn/VPNRoutingTypes.html).
- [Site-to-Site introduction](https://docs.aws.amazon.com/vpn/latest/s2svpn/VPC_VPN.html).
- [Client VPN authentication](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/client-authentication.html).
- [Client authorization](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/cvpn-working-rules.html).
- [Pricing](https://aws.amazon.com/vpn/pricing/).

## Across the wiki

- [[GCP/networking/hybrid/README|GCP Cloud Interconnect & HA VPN]] — hybrid connectivity (GCP)
- [[Kubernetes/eks/compute/hybrid-nodes/README|EKS Hybrid Nodes]] — hybrid connectivity (Kubernetes)
