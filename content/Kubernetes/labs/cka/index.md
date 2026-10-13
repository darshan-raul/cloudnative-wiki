---
title: CKA Labs
tags: [kubernetes, labs, cka, hands-on]
date: 2026-10-13
description: "Hands-on labs for the Certified Kubernetes Administrator exam, covering storage, scheduling, kubeadm, etcd, certificates and control plane repair."
---

# CKA Labs

Twelve labs for the [[Kubernetes/certifications/cka|CKA Track]]. Each uses its own namespace and is self-contained, except that Lab 04 upgrades the cluster Lab 03 installs and Lab 08 needs metrics-server from [[Kubernetes/labs/ckad/06-observability-and-troubleshooting|Lab CKAD-06]]. All but two run on the `kind` cluster from [[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]]. The `kubeadm` install lab needs virtual machines and has not been run on them; the upgrade lab's command sequence was run on kind.

The CKA also examines workloads, configuration, Services and Ingress. Those are practised in the [[Kubernetes/labs/ckad/index|CKAD Labs]].

| Lab                                                                 | Title                                            | Core Focus                                                                                            | Controlled Failure Scenario                                             |
| :------------------------------------------------------------------ | :----------------------------------------------- | :---------------------------------------------------------------------------------------------------- | :---------------------------------------------------------------------- |
| [[Kubernetes/labs/cka/01-storage-and-persistence\|CKA-01]]          | **Stateful Persistence & PVCs**                  | Dynamic provisioning, a checksum across Pod replacement, static PV binding, reclaim policy            | Claim that will not bind to a Released volume; missing StorageClass     |
| [[Kubernetes/labs/cka/02-scheduling-and-autoscaling\|CKA-02]]       | **Scheduling, QoS & Disruption Budgets**         | Requests and limits, QoS classes, topology spread, PDB and node drain                                 | Drain deadlocked by a spread constraint and a budget; unschedulable Pod |
| [[Kubernetes/labs/cka/03-kubeadm-cluster-install\|CKA-03]]          | **kubeadm Cluster Install**                      | Node preparation, containerd, `kubeadm init` and `join`, CNI, cri-dockerd (virtual machines; not run) | Preflight failure on join                                               |
| [[Kubernetes/labs/cka/04-kubeadm-upgrade\|CKA-04]]                  | **kubeadm Cluster Upgrade**                      | v1.36 to v1.37: control plane then workers, drain and uncordon                                        | Drain blocked by a PodDisruptionBudget and a bare Pod                   |
| [[Kubernetes/labs/cka/05-etcd-backup-restore\|CKA-05]]              | **etcd Backup & Restore**                        | `etcdctl snapshot save`, `etcdutl snapshot restore` with a revision bump, repointing the static Pod   | Stale API server cache after an in-place restore                        |
| [[Kubernetes/labs/cka/06-users-and-certificate-requests\|CKA-06]]   | **Users & Certificate Requests**                 | CertificateSigningRequest, approval, kubeconfig, RBAC                                                 | Binding to a group nobody belongs to                                    |
| [[Kubernetes/labs/cka/07-control-plane-and-kubelet-repair\|CKA-07]] | **Control Plane & Kubelet Repair**               | `crictl`, `journalctl`, static Pod manifests, kubelet configuration                                   | Broken API server, scheduler and kubelet                                |
| [[Kubernetes/labs/cka/08-autoscaling-with-hpa\|CKA-08]]             | **Autoscaling with the HorizontalPodAutoscaler** | HPA on CPU, load generation, scale-down behaviour                                                     | `<unknown>` metrics from a missing request                              |
| [[Kubernetes/labs/cka/09-scheduling-constraints\|CKA-09]]           | **Taints, Affinity, Priority & Static Pods**     | Taints and tolerations, node and Pod affinity, preemption, `nodeName`, static Pods                    | Every node tainted; a static Pod that returns after deletion            |
| [[Kubernetes/labs/cka/10-operators-and-custom-resources\|CKA-10]]   | **CRDs, Custom Resources & Operators**           | Writing and discovering a CRD, installing cert-manager, reconciliation                                | Schema rejections; custom resource ignored while the operator is down   |
| [[Kubernetes/labs/cka/11-service-and-dns-troubleshooting\|CKA-11]]  | **Service & DNS Troubleshooting**                | Unguided: four unreachable applications and a cluster-wide fault                                      | Selector, `targetPort`, readiness, NetworkPolicy, CoreDNS               |
| [[Kubernetes/labs/cka/12-gateway-api\|CKA-12]]                      | **Gateway API**                                  | GatewayClass, Gateway, HTTPRoute, weights, status conditions                                          | Missing backend, disallowed namespace, unserved port                    |

A highly-available control plane has no lab; see the track's gap table. Test yourself with the [[Kubernetes/certifications/cka-mock-exam|CKA practice set]].
