---
title: Incident Response
tags: [incident-response, ir, forensics, threat-hunting, playbook]
date: 2025-05-24
description: Incident response - playbooks, forensics, threat hunting, postmortems, and blameless reviews
---

# Incident Response

Incident response procedures, forensics, threat hunting, and postmortems.

## IR Lifecycle

```
PREPARE → DETECT → CONTAIN → ERADICATE → RECOVER → LESSONS LEARNED
    ↑                                                                    |
    └────────────────────────────────────────────────────────────────────┘
```

## Sections

- [[Security/incident-response/playbooks/README|Playbooks]] — IR playbooks for common scenarios (AWS cred compromise, malware, phishing, K8s compromise, S3 public access)
- [[Security/incident-response/forensics/README|Forensics]] — Memory dump, disk acquisition, log analysis, evidence preservation
- [[Security/incident-response/threat-hunting/README|Threat Hunting]] — Proactive hunting methodology and queries
- [[Security/incident-response/postmortem/README|Postmortem]] — Blameless incident reviews and templates

## Key Playbooks

| Scenario | Priority | Automation Target |
|----------|----------|-------------------|
| AWS compromised credentials | Critical | n8n: block IP + rotate creds |
| Malware on endpoint | Critical | n8n: isolate + alert |
| Phishing link clicked | High | n8n: reset creds + scan endpoint |
| Data exfiltration | Critical | n8n: block + notify |
| K8s cluster compromise | Critical | n8n: isolate namespace |

## Your n8n + Planio Integration

Your existing n8n + Planio setup maps to IR:

```
Alert → n8n webhook → workflow → Planio ticket
                         ↓
                   Slack notification
                         ↓
                   Auto-remediation (block IP, isolate)
```

## Related

- [[Security/siem/README|SIEM]] — Detection and alerting
- [[Security/siem/wazuh/integrations/README|Wazuh Integrations]] — n8n automation