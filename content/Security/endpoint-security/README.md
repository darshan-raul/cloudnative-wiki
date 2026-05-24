---
title: Endpoint Security
tags: [endpoint, security, hardening, ids, linux]
date: 2025-05-24
description: Endpoint security - Linux hardening, IDS/IPS, host-based detection, and runtime security
---

# Endpoint Security

Security for endpoints — Linux hardening, host-based intrusion detection, and runtime security.

## Sections

### Linux Hardening
- [[Security/endpoint-security/hardening/README|Linux Hardening]] — AppArmor, SELinux, sysctl, PAM

### IDS/IPS
- [[Security/endpoint-security/ids-ips/README|IDS/IPS]] — Network and host-based intrusion detection (Suricata, Wazuh HIDS)

### Falco
- [[Security/endpoint-security/falco/README|Falco]] — Runtime security for Kubernetes and Linux

## Endpoint Security Layers

1. **Hardening** — Reduce attack surface (disable services, patch)
2. **Access Control** — PAM, sudo, file permissions
3. **Monitoring** — Logs, audit, syscall monitoring
4. **Detection** — IDS, file integrity, rootkit detection
5. **Response** — Auto-isolate, block, notify

## Tool Stack

| Tool | Type | Purpose |
|------|------|---------|
| Wazuh Agent | HIDS | File integrity, rootkit detection, log collection |
| Falco | HIDS | Runtime syscall monitoring |
| AppArmor | LSM | Application sandboxing |
| SELinux | LSM | Mandatory access control |
| auditd | Logging | System call auditing |

## Related

- [[Security/siem/wazuh/README|Wazuh]] — Agent-based endpoint collection
- [[Security/siem/alerting/README|Alerting]] — Endpoint alert design