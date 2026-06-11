---
title: Kubernetes Guides
tags:
  - Kubernetes
  - Guides
  - Hub
---

Practical, day-2 k8s content. **Concepts** explain *what* and *why* — **Guides** explain *how*: how to use the tools, how to recover from breakage, how to operate against non-functional requirements, and how to ship code to production.

If you're new to k8s, read [[Kubernetes/concepts/00-hub|Concepts]] first.

## The five sections

| Section | What it covers | Status |
|---------|----------------|--------|
| **[[Kubernetes/guides/tools\|tools]]** | CLI / TUI / debugging UIs (kubectl, k9s, Lens, multi-cluster workflows) | 🟡 Partial |
| **[[Kubernetes/guides/troubleshooting\|troubleshooting]]** | Issue → diagnosis → fix playbooks for the most common cluster problems | 🟡 Partial |
| **[[Kubernetes/guides/non-functional\|non-functional]]** | NFRs: scale, cost, HA, performance, security baseline, backup, upgrades, multi-tenancy | 🟠 Stub phase |
| **[[Kubernetes/guides/delivery\|delivery]]** | How code reaches prod: GitOps, Helm/Kustomize, CI/CD pipelines, progressive delivery | 🟢 Solid (helm), 🟠 rest stub |
| **[[Kubernetes/guides/networking\|networking]]** | Ingress, Gateway API, service mesh (the practical/network side, not the L04 concepts) | 🟡 Partial |

## Section summaries

### tools/

Working with k8s day-to-day. The CLI, the TUIs, the multi-cluster context switches.

- [[Kubernetes/guides/tools/k9s|k9s]] — terminal UI, the depth benchmark ✅
- [[Kubernetes/guides/tools/kubectl|kubectl]] — reference for the CLI
- [[Kubernetes/guides/tools/context-switching|context-switching]] — kubeconfig management
- [[Kubernetes/guides/tools/multi-cluster|multi-cluster]] — multi-cluster strategies

### troubleshooting/

Issue-driven playbooks. "My pod is stuck in CrashLoopBackOff" → "check X, then Y, then Z". Each note follows the same shape: **symptom → diagnosis → fix → gotchas**.

- [[Kubernetes/guides/troubleshooting/crashloop-backoff|crashloop-backoff]] ✅
- pod-eviction — Pending pods that won't schedule
- networking — Service unreachable, DNS resolution failures
- image-pull — ImagePullBackOff, registry auth
- node-not-ready — Node conditions, kubelet logs
- storage — PVC stuck, RWX issues
- helm — release failures, hooks, drift
- gitops — Argo CD sync errors, drift, missing apps
- istio-linkerd — mesh-specific failures (sidecar injection, mTLS)

### non-functional/

NFRs as standalone deep-dives. Each note is a practical operating guide for one axis of cluster quality.

- auto-scaling — HPA / VPA / CA / Karpenter / KEDA
- cost-optimization — rightsizing, spot, cluster autoscaler
- high-availability — control plane, multi-AZ, PDBs
- performance-tuning — resource limits, QoS, JVM/GC, kernel tuning
- security-baseline — PSA, NetworkPolicy default-deny, image policy, Kyverno, OPA, Checkov
- backup-restore ✅ (Velero, etcd, managed-service backup)
- disaster-recovery — RTO/RPO, multi-region
- multi-tenancy — namespaces, Projects, virtual clusters
- chaos-engineering — Chaos Mesh, Litmus, steady-state hypothesis
- upgrade-strategy — kubeadm, EKS, GKE version paths
- deprecations — k8s 1.29+ removals, what to watch
- oidc-integration — Dex, Keycloak, Pinniped

### delivery/

How code reaches production.

- [[Kubernetes/guides/delivery/gitops/basics|gitops/basics]] — what GitOps is and isn't
- [[Kubernetes/guides/delivery/gitops/argo-cd/README|gitops/argo-cd]] — Argo CD
  - best-practices, image-updater, app-of-apps, multi-tenancy (Projects/AppSets), troubleshooting
- [[Kubernetes/guides/delivery/templating-patching/helm/README|helm]] — package & deploy ✅ (all 10 notes solid)
- [[Kubernetes/guides/delivery/templating-patching/kustomize|kustomize]] — overlay/patch model
- [[Kubernetes/guides/delivery/pipeline-workflows/argo-workflows|argo-workflows]] — K8s-native pipelines
- [[Kubernetes/guides/delivery/progressive-delivery/argo-rollouts|argo-rollouts]] — canary, blue/green
- ci-cd-integration — GitHub Actions / GitLab CI / buildkit / kaniko, image signing, scanning

### networking/

Practical / network-side notes. Complements L04 concepts with hands-on controller configuration.

- [[Kubernetes/guides/networking/envoy-gateway|envoy-gateway]] — Gateway API implementation ✅
- traefik — Traefik ingress controller
- nginx — NGINX ingress controller
- gateway-api — overview, points to envoy-gateway
- service-mesh — overview
  - [[Kubernetes/guides/networking/service-mesh/istio|istio]]
  - [[Kubernetes/guides/networking/service-mesh/linkerd|linkerd]]
  - comparison — istio vs linkerd vs cilium service mesh

## Status legend

- ✅ Done — comprehensive content (200+ lines)
- 🟡 Partial — substantial but not deep (100-200 lines) or mid-thin with growth plan
- 🟠 Stub phase — placeholder, expansion planned
- ⚪ Empty — placeholder
