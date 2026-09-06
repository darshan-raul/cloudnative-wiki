---
title: Kubernetes Certifications (CKA, CKAD, CKS)
tags: [kubernetes, certifications, cka, ckad, cks]
date: 2026-09-06
description: Curriculum alignment, time management, command recipes, and practical exam guidance for CKA, CKAD, and CKS.
aliases:
  - Kubernetes/certifications
---

# Kubernetes Certifications (CKA, CKAD, CKS)

A practical roadmap and curriculum cross-reference for the Linux Foundation and CNCF Kubernetes certification exams:

- **CKA** (Certified Kubernetes Administrator)
- **CKAD** (Certified Kubernetes Application Developer)
- **CKS** (Certified Kubernetes Security Specialist)

---

## Exam Domain Cross-Reference

| Exam Domain | Weight (Approx) | Wiki Curriculum Levels | Hands-On Labs |
| :--- | :--- | :--- | :--- |
| **Cluster Architecture, Installation & Config** | 25% (CKA) | [[Kubernetes/concepts/L01-architecture/00-README\|L01 Architecture]] | [[Kubernetes/labs/00-cluster-setup\|Lab 00 Cluster Setup]] |
| **Workloads & Scheduling** | 15% (CKA) / 30% (CKAD) | [[Kubernetes/concepts/L03-workloads/00-README\|L03 Workloads]], [[Kubernetes/concepts/L06-scheduling-scaling/00-README\|L06 Scheduling]] | [[Kubernetes/labs/01-deploy-workload\|Lab 01 Workloads]], [[Kubernetes/labs/06-scheduling-and-autoscaling\|Lab 06 Scheduling]] |
| **Services & Networking** | 20% (CKA) / 20% (CKAD) | [[Kubernetes/concepts/L04-services-networking/00-README\|L04 Networking]] | [[Kubernetes/labs/04-networking-and-services\|Lab 04 Services & DNS]] |
| **Storage & Configuration** | 10% (CKA) / 15% (CKAD) | [[Kubernetes/concepts/L05-config-storage/00-README\|L05 Config & Storage]] | [[Kubernetes/labs/03-configuration\|Lab 03 Config]], [[Kubernetes/labs/05-storage-and-persistence\|Lab 05 Persistence]] |
| **Troubleshooting & Maintenance** | 30% (CKA) | [[Kubernetes/concepts/L08-operations/00-README\|L08 Operations]], [[Kubernetes/troubleshooting\|Troubleshooting]] | [[Kubernetes/labs/02-updates-and-rollbacks\|Lab 02 Rollbacks & Failure]] |
| **Cluster & Workload Security** | 100% (CKS) | [[Kubernetes/concepts/L07-security/00-README\|L07 Security]] | Security hardening labs (P3) |

---

## Essential Speed Techniques

In performance-based exams like CKA/CKAD, time management is paramount:

### 1. Fast Shell Aliases
```bash
alias k=kubectl
alias kgp="kubectl get pods"
alias kgs="kubectl get svc"
export do="--dry-run=client -o yaml"
```

### 2. Imperative Manifest Generation
Never write YAML from scratch during an exam:
```bash
# Generate Deployment skeleton
k create deployment my-deploy --image=nginx:alpine --replicas=3 $do > deploy.yaml

# Generate Job skeleton
k create job my-job --image=busybox $do -- echo done > job.yaml

# Expose as ClusterIP
k expose deployment my-deploy --port=80 --target-port=8080 $do > svc.yaml
```

---

## Next Steps

Review core concepts starting with **[[Kubernetes/concepts/L00-start-here/00-start-here|L00 — Start Here]]** or practice your hands-on speed in **[[Kubernetes/labs/index|Kubernetes Hands-On Labs]]**.
