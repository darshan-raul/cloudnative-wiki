---
title: Azure Security
tags: [security, azure, microsoft, defender, entra-id]
date: 2025-05-24
description: Azure security - Microsoft Defender for Cloud, Entra ID protection, Azure Sentinel, and Azure-native security tooling
---

# Azure Security ☁️🔐

Microsoft Azure security services and configuration.

## Core Services

| Service | Purpose |
|---------|---------|
| **Microsoft Defender for Cloud** | Cloud security posture management (CSPM) |
| **Microsoft Entra ID** | Identity and access management (formerly Azure AD) |
| **Microsoft Sentinel** | Cloud-native SIEM (Azure's SIEM solution) |
| **Azure Firewall** | Managed firewall-as-a-service |
| **Azure Bastion** | Secure RDP/SSH access without public IPs |

## Defender for Cloud

Cloud-native CSPM — security posture management and threat protection across Azure workloads.

### Security Posture

- **Secure Score** — Overall security posture rating (0-100%)
- **MSSA** — Microsoft Security Score Analytics
- **Recommendations** — Hardening actions prioritized by risk

### Threat Protection

- **Defender for Servers** — Runtime protection, alerting
- **Defender for Storage** — Anomaly detection on blob access
- **Defender for SQL** — Vulnerability assessment, threat detection

## Entra ID (Azure AD) Security

### Conditional Access

```json
{
  "conditions": {
    "signInRiskLevel": "high",
    "devicePlatform": "iOS"
  },
  "grantControls": {
    "operator": "AND",
    "controls": ["blockAccess"]
  }
}
```

### Identity Protection

- **Risky users** — Detect compromised accounts
- **Risky sign-ins** — Anomaly-based risk scoring
- **MFA enforcement** — Conditional access policies

## Related

- [[Security/cloud-security/README|Cloud Security Hub]]
- [[Azure/identity/entraid|Entra ID]]