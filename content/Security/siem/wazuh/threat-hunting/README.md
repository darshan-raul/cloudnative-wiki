---
title: Wazuh Threat Hunting
tags: [wazuh, threat-hunting, siem, detection, mitre, ir]
date: 2025-05-24
description: Proactive threat hunting in Wazuh - queries, MITRE coverage, investigation playbooks for multi-account AWS security monitoring
---

# Wazuh Threat Hunting

Threat hunting is proactively searching through security data to find attacks that evade automated detection. Wazuh's centralized log collection and rich query capabilities make it effective for hunting across your 40+ AWS accounts.

## Hunting Methodology

### Hypothesis-Driven Hunting

```
1. Form hypothesis → "Lateral movement via SSM session manager"
2. Collect evidence → "Find aws:CreateConnection events in CloudTrail"
3. Analyze data → "Correlate with anomalous timing"
4. Investigate → "Is this user normally active at this hour?"
5. Respond → "Block, isolate, contain"
```

### MITRE ATT&CK Based Hunting

Map your hunting to MITRE ATT&CK tactics for coverage:

| Phase | MITRE Tactic | What to Hunt |
|-------|-------------|--------------|
| Reconnaissance | TA0043 | Port scans, DNS enumeration |
| Resource Development | TA0011 | New AWS users, unusual API calls |
| Initial Access | TA0001 | Phishing, valid creds, exposed credentials |
| Execution | TA0002 | Shell commands, PowerShell, malicious scripts |
| Persistence | TA0003 | New users, scheduled tasks, cron jobs |
| Privilege Escalation | TA0004 | sudo/su attempts, policy changes |
| Defense Evasion | TA0005 | Disabling logging, clearing logs |
| Lateral Movement | TA0008 | SSH, RDP, SSM, port forwarding |
| Collection | TA0009 | Data staging, large uploads to S3 |
| Exfiltration | TA0010 | Large data transfers, unusual S3 downloads |
| Impact | TA0040 | Ransomware, encryption, data destruction |

## Hunting Queries

### AWS: Credential Access — Brute Force Detection

```sql
-- Find multiple failed console logins from same IP (potential brute force)
rule_group:cloudtrail AND eventName:ConsoleLogin AND responseElements.consoleLogin:Failure

| bucket src_ip by 5m
| where failed_count > 10
| sort failed_count desc

-- Hunt: Check if IP is in your trusted ranges
-- Alert: If IP not in whitelist, threshold > 5 failures
```

### AWS: Privilege Escalation — Admin Policy Attachment

```sql
-- Find if any user gains Admin access
eventName:AttachUserPolicy OR eventName:PutUserPolicy
requestParameters.policyArn:*AdministratorAccess*

-- Hunt: Correlate with user normally not performing admin actions
-- Alert: Immediate if attached to non-admin users
```

### AWS: Persistence — New Trusted Entity

```sql
-- Find new IAM users created outside business hours (for your org)
eventName:CreateUser
userIdentity.type:IAMUser
| where timestamp.hour NOT BETWEEN 8 AND 18

-- Hunt: New users who have never logged in after 48h
-- Find: Users created but never used
```

### AWS: Lateral Movement — SSM Session Start

```sql
-- Find SSM Session Manager usage (potential lateral movement)
eventName:StartSession
requestParameters.documentName:AWS-StartPortForwardingSession

-- Hunt: Is this user known to use SSM?
-- Hunt: From which IP did they start the session?
-- Alert: If user never uses SSM, investigate
```

### AWS: Exfiltration — Large S3 Downloads

```sql
-- Find large S3 GET requests (potential data exfil)
eventName:GetObject
requestParameters.maxKeys:>1000
| where bytes_transferred > 100000000  -- > 100MB

-- Hunt: Who downloaded what, from where, when?
-- Alert: Unusual volume from a user not normally downloading bulk data
```

### Kubernetes: Anonymous API Access

```sql
-- Hunt for all anonymous access to K8s API
program_name:kubernetes-api-server
user.username:system:anonymous
user.authentication_token:anonymous

-- Alert: Any anonymous access should trigger investigation
-- Check: Is this from a known jump host?
```

