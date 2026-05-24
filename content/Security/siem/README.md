---
title: SIEM
tags: [security, siem, logging, monitoring, detection]
date: 2025-05-24
description: Security Information and Event Management - centralizing security monitoring, detection, and alerting across AWS, Kubernetes, and Linux
---

# SIEM

Security Information and Event Management (SIEM) platforms centralize log collection, correlation, and alerting for security monitoring across your entire environment.

## Core Functions

| Function | Description |
|----------|-------------|
| Log Collection | Gather logs from agents, syslog, cloud APIs |
| Normalization | Parse diverse log formats into structured data |
| Correlation | Link events across sources to detect attacks |
| Alerting | Generate alerts based on rules and thresholds |
| Retention | Store logs for compliance and forensics |

## SIEM Tools Comparison

| Tool | Type | Strengths | Best For |
|------|------|-----------|----------|
| [[Security/siem/wazuh/README|Wazuh]] | Open source | CloudTrail native, agentless AWS, built-in XDR | Your multi-account AWS (40+ org), homelab |
| [[Security/siem/elastic-security/README|Elastic Security]] | Open source | Scale, performance, ML features | High-volume environments |
| [[Security/siem/splunk/README|Splunk]] | Commercial | SPL language, enterprise integrations | Large enterprises |
| Microsoft Sentinel | SaaS | Azure integration, M365 integration | Azure-heavy shops |
| XSIAM (Palo Alto) | SaaS | ML-driven, automated response | Advanced SOCs |

## Your Setup: Wazuh

Given your environment (40+ AWS accounts, homelab Kubernetes, Wazuh SIEM), Wazuh is your primary SIEM:

- **Agentless** — CloudTrail, GuardDuty, VPC Flow Logs from AWS
- **Agents** — Linux, Windows endpoints in homelab
- **Kubernetes** — EKS audit logs via agent or sidecar
- **n8n integration** — Automated incident response with Planio

## Multi-Account Architecture

```
AWS Organization (40+ accounts)
  │
  ├── Security Tooling Account
  │     ├── Wazuh Manager (primary)
  │     └── S3 bucket (CloudTrail aggregated)
  │
  ├── Production Account 1
  │     └── CloudTrail → S3 → Security account
  │
  └── Production Account N
        └── CloudTrail → S3 → Security account

Wazuh Agentless:
  - Reads CloudTrail from S3
  - Reads GuardDuty findings
  - Reads VPC Flow Logs
  - Generates alerts
  - Sends to n8n → Planio
```

## Alert Flow

```
Log Source → Wazuh Agent/Agentless → Manager (parse/rule) → Alert
                                                          │
                                                          ▼ HTTP POST
                                                        n8n Workflow
                                                          │
                                          ┌───────────────┼───────────────┐
                                          ▼               ▼               ▼
                                      Slack          PagerDuty         Planio
                                      (info)         (critical)        (tickets)
```

## Related

- [[Security/siem/wazuh/README|Wazuh]] — Your primary SIEM
- [[Security/siem/alerting/README|Alerting]] — Alert design best practices
- [[Security/siem/elastic-security/README|Elastic Security]] — Alternative open-source SIEM
- [[Security/siem/splunk/README|Splunk]] — Commercial SIEM