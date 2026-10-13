---
title: "Amazon VPC Lattice"
description: "Configure service-network boundaries, target routing and caller authorization with a complete staged workflow."
tags:
  - cloud/aws/networking
date: 2026-10-12
---

# Amazon VPC Lattice

VPC Lattice provides supported managed service networking and resource-access capabilities. It does not replace every VPC route, firewall or application authorization requirement. Start with [[AWS/networking/vpc/README|VPC]] and [[AWS/security/iam/policy-evaluation|IAM evaluation]].

## Service workflow

A service network groups services/access boundaries. Associate the intended consumer VPCs. A service needs a supported target group, registered targets, a listener and routing rules/default action. Creating only the network/service association does not create a working endpoint.

For AWS_IAM authentication, configure appropriate network/service auth policies and caller permissions, then use supported SigV4 signing. An auth-type setting without permitted identities does not provide successful access. Test unauthorized callers explicitly.

Supported HTTP/HTTPS/TLS and resource configurations have separate constraints; do not infer that a generic L7 path/header rule applies to every TCP/resource path. RAM sharing and network association do not grant arbitrary application permissions.

## Complete sandbox setup sequence

Prerequisites: two approved sandbox VPCs, a healthy disposable backend, scoped Lattice/RAM/IAM permissions and a cost budget.

1. Create the dedicated service network and intended VPC association with reviewed SGs.
2. Create a compatible target group; register the actual backend targets and inspect health.
3. Create a service, listener and a default forward action to that target group.
4. Associate the service with the network, configure auth policies and enable an approved access-log destination.
5. From the allowed consumer, resolve the returned DNS name and invoke with the required signing.
6. Repeat from an excluded identity/network; expect denial.
7. Temporarily make the sandbox target unhealthy; distinguish target-health failure from authentication failure.
8. Restore health, then remove associations, listener/rules, target registrations/group, service/network and dedicated logs in dependency order.

Use the owning CLI/API contracts with the **returned identifiers**, not fabricated sn-/svc- placeholders described as production commands. Do not report the exercise as tested until these checkpoints are executed in an approved account.

## Kubernetes and migration

Reuse [[Kubernetes/eks/networking/vpc-lattice/README|the canonical Gateway API controller lesson]]. Controller permissions/resources and supported route kinds must match the installed version. [[AWS/concepts/app-mesh-vs-vpc-lattice|App Mesh migration]] requires capability mapping and failure tests.

## Building-block map and diagnosis

```text
consumer VPC ─ associate → service network ─ associate → service
       │                      │                           ├─ auth policy
       │                 network auth policy              └─ listener/rule
       │                                                     │
       └── DNS + signed request ─────────────────────────→ target group
                                                          └─ registered backend
```

The service network groups associations and network-level policy. The service owns its listener, routing and service-level policy. A target group owns target type and health. These objects can exist independently; an associated network with no listener/healthy target will not serve the request. In a multi-account setup, resource sharing and consumer association are also distinct from IAM caller permission.

| Symptom                                 | Inspect first                                                   |
| --------------------------------------- | --------------------------------------------------------------- |
| Name does not resolve                   | Consumer VPC association and DNS path                           |
| Request denied                          | Auth type, SigV4 signing, caller IAM and network/service policy |
| Authorized request gets backend failure | Listener action, target registration, health and backend SG     |
| One path works, another fails           | Protocol and routing support for that target/resource type      |

For a rollout, publish a small sandbox service, collect access logs and test allowed and denied callers before adding production traffic. Compare the returned service DNS name and real target health with the expected configuration. Record all identifiers for dependency-order cleanup.

## References

- [Lattice concepts](https://docs.aws.amazon.com/vpc-lattice/latest/ug/what-is-vpc-lattice.html).
- [Target groups](https://docs.aws.amazon.com/vpc-lattice/latest/ug/target-groups.html).
- [Authentication](https://docs.aws.amazon.com/vpc-lattice/latest/ug/auth-policies.html).
- [CLI contract index](https://docs.aws.amazon.com/cli/latest/reference/vpc-lattice/).
- [Pricing](https://aws.amazon.com/vpc/lattice/pricing/).

## Across the wiki

- [[Azure/networking/private-link/README|Azure Private Link, Private Endpoints, and Private DNS Architecture]] — private connectivity (Azure)
- [[GCP/networking/private-service-connect/README|GCP Private Service Connect (PSC)]] — private connectivity (GCP)
- [[Azure/networking/virtual-wan/README|Azure Virtual WAN (vWAN) Architecture & Global Transit Routing]] — private connectivity (Azure)