### Kubernetes: Service Account Token Mount

```sql
-- Find pods mounting service account tokens (potential credential theft)
objectRef.resource:serviceaccounts
objectRef.subresource:token
verb:create

-- Hunt: Which pods requested tokens? Are those pods in namespaces that shouldn't have them?
-- MITRE: T1552.001 - Service Account Credentials
```

### Linux: Persistence — Suspicious Cron Jobs

```sql
-- Find cron jobs created or modified outside deployment windows
program_name:cron
full_log:*FROM*root*  -- Cron running as root from unusual source

-- Hunt: Is this cron in /etc/cron.d or /var/spool/cron?
-- Hunt: What command does it execute? Is it base64 encoded?
```

### Linux: Privilege Escalation — Sudo Invalid User

```sql
-- Find sudo attempts for non-existent users
program_name:sudo
full_log:user NOT in (known_users)

-- Hunt: Could indicate lateral movement attempt
-- Alert: If > 3 attempts for invalid users, likely attack
```

### Linux: Defense Evasion — Log Deletion

```sql
-- Find truncation or deletion of auth logs
program_name:kernel
full_log:*truncat* OR *delet* OR *cleared*

-- Hunt: Check which user performed the deletion
-- MITRE: T1070.002 - Clear Linux or Mac System Logs
```

### Network: Port Scan Detection (VPC Flow Logs)

```sql
-- Find single source IP hitting many ports (potential port scan)
action:REJECT
| bucket src_ip by 1m
| where distinct_ports > 20
| sort distinct_ports desc

-- Hunt: Is this IP from external range? Internal range?
-- MITRE: T1046 - Network Service Discovery
```

## MITRE ATT&CK Coverage Matrix for Wazuh

### Coverage by Tactic

| Tactic | Technique | Wazuh Rule/SID | Log Source |
|--------|-----------|----------------|------------|
| **Reconnaissance** | | | |
| Resource Development | T1586 - Compromise Accounts | 100103 | CloudTrail |
| Reconnaissance | T1595 - Active Scanning | 100105 | VPC Flow |
| **Initial Access** | | | |
| Valid Accounts | T1078.004 - Cloud Accounts | 100100 | CloudTrail |
| Phishing | T1566 - Spearphishing | - | Email gateway |
| **Execution** | | | |
| Command and Script | T1059 - Command and Script | 100300 | Linux syslog |
| PowerShell | T1059.001 - PowerShell | - | Windows |
| **Persistence** | | | |
| Account Creation | T0859 - IAM User Creation | 100500 | CloudTrail |
| Cron Job | T1053 - Scheduled Task | 100303 | Linux cron |
| **Privilege Escalation** | | | |
| Sudo/Sudoers | T1548.003 - Sudo/Sudoers | 100304 | Linux sudo |
| Policy Change | T1098 - Account Manipulation | 100501 | CloudTrail |
| **Defense Evasion** | | | |
| Log Deletion | T1070.002 - Clear Logs | 100306 | Linux |
| Disable Logging | T1070 - Indicator Removal | - | Linux auditd |
| **Lateral Movement** | | | |
| SSH | T1021.004 - Remote Services | 100001 | SSH logs |
| SSM Session | T1021.008 - Cloud Services | 100600 | CloudTrail |
| **Collection** | | | |
| S3 Collection | T1530 - Cloud Data | 100601 | CloudTrail |
| **Exfiltration** | | | |
| Large S3 GET | T1047 - Exfil | 100602 | CloudTrail |
| **Impact** | | | |
| Data Destruction | T0899 - S3 Data Destruction | 100103 | CloudTrail |

## Investigation Playbooks

### Playbook: AWS Console Login from New IP

