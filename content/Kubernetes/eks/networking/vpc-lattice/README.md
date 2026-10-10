---
title: VPC Lattice with EKS
tags: [eks, networking, vpc-lattice, gateway-api, service-networking]
date: 2026-05-17
description: Connecting services across clusters, VPCs and accounts with Amazon VPC Lattice — its building blocks, the Gateway API controller, IAM auth policies, how traffic reaches it, and when to choose it over a service mesh or a load balancer.
---

# VPC Lattice with EKS

Amazon VPC Lattice is a managed application-networking service. It lets a client in one VPC call a service in another — a different cluster, a different account, or not Kubernetes at all — by name, **without any IP routing between the networks**. No peering, no Transit Gateway, no overlapping-CIDR problem, and no proxies for you to run.

On EKS it is driven through the Kubernetes [[Kubernetes/concepts/L04-services-networking/09-gateway-api|Gateway API]].

## Building blocks

| Lattice concept     | What it is                                                                | Gateway API object        |
| :------------------ | :------------------------------------------------------------------------ | :------------------------ |
| **Service network** | A logical boundary that groups services and the VPCs allowed to call them | `Gateway`                 |
| **Service**         | A named endpoint with listeners and routing rules                         | `HTTPRoute`, `GRPCRoute`  |
| **Target group**    | The backends: pod IPs, instances, Lambda functions, ALBs                  | The route's `backendRefs` |
| **VPC association** | Lets clients in a VPC reach the service network                           | Created with the Gateway  |
| **Auth policy**     | An IAM policy on a service network or service                             | `IAMAuthPolicy`           |

```
client VPC (any account) ──association──► service network ──► service "orders" ──► target group ──► pods in cluster B
        │                                        ▲
        └── DNS: orders-xyz.vpc-lattice-svcs…    └── service "payments" ──► Lambda
```

A client resolves the service's DNS name to a **link-local address** that only exists inside associated VPCs. Lattice carries the request over AWS's network and delivers it to a healthy target. Because routing is not IP-based, the two VPCs can use identical CIDRs.

## The Gateway API controller

Install the **AWS Gateway API Controller** in each cluster that publishes or consumes services. It needs an [[AWS/security/iam/README|IAM]] role (through [[Kubernetes/eks/security/pod-identity|Pod Identity]]) allowing `vpc-lattice:*` actions and tagging, and the node security group must allow inbound traffic from the Lattice managed prefix list.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: amazon-vpc-lattice
spec:
  controllerName: application-networking.k8s.aws/gateway-api-controller
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shared-services # maps to a service network of the same name
  namespace: platform
spec:
  gatewayClassName: amazon-vpc-lattice
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      allowedRoutes:
        namespaces: { from: All }
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: orders
  namespace: orders
spec:
  parentRefs:
    - name: shared-services
      namespace: platform
      sectionName: https
  rules:
    - matches:
        - path: { type: PathPrefix, value: /v2 }
      backendRefs:
        - { name: orders-v2, port: 80, weight: 90 }
        - { name: orders-v3, port: 80, weight: 10 }
```

The controller creates the Lattice service, target groups registered with pod IPs, and the listener rules. Weighted backends give canary releases without a mesh.

**Across clusters:** a `ServiceExport` in one cluster publishes a Kubernetes Service as a Lattice target group; a `ServiceImport` in another lets an `HTTPRoute` reference it as a backend. One route can therefore split traffic between clusters — useful for migrations and blue-green cluster upgrades.

## Authentication and authorization

Lattice can require every request to be **SigV4-signed**, and evaluates an IAM policy before forwarding it:

```yaml
apiVersion: application-networking.k8s.aws/v1alpha1
kind: IAMAuthPolicy
metadata:
  name: orders-callers
  namespace: orders
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: orders
  policy: |
    {
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": { "AWS": "arn:aws:iam::111122223333:role/checkout" },
        "Action": "vpc-lattice-svcs:Invoke",
        "Resource": "*",
        "Condition": { "StringEquals": { "vpc-lattice-svcs:RequestMethod": "GET" } }
      }]
    }
