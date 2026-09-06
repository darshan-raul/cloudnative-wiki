---
title: Kubernetes Section Refactor Tracker
tags: [kubernetes, refactor, planning, tracker]
date: 2026-09-06
draft: true
description: Multi-session persistent execution tracker for the Kubernetes section curriculum refactor.
---

# Kubernetes Section Refactor Tracker

**Baseline:** Kubernetes 1.37 ("Garhwal", Released August 26, 2026)  
**Target Structure:** Dual-Spine (Learner Spine + Rapid Reference / Troubleshooting)  
**Sample Application:** `podinfo` (stateless API + batch worker + ConfigMap/Secret + PVC stateful + HPA + network policies)  
**Contract Model:** Two-Tier Page Contract (Tier 1 Milestone Lessons vs Tier 2 Atomic Concepts)

---

## Phase Execution Checklist

### Phase 0: Trust & Navigation Baseline (Complete ✅)
- [x] Create automated content validation script: `scripts/check-k8s-content.mjs`.
- [x] Add `"check:k8s": "node scripts/check-k8s-content.mjs"` to `package.json`.
- [x] Fix empty `content/Kubernetes/concepts/L07-security.md` (removed 0-byte file; configured alias in `L07-security/00-README.md`).
- [x] Fix malformed markdown tables starting with `||` in `L01`, `L02`, `L04`, `L05`, `L08`, `L09`.
- [x] Fix all 9 broken wikilinks in `Kubernetes.md`, `00-hub.md`, `guides/README.md`, `adot.md`, and troubleshooting guides.
- [x] Ensure folder routing in Quartz works via curated `index.md` (created landing pages for `guides/tools`, `troubleshooting`, `non-functional`, `delivery`, `networking`).
- [x] Add missing H1 headings in `guides/README.md`, `guides/tools/multi-cluster.md`, etc.

### Phase 1: 2026 & v1.37 Technical Currency (Complete ✅)
- [x] Update `updates-along-the-versions.md` with release matrix through Kubernetes 1.37 ("Garhwal", August 2026) and add frontmatter.
- [x] Ingress & Gateway: update `04-ingress.md` to note official retirement of `ingress-nginx` (March 2026) and position Gateway API / maintained ingress controllers.
- [x] Networking: update `08-ipvs.md` marking IPVS mode deprecated in `kube-proxy` (v1.35+) and noting transition to `nftables`.
- [x] Storage: verify `Recycle` deprecation in `04-persistentvolume.md` and add standard frontmatter.
- [x] Node & Kubelet: correct `NodeSwap` guidance in `05-need-for-swapoff.md` explaining `failSwapOn: false` and `memorySwap.swapBehavior` requirements on cgroup v2.
- [x] Update `client-go.md` and `troubleshooting.md` with structured directories and frontmatter.
- [x] Rewrite `Kubernetes.md` landing page by reader intent with v1.37 baseline and visual curriculum map.

### Phase 2: Beginner Spine & Sample Application (Complete ✅)
- [x] Define canonical `kind-config.yaml` with multi-node roles and `extraPortMappings` (ports 80/443).
- [x] Create hands-on labs landing page `content/Kubernetes/labs/index.md` with visual curriculum map.
- [x] Build continuous `podinfo` manifest sequence for Labs 00–06:
  - `00-cluster-setup.md`: multi-node kind cluster, system namespaces, kubelet disconnect test.
  - `01-deploy-workload.md`: podinfo Deployment, ReplicaSet reconciliation, labels/selectors.
  - `02-updates-and-rollbacks.md`: RollingUpdate surge parameters, stuck rollout diagnosis, `rollout undo`.
  - `03-configuration.md`: ConfigMaps, Secrets, env vars, live volume reload, missing key failure.
  - `04-networking-and-services.md`: ClusterIP, modern EndpointSlices, CoreDNS, zero-endpoint typo.
  - `05-storage-and-persistence.md`: Dynamic PVC provisioning, persistent cache data across pod deletion, `WaitForFirstConsumer`.
  - `06-scheduling-and-autoscaling.md`: Requests/limits, QoS, topologySpreadConstraints, PDB node drain, unschedulable pod diagnosis.
- [x] Slim down oversized core notes (`01-pods.md` refactored into Tier 1 milestone 14-section contract; created companion `01-pods-deep-dive.md` reference).
- [x] Apply Two-Tier page contract with Mermaid sequence & architecture diagrams, controlled failures, and scenario knowledge checks.

### Phase 3: Security & Operational Depth (Complete ✅)
- [x] Restructure `L07-security` around progressive threat model:
  - Created `L07-security/index.md` with defense-in-depth architecture, control matrix, and note index.
  - Added YAML frontmatter and threat-domain mapping to `L07-security/07-security.md`.
- [x] Build insecure-to-hardened workload lab with `podinfo`:
  - `07-security-hardening.md`: 5-layer hardening pipeline (Dedicated SA, least-privilege RBAC, PSS `restricted`, hardened securityContext, default-deny NetworkPolicy, root admission rejection).
- [x] Expand `L08-operations` and connect symptom playbooks:
  - Created `L08-operations/index.md` with end-to-end triage flowchart and modern `readyz`/`livez` checks replacing legacy `componentstatuses`.
  - Added frontmatter and connected symptom playbooks to `01-troubleshooting.md`, `02-kubectl-debug.md`, `03-common-failure-modes.md`, and `04-metrics-sources.md`.
- [x] Implement Labs 07–09 (Hardened security, day-2 observability, GitOps delivery):
  - `07-security-hardening.md`: Multi-layer security hardening and admission violation testing.
  - `08-observability-and-troubleshooting.md`: Prometheus metrics, `kubectl debug` ephemeral containers, panic crash-loop triage, and exit code analysis.
  - `09-gitops-and-lifecycle.md`: Declarative Kustomize overlays, drift auto-healing, API deprecation discovery, and disaster recovery drill.
- [x] Update `content/Kubernetes/labs/index.md` flowchart and curriculum table to span Labs 00 through 09.

### Phase 4: Revision System & Decision Tables (Complete ✅)
- [x] Create 5-minute refresher pages:
  - `architecture-refresher.md`: Control plane, nodes, and `kubectl apply` request trace.
  - `workloads-refresher.md`: Controller hierarchy, rolling updates, and graceful termination.
  - `networking-refresher.md`: Packet flow, Service VIPs, EndpointSlices, and Gateway API.
  - `storage-refresher.md`: Storage provisioning pipeline, CSI volume attachment, and access modes.
  - `scheduling-scaling-refresher.md`: Scheduler pipeline, QoS eviction tiers, and PDB node drains.
  - `security-refresher.md`: AuthN/Z, RBAC, PSS profiles, securityContext, and NetworkPolicy.
- [x] Add standard decision flowcharts and tables:
  - `decision-tables.md`: Workload controllers, configuration & secrets, traffic exposition, storage access modes, autoscaling family, placement controls, and cluster governance.
- [x] Add scenario-based review questions with solutions:
  - `scenarios.md`: Production post-mortems analyzing stuck rollouts, zero-endpoint DNS timeouts, HPA capacity ceilings, blocked node drains, and admission webhook outages.
- [x] Create revision hub:
  - `review/index.md`: Central landing page connecting refreshers, decision tables, and incident walkthroughs.

### Phase 5: Extensibility & EKS Provider Track (Complete ✅)
- [x] Complete L09 Advanced & Extensibility track:
  - Added Quartz folder landing page `content/Kubernetes/concepts/L09-advanced/index.md` with full control plane extensibility architecture diagram.
  - Added YAML frontmatter and technical metadata across all notes: `01-operators.md`, `02-custom-controllers.md`, `03-customresourcedefinitions.md`, `04-admission-controllers.md`, `05-finalizers.md`, `06-garbage-collection.md`, `07-aggregation-layer.md`, `08-ipvs.md`, `09-pause-container.md`, `10-etcd.md`, `11-scheduler-extenders.md`.
  - Updated status badges to 100% complete in `L09-advanced/00-README.md`.
- [x] Create comprehensive `client-go` and custom controller guide:
  - Deepened `content/Kubernetes/client-go.md` covering client hierarchy (Clientset, DynamicClient, MetadataClient), Informer/DeltaFIFO mechanics, ThreadSafeStore, rate-limiting work queues, exponential backoff, worker reconcile loops, and leader election.
- [x] Decouple universal concepts from AWS-specific implementations in `content/Kubernetes/eks/README.md`:
  - Prepended the Universal Concept → EKS Implementation Translation Matrix (AuthN, AuthZ, Pod Identity, VPC CNI, Network Policy, Karpenter, Managed Node Groups, EBS/EFS CSI, ALB/NLB, VPC Lattice, Secrets Manager, CloudWatch/AMP).
  - Wired bidirectional cross-links between upstream conceptual levels (L01–L08) and EKS architecture chapters.

### Phase 6: CI Gates & Upstream Maintenance (Complete ✅)
- [x] Wire `check:k8s` into CI test pipeline / `package.json`:
  - Integrated `check:k8s` into `npm test` (`tsx --test && npm run check:k8s`) and `npm run check` (`tsc --noEmit && npm run check:k8s && npx prettier . --check`).
  - Verified end-to-end site generation with `npx quartz build` (1001 Markdown files processed, 3337 output files emitted cleanly).
- [x] Document upstream synchronization playbook:
  - Created `content/Kubernetes/MAINTENANCE.md` specifying tri-annual release audit cadence (April, August, December), deprecation tracking, lab verification protocols with pinned versions/digests, and editorial guidelines.
  - Linked maintenance playbook, cumulative labs, and revision system into the root curriculum map `content/Kubernetes.md`.

