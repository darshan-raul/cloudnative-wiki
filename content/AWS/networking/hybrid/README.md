---
title: "Hybrid connectivity: Direct Connect and VPN"
description: "Map VIFs, gateways, tunnels, routing and encryption, then test failover without treating topology labels as SLAs."
tags:
  - cloud/aws/networking/hybrid
date: 2026-10-12
---

# Hybrid connectivity: Direct Connect and VPN

Direct Connect supplies dedicated connectivity; Site-to-Site VPN supplies supported encrypted tunnels. They can complement each other, but neither independently guarantees workload availability. Start with [[AWS/networking/vpc/README|VPC]], [[AWS/networking/vpc/transit-gateway|TGW]] and [[AWS/networking/vpc/vpn|VPN]].

## Map the components

Private VIFs connect supported private paths through VGW/DX gateway associations. Public VIFs reach supported public AWS service addresses, not arbitrary internet destinations. Transit VIFs connect through the supported DX gateway/TGW design. Physical connections, provider cross-connects and virtual interfaces are distinct.

Direct Connect uses BGP. VPN supports dynamic BGP or static routing; lack of BGP does not prohibit a TGW VPN attachment. Configure both VPN tunnels and test route preference/convergence. Association and propagation must be deliberate.

A DX gateway is not a general transitive router among every attached VPC. Inspect allowed prefixes, association rules and supported topology before promising multi-Region connectivity.

## Encryption and resilience

DX is not inherently end-to-end application encryption. Use supported MACsec and/or IPsec-over-DX designs as appropriate, and TLS for application confidentiality. Private IP VPN over DX has its own supported prerequisites; a public VIF is not universally required for every encrypted DX architecture.

Spread resilient connections across the documented locations/devices and measure recovery when a circuit/router fails. A quoted SLA requires the corresponding topology and contract conditions; it is not a fixed latency or failover promise.

## Failover design exercise

Prerequisites: an existing approved sandbox/test hybrid path or a documented tabletop model; do not purchase physical circuits for this drill.

1. Record prefixes, ASNs, advertisements, route priorities and application endpoints.
2. Confirm primary traffic follows the intended DX path and backup tunnels are ready.
3. Simulate an approved path withdrawal/failure without changing production.
4. Observe BGP/static route behavior, application retries and return-path symmetry.
5. Restore the path and verify failback without loops/blackholes.
6. Document timings, packet loss and owner actions; restore every temporary route/policy.

For private DNS, follow [[AWS/networking/private-access-and-hybrid-dns|Resolver forwarding]]; network reachability does not imply namespace resolution.

## Cost and capacity

Model DX port-hours, provider/cross-connect charges and applicable outbound transfer; VPN connection-hours and transfer/accelerated options are separate. VPN is not priced universally per tunnel, and it is not a flat all-inclusive unlimited-data bill. Add TGW and inspection charges if present.

Prefix/bandwidth limits differ by VIF/connection/tunnel type and quota scope. Use the owning tables, not a universal “100 prefixes adjustable to any count” statement.

## Connection and routing map

```text
on-prem router ─ cross-connect/provider ─ DX location
     │                                  └─ private/transit VIF → DX gateway → VGW/TGW
     └─ IPsec Site-to-Site VPN tunnels ──────────────────────────────→ VGW/TGW
                                                       │
                                                 VPC route tables
                                                       │
                                                    workload
```

| Path             | Strength                                                             | Important dependency                                             |
| ---------------- | -------------------------------------------------------------------- | ---------------------------------------------------------------- |
| Direct Connect   | Dedicated physical connectivity and predictable path characteristics | Circuit/provider, BGP, correct VIF/gateway association           |
| Site-to-Site VPN | Encrypted tunnel on supported underlying connectivity                | Both tunnels, internet or private transport, routing convergence |
| Both             | Primary/backup or encryption over dedicated path                     | Route preference, return symmetry and tested failover            |

Arrange the connection or hosted connection, create the matching VIF, establish BGP, attach/associate the gateway, advertise only approved prefixes and update VPC/on-prem routes. Validate MTU, allowed prefixes, security policy and DNS from an actual workload. A BGP-established session proves route exchange, not end-to-end application reachability. For resilience, test independent equipment and failure domains, then record how long both directions take to converge.

### Example failure record

For a test application on `10.20.0.0/16`, record the on-prem prefix, AWS prefix, both tunnel/circuit states and the next hop chosen in each direction. Withdraw only the approved primary BGP path. The test succeeds if the route moves to the backup path, application connections recover within the agreed objective, and DNS still resolves to the intended private address. If packets leave on VPN but return on DX, review route preferences and firewall state; an asymmetric return can break a stateful security appliance. Restore the primary advertisement and verify failback without a route loop.

## References

- [DX virtual interfaces](https://docs.aws.amazon.com/directconnect/latest/UserGuide/WorkingWithVirtualInterfaces.html).
- [DX gateways](https://docs.aws.amazon.com/directconnect/latest/UserGuide/direct-connect-gateways-intro.html).
- [DX resiliency](https://docs.aws.amazon.com/directconnect/latest/UserGuide/resiliency_toolkit.html).
- [VPN routing](https://docs.aws.amazon.com/vpn/latest/s2svpn/VPNRoutingTypes.html).
- [DX pricing](https://aws.amazon.com/directconnect/pricing/).
- [VPN pricing](https://aws.amazon.com/vpn/pricing/).

## Across the wiki

- [[GCP/networking/hybrid/README|GCP Cloud Interconnect & HA VPN]] — hybrid connectivity (GCP)
- [[Kubernetes/eks/compute/hybrid-nodes/README|EKS Hybrid Nodes]] — hybrid connectivity (Kubernetes)
