---
title: Kubernetes Security
tags: [kubernetes, k8s, security, rbac, network-policy]
date: 2025-05-24
description: Kubernetes security - RBAC, network policies, pod security, secrets management, and vulnerability scanning
---

# Kubernetes Security

Security for Kubernetes clusters — from RBAC and network policies to secrets management and vulnerability scanning.

## Sections

- [[Security/kubernetes-security/rbac/README|RBAC]] — Role-based access control, ClusterRoles, ServiceAccounts
- [[Security/kubernetes-security/network-policies/README|Network Policies]] — K8s network segmentation, zero-trust networking
- [[Security/kubernetes-security/pod-security/README|Pod Security]] — Pod Security Standards, security contexts, PSP migration
- [[Security/kubernetes-security/secrets/README|Secrets Management]] — Sealed Secrets, Vault, AWS SM, ESO
- [[Security/kubernetes-security/vulnerability-scanning/README|Vulnerability Scanning]] — Trivy, Grype, Snyk, admission control

## Core Principles

1. **Least privilege** — RBAC with minimal permissions
2. **Defense in depth** — Network policies + pod security + secrets encryption
3. **Immutable workloads** — No privileged containers, read-only root filesystems
4. **Scan everything** — Container images, Helm charts, K8s YAML
5. **Log everything** — Audit logs, API server logs, node logs

## Key Security Controls

| Layer | Control | Tool/Feature |
|-------|---------|--------------|
| API Server | RBAC | Role, ClusterRole, RoleBinding |
| Network | Segmentation | NetworkPolicy |
| Pod | Runtime security | PodSecurityStandards, SecurityContext |
| Data | Secrets encryption | Sealed Secrets, Vault |
| Images | Vulnerability scanning | Trivy, Grype |
| Admission | Policy enforcement | OPA Gatekeeper, Kyverno |

## Your EKS Environment

For your EKS clusters:

```yaml
# Pod security context example
securityContext:
  runAsNonRoot: true
  runAsUser: 10000
  runAsGroup: 10000
  fsGroup: 10000
  readOnlyRootFilesystem: true
  capabilities:
    drop: [ALL]

---
# Network policy - default deny
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

## Existing Vault Content

Your vault already has extensive K8s security content:
- `Kubernetes/eks/security/` — EKS-specific security
- `Kubernetes/concepts/security.md` — K8s security concepts
- `Kubernetes/guides/zero-cve-images.md` — Image security

## Related

- [[Security/endpoint-security/falco/README|Falco]] — Runtime security for K8s
- [[Security/devsecops/README|DevSecOps]] — Shift-left security in CI/CD
- [[Security/siem/wazuh/integrations/README|Wazuh K8s Integration]]