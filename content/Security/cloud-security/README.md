---
title: Cloud Security Hub
tags: [security, cloud, aws, azure, gcp, cloud-security]
date: 2025-05-24
description: Cloud security best practices, tooling, and configuration for AWS, Azure, and GCP
---

# Cloud Security Hub ☁️🔐

Security tooling and configuration across AWS, Azure, and GCP.

## AWS Security

- [[Security/cloud-security/aws/README|AWS Security Hub]] — Security Hub, GuardDuty, CloudTrail, SCPs, multi-account monitoring

## Azure Security

- [[Security/cloud-security/azure/README|Azure Security]] — Defender for Cloud, Entra ID, Azure Sentinel

## GCP Security

- [[Security/cloud-security/gcp/README|GCP Security]] — Security Command Center, Chronicle, Workload Identity

## Multi-Cloud Themes

### Identity & Access Management
- Enforce least privilege via cloud-native IAM
- Use workload identity (IRSA, WIF) instead of service account keys
- Regular access reviews and automated remediation

### Logging & Monitoring
- Centralize cloud logs to your SIEM (Wazuh agentless for AWS)
- Enable guardduty/defender-for-cloud/chronicle everywhere
- Ship logs to S3 → Wazuh → n8n → Planio

### Network Security
- No public ingress to control planes
- Private subnets for workloads
- Security groups / NSGs as firewalls
- Zero-trust network segmentation

## Related

- [[Security/siem/wazuh/README|Wazuh]]
- [[Security/incident-response/README|Incident Response]]