```yaml
trigger: Alert level >= 8 for ConsoleLogin from unexpected location

steps:
  1. Identify:
     - Which account (recipient_account_id)?
     - Which user (userIdentity.arn)?
     - Which IP (sourceIPAddress)?
     - Which location (geo details)?
     - Time of login?

  2. Enrich:
     - Is this IP in our known IP list?
     - Has this user logged in from this IP before?
     - Is this geolocation unexpected for this user?
     - Is this login time normal for this user?

  3. Determine:
     - If new IP + unusual location → Potential compromised credential
     - If known IP + normal time → Likely legitimate
     - If new IP + MFA not used → Investigate MFA bypass

  4. Response:
     - If compromised: Revoke session, reset password, check CloudTrail for follow-on actions
     - If inconclusive: Create ticket for user verification
     - If legitimate: Add IP to whitelist, update rules

  5. Document:
     - Log in incident response tracker
     - Note: if false positive, update detection rules
```

### Playbook: Lateral Movement via SSM

```yaml
trigger: StartSession event in CloudTrail for unusual user

steps:
  1. Identify:
     - Who initiated the session?
     - From which IP?
     - Which target instance?
     - Which region?

  2. Check:
     - Is this user known to use SSM? (check last 30 days)
     - Is this IP their normal IP?
     - What role does the target instance have?
     - What other instances has this user accessed recently?

  3. Correlate:
     - Any privilege escalation in last 24h?
     - Any unusual API calls from that instance?
     - Any data access patterns from that instance?

  4. Response:
     - If suspicious: Terminate SSM session, isolate instance
     - If confirmed attack: Revoke IAM role, check for data exfil

  5. MITRE mapping: T1021.008 - Remote Services: Cloud Services
```

### Playbook: Kubernetes Anonymous API Access

```yaml
trigger: K8s API accessed by system:anonymous

steps:
  1. Identify:
     - Which cluster?
     - Source IP of the request?
     - What API endpoints were accessed?
     - What was the HTTP response code?

  2. Check:
     - Is this from our VPN/jump host range?
     - Is this a known K8s API call pattern?
     - Was authentication attempted?

  3. Investigate:
     - Check if this IP has accessed K8s API before legitimately
     - Look for follow-on authenticated requests from same IP
     - Check other clusters for same source

  4. Response:
     - If external IP + unauthenticated: Block at network level
     - If internal jump host: Verify with owner, check for compromise

  5. MITRE mapping: T0853 - Virtualization/Sandbox Escape
```

### Playbook: Brute Force SSH (Linux)

```yaml
trigger: >5 failed SSH attempts from same IP in 10 minutes

steps:
  1. Identify:
     - Source IP and geolocation
     - Which usernames were attempted?
     - Any successful logins?

  2. Check:
     - Is this IP in our whitelist?
     - Are these valid usernames? (check against local accounts)
     - Is this a known pattern for this IP? (historical)

  3. Correlate:
     - Did any of the attempted usernames succeed?
     - Any follow-on commands after successful login?
     - Any cron jobs or persistence mechanisms created?

  4. Response:
     - Block IP at firewall (via n8n automation)
     - If successful login: Investigate the account
     - Reset passwords for accounts that were tried

  5. MITRE mapping: T1110 - Brute Force
```

### Playbook: S3 Bucket Made Public

```yaml
trigger: S3 PutBucketAcl with ALLUSERS grant

steps:
  1. Identify:
     - Which bucket?
     - Which account?
     - Who made the change (arn)?
     - When?

  2. Assess:
     - What's in the bucket? (check contents)
     - What objects are public?
     - Any sensitive data (check with Macie or custom scanner)?

  3. Response:
     - Immediately: Revert the ACL change
     - Identify: What data was exposed, for how long?
     - Notify: Data owner, security team
     - Document: Incident report

  4. Prevention:
     - Add S3 block public access at account level
     - Enable S3 access logging for audit
     - Add SCP in AWS Org to prevent public access

  5. MITRE mapping: T0899 - Data Destruction
```

## Automation with n8n for Hunting

### Automated Threat Hunting Workflow

```javascript
// n8n workflow: Daily hunting report
// Runs daily via cron → queries Wazuh → generates report → sends to Slack

const yesterday = new Date();
yesterday.setDate(yesterday.getDate() - 1);
const dateStr = yesterday.toISOString().split('T')[0];

// Query Wazuh API for hunting results
const queries = [
  { name: 'New IAM Users', query: `rule.groups:cloudtrail AND eventName:CreateUser` },
  { name: 'Failed Logins', query: `rule.level:>5 AND action:failure` },
  { name: 'S3 Public Access', query: `eventName:PutBucketAcl AND requestParameters.accessControlList.grant:ALLUSERS` },
  { name: 'SSM Sessions', query: `eventName:StartSession` }
];

const results = [];

for (const q of queries) {
  const response = await fetch(`https://wazuh-server:55000/alerts?q=${encodeURIComponent(q.query)}&from=${dateStr}&limit=20`, {
    headers: { 'Authorization': 'Basic <base64-credentials>' }
  });
  const data = await response.json();
  results.push({ query: q.name, count: data.total, alerts: data.data });
}

// Generate report
const report = results.map(r => `*${r.query}*: ${r.count} alerts`).join('\n');

// Send to Slack
return {
  report,
  summary: `Daily Threat Hunt Report - ${dateStr}`,
  results
};
```

### Automated IOC Scanner

```javascript
// n8n: Weekly IOC scan against Wazuh logs
// Query all alerts for known IOCs (from AlienVault OTX, MISP)

const iocList = [
  '185.234.xx.xx',   // Known malicious IP from OTX
  'malware-domain.com',
  'a1b2c3d4e5f6.hash'
];

const suspiciousAlerts = [];

for (const ioc of iocList) {
  const query = `srcip:${ioc} OR dstip:${ioc} OR file_hash:${ioc}`;
  const response = await fetch(`https://wazuh-server:55000/alerts?q=${encodeURIComponent(query)}&from=now-7d`);
  const data = await response.json();
  
  if (data.total > 0) {
    suspiciousAlerts.push({ ioc, count: data.total, alerts: data.data });
  }
}

if (suspiciousAlerts.length > 0) {
  // Trigger incident response workflow
  return {
    action: 'create_incident',
    iocs: suspiciousAlerts
  };
}
```

## Wazuh API for Hunting

```bash
# Get alerts by rule level
curl -k -u admin:password https://localhost:55000/alerts?rule_level=8

# Get alerts from specific source IP
curl -k -u admin:password https://localhost:55000/alerts?q=srcip:203.0.113.50

# Get alerts by MITRE technique
curl -k -u admin:password https://localhost:55000/alerts?q=mitre.id:T1078

# Get agents and their last activity
curl -k -u admin:password https://localhost:55000/agents

# Get manager status
curl -k -u admin:password https://localhost:55000/manager/status

# Search CloudTrail alerts (with date range)
curl -k -u admin:password "https://localhost:55000/alerts?q=rule.groups:cloudtrail&from=now-24h&limit=100"

# Get statistics for dashboard
curl -k -u admin:password https://localhost:55000/overview/stats
```

## Hunting Dashboard (Kibana Saved Searches)

Save these searches in Wazuh dashboard for regular hunting:

1. **High Severity Alerts** — `rule.level:>=8`
2. **New AWS Users** — `eventName:CreateUser AND rule.groups:cloudtrail`
3. **Failed Console Logins** — `eventName:ConsoleLogin AND responseElements.consoleLogin:Failure`
4. **S3 Public Access Attempts** — `eventName:PutBucketAcl`
5. **SSM Sessions** — `eventName:StartSession`
6. **Linux Brute Force** — `program_name:sshd AND failed AND >5 in 10m`
7. **K8s Anonymous Access** — `userIdentity.userName:system:anonymous`
8. **Unusual Admin Activity** — `eventName:AttachUserPolicy AND AdministratorAccess`

## Related

- [[Security/siem/wazuh/README|Wazuh]] — Overview
- [[Security/siem/wazuh/deployment/README|Deployment]] — Installing Wazuh
- [[Security/siem/wazuh/rules-decoders/README|Rules & Decoders]] — Custom rules
- [[Security/siem/wazuh/integrations/README|Integrations]] — n8n automation