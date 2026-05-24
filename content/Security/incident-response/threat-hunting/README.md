---
title: Threat Hunting
tags: [threat-hunting, hunting, detection, proactive, siem]
date: 2025-05-24
description: Proactive threat hunting methodology - hypotheses, MITRE ATT&CK mapping, and hunting queries
---

# Threat Hunting 🎯

Proactive hunting assumes an adversary is already in the environment. You look for indicators of compromise (IOCs) and behavioral anomalies that automated rules miss.

## Hunting Methodology

```
Hypothesis → Data Collection → Analysis → Lead → Response
```

Start with a hypothesis: "Threat actors are using living-off-the-land binaries to evade detection."

## MITRE ATT&CK Alignment

Map your hunts to ATT&CK techniques:

| Technique | Hunt For |
|----------|----------|
| T1059 (Command & Scripting Interpreter) | PowerShell/Bash spawned from browser/email client |
| T1070 (Indicator Removal) | Log clearing, history deletion |
| T1048 (Exfiltration) | Large data transfers to unexpected external IPs |
| T1053 (Scheduled Task) | Cron jobs created by non-root users |

## Wazuh Hunting Queries

```bash
# Find PowerShell running from browser
alert.rule.group: "webshell" AND rule.description: "*cmd.exe*"

# Find lateral movement (RDP from unusual host)
alert.location: "windows" AND data.win.eventdata.destPort: 3389
| stats count by src_ip, user

# Find data exfiltration (large outbound)
alert.rule.group: "aws-cloudtrail" AND eventName: "PutObject"
| where size > 100MB

# Find privilege escalation (new admin added)
alert.rule.group: "windows" AND eventID: 4720
```

## CloudTrail Hunting

```bash
# Find console logins from new locations
eventName=ConsoleLogin AND NOT (awsRegion IN ["us-east-1", "us-west-2"])

# Find API calls from tor exit nodes
eventName=* AND sourceIPAddress=<tor-exit-ip>

# Find unusual AssumeRole chains
eventName=AssumeRole | stats count by requestParameters.roleArn, userIdentity.arn
```

## Behavioral Anomalies

- User login at unusual hour (compared to baseline)
- Service account used for interactive login
- Large number of failed logins followed by success
- API calls from a region you've never seen traffic from

## Automation

```
Hunt query → Positive result → Auto-create Planio ticket + Slack alert
```

## Related

- [[Security/siem/wazuh/README|Wazuh]]
- [[Security/siem/wazuh/threat-hunting/README|Wazuh Threat Hunting]]