---
title: "L07 — Security"
tags: [kubernetes, k8s, security, rbac, pss, authentication, encryption, compliance]
date: 2026-06-09
description: Kubernetes security — authN/Z, RBAC, ServiceAccounts, PSS, encryption at rest/transit, mTLS, admission, image/runtime hardening, compliance
---

# L07 — Security

Five concerns that all get called "Kubernetes security":

1. **Who can talk to the API** (authentication, RBAC, ServiceAccounts)
2. **What a pod is allowed to do** (SecurityContext, Pod Security Standards, NetworkPolicy — see L04)
3. **Encrypting data in transit and at rest** (TLS / mTLS, etcd encryption, Secret encryption, SPIFFE)
4. **What code/images are allowed to run** (admission control, image hardening, signing, OPA / Kyverno)
5. **Detecting the bad things that got through** (audit logging, runtime detection, seccomp / AppArmor, runtime sandboxing)

This level covers all five.

## What you'll understand after this level

- **The authN / authZ split** — who are you, what can you do, the apiserver's pipeline
- **RBAC** — Role, ClusterRole, RoleBinding, ClusterRoleBinding, the verbs, the subresources, the aggregation model
- **ServiceAccounts** — workload identity, bound tokens, IRSA / Pod Identity, automount
- **Certificates and PKI** — the cluster CA, the front-proxy CA, the SA signing key, kubelet cert rotation
- **TLS / mTLS** — control plane mTLS, in-cluster mTLS via service mesh, SPIFFE / SPIRE workload identity
- **Admission control** — the mutating / validating pipeline, built-in plugins, dynamic webhooks
- **Policy engines** — PSS (built-in), OPA / Gatekeeper, Kyverno — the three options
- **Encryption at rest** — etcd encryption (KMS-backed), Secret encryption
- **Audit logging** — the apiserver's forensic record, the policy, the stages
- **Workload sandboxing** — seccomp, AppArmor, gVisor, Kata Containers
- **Runtime detection** — Falco, Tetragon, eBPF-based observability
- **Image hardening** — distroless, scratch, multi-stage builds, scanning, signing
- **SBOMs** — SPDX / CycloneDX, generation, signing, VEX, cluster-wide vulnerability monitoring
- **Cluster and node hardening** — apiserver flags, kubelet config, CIS benchmarks
- **Compliance** — NIST 800-190, CIS Kubernetes Benchmark, OWASP k8s Top 10, SLSA, PCI-DSS / SOC2 / HIPAA / FedRAMP

## Notes in this level

### API access (authN / authZ, RBAC, ServiceAccounts, Certificates)

| Note | Status | What's in it |
|------|--------|--------------|
| [[Kubernetes/concepts/L07-security/01-authentication-authorization\|AuthN vs AuthZ]] | ✅ | The split, the chain, OIDC, impersonation, anonymous auth footgun |
| [[Kubernetes/concepts/L07-security/02-service-accounts\|ServiceAccounts]] | ✅ | Bound tokens, projected volumes, IRSA, automount, default SA footgun |
| [[Kubernetes/concepts/L07-security/03-rbac\|RBAC]] | ✅ | Role/ClusterRole/Binding, verbs, subresources, aggregation, impersonate/escalate |
| [[Kubernetes/concepts/L07-security/04-certificates\|Certificates]] | ✅ | Full cluster PKI, CAs, kubelet cert rotation, front-proxy CA |

### Workload sandboxing (PSS, SecurityContext, seccomp, AppArmor, runtime)

| Note | Status | What's in it |
|------|--------|--------------|
| [[Kubernetes/concepts/L07-security/05-security-context\|SecurityContext]] | ✅ | Every field, the runAsUser/Group, capabilities, readOnlyRootFilesystem, seccomp |
| [[Kubernetes/concepts/L07-security/06-pod-security-standards\|PSS]] | ✅ | The three profiles, enforce/audit/warn, namespace labels, migration cookbook |
| [[Kubernetes/concepts/L07-security/16-seccomp-apparmor\|Seccomp / AppArmor]] | ✅ | Kernel-level filters, RuntimeDefault, Localhost, profile generation |
| [[Kubernetes/concepts/L07-security/17-runtime-sandboxing\|Runtime Sandboxing]] | ✅ | gVisor, Kata Containers, RuntimeClass, performance / compatibility tradeoffs |
| [[Kubernetes/concepts/L07-security/18-runtime-detection\|Runtime Detection]] | ✅ | Falco, Tetragon, eBPF, the philosophy (detect vs prevent) |
| [[Kubernetes/concepts/L07-security/19-image-hardening\|Image Hardening]] | ✅ | distroless, scratch, multi-stage, vulnerability scanning, image signing, SBOM |

### Encryption and identity in transit (TLS, mTLS, SPIFFE, etcd / Secret encryption)

| Note | Status | What's in it |
|------|--------|--------------|
| [[Kubernetes/concepts/L07-security/08-tls-mtls\|TLS / mTLS]] | ✅ | TLS handshake, mTLS, in-cluster mTLS, cert rotation, the cluster CA bundle |
| [[Kubernetes/concepts/L07-security/09-spiffe-spire\|SPIFFE / SPIRE]] | ✅ | Workload identity, SVIDs, the trust bundle, service-mesh mTLS |
| [[Kubernetes/concepts/L07-security/13-etcd-encryption\|etcd Encryption]] | ✅ | EncryptionConfiguration, KMS providers, envelope encryption, key rotation |
| [[Kubernetes/concepts/L07-security/14-secret-encryption\|Secret Encryption]] | ✅ | The three states (at rest, in transit, in use), external managers, ESO, sealed-secrets, SOPS |

### Admission control and policy engines

| Note | Status | What's in it |
|------|--------|--------------|
| [[Kubernetes/concepts/L07-security/10-admission-controllers\|Admission Controllers]] | ✅ | The mutating/validating pipeline, built-in plugins, dynamic webhooks, side effects |
| [[Kubernetes/concepts/L07-security/11-opa-gatekeeper\|OPA / Gatekeeper]] | ✅ | Rego policies, ConstraintTemplates, audit mode, multi-system policy |
| [[Kubernetes/concepts/L07-security/12-kyverno\|Kyverno]] | ✅ | YAML policies, validate/mutate/generate, image signature verification, CEL |
| [[Kubernetes/concepts/L07-security/23-sboms\|SBOMs]] | ✅ | SPDX / CycloneDX formats, generation, signing, VEX, k8s cluster scanning, regulatory context |

### Audit and operations

| Note | Status | What's in it |
|------|--------|--------------|
| [[Kubernetes/concepts/L07-security/15-audit-logging\|Audit Logging]] | ✅ | The audit policy, log levels (Metadata / Request / RequestResponse), stages, backends |
| [[Kubernetes/concepts/L07-security/20-cluster-hardening\|Cluster Hardening]] | ✅ | Apiserver flags, etcd, kubelet, control plane lockdown |
| [[Kubernetes/concepts/L07-security/21-node-hardening\|Node Hardening]] | ✅ | Host OS, container runtime, kernel parameters, kubelet config in depth |

### Compliance

| Note | Status | What's in it |
|------|--------|--------------|
| [[Kubernetes/concepts/L07-security/22-compliance-frameworks\|Compliance Frameworks]] | ✅ | NIST 800-190, CIS Kubernetes Benchmark, OWASP k8s Top 10, SLSA, PCI-DSS/SOC2/HIPAA/FedRAMP |

### Overview

| Note | Status | What's in it |
|------|--------|--------------|
| [[Kubernetes/concepts/L07-security/07-security\|Security Overview]] | ✅ | The L07 hub: the five concerns, the defense-in-depth stack, the threat model, the checklist |

## Suggested reading order

### Path 1: API access (the foundation)

1. [[Kubernetes/concepts/L07-security/01-authentication-authorization|AuthN vs AuthZ]] — the conceptual split
2. [[Kubernetes/concepts/L07-security/02-service-accounts|ServiceAccounts]] — the workload identity
3. [[Kubernetes/concepts/L07-security/03-rbac|RBAC]] — the authorization model
4. [[Kubernetes/concepts/L07-security/04-certificates|Certificates]] — the PKI
5. [[Kubernetes/concepts/L07-security/08-tls-mtls|TLS / mTLS]] — transport security
6. [[Kubernetes/concepts/L07-security/09-spiffe-spire|SPIFFE / SPIRE]] — workload identity for service mesh

### Path 2: Workload hardening (what pods are allowed to do)

1. [[Kubernetes/concepts/L07-security/05-security-context|SecurityContext]] — per-container knobs
2. [[Kubernetes/concepts/L07-security/06-pod-security-standards|PSS]] — apply it cluster-wide
3. [[Kubernetes/concepts/L07-security/16-seccomp-apparmor|Seccomp / AppArmor]] — kernel-level filters
4. [[Kubernetes/concepts/L07-security/19-image-hardening|Image Hardening]] — what code can run
5. [[Kubernetes/concepts/L07-security/23-sboms|SBOMs]] — what's in the image, with signatures
6. [[Kubernetes/concepts/L07-security/10-admission-controllers|Admission Controllers]] — where policy is enforced
7. [[Kubernetes/concepts/L07-security/12-kyverno|Kyverno]] — k8s-native policies
8. [[Kubernetes/concepts/L07-security/11-opa-gatekeeper|OPA / Gatekeeper]] — Rego-based policies

### Path 3: Encryption and detection

1. [[Kubernetes/concepts/L07-security/13-etcd-encryption|etcd Encryption]] — at-rest encryption
2. [[Kubernetes/concepts/L07-security/14-secret-encryption|Secret Encryption]] — secrets in flight
3. [[Kubernetes/concepts/L07-security/15-audit-logging|Audit Logging]] — the forensic record
4. [[Kubernetes/concepts/L07-security/18-runtime-detection|Runtime Detection]] — Falco / Tetragon
5. [[Kubernetes/concepts/L07-security/17-runtime-sandboxing|Runtime Sandboxing]] — gVisor / Kata

### Path 4: Operations and compliance

1. [[Kubernetes/concepts/L07-security/20-cluster-hardening|Cluster Hardening]] — control plane
2. [[Kubernetes/concepts/L07-security/21-node-hardening|Node Hardening]] — per-node
3. [[Kubernetes/concepts/L07-security/22-compliance-frameworks|Compliance Frameworks]] — NIST / CIS / OWASP

## The "defense in depth" stack

A production cluster has **multiple layers** of security, each addressing a different threat:

```
Threat                          Defense
──────────────────────────────────────────────────────────
Unauthorized kubectl            OIDC SSO, RBAC, audit logs
Compromised kubelet             PSS restricted, SecurityContext
Compromised Pod → host          PSS, NetworkPolicy, seccomp, AppArmor
Compromised Pod → DB            NetworkPolicy, mTLS, secrets encryption
Compromised Pod → other Pods    NetworkPolicy, mTLS
Compromised image               Image scanning, signed images, admission
Lateral movement                NetworkPolicy, microsegmentation
Data exfiltration               NetworkPolicy egress, audit logs
Privilege escalation            PSS baseline+, capabilities dropped
```

No single layer is sufficient. They **complement** each other.

## AWS-specific notes

The EKS-specific versions of these (IRSA, Pod Identity, EKS access entries, GuardDuty) live in [[Kubernetes/eks/security/README|EKS Security]] — they're concrete implementations of these primitives on AWS.

## Where to go next

→ [[Kubernetes/concepts/L08-operations|L08 — Operations]]: keep things running, debug them, scale them.
