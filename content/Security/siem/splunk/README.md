---
title: Splunk
tags: [siem, splunk, splunk-enterprise-security, spl]
date: 2025-05-24
description: Splunk Enterprise Security - SPL queries, dashboards, Enterprise Security app, and SIEM comparison
---

# Splunk 🟥

Splunk is an enterprise-grade SIEM platform known for its powerful SPL (Search Processing Language) and scalability.

## Core Concepts

### SPL (Search Processing Language)

```spl
# Find AWS console logins from unexpected locations
index=aws_cloudtrail eventName=ConsoleLogin
| eval is_ok = mvfind(location, "^(us|eu)-east-1$")
| where isnull(is_ok)

# Find privilege escalation
index=security action=failure | stats count by user src_ip
| where count > 10
```

### Splunk Enterprise Security (ES)

The ES app provides:
- **Correlation searches** — Pre-built detection rules
- **Notable events** — Alert triage interface
- **Risk analysis** — Risk score per entity
- **Incident review** — Case management

## Splunk vs Wazuh

| Feature | Splunk | Wazuh |
|---------|--------|-------|
| License | Proprietary (expensive) | Open source (free) |
| SPL vs rules | Custom SPL search language | XML rules |
| Scale | 10B+ events/day | ~1M events/day per manager |
| Cloud-native | Yes (Splunk Cloud) | Self-hosted |
| ML | Built-in MLTK | Via integration |

## Your Context

Splunk is overkill for your homelab and likely unnecessary for a 40-account AWS org unless you have massive log volume. Wazuh fits better for your current scale.

## Related

- [[Security/siem/README|SIEM Overview]]
- [[Security/siem/wazuh/README|Wazuh]]