```

The caller's identity is its IAM role — the same role a pod already has through Pod Identity. That gives identity-based, cross-account authorization with no certificates to manage. The catch is that **clients must sign requests**: either in application code with an AWS SDK signer, or through a signing proxy sidecar. Unsigned traffic is rejected when auth is enabled.

Encryption in transit is HTTPS to the Lattice endpoint, with your own certificate from [[AWS/security/certificate-manager/README|ACM]] for custom domain names.

## Lattice, a service mesh, or a load balancer

|                           | VPC Lattice                           | [[Kubernetes/guides/networking/service-mesh\|Service mesh]] | Internal ALB / NLB                |
| :------------------------ | :------------------------------------ | :---------------------------------------------------------- | :-------------------------------- |
| Data plane you operate    | None                                  | Sidecars or node proxies                                    | None                              |
| Crosses VPCs and accounts | Natively, no routing needed           | With multi-cluster setup and connectivity                   | Needs peering, TGW or PrivateLink |
| Overlapping CIDRs         | Fine                                  | A problem                                                   | A problem                         |
| Non-Kubernetes targets    | EC2, Lambda, ECS, ALB                 | Limited                                                     | Yes                               |
| Identity                  | IAM (SigV4)                           | mTLS workload identity                                      | None built in                     |
| Traffic management        | Path, header, method, weights         | Rich: retries, timeouts, mirroring, fault injection         | Basic                             |
| In-cluster pod-to-pod     | Possible, not the main use            | The main use                                                | Not applicable                    |
| Pricing                   | Per service-hour, per GB, per request | Compute for proxies                                         | Per LB-hour and per GB            |

They are complementary. A mesh handles dense east-west traffic _inside_ a cluster with fine-grained control; Lattice connects services _between_ clusters, accounts and compute types. AWS App Mesh has been retired, and Lattice is the suggested path for cross-boundary service networking — [[AWS/concepts/app-mesh-vs-vpc-lattice|App Mesh vs VPC Lattice]].

## When it fits

- Many accounts and VPCs, where maintaining peering or Transit Gateway routes for service calls has become a burden.
- Overlapping address ranges that make routing impossible.
- Services spread across EKS, ECS, Lambda and EC2 that need one way to find and call each other.
- Migrations: shift traffic gradually from an old cluster or from instances to a new cluster.
- A requirement for IAM-based, auditable service-to-service authorization.

## Limits and pitfalls

| Issue                       | Detail                                                                                     |
| :-------------------------- | :----------------------------------------------------------------------------------------- |
| Security group rule missing | Targets show unhealthy until the Lattice prefix list is allowed on the node or pod SG      |
| Clients not signing         | `403 AccessDenied` once an auth policy is attached                                         |
| Cost at high volume         | Per-request and per-GB charges add up for very chatty services                             |
| Protocols                   | HTTP, HTTPS, gRPC and TLS passthrough; not arbitrary TCP or UDP                            |
| Source IP                   | Targets see Lattice's address; the caller is in the `X-Forwarded-For` and identity headers |
| Request limits              | Timeouts and payload sizes are bounded — check the service quotas                          |
| Observability               | Enable access logs to CloudWatch, S3 or Firehose per service network                       |

## Related

- [[Kubernetes/eks/networking/README|EKS networking overview]]
- [[AWS/concepts/vpc-lattice|VPC Lattice (AWS section)]]
- [[Kubernetes/eks/advanced/advanced-networking|Advanced EKS networking]]
- [[Kubernetes/guides/tools/multi-cluster|Multi-cluster tooling]]
- [VPC Lattice with EKS](https://docs.aws.amazon.com/eks/latest/userguide/vpc-lattice.html)
- [EKS Workshop: VPC Lattice](https://www.eksworkshop.com/docs/networking/vpc-lattice/)

## Across the wiki

- [[Azure/networking/private-link/README|Azure Private Link, Private Endpoints, and Private DNS Architecture]] — private connectivity (Azure)
- [[GCP/networking/private-service-connect/README|GCP Private Service Connect (PSC)]] — private connectivity (GCP)
- [[Azure/networking/virtual-wan/README|Azure Virtual WAN (vWAN) Architecture & Global Transit Routing]] — private connectivity (Azure)
