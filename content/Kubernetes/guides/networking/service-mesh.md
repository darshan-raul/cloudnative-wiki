---
title: Service Mesh
tags: [kubernetes, networking, service-mesh, istio, linkerd, cilium, mtls]
date: 2026-10-10
description: What a service mesh is and whether you need one — the problems it solves, sidecar versus sidecarless data planes, what mTLS identity gives you, the main implementations compared, the costs, and an adoption path.
---

# Service Mesh

A service mesh is infrastructure that handles communication **between services** on their behalf. Instead of each application implementing encryption, retries, timeouts, load balancing and request metrics in its own language and library, a proxy layer does it uniformly for every service, configured centrally.

It is powerful and it is not free. Many clusters do not need one. This note is about deciding, and then about choosing.

## The problems it addresses

| Need                                               | Without a mesh                                                                                    | With a mesh                                     |
| :------------------------------------------------- | :------------------------------------------------------------------------------------------------ | :---------------------------------------------- |
| Encrypt service-to-service traffic                 | TLS code and certificate handling in every service                                                | Automatic mutual TLS, with rotation             |
| Know _which workload_ is calling                   | Network location (IP) or shared secrets                                                           | A cryptographic identity per workload           |
| Allow service A to call B but not C                | [[Kubernetes/concepts/L04-services-networking/05-network-policy\|NetworkPolicy]] on IPs and ports | Policy on identity, and on HTTP method and path |
| Retries, timeouts, circuit breaking                | A library per language, configured per service                                                    | Declared once, enforced by the proxy            |
| Canary and traffic splitting                       | Replica-count arithmetic                                                                          | Exact percentages, header-based routing         |
| Request rate, errors and latency for every service | [[Observability/prometheus/instrumenting\|Instrument]] every service                              | Emitted by the proxy with no code change        |

If you have none of these needs acutely, you do not need a mesh yet.

## Architecture

```
                    control plane  (istiod / linkerd-destination / cilium-agent)
                    issues certificates, distributes config and endpoints
                          │                         │
        ┌─────────────────▼───────┐       ┌─────────▼───────────────┐
        │ pod A                   │       │ pod B                   │
        │  app ──► proxy ═════════╪═ mTLS ╪═════► proxy ──► app     │
        └─────────────────────────┘       └─────────────────────────┘
                              data plane
```

- The **data plane** is the set of proxies that carry the traffic.
- The **control plane** tells the proxies what to do and acts as a certificate authority.

Applications keep making plain HTTP or gRPC calls to a Service name. The interception is transparent.

## Data plane models

| Model                         | How                                                                        | Strengths                                          | Costs                                                          |
| :---------------------------- | :------------------------------------------------------------------------- | :------------------------------------------------- | :------------------------------------------------------------- |
| **Sidecar**                   | A proxy container in every pod; traffic is redirected to it                | Mature; full L7 features; strong per-pod isolation | Memory and CPU per pod; added latency; pod restarts to upgrade |
| **Ambient (node + waypoint)** | A per-node L4 proxy handles mTLS; optional shared L7 proxies per namespace | No sidecars; pay for L7 only where needed          | Newer; a different operational model                           |
| **eBPF + shared proxy**       | The kernel handles L3/L4; a per-node proxy handles L7                      | Lowest overhead for L4                             | L7 features concentrated in a shared proxy                     |

Sidecars are natively supported by Kubernetes as restartable init containers, which fixed the long-standing start-up and shutdown ordering problems — see [[Kubernetes/concepts/L03-workloads/09-multi-container-pods|multi-container pods]]. The kernel side of the sidecarless designs is explained in [[Observability/ebpf|eBPF]].

## Identity and mTLS

This is the feature most teams adopt a mesh for.

- Each workload gets an X.509 certificate that encodes its identity, usually derived from its Kubernetes service account in SPIFFE form: `spiffe://cluster.local/ns/payments/sa/checkout`.
- Certificates are short-lived and rotated automatically.
- Both sides of every connection present and verify certificates: **mutual** TLS.
- Authorization policies then refer to identities, not IP addresses.

```yaml
# Istio: only the checkout service account may POST to payments
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: payments-allow-checkout
  namespace: payments
spec:
  selector:
    matchLabels: { app: payments }
  action: ALLOW
  rules:
    - from:
        - source:
            principals: ["cluster.local/ns/checkout/sa/checkout"]
      to:
        - operation:
            methods: ["POST"]
            paths: ["/v1/charges"]
```

This is the mechanism behind [[Security/zero-trust|zero trust]] inside a cluster: no implicit trust from being on the network. Background in [[Kubernetes/concepts/L07-security/03-encryption-identity/08-tls-mtls|TLS and mTLS]] and [[Kubernetes/concepts/L07-security/03-encryption-identity/09-spiffe-spire|SPIFFE and SPIRE]].

Mesh identity authenticates _workloads_. It does not replace end-user authentication, which still needs tokens validated at the edge or in the service — see [[Architecture/solution-architecture-concepts/authentication/README|authentication]].

