---
title: "L04 — Services & Networking"
tags: [kubernetes, k8s, networking, services, ingress, cni]
date: 2026-06-06
description: Kubernetes networking — Services, DNS, Ingress, NetworkPolicy, CNI, endpoint slices
---

# L04 — Services & Networking

Pods are ephemeral and get random IPs. Networking in Kubernetes is the layer that makes that chaos usable: stable virtual IPs, DNS names, ingress, and policy.

## What you'll understand after this level

- Why a **Service** exists and what problem it solves (stable virtual IP + load balancing across a dynamic set of pods)
- The four Service types: **ClusterIP**, **NodePort**, **LoadBalancer**, **ExternalName**
- How **DNS** in Kubernetes works (CoreDNS, search paths, the cluster domain)
- **Ingress** vs **Service** vs **Gateway API** — three layers, not the same thing
- **NetworkPolicy** — the k8s-native way to control pod-to-pod traffic
- **CNI** — how pods actually get IPs and L3 connectivity
- **EndpointSlices** — the scalable version of the Endpoints API

## Notes in this level

| Note | Status | What's in it |
|------|--------|--------------|
| [[Kubernetes/concepts/L04-services-networking/01-networking\|Networking]] | ⚪ | Top-level mental model for k8s networking |
| [[Kubernetes/concepts/L04-services-networking/02-services\|Services]] | ✅ | The four Service types (ClusterIP, NodePort, LoadBalancer, ExternalName), headless services, Endpoints |
| [[Kubernetes/concepts/L04-services-networking/03-dns\|DNS]] | ✅ | CoreDNS, Service/Pod DNS names, `ndots` and the search path gotcha |
| [[Kubernetes/concepts/L04-services-networking/04-ingress\|Ingress]] | ✅ | The HTTP routing layer, ingressClassName, TLS, Ingress vs Gateway API |
| [[Kubernetes/concepts/L04-services-networking/05-network-policy\|NetworkPolicy]] | ✅ | Pod-to-pod firewall rules, selectors, default-deny recipes |
| [[Kubernetes/concepts/L04-services-networking/06-cni\|CNI]] | ✅ | How Pods actually get IPs, overlay vs underlay, plugin comparison |
| [[Kubernetes/concepts/L04-services-networking/08-endpoint-slices\|EndpointSlices]] | 🟡 | Scalable endpoint tracking, why it replaced Endpoints |
| [[Kubernetes/concepts/L04-services-networking/07-k8s-networking-deep-dive\|Networking Deep Dive]] | 🟡 | Pod-to-pod, pod-to-service, service-to-external — packet-level walkthroughs |

## Suggested reading order

1. [[Kubernetes/concepts/L04-services-networking/02-services|Services]] — the foundational object after a Pod
2. [[Kubernetes/concepts/L04-services-networking/03-dns|DNS]] — how clients find Services (and the gotcha you'll hit immediately)
3. [[Kubernetes/concepts/L04-services-networking/08-endpoint-slices|EndpointSlices]] — what the Service is actually pointing at
4. [[Kubernetes/concepts/L04-services-networking/04-ingress|Ingress]] — when you need HTTP routing from outside the cluster
5. [[Kubernetes/concepts/L04-services-networking/05-network-policy|NetworkPolicy]] — when you start designing multi-tenant or hardened clusters
6. [[Kubernetes/concepts/L04-services-networking/06-cni|CNI]] — understand the layer below all of this
7. [[Kubernetes/concepts/L04-services-networking/07-k8s-networking-deep-dive|Networking Deep Dive]] — when you need to debug, not before

## Where to go next

→ [[Kubernetes/concepts/L05-config-storage|L05 — Config & Storage]]: services are configured and persistent data lives somewhere.
