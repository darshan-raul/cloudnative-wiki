---
title: Wazuh Rules & Decoders
tags: [wazuh, rules, decoders, detection, siem, mitre]
date: 2025-05-24
description: Writing custom Wazuh rules, decoders, alert thresholds, and MITRE ATT&CK mapping for AWS CloudTrail, Kubernetes, and Linux
---

# Wazuh Rules & Decoders

Rules and decoders are the core of Wazuh's detection engine. Decoders normalize raw log data; rules match patterns and generate alerts.

## Architecture

```
Raw Log → Decoder (normalize) → Rule Engine (match) → Alert
          ↓                              ↓
      Field extraction              If matched → alert + level
                                     If not → discarded
```

- **Decoders** — Parse raw logs into structured fields (source, destination, action, etc.)
- **Rules** — Match decoded fields against patterns; assign level, group, and actions
- **Alerts** — Generated when rules match; stored in the indexer for visualization

## Decoder Structure

### Basic Decoder Example

```xml
<!-- /var/ossec/etc/decoders/0000-custom-decoder.xml -->

<decoder name="custom-ssh">
  <program_name>sshd</program_name>
  <prematch>^Accepted</prematch>
  <regex>^(\S+) (\S+) for (\S+) from (\S+) port (\d+) (\S+)</regex>
  <order>srcuser, user, srcip, srcport, protocol</order>
  <description>SSH login success</description>
</decoder>
```

### Decoder Fields

| Field | Description |
|-------|-------------|
| `program_name` | Match logs by the program generating them |
| `prematch` | Fast regex check before full decode |
| `regex` | Full regex with capture groups for fields |
| `order` | Ordered list of captured fields |
| `fts` | First time seen — tracks new unique events |

### Decoder with Parent (Inheritance)

```xml
<!-- Base decoder for SSH -->
<decoder name="sshd-base">
  <program_name>sshd</program_name>
  <prematch>^sshd</prematch>
</decoder>

<!-- Child decoder for specific SSH event -->
<decoder name="sshd-accepted" parent="sshd-base">
  <prematch>^Accepted</prematch>
  <regex>^Accepted (\S+) for (\S+) from (\S+) port (\d+)</regex>
  <order>auth_method, user, srcip, srcport</order>
  <description>SSH authentication success</description>
</decoder>
```

## Rule Structure

### Basic Rule Example

```xml
<!-- /var/ossec/etc/rules/local_rules.xml -->

<group name="custom-ssh">
  <rule id="100001" level="3">
    <if_sid>SSH</if_sid>  <!-- or decoder name -->
    <match>Accepted</match>
    <description>SSH login successful</description>
    <group>authentication_success,ssh</group>
  </rule>

  <rule id="100002" level="6">
    <if_sid>100001</if_sid>
    <srcip>10.0.0.0/8</srcip>  <!-- Internal IP - lower level -->
    <description>SSH login from internal network</description>
    <level>2</level>
  </rule>

  <rule id="100003" level="10">
    <if_sid>100001</if_sid>
    <srcip>!10.0.0.0/8</srcip>  <!-- Not internal -->
    <description>SSH login from external IP - alert</description>
    <group>authentication_fail,threat</group>
  </rule>
</group>
```

### Rule Levels (0-15)

| Level | Meaning |
|-------|---------|
| 0 | None (log only, no alert) |
| 1 | Low (information) |
| 3-5 | Medium (important but normal) |
| 6-7 | High (值得关注) |
| 10-14 | Critical (immediate attention) |
| 15 | Highest (flood/lockout) |

### Rule ID Ranges

| Range | Owner |
|-------|-------|
| 0-99999 | Wazuh built-in rules |
| 100000-100999 | Local rules (custom) |
| 101000+ | Shared rules (custom) |

## Custom Rules for AWS CloudTrail

### CloudTrail Decoder

```xml
<!-- CloudTrail event decoder -->
<decoder name="aws-cloudtrail">
  <program_name>aws-cloudtrail</program_name>
  <prematch>^\{"eventVersion"</prematch>
  <json/>
  <order>src_ip,user,action,result</order>
  <description>AWS CloudTrail JSON logs</description>
</decoder>

<!-- More granular decoder for specific events -->
<decoder name="cloudtrail-console-login" parent="aws-cloudtrail">
  <prematch>"eventName":"ConsoleLogin"</prematch>
  <json/>
  <order>aws_region, recipient_acc_id, session_arn</order>
  <description>AWS Console Login event</description>
</decoder>
```

### CloudTrail Rules

```xml
<!-- AWS Console Login from unexpected location -->
<rule id="100100" level="8">
  <if_sid>aws-cloudtrail</if_sid>
  <field name="eventName">ConsoleLogin</field>
  <field name="responseElements.consoleLogin">Failure</field>
  <description>AWS Console login failed</description>
  <group>aws,cloudtrail,authentication_failure</group>
  <mitre>
    <id>T1078.004</id>
  </mitre>
</rule>

<rule id="100101" level="6">
  <if_sid>aws-cloudtrail</if_sid>
  <field name="eventName">ConsoleLogin</field>
  <field name="responseElements.consoleLogin">Success</field>
  <field name="aws.region">us-east-1</field>
  <field name="userIdentity.arn">arn:aws:iam::123456789012:root</field>
  <description>AWS Console login as root account</description>
  <group>aws,cloudtrail,privileged_account</group>
</rule>

<!-- AWS API call from new IP for user -->
<rule id="100102" level="7">
  <if_sid>aws-cloudtrail</if_sid>
  <field name="errorCode">.</field>  <!-- Any error -->
  <description>AWS API call returned error - possible reconnaissance</description>
  <group>aws,cloudtrail,api_error</group>
</rule>

<!-- S3 bucket made public -->
<rule id="100103" level="10">
  <decoded_as>aws-cloudtrail</decoded_as>
  <field name="eventName">PutBucketAcl</field>
  <field name="requestParameters.accessControlList.grant">ALLUSERS</field>
  <description>AWS S3 bucket ACL made public - data exposure risk</description>
  <group>aws,cloudtrail,s3,data_exposure</group>
  <mitre>
    <id>T0899</id>
  </mitre>
</rule>

<!-- IAM policy changed to allow public access -->
<rule id="100104" level="10">
  <if_sid>aws-cloudtrail</if_sid>
  <field name="eventName">PutAccountPolicy</field>
  <description>AWS account-level policy modified - potential misconfiguration</description>
  <group>aws,cloudtrail,iam,policy_change</group>
</rule>

<!-- VPC Flow Logs - suspicious port scan -->
<rule id="100105" level="7">
  <if_sid>vpc-flowlogs</if_sid>
  <field name="action">REJECT</field>
  <same_srcip>15</same_srcip>  <!-- Same src IP, 15+ events -->
  <description>Potential port scan from single source</description>
  <group>aws,vpc,reconnaissance,port_scan</group>
  <mitre>
    <id>T1046</id>
  </mitre>
</rule>
```

## Custom Rules for Kubernetes

```xml
<!-- Kubernetes: Anonymous access to API -->
<rule id="100200" level="8">
  <if_sid>kubernetes-api</if_sid>
  <field name="user.username">system:anonymous</field>
  <description>Kubernetes API accessed anonymously</description>
  <group>k8s,authentication,anonymous</group>
  <mitre>
    <id>T0853</id>
  </mitre>
</rule>

<!-- Kubernetes: Failed pod creation attempt -->
<rule id="100201" level="5">
  <if_sid>kubernetes-api</if_sid>
  <field name="verb">create</field>
  <field name="resource">pods</field>
  <field name="responseStatus.code">403</field>
  <description>User denied pod creation in Kubernetes</description>
  <group>k8s,RBAC,access_denied</group>
</rule>

<!-- Kubernetes: Service account token mounted in pod -->
<rule id="100202" level="8">
  <if_sid>kubernetes-api</if_sid>
  <field name="objectRef.resource">pods</field>
  <field name="objectRef.subresource">serviceaccounts/token</field>
  <field name="verb">create</field>
  <description>Service account token mount requested</description>
  <group>k8s,privilege_escalation,service_account</group>
  <mitre>
    <id>T1552.001</id>
  </mitre>
</rule>
```

## Custom Rules for Linux (Hardening)

```xml
<!-- SSH: Root login attempted -->
<rule id="100300" level="6">
  <if_sid>sshd</if_sid>
  <match>ROOT</match>
  <regex>user (root) from (\S+)</regex>
  <description>SSH root login attempted</description>
  <group>authentication,ssh,root</group>
</rule>

<!-- Failed sudo attempt -->
<rule id="100301" level="4">
  <if_sid>sudo</if_sid>
  <match>authentication failure</match>
  <description>Failed sudo attempt</description>
  <group>authentication,privilege_escalation</group>
</rule>

<!-- New user added to sudo group -->
<rule id="100302" level="8">
  <if_sid>sudo</if_sid>
  <match>add to group sudo</match>
  <description>User added to sudo group</description>
  <group>privilege_escalation,persistence</group>
  <mitre>
    <id>T1098</id>
  </mitre>
</rule>

<!-- Cron job created/modified -->
<rule id="100303" level="5">
  <if_sid>syslog</if_sid>
  <program_name>cron</program_name>
  <match>(CRON|anacron)\s+(user|job)</match>
  <regex>^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)</regex>
  <description>New cron job detected</description>
  <group>persistence,cron</group>
</rule>

<!-- Sudoers file modified -->
<rule id="100304" level="10">
  <if_sid>syslog</if_sid>
  <program_name>sudo</program_name>
  <match>/etc/sudoers</match>
  <description>Sudoers file modified - potential privilege escalation</description>
  <group>privilege_escalation,config_change</group>
  <mitre>
    <id>T1548.003</id>
  </mitre>
</rule>
```

## Alert Thresholds & Rate Limiting

### Threshold Rules (Avoid Alert Flood)

```xml
<!-- Alert only after 5 failed SSH attempts in 10 minutes -->
<rule id="100400" level="6">
  <if_sid>100001</if_sid>
  <field name="action">failure</field>
  <same_field srcip>5</same_field>  <!-- Same src IP, 5+ events -->
  <time_frame>10m</time_frame>
  <description>Multiple SSH login failures from same IP</description>
  <group>brute_force,ssh</group>
  <mitre>
    <id>T1110</id>
  </mitre>
</rule>

<!-- Block IP after 10 failures (for automation) -->
<rule id="100401" level="10">
  <if_sid>100400</if_sid>
  <same_field srcip>10</same_field>
  <time_frame>5m</time_frame>
  <description>Brute force attack detected - 10+ failures</description>
  <group>brute_force,attack</group>
  <!-- Integrate with n8n for firewall block -->
</rule>

<!-- Disable alerting for known OK sources -->
<rule id="100402" level="0">
  <if_sid>100001</if_sid>
  <srcip>10.0.1.100</srcip>  <!-- Your jump host -->
  <description>SSH from trusted jump host - no alert</description>
  <noalert>yes</noalert>
</rule>
```

### Dynamic Threshold (Statistical)

```xml
<!-- Above average failed logins for user -->
<rule id="100403" level="6">
  <if_sid>sshd</if_sid>
  <field name="action>failure</field>
  <same_field user>10</same_field>
  <time_frame>1h</time_frame>
  <description>Unusual number of failed SSH attempts for user</description>
  <group>threat,user_anomaly</group>
</rule>
```

## MITRE ATT&CK Mapping

Map your rules to MITRE ATT&CK for better threat context.

### MITRE Integration in Rules

```xml
<rule id="100500" level="8">
  <if_sid>aws-cloudtrail</if_sid>
  <field name="eventName">CreateUser</field>
  <description>New IAM user created</description>
  <group>aws,persistence,iam</group>
  <mitre>
    <id>T0859</id>  <!-- Account Manipulation: Add IAM user -->
  </mitre>
</rule>

<rule id="100501" level="8">
  <if_sid>aws-cloudtrail</if_sid>
  <field name="eventName">AttachUserPolicy</field>
  <field name="requestParameters.policyArn">arn:aws:iam::.*:policy/AdministratorAccess</field>
  <description>Administrator policy attached to user</description>
  <group>aws,privilege_escalation</group>
  <mitre>
    <id>T1098</id>  <!-- Account Manipulation: IAM privilege escalation -->
  </mitre>
</rule>

<rule id="100502" level="10">
  <if_sid>aws-cloudtrail</if_sid>
  <field name="eventName">GetSecretAccessKey</field>
  <description>AWS Secret Access Key accessed</description>
  <group>aws,credential_access,secrets</group>
  <mitre>
    <id>T1552</id>  <!-- Unsecured Credentials -->
  </mitre>
</rule>
```

### MITRE Coverage Matrix

| MITRE ID | Technique | Rule Example |
|----------|----------|--------------|
| T1078.004 | Valid Accounts: Cloud Accounts | AWS console login from unexpected location |
| T0859 | Account Manipulation: IAM | New IAM user created |
| T1098 | Account Manipulation: Authorization | Admin policy attached to user |
| T1552 | Unsecured Credentials | Secret access key accessed |
| T0899 | Data Destruction | S3 bucket policy changed to public |
| T1046 | Network Service Discovery | Port scan detected in VPC logs |
| T1110 | Brute Force | SSH brute force from single IP |
| T1548.003 | Sudo/Sudoers | Sudoers file modified |
| T0853 | Virtualization/Sandbox | K8s anonymous API access |
| T1552.001 | Service Account Credentials | SA token mounted in pod |

## Testing Rules

```bash
# Test configuration
/var/ossec/bin/wazuh-logtest

# Example input for SSH failed login:
Wed Jan 15 10:30:00 server sshd[12345]: Failed password for invalid user admin from 203.0.113.50 port 54321 ssh2

# Test JSON decoder
echo '{"eventVersion":"1.08","userIdentity":{"type":"Root","arn":"arn:aws:iam::123456789012:root"}}' | /var/ossec/bin/wazuh-logtest -t

# Reload rules without restarting
/var/ossec/bin/wazuh-control reload

# Check rules are loaded
/var/ossec/bin/wazuh-rules --debug
```

## Rule File Organization

```bash
# Wazuh rule directories
/var/ossec/ruleset/rules/          # Built-in rules (read-only)
var/ossec/etc/rules/               # Custom rules (your changes)
  local_rules.xml                  # Main custom rules file

# Decoder directories
/var/ossec/decoders/               # Built-in decoders
/var/ossec/etc/decoders/           # Custom decoders

# Best practice: Don't modify built-in files
# Use local_rules.xml for custom rules
# Create new decoder files in /var/ossec/etc/decoders/
```

## Common Gotchas

- Rules use regex **not** glob patterns (use `.*` not `*`)
- `if_sid` must be decoder ID or rule ID
- `decoded_as` matches decoder by name
- `match` is case-insensitive; `regex` is case-sensitive
- `same_field` requires `time_frame`
- Levels 0-15; use `noalert` for silent rules
- JSON decoder uses field names exactly as they appear in JSON
- For nested JSON fields, use dot notation: `requestParameters.policyName`

## Related

- [[Security/siem/wazuh/deployment/README|Deployment]] — Installing Wazuh
- [[Security/siem/wazuh/integrations/README|Integrations]] — Alert automation
- [[Security/siem/wazuh/threat-hunting/README|Threat Hunting]] — Hunting queries