## Implementations

|                    | [[Kubernetes/guides/networking/istio\|Istio]]                  | [[Kubernetes/guides/networking/linkerd\|Linkerd]]          | Cilium Service Mesh                               |
| :----------------- | :------------------------------------------------------------- | :--------------------------------------------------------- | :------------------------------------------------ |
| Proxy              | Envoy (sidecar), or ztunnel + Envoy waypoints (ambient)        | Its own Rust micro-proxy (sidecar)                         | eBPF in the kernel + per-node Envoy               |
| Character          | The most features and the largest ecosystem                    | Deliberately small and simple                              | Comes with the CNI; least extra machinery         |
| Traffic management | Extensive                                                      | The essentials                                             | Growing                                           |
| Operational weight | Highest, lower with ambient                                    | Low                                                        | Low if Cilium is already the CNI                  |
| Choose when        | You need rich L7 routing, multi-cluster, or broad integrations | You mainly want mTLS and golden metrics with little effort | You already run Cilium and want to avoid sidecars |

Managed and cloud options change over time: AWS App Mesh has been retired in favour of [[AWS/concepts/vpc-lattice|VPC Lattice]] and ECS Service Connect ([[AWS/concepts/app-mesh-vs-vpc-lattice|comparison]]); Google and Azure offer managed Istio-based meshes.

All of them increasingly configure routing through the [[Kubernetes/concepts/L04-services-networking/09-gateway-api|Gateway API]], including for service-to-service traffic (the GAMMA initiative), so route definitions are portable between meshes. A broader comparison with ingress controllers is in [[Kubernetes/guides/networking/comparison|the networking comparison]].

## The costs

| Cost                | Detail                                                                                     |
| :------------------ | :----------------------------------------------------------------------------------------- |
| Resources           | A sidecar per pod adds memory and CPU; multiplied by thousands of pods it is a real bill   |
| Latency             | Two extra proxy hops per call; small, but it compounds across deep call chains             |
| Complexity          | A new control plane, new CRDs, new failure modes, another upgrade cycle                    |
| Debugging           | "Is it the app, the proxy, the policy or the network?" becomes a standing question         |
| Retry amplification | Mesh retries on top of application retries can turn a blip into an overload                |
| Protocol quirks     | Server-first protocols, long-lived connections and non-HTTP traffic need explicit handling |

Set retries in one layer only, always with timeouts and budgets — [[Architecture/solution-architecture-concepts/reliability/resilience|resilience patterns]].

## Do you need one?

**Probably yes** if you have a compliance requirement for encryption in transit between all services, many teams and languages that cannot standardise on libraries, a need for identity-based authorization between services, or multi-cluster service communication.

**Probably not yet** if you have a handful of services, one language with good libraries, and network policies that already express your segmentation.

Lighter alternatives to consider first:

- NetworkPolicy for segmentation ([[Kubernetes/eks/networking/vpc-cni/network-policies|on EKS]]).
- Transparent encryption at the CNI layer (WireGuard or IPsec) when the only requirement is encryption.
- [[Observability/ebpf|eBPF-based tools]] for golden metrics and service maps without proxies.
- [[Kubernetes/guides/delivery/progressive-delivery/argo-rollouts|Argo Rollouts]] with an ingress or Gateway for canaries.

## An adoption path

1. **Start with observability only.** Add the mesh to one namespace in permissive mode and look at the traffic it reveals.
2. **Turn on mTLS in permissive mode**, so both plain and encrypted traffic are accepted.
3. **Move to strict mTLS** namespace by namespace once everything in it is meshed.
4. **Add authorization policies**, starting in audit or dry-run mode.
5. **Use traffic management** only where a concrete need exists.
6. **Practise the upgrade** of the mesh itself before you depend on it.

Do not enable it cluster-wide on day one, and do not adopt features because they exist.

## Related

- [[Kubernetes/guides/networking/index|Networking guides]]
- [[Kubernetes/guides/networking/envoy-gateway|Envoy Gateway]] — the same proxy at the edge
- [[Kubernetes/concepts/L04-services-networking/02-services|Services]] and [[Kubernetes/concepts/L04-services-networking/07-k8s-networking-deep-dive|the networking deep dive]]
- [[Kubernetes/guides/non-functional/multi-tenancy|Multi-tenancy]]
- [[Observability/tracing|Distributed tracing]] — proxies emit spans, but applications must still forward headers

## Across the wiki

- [[AWS/security/certificate-manager/README|AWS ACM]] — TLS and certificates (AWS)
- [[Architecture/solution-architecture-concepts/authentication/stage0/03-http-tls-foundations|0.3 — HTTP & TLS Foundations Every Auth Engineer Must Know]] — TLS and certificates (Architecture)
- [[Architecture/solution-architecture-concepts/cryptography/keystore|Keystore]] — TLS and certificates (Architecture)
- [[Architecture/solution-architecture-concepts/cryptography/signing-and-verifying|Signing and Verifying]] — TLS and certificates (Architecture)
