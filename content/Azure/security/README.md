---
title: Azure Security & Zero Trust Architecture Hub
description: Master architectural guide to Microsoft Azure security services — Microsoft Defender for Cloud (CSPM/CWPP), Azure Key Vault, Managed HSM, Bastion, Network Firewalls, and Zero Trust identity.
tags:
  - azure
  - security
  - defender
  - key-vault
  - zero-trust
  - secops
date: 2026-10-15
---

# Azure Security & Zero Trust Architecture Hub 🔐🛡️

Microsoft Azure's security framework is engineered around the core principles of **Zero Trust**: _Verify Explicitly_, _Use Least Privilege Access_, and _Assume Breach_. The portfolio unites cloud security posture management, runtime workload protection, hardware-backed cryptographic governance, network perimeter isolation, and cloud-native SIEM/SOAR.

---

## Architectural Decision Framework

```
                                  Security Horizon
                                         │
         ┌───────────────────────────────┼───────────────────────────────┐
         ▼                               ▼                               ▼
Postures & Threat Protection     Hardware Cryptography & Secrets    Perimeter & Network Defense
(CSPM / CWPP / Vulnerabilities) (FIPS 140-2 Level 3 / Secrets)  (Micro-segmentation / WAF)
         │                               │                               │
[[Azure/security/defender-for-cloud|Defender for Cloud (CNAPP)]] [[Azure/security/key-vault/README|Key Vault & Managed HSM]]   [[Azure/networking/firewall/README|Azure Firewall & NSGs]]
- Secure Score & Attack Paths    - Customer Managed Keys (CMK)   - Layer 7 IDPS & TLS Inspect
- Defender for Servers / AKS     - Secret Auto-Rotation tmpfs    - Private Link Zero Public IP
- Agentless Vulnerability Scans  - Soft-Delete & Purge Protect   - Bastion Zero Public RDP/SSH
```

### Security Capabilities Matrix

| Security Layer            | Azure Core Service                                           | AWS Equivalent                    | GCP Equivalent                | Key Cloud Native Differentiator                                                                      |
| :------------------------ | :----------------------------------------------------------- | :-------------------------------- | :---------------------------- | :--------------------------------------------------------------------------------------------------- |
| **Cloud Posture & CNAPP** | [[Azure/security/defender-for-cloud\|Defender for Cloud]]    | AWS Security Hub / GuardDuty      | Security Command Center (SCC) | Unifies posture (CSPM), attack paths, and runtime CWPP across Azure, AWS, and GCP with Secure Score. |
| **Secrets & Encryption**  | [[Azure/security/key-vault/README\|Key Vault & Managed HSM]] | AWS Secrets Manager / KMS         | Cloud KMS / Secret Manager    | Dedicated single-tenant FIPS 140-2 Level 3 HSM pools; native tmpfs volume driver for Kubernetes.     |
| **Enterprise Identity**   | [[Azure/identity/README\|Microsoft Entra ID & RBAC]]         | AWS IAM / Identity Center         | Cloud Identity & IAM          | Unified enterprise directory spanning Office 365, Windows, conditional access, and cloud RBAC.       |
| **SIEM & SOAR Ops**       | [[Azure/monitoring/sentinel/README\|Microsoft Sentinel]]     | Amazon Security Lake / OpenSearch | Google SecOps (Chronicle)     | Cloud-native SIEM running on Kusto Query Language (KQL) with automated Logic Apps SOAR playbooks.    |
| **Managed Jump Host**     | [[Azure/networking/bastion-nat\|Azure Bastion]]              | EC2 Instance Connect Endpoint     | Identity-Aware Proxy (IAP)    | Web browser and CLI-based RDP/SSH access with zero public IPs on target virtual machines.            |

---

## Service Catalog

- [[Azure/security/defender-for-cloud|Microsoft Defender for Cloud Architecture & CNAPP]] — Cloud Security Posture Management (CSPM), Cloud Workload Protection Platform (CWPP), Secure Score, Defender for Servers/Containers/Storage, and multi-cloud security.
- [[Azure/security/key-vault/README|Azure Key Vault & Managed HSM Architecture]] — FIPS 140-2 Level 3 hardware HSM, Azure RBAC authorization, Keys, Secrets, Certificates, Soft-Delete, and Purge Protection.
- [[Azure/identity/README|Microsoft Entra ID & Azure RBAC Architecture]] — Tenant architecture, Directory Roles vs Azure Resource RBAC, Managed Identities, PIM, and Conditional Access.
- [[Azure/networking/firewall/README|Azure Firewall & IDPS]] — Standard vs Premium tiers, TLS inspection, 67,000+ signature intrusion detection system (IDPS), and Virtual WAN Secured Hub integration.
- [[Azure/networking/bastion-nat|Azure Bastion & NAT Gateway Architecture]] — Secure zero-public-IP administration for Linux and Windows VMs via browser and native CLI.

---

## Related Hubs

- [[Security/cloud-security/azure/README|Azure Security Operations Hub]] — Centralized cloud-native security operations, threat hunting, and compliance posture.
- [[Azure/monitoring/sentinel/README|Microsoft Sentinel SIEM/SOAR]] — Automated threat detection and incident orchestration.
- [[Azure/compute/aks/security-workload-identity|AKS Workload Identity]] — Keyless OIDC authentication for containerized workloads.
