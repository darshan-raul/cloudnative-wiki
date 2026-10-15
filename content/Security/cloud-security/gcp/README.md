---
title: GCP Security Operations
tags:
  [security, gcp, google-cloud, scc, chronicle, workload-identity, zero-trust]
date: 2026-10-15
description: GCP security architecture — Security Command Center, Chronicle SIEM, Workload Identity Federation, Cloud Armor, and BeyondCorp Zero Trust tooling.
---

# GCP Security Operations 🟠🔐

Google Cloud Platform security architecture unifies Cloud Security Posture Management (CSPM), Cloud Workload Protection (CWPP), Security Information and Event Management (SIEM), and identity federation under a Zero Trust model.

---

## Core Security & Zero Trust Services

| Service                                   | Category                | Purpose & Architecture                                                                     | Deep Dive Reference                                              |
| :---------------------------------------- | :---------------------- | :----------------------------------------------------------------------------------------- | :--------------------------------------------------------------- |
| **Security Command Center (SCC)**         | CSPM / CWPP             | Centralized vulnerability management and agentless hypervisor VM Threat Detection (VMTD).  | [[GCP/security/scc\|Security Command Center (SCC)]]              |
| **Cloud Armor**                           | Edge WAF & DDoS         | Global Anycast edge DDoS defense, OWASP ModSecurity CRS, and ML Adaptive Protection.       | [[GCP/security/cloud-armor\|Cloud Armor Deep Dive]]              |
| **Identity-Aware Proxy (IAP)**            | Zero Trust Access       | BeyondCorp context-aware HTTPS/TCP proxying, eliminating VPNs for SSH/RDP.                 | [[GCP/security/iap-beyondcorp\|IAP & BeyondCorp Deep Dive]]      |
| **Workload Identity Federation**          | Keyless Auth            | OIDC/SAML token exchange eliminating static JSON service account keys for GitHub and AWS.  | [[GCP/identity/workload-identity\|Workload Identity Federation]] |
| **Cloud KMS & Cloud HSM**                 | Key Management          | FIPS 140-2 Level 3 hardware HSM, CMEK envelope encryption, and External Key Manager (EKM). | [[GCP/security/kms/README\|Cloud KMS & Envelope Encryption]]     |
| **Sensitive Data Protection (Cloud DLP)** | Data Privacy            | Automated discovery, classification, and cryptographic tokenization of PII/PHI.            | [[GCP/security/cloud-dlp\|Cloud DLP Deep Dive]]                  |
| **Certificate Authority Service (CAS)**   | Enterprise PKI          | Managed private CA hierarchy (Root/Subordinate CAs) and Certificate Manager client mTLS.   | [[GCP/security/cas\|Certificate Authority Service]]              |
| **Organization Policies**                 | Preventive Guardrails   | Programmatic admission-control guardrails across Org/Folder/Project hierarchies.           | [[GCP/governance/org-policies\|Organization Policies Deep Dive]] |
| **Binary Authorization**                  | Supply Chain Gatekeeper | Cryptographic container image deploy-time verification enforcing SLSA Level 3 provenance.  | [[GCP/compute/gke/binary-authorization\|Binary Authorization]]   |

---

## Security Command Center (SCC)

Google Cloud's cloud-native CSPM and CWPP platform. Activate at organization or project level.

```bash
# Enable Security Command Center API
gcloud services enable securitycenter.googleapis.com

# List high-severity active security findings across the organization
gcloud scc findings list --organization=<org-id> --severity=HIGH --filter="state=\"ACTIVE\""
```

### Tiers & Detection Capabilities

- **SCC Standard:** Included free of charge; reports basic asset inventory and basic misconfigurations.
- **SCC Premium / Enterprise:** Advanced threat detection, Event Threat Detection (ETD), Container Threat Detection (CTD), agentless hypervisor-level VM Threat Detection (VMTD), and compliance reporting against CIS GCP Foundations Benchmark.

---

## Chronicle SIEM & Security Operations

Google SecOps (Chronicle) is Google's cloud-native SIEM built on Google search infrastructure, designed for petabyte-scale security telemetry ingestion, sub-second threat hunting, and YARA-L detection rule execution.

```bash
# Ingest security telemetry logs directly via Cloud Logging sinks
gcloud logging sinks create chronicle-ingest-sink \
  chronicle.googleapis.com/v1alpha/projects/<PROJECT_ID>/locations/<LOCATION>/instances/<INSTANCE_ID> \
  --log-filter="logName:\"logs/cloudaudit.googleapis.com\""
```

---

## Workload Identity Federation

Eliminates high-risk static JSON service account keys by federating identities from AWS, Azure, GitHub Actions, or Kubernetes via standard OIDC token exchange:

```bash
# Create a Workload Identity Pool for external CI/CD runners
gcloud iam workload-identity-pools create github-actions-pool \
  --location="global" \
  --description="Pool for GitHub Actions CI/CD workflows"

# Bind an external repository subject to a Google Cloud Service Account
gcloud iam service-accounts add-iam-policy-binding deployer-sa@my-prod-project.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/1234567890/locations/global/workloadIdentityPools/github-actions-pool/attribute.repository/my-org/my-repo"
```

---

## Related Knowledge Hubs

- [[GCP/security/README|GCP Security & Identity Hub]] — Complete Google Cloud security catalog
- [[GCP/governance/README|GCP Governance Hub]] — Resource hierarchy and organization policies
- [[Security/cloud-security/README|Cloud Security Hub]] — Multi-cloud security posture
- [[GCP/compute/gke/security|GKE Security & Hardening]] — Kubernetes cluster defense and Workload Identity
- [[AWS/security/README|AWS Security Comparison]] — Architectural comparison with AWS security services
