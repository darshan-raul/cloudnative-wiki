---
title: Elastic Security
tags: [siem, elastic, elasticsearch, kibana, elastic-security]
date: 2025-05-24
description: Elastic Security (Elastic SIEM) - Elasticsearch-based security analytics, detection rules, and threat hunting
---

# Elastic Security 🟦

Elastic Security provides SIEM capabilities built on the Elasticsearch/Logstash/Kibana (ELK) stack.

## Components

- **Elasticsearch** — Security events storage and search
- **Beats/Fleet** — Lightweight agents for log collection
- **Elastic Defend** — Endpoint security integration (replacement for Endpoint Integrations)
- **Kibana Security** — Dashboards, detection rules, case management

## Architecture

```
Agents (Elastic Defend, Filebeat)
    │
    ▼
Logstash / Fleet Server
    │
    ▼
Elasticsearch Indexer
    │
    ▼
Kibana (Security App)
  ├── Detection Rules
  ├── Cases
  ├── Timelines
  └── Dashboards
```

## Detection Rules

Built-in rules mapped to MITRE ATT&CK. Custom rules written in KQL (Kibana Query Language).

```kql
event.category: process and process.name: "powershell.exe" and
process.args: "-enc" and not user.name: "SYSTEM"
```

## Your Context

If you're using Wazuh as primary SIEM, Elastic Security is a potential migration target for:
- Large-scale environments (Elastic scales better at 10B+ events/day)
- Teams already on the ELK stack
- When you need advanced ML anomaly detection (Elastic SIEM has built-in ML jobs)

## Related

- [[Security/siem/README|SIEM Overview]]
- [[Security/siem/wazuh/README|Wazuh]]