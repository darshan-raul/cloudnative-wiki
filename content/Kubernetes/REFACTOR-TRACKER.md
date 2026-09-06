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

### Phase 2: Beginner Spine & Sample Application (Next Focus 🔄)
- [ ] Define canonical `kind-config.yaml` with multi-node roles and `extraPortMappings` (ports 80/443).
- [ ] Build continuous `podinfo` manifest sequence for Labs 00–06.
- [ ] Slim down oversized core notes (e.g. `01-pods.md`).
- [ ] Apply Two-Tier page contract (Tier 1 Milestone Lessons vs Tier 2 Atomic Concepts).

### Phase 3: Security & Operational Depth
- [ ] Restructure `L07-security` around layered threat model.
- [ ] Build insecure-to-hardened workload lab with `podinfo`.
- [ ] Expand `L08-operations` and connect symptom playbooks.
- [ ] Implement Labs 07–09 (hardened security, day-2 observability, GitOps delivery).

### Phase 4: Revision System & Decision Tables
- [ ] Create 5-minute refresher pages.
- [ ] Add standard decision flowcharts and tables (Workload selection, Storage access, Ingress vs Gateway API).
- [ ] Add scenario-based review questions with solutions.

### Phase 5: Extensibility & EKS Provider Track
- [ ] Reorganize advanced internals as L10 Extensibility.
- [ ] Decouple universal concepts from AWS-specific implementations in `eks/`.
- [ ] Add client-go and custom controller guide.

### Phase 6: CI Gates & Upstream Maintenance
- [ ] Wire `check:k8s` into CI test pipeline.
- [ ] Document upstream synchronization playbook.
