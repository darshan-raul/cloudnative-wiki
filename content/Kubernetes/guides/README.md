---
title: Kubernetes Guides
tags:
  - Kubernetes
  - Guides
  - Hub
---

Tool & task walkthroughs on top of core concepts. If you're new to k8s, read [[Kubernetes/concepts/00-hub|Concepts]] first — guides assume you know the vocabulary.

## Quick start

- [[Kubernetes/guides/tools/kubectl|kubectl]] — the CLI
- [[Kubernetes/guides/tools/k9s|k9s]] — terminal UI
- [[Kubernetes/guides/delivery/templating-patching/helm/README|Helm]] — package & deploy
- [[Kubernetes/guides/delivery/gitops/README|GitOps]] — Argo CD, Flux
- [[Kubernetes/guides/security/secret-management|secrets]] — Sealed Secrets, External Secrets, etc.

## Sections

### Tools
Working with k8s day-to-day: CLI, TUI, multi-cluster.

- [[Kubernetes/guides/tools/kubectl|kubectl]] — Kubernetes CLI
- [[Kubernetes/guides/tools/k9s|k9s]] — Terminal UI for clusters
- [[Kubernetes/guides/tools/context-switching|context-switching]] — Managing multiple kubeconfigs
- [[Kubernetes/guides/tools/multi-cluster|multi-cluster]] — Multi-cluster strategies
- [[Kubernetes/guides/tools/tools|tools]] — Tool roundup
- [[Kubernetes/guides/tools/multiple-tools|multiple-tools]] — Tool combinations (arkade, etc.)

### Networking
Ingress, gateways, service mesh.

- [[Kubernetes/guides/networking/envoy-gateway|envoy-gateway]] — Envoy Gateway API
- [[Kubernetes/guides/networking/ingress/README|ingress]] — Ingress controllers
  - [[Kubernetes/guides/networking/ingress/traefik|traefik]]
- [[Kubernetes/guides/networking/service-mesh/README|service-mesh]] — Service mesh implementations
  - [[Kubernetes/guides/networking/service-mesh/istio|istio]]
  - [[Kubernetes/guides/networking/service-mesh/linkerd|linkerd]]

### Delivery
How code gets to production: GitOps, templating, pipelines, progressive delivery.

- [[Kubernetes/guides/delivery/gitops/README|gitops]] — GitOps workflows
  - [[Kubernetes/guides/delivery/gitops/basics|basics]]
  - [[Kubernetes/guides/delivery/gitops/argo-cd/README|argo-cd]]
    - [[Kubernetes/guides/delivery/gitops/argo-cd/best-practices|best-practices]]
    - [[Kubernetes/guides/delivery/gitops/argo-cd/go-sdk|go-sdk]]
    - [[Kubernetes/guides/delivery/gitops/argo-cd/image-updater|image-updater]]
- [[Kubernetes/guides/delivery/templating-patching/README|templating-patching]] — Kustomize and patches
  - [[Kubernetes/guides/delivery/templating-patching/kustomize|kustomize]]
  - [[Kubernetes/guides/delivery/templating-patching/helm/README|helm]]
    - [[Kubernetes/guides/delivery/templating-patching/helm/charts|charts]]
    - [[Kubernetes/guides/delivery/templating-patching/helm/commands|commands]]
    - [[Kubernetes/guides/delivery/templating-patching/helm/cicd|cicd]]
    - [[Kubernetes/guides/delivery/templating-patching/helm/gitops|gitops]]
    - [[Kubernetes/guides/delivery/templating-patching/helm/helmfile|helmfile]]
    - [[Kubernetes/guides/delivery/templating-patching/helm/library-charts|library-charts]]
    - [[Kubernetes/guides/delivery/templating-patching/helm/oci|oci]]
    - [[Kubernetes/guides/delivery/templating-patching/helm/production|production]]
    - [[Kubernetes/guides/delivery/templating-patching/helm/testing|testing]]
    - [[Kubernetes/guides/delivery/templating-patching/helm/troubleshooting|troubleshooting]]
- [[Kubernetes/guides/delivery/pipeline-workflows/README|pipeline-workflows]] — CI/CD on k8s
  - [[Kubernetes/guides/delivery/pipeline-workflows/argo-workflows|argo-workflows]]
  - [[Kubernetes/guides/delivery/pipeline-workflows/jenkins|jenkins]]
  - [[Kubernetes/guides/delivery/pipeline-workflows/tekton-pipelines|tekton-pipelines]]
- [[Kubernetes/guides/delivery/progressive-delivery/README|progressive-delivery]] — Canary, blue/green
  - [[Kubernetes/guides/delivery/progressive-delivery/argo-rollouts|argo-rollouts]]

### Security
Secrets, auth, policy, scanning, supply chain.

- [[Kubernetes/guides/security/secret-management|secret-management]] — Managing secrets
  - [[Kubernetes/guides/security/sealed-secrets-README|sealed-secrets]] — Sealed Secrets
- [[Kubernetes/guides/security/authentication/README|authentication]] — Auth strategies
  - [[Kubernetes/guides/security/authentication/oidc-with-keycloak|oidc-with-keycloak]]
- [[Kubernetes/guides/security/policy-engine/README|policy-engine]] — Policy as code
  - [[Kubernetes/guides/security/policy-engine/kyverno|kyverno]]
- [[Kubernetes/guides/security/auditing/README|auditing]] — Compliance scanning
  - [[Kubernetes/guides/security/auditing/checkov|checkov]]
- [[Kubernetes/guides/security/security-scanning|security-scanning]] — Image scanning
- [[Kubernetes/guides/security/image-signing|image-signing]] — Cosign, Notary
- [[Kubernetes/guides/security/zero-cve-images|zero-cve-images]] — Distroless, minimal base images

### Operations
Day-2: logging, troubleshooting, backup, scaling, chaos, multi-tenancy.

- [[Kubernetes/guides/operations/logging/README|logging]] — Logging strategies
  - [[Kubernetes/guides/operations/logging/fluentbit|fluentbit]]
- [[Kubernetes/guides/operations/troubleshooting/README|troubleshooting]] — Common issues
  - [[Kubernetes/guides/operations/troubleshooting/crashloop-backoff|crashloop-backoff]]
  - [[Kubernetes/guides/operations/troubleshooting/networking|networking]]
- [[Kubernetes/guides/operations/backup-restore|backup-restore]] — Backup strategies (Velero, etc.)
- [[Kubernetes/guides/operations/auto-scaling|auto-scaling]] — HPA, VPA, KEDA, Karpenter
- [[Kubernetes/guides/operations/chaos-engineering|chaos-engineering]] — Chaos Mesh, Litmus
- [[Kubernetes/guides/operations/multi-tenancy|multi-tenancy]] — Multi-tenant clusters

### Infrastructure
Cluster lifecycle: build, upgrade, scale, cost.

- [[Kubernetes/guides/infrastructure/cluster-upgrades|cluster-upgrades]] — Upgrading clusters
- [[Kubernetes/guides/infrastructure/cluster-api|cluster-api]] — Cluster API
- [[Kubernetes/guides/infrastructure/high-availability|high-availability]] — HA patterns
- [[Kubernetes/guides/infrastructure/cost-management|cost-management]] — Cost optimization
- [[Kubernetes/guides/infrastructure/federation|federation]] — Cluster federation
- [[Kubernetes/guides/infrastructure/stateful-workloads|stateful-workloads]] — StatefulSets
- [[Kubernetes/guides/infrastructure/databases/README|databases]] — Database operators
  - [[Kubernetes/guides/infrastructure/databases/cloudnativepg|cloudnativepg]]
- [[Kubernetes/guides/infrastructure/container-builds/README|container-builds]] — Building images for k8s
  - [[Kubernetes/guides/infrastructure/container-builds/bazel|bazel]]
  - [[Kubernetes/guides/infrastructure/container-builds/kaniko|kaniko]]
- [[Kubernetes/guides/infrastructure/private-image-registry|private-image-registry]] — Harbor, ECR, etc.
- [[Kubernetes/guides/infrastructure/convertors|convertors]] — KubeVirt, Crossplane
- [[Kubernetes/guides/infrastructure/client-go|client-go]] — Writing k8s controllers
- [[Kubernetes/guides/infrastructure/validation/README|validation]] — Schema/policy validation
  - [[Kubernetes/guides/infrastructure/validation/datree|datree]]

### Topical
- [[Kubernetes/guides/best-practices|best-practices]] — Cluster & app best practices
- [[Kubernetes/guides/api-management|api-management]] — API gateways on k8s

## Status legend

- ✅ Done — comprehensive content (200+ lines)
- 🟡 Partial — substantial but not deep (100-200 lines)
- 🟠 Skeleton — stub or near-stub (10-50 lines)
- ⚪ Empty — placeholder

## Status

| Section | Status | Notes |
|---------|--------|-------|
| Tools (k9s) | ✅ | k9s.md is the depth benchmark for the section |
| Tools (others) | 🟠 | Stubs only |
| Networking/envoy-gateway | ✅ | Full Gateway API walkthrough |
| Networking/ingress | 🟠 | Stubs |
| Networking/service-mesh | 🟠 | Stubs |
| Delivery/helm | ✅ | All 10 sub-notes solid |
| Delivery/gitops | 🟠 | argo-cd notes are stubs; basics is medium |
| Delivery/templating-patching (kustomize) | 🟠 | Stub |
| Delivery/pipeline-workflows | 🟠 | All stubs |
| Delivery/progressive-delivery | 🟠 | Stub |
| Security (sealed-secrets) | 🟠 | Stubs |
| Security/authentication | 🟠 | Stubs |
| Security/policy-engine | 🟠 | Stubs |
| Security/auditing | 🟠 | Stubs |
| Security/security-scanning | 🟠 | Stub |
| Security/image-signing | 🟠 | Stub |
| Security/zero-cve-images | 🟠 | Stub |
| Security/secret-management | 🟠 | Stub |
| Operations/logging | 🟠 | Stubs |
| Operations/troubleshooting | 🟡 | crashloop-backoff is medium (55 lines) |
| Operations/backup-restore | 🟡 | 81 lines, near-ready |
| Operations/auto-scaling | 🟠 | Stub |
| Operations/chaos-engineering | 🟠 | Stub |
| Operations/multi-tenancy | 🟠 | Stub |
| Infrastructure/* | 🟠 | All stubs (private-image-registry is 290 lines, ✅) |
| Best practices | 🟠 | Stub |
| API management | 🟠 | Stub |
