---
title: Alerting
tags: [siem, alerting, detection, wazuh]
date: 2025-05-24
description: Designing effective security alerts - thresholds, severity, fatigue metrics, and SIEM alert best practices
---

# Alerting 📯

Alert design is critical — too many alerts causes fatigue, too few misses incidents.

## Alert Design Principles

### Severity Tiers

| Level | Description | Response Time | Example |
|-------|-------------|---------------|---------|
| 1-4 | Low —值得监控但不需要立即处理 | Batch review | Unusual process, non-critical failed logins |
| 5-6 | Medium —可疑活动 | Within 4h | New IAM user, port scan detected |
| 7-8 | High —可能入侵 | Within 1h | Brute force attempt, anomalous API call |
| 9-10 | Critical —确认事件 | Immediate | Ransomware, data exfiltration |

### Alert Fatigue Metrics

Track these to keep signal quality high:

- **True Positive Rate (TPR)** — % of alerts that are real incidents
- **False Positive Rate (FPR)** — alerts that don't represent real threats
- **Mean Time to Investigate (MTTI)** — average time from alert to resolution
- **Alert volume per analyst** — too many alerts overwhelms teams

## Wazuh Alert Configuration

```xml
<!-- ossec.conf - set minimum alert level -->
<alerts>
  <log_alerts_level>6</log_alerts_level>
  <email_alerts_level>12</email_alerts_level>
</alerts>
```

### Custom Alert Thresholds

```bash
# Adjust alert frequency per rule
# In local_rules.xml
<rule id="100101" level="8">
  <match>failed password</match>
  <count>5 in 60</count>  <!-- 5 failures in 60s triggers alert -->
  <description>Brute force attempt detected</description>
</rule>
```

## Alert Enrichment

Before routing to humans, enrich alerts with context:

- **Asset context** — Is this a production server or test box?
- **User context** — Is this a service account or admin?
- **Threat intel** — Is the source IP known malicious?
- **Historical baseline** — Is this behavior anomalous for this user?

## Escalation Paths

```
Level 8+ → PagerDuty + Slack #security-incidents
Level 6-7 → Slack #security-alerts
Level 5 → Log only, batch review
```

## Related

- [[Security/siem/wazuh/README|Wazuh]]
- [[Security/siem/wazuh/integrations/README|Integrations]]