---
title: Security
tags: [security, index]
date: 2025-05-24
description: Security best practices, tooling, and operations across cloud, Kubernetes, Linux, and SIEM
---

# Security 🔐

Security coverage across cloud providers, Kubernetes, Linux hardening, SIEM, and incident response. This section consolidates security knowledge from your Wazuh SIEM expertise, AWS multi-account security monitoring, and homelab Kubernetes environment.

## Sections

### SIEM — Security Information & Event Management
Centralized security monitoring, detection, and alerting across all sources.

- [[Security/siem/README|SIEM Hub]] — Overview, tool comparison, Wazuh vs Elastic vs Splunk
- [[Security/siem/wazuh/README|Wazuh]] — Open-source SIEM/XDR, your primary tool
  - [[Security/siem/wazuh/deployment/README|Deployment]] — Single-node, distributed, agents, agentless
  - [[Security/siem/wazuh/rules-decoders/README|Rules & Decoders]] — Custom AWS CloudTrail, K8s, Linux rules
  - [[Security/siem/wazuh/integrations/README|Integrations]] — n8n → Planio → PagerDuty/Slack
  - [[Security/siem/wazuh/threat-hunting/README|Threat Hunting]] — Queries, playbooks, MITRE matrix
- [[Security/siem/alerting/README|Alerting]] — Alert design, thresholds, fatigue metrics
- [[Security/siem/elastic-security/README|Elastic Security]] — ELK-based SIEM
- [[Security/siem/splunk/README|Splunk]] — SPL queries, Enterprise Security

### Cloud Security — AWS, Azure, GCP
Security tooling and configuration per cloud provider.

- [[Security/cloud-security/README|Cloud Security Hub]] — AWS, Azure, GCP security tooling
- [[Security/cloud-security/aws/README|AWS Security]] — Security Hub, GuardDuty, CloudTrail, SCPs, multi-account
- [[Security/cloud-security/azure/README|Azure Security]] — Defender for Cloud, Entra ID
- [[Security/cloud-security/gcp/README|GCP Security]] — Security Command Center, Chronicle

### Kubernetes Security
Security for your EKS clusters and homelab K8s environment.

- [[Security/kubernetes-security/README|K8s Security Hub]]
- [[Security/kubernetes-security/rbac/README|RBAC]] — Role-based access control
- [[Security/kubernetes-security/network-policies/README|Network Policies]] — Micro-segmentation
- [[Security/kubernetes-security/pod-security/README|Pod Security]] — PodSecurityStandards, security contexts
- [[Security/kubernetes-security/secrets/README|Secrets Management]] — Sealed Secrets, Vault, ESO
- [[Security/kubernetes-security/vulnerability-scanning/README|Vulnerability Scanning]] — Trivy, Grype, Snyk

### Endpoint Security
Host-based security — Linux hardening, IDS/IPS, runtime security.

- [[Security/endpoint-security/README|Endpoint Security Hub]]
- [[Security/endpoint-security/hardening|Linux Hardening]] — AppArmor, SELinux, sysctl, PAM
- [[Security/endpoint-security/ids-ips|IDS/IPS]] — Suricata (NIDS), Wazuh HIDS
- [[Security/endpoint-security/falco|Falco]] — Runtime security, K8s syscall monitoring

### Application Security
Auth, secrets, dependency scanning, supply chain.

- [[Security/application-security/README|Application Security Hub]]
- [[Architecture/solution-architecture-concepts/authentication/README|Authentication]] — OAuth2/OIDC/JWT
- Secrets Management — Vault, AWS Secrets Manager, K8s secrets
- Dependency Scanning — Trivy, Snyk, Grype
- Supply Chain — SBOM, Sigstore, SLSA

### Network Security
TLS/mTLS, zero trust, VPN, firewall.

- [[Security/network-security/README|Network Security Hub]]
- [[Security/network-security/README|TLS/mTLS]] — Certificate management, mutual TLS
- Zero Trust — BeyondCorp model, identity-based access
- VPN — WireGuard, OpenVPN, IPSec

### DevSecOps
Shift-left security, CI/CD pipeline security, container hardening.

- [[Security/devsecops/README|DevSecOps Hub]]
- Pipeline Security — Securing GitHub Actions, Tekton, supply chain security
- Container Security — Distroless, rootless, capabilities, seccomp

### Incident Response
Playbooks, forensics, threat hunting, postmortems.

- [[Security/incident-response/README|Incident Response Hub]]
- [[Security/incident-response/playbooks/README|Playbooks]] — AWS cred compromise, malware, phishing
- [[Security/incident-response/forensics/README|Forensics]] — Memory dump, disk imaging, log analysis
- [[Security/incident-response/threat-hunting/README|Threat Hunting]] — Proactive hunting methodology
- [[Security/incident-response/postmortem/README|Postmortem]] — Blameless review template

## Your Security Stack

| Layer | Tool | Status |
|-------|------|--------|
| SIEM | Wazuh | Primary |
| Cloud Monitoring | Wazuh agentless (CloudTrail, GuardDuty) | Multi-account (40+ org) |
| Automation | n8n + Planio | Incident response workflow |
| K8s Security | Falco + Wazuh agent | EKS clusters |
| Container Scanning | Trivy | CI/CD |
| Secrets | Vault (existing notes) | Homelab |

## Key Vault References

Your existing notes that inform this section:

- [[AWS/concepts/iam|IAM]] — Identity and access management
- [[Kubernetes/eks/security|EKS Security]] — Cluster hardening, network policies
- [[Linux/hardening/pam|PAM]] — Pluggable authentication modules
- [[Resources/guides/security/ids|IDS/IPS]] — Network and host intrusion detection
- [[Resources/guides/security/zero-trust|Zero Trust]] — Network architecture
- [[Resources/guides/security/supply-chain-security|Supply Chain]] — SBOM, Sigstore

## Quick Navigation

```
SIEM          → Wazuh deployment, rules, n8n integrations, threat hunting
Cloud         → AWS Security Hub, GuardDuty, multi-account SCPs, CloudTrail
K8s           → RBAC, network policies, pod security, secrets, Trivy
Linux         → AppArmor, SELinux, PAM, sysctl hardening
IR            → Playbooks, forensics, postmortems, n8n automation
```

## Contributing

This section is actively expanded. Key areas to develop:
- [ ] Add Wazuh agent deployment on EKS with IRSA
- [ ] Add AWS SCP examples for security baseline
- [ ] Add Falco → n8n → Planio workflow
- [ ] Add Vault deployment guide for secrets
- [ ] Add K8s audit log analysis with Wazuh