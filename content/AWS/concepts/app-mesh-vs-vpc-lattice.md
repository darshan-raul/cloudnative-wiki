---
title: "App Mesh retirement and service-networking choices"
description: "Retain historical App Mesh context and select supported networking alternatives by workload requirements."
tags:
  - cloud/aws/networking
date: 2026-10-12
---

# App Mesh retirement and service-networking choices

AWS App Mesh reached end of support on **September 30, 2026**; its console/resources are no longer available. Do not recommend a new App Mesh deployment.

## Historical model versus supported choices

App Mesh configured Envoy-based service proxies. [[AWS/concepts/vpc-lattice|VPC Lattice]] provides supported managed service-networking capabilities without requiring an App Mesh-style sidecar for every service, but it is not a promise of feature-for-feature migration.

For ECS, evaluate supported Service Connect. For Kubernetes, evaluate the [[Kubernetes/eks/networking/vpc-lattice/README|Gateway API/Lattice track]] or an intentionally operated mesh if its required features justify that ownership.

Compare protocols, caller authentication, routing/traffic shifting, retries/timeouts, telemetry, network reachability and resource-access needs. Do not equate service networking with general transitive IP routing.

## Migration exercise

Inventory every old proxy-dependent capability and map it to a supported replacement or explicit application change. Run a small parallel test path, verify identity/authorization and failure behavior, then shift traffic with rollback. Sidecar removal alone does not prove preserved policy or telemetry.

## Capability comparison for migration

| Requirement                                     | Historical App Mesh design                             | Supported choice to evaluate                                           |
| ----------------------------------------------- | ------------------------------------------------------ | ---------------------------------------------------------------------- |
| Per-workload proxy telemetry and traffic policy | Envoy sidecar/proxy managed with mesh resources        | Operated Envoy/Istio where that exact proxy behavior is required       |
| Cross-VPC service access                        | Additional network connectivity and mesh configuration | VPC Lattice service network, service/resource access and authorization |
| ECS service-to-service discovery/traffic        | Mesh sidecar integration                               | ECS Service Connect for supported workloads                            |
| Kubernetes route resources                      | App Mesh controller/proxies                            | Gateway API/Lattice or an operated mesh, according to needed features  |

For each migrated service, inventory protocol, retry/timeout behavior, weighted traffic, authentication identity, TLS boundary, logs/metrics/traces and service discovery. Build a test matrix for success, denied caller, unhealthy target and rollback. Lattice can simplify cross-VPC exposure, but a service-network association still needs targets, listeners and policies; an Envoy policy does not automatically translate to a Lattice policy.

## References

- [Owning App Mesh retirement notice](https://docs.aws.amazon.com/app-mesh/latest/userguide/what-is-app-mesh.html).
- [ECS Service Connect](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect.html).
- [Lattice overview](https://docs.aws.amazon.com/vpc-lattice/latest/ug/what-is-vpc-lattice.html).
