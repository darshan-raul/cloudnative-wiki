---
title: Wazuh Integrations
tags: [wazuh, integration, automation, n8n, webhook, siem]
date: 2025-05-24
description: Integrating Wazuh with n8n, PagerDuty, Slack, webhooks, and threat intelligence feeds for automated incident response
---

# Wazuh Integrations

Wazuh alerts can be routed to external systems for automated incident response. The most powerful integration for your setup is **n8n** — which you already use for incident response automation with Planio.

## Architecture Overview

```
Wazuh Alert
    │
    ▼
┌──────────────┐     Webhook (POST JSON)      ┌─────────────┐
│ Internal    │ ───────────────────────────►│   n8n       │
│ Integrations│                              │  Workflow   │
└──────────────┘                              └──────┬──────┘
                                                      │
                              ┌────────────────────────┼────────────────────────┐
                              │                        │                        │
                              ▼                        ▼                        ▼
                        ┌──────────┐            ┌──────────┐           ┌──────────┐
                        │  Slack  │            │ PagerDuty│           │  Planio   │
                        │ Notif   │            │ Incident │           │  Tickets  │
                        └──────────┘            └──────────┘           └──────────┘
```

## Wazuh → n8n (Primary Automation)

### How It Works

1. Wazuh generates an alert (rule matches)
2. Wazuh sends HTTP POST webhook to n8n with JSON payload
3. n8n workflow receives payload, processes alert
4. n8n routes to Slack, PagerDuty, Planio, or executes automations

### Webhook Integration Setup

#### Step 1: Create n8n Webhook Trigger

In n8n:

1. Create new workflow
2. Add **Webhook** node
3. Set path: `wazuh-alerts` (or any unique path)
4. Set method: `POST`
5. Set authentication (optional): API key or basic auth
6. Copy the webhook URL: `https://<n8n-host>/webhook/wazuh-alerts`

#### Step 2: Configure Wazuh Internal Integration

```bash
# Edit /var/ossec/etc/ossec.conf
# Add webhook integration under <integration> section

<integration>
  <name>wazuh-n8n</name>
  <hook_url>https://<n8n-host>/webhook/wazuh-alerts</hook_url>
  <level>6</level>  <!-- Only send alerts level 6+ -->
  <rule_id>100100,100101,100102</rule_id>  <!-- Optional: specific rules -->
  <alert_format>json</alert_format>
</integration>
```

Or configure via dashboard: **Settings → Integrations → Custom → Webhook**

#### Step 3: Advanced Integration with API Key

```bash
<integration>
  <name>wazuh-n8n-auth</name>
  <hook_url>https://<n8n-host>/webhook/wazuh-alerts?key=<your-api-key></hook_url>
  <level>5</level>
  <alert_format>json</alert_format>
  <timeout>30</timeout>  <!-- seconds to wait for response -->
</integration>
```

### n8n Workflow for Wazuh Alerts

```
┌─────────────────────────────────────────────────────────────────┐
│                        n8n Workflow                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  [Webhook] ← Wazuh POST                                          │
│       │                                                          │
│       ▼                                                          │
│  [Switch] ──── alert.level >= 8 (critical) ─────► [PagerDuty]     │
│       │                                                          │
│       ├─── alert.level >= 6 (medium/high) ──────► [Slack]         │
│       │                                                          │
│       └─── alert.level < 6 (low) ─────────────► [Log Only]        │
│                                                                  │
│  [Code Node] ← Normalize alert fields                            │
│       │                                                          │
│       ▼                                                          │
│  [Planio] ← Create ticket via REST API                           │
│       │                                                          │
│       ▼                                                          │
│  [HTTP Request] ← Enrich with threat intel (optional)            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### n8n Workflow JSON Example (Importable)

```json
{
  "name": "Wazuh Alert Workflow",
  "nodes": [
    {
      "parameters": {
        "path": "wazuh-alerts",
        "method": "POST"
      },
      "name": "Webhook",
      "type": "n8n-nodes-base.webhook",
      "typeVersion": 1
    },
    {
      "parameters": {
        "jsCode": "// Normalize Wazuh alert\nconst alert = $json;\nconst normalized = {\n  alert_id: alert.id,\n  timestamp: alert.timestamp,\n  rule_id: alert.rule.id,\n  rule_description: alert.rule.description,\n  level: alert.rule.level,\n  srcip: alert.data_srcip || alert.src_ip,\n  user: alert.data_user || alert.user,\n  full_log: alert.full_log,\n  location: alert.location,\n  mitre_ids: alert.rule.mitre?.map(m => m.id) || [],\n  groups: alert.rule.groups || []\n};\nreturn normalized;"
      },
      "name": "Normalize Alert",
      "type": "n8n-nodes-base.code",
      "typeVersion": 1
    },
    {
      "parameters": {
        "conditions": {
          "options": {
            "caseSensitive": true
          },
          "conditions": [
            {
              "id": "level",
              "leftValue": "{{ $json.level }}",
              "rightValue": 8,
              "operator": {
                "type": "numeric",
                "operation": ">="
              }
            }
          ]
        }
      },
      "name": "Critical Alert?",
      "type": "n8n-nodes-base.switch",
      "typeVersion": 1
    },
    {
      "parameters": {
        "channel": "#security-alerts",
        "text": "=Wazuh Critical Alert: {{ $json.rule_description }}\nIP: {{ $json.srcip }}\nUser: {{ $json.user }}\nTime: {{ $json.timestamp }}\nMITRE: {{ $json.mitre_ids.join(', ') }}",
        "username": "Wazuh Bot"
      },
      "name": "Slack Critical",
      "type": "n8n-nodes-base.slack",
      "typeVersion": 1
    },
    {
      "parameters": {
        "summary": "=Wazuh: {{ $json.rule_description }}",
        "severity": "critical",
        "source": "wazuh"
      },
      "name": "PagerDuty Incident",
      "type": "n8n-nodes-base.pagerDuty",
      "typeVersion": 1
    },
    {
      "parameters": {
        "url": "https://<planio-host>/api/issues.json",
        "method": "POST",
        "authentication": "genericCredentialType",
        "sendHeaders": true,
        "headerParameters": {
          "parameters": [
            {
              "name": "Content-Type",
              "value": "application/json"
            },
            {
              "name": "X-Planio-API-Key",
              "value": "<your-planio-api-key>"
            }
          ]
        },
        "sendBody": true,
        "bodyParameters": {
          "parameters": [
            {
              "name": "issue",
              "value": "{\n  \"project_id\": 1,\n  \"tracker_id\": 1,\n  \"subject\": \"Wazuh Alert: {{ $json.rule_description }}\",\n  \"description\": \"Alert ID: {{ $json.alert_id }}\\nIP: {{ $json.srcip }}\\nUser: {{ $json.user }}\\nTime: {{ $json.timestamp }}\\nFull Log: {{ $json.full_log }}\",\n  \"priority_id\": 4\n}"
            }
          ]
        }
      },
      "name": "Planio Ticket",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 1
    }
  ],
  "connections": {
    "Webhook": {
      "main": [["Normalize Alert"]]
    },
    "Normalize Alert": {
      "main": [["Critical Alert?"]]
    },
    "Critical Alert?": {
      "main": [
        [["PagerDuty Incident"]],
        [["Slack Critical"]],
        [["Planio Ticket"]]
      ]
    }
  }
}
```

### n8n: Enrichment Node (Threat Intelligence)

```javascript
// n8n Code node: Enrich IP with threat intel (AlienVault OTX example)
const alert = $nodeData;
const srcip = alert.srcip;

// Check AlienVault OTX for IP reputation
const otxApiKey = '<your-otx-api-key>';
const response = await fetch(`https://otx.alienvault.com/api/v1/indicators/IPv4/${srcip}/general`, {
  headers: { 'X-OTX-API-KEY': otxApiKey }
});
const data = await response.json();

return {
  ip: srcip,
  reputation_score: data.reputation || 0,
  pulse_count: data.pulse_count || 0,
  is_malicious: data.pulse_count > 0,
  tags: data.tags || [],
  geo: data.geo || null
};
```

### n8n: Auto-Block IP Workflow

```javascript
// Firewall block workflow trigger from Wazuh
const srcip = $json.srcip;

// AWS: Block via Security Group (for Wazuh running on AWS)
const awsRegion = 'us-east-1';
const securityGroupId = 'sg-xxxxxxxx';

const params = {
  GroupId: securityGroupId,
  IpPermissions: [{
    IpProtocol: '-1',
    IpRanges: [{ CidrIp: `${srcip}/32` }]
  }]
};

// Note: In production, use IAM role with describe/authorize-sg permissions
return {
  action: 'block_ip',
  ip: srcip,
  reason: 'Wazuh brute force alert',
  timestamp: new Date().toISOString()
};
```

## PagerDuty Integration

### Native Integration

```bash
# /var/ossec/etc/ossec.conf
<integration>
  <name>pagerduty</name>
  <api_key><your-pagerduty-integration-key></api_key>
  <level>8</level>
</integration>
```

### n8n → PagerDuty (Recommended for your setup)

Since you're using n8n:

```
Wazuh → n8n webhook → n8n PagerDuty node (with incident routing based on severity)
```

Benefits:
- One webhook from Wazuh
- n8n handles routing logic (severity → different PD services/teams)
- Enrich alert data before creating PD incident
- Custom escalation logic

## Slack Integration

### Native Integration

```bash
<integration>
  <name>slack</name>
  <hook_url>https://hooks.slack.com/services/XXX/YYY/ZZZ</hook_url>
  <level>5</level>
</integration>
```

### n8n → Slack (Recommended for you)

Benefits over native:
- Rich formatting with blocks
- Thread management (group related alerts)
- Channel routing based on alert type
- Add threat intel context before sending

## Custom Webhook for Generic Systems

```bash
<integration>
  <name>generic-webhook</name>
  <hook_url>https://your-system.com/webhook</hook_url>
  <level>6</level>
  <alert_format>json</alert_format>
  <timeout>60</timeout>
  <retry_attempts>3</retry_attempts>
</integration>
```

### Wazuh Alert JSON Payload

```json
{
  "id": "1234567890",
  "timestamp": "2025-05-24T10:30:45Z",
  "rule": {
    "id": "100101",
    "level": 8,
    "description": "AWS Console login from external IP",
    "groups": ["aws", "cloudtrail", "authentication"],
    "mitre": [
      { "id": "T1078.004", "tactic": "Defense Evasion" }
    ]
  },
  "agent": {
    "id": "002",
    "name": "aws-cloudtrail-collector",
    "ip": "10.0.1.50"
  },
  "manager": {
    "name": "wazuh-server",
    "ip": "10.0.1.10"
  },
  "src_ip": "203.0.113.50",
  "dst_ip": null,
  "user": "admin@example.com",
  "full_log": "{\"eventVersion\":\"1.08\",\"userIdentity\":{\"type\":\"Root\"}}...",
  "location": "aws-cloudtrail",
  "data": {
    "aws_region": "us-east-1",
    "recipient_account_id": "123456789012"
  }
}
```

## Threat Intelligence: AlienVault OTX

```bash
# Configure Wazuh to use AlienVault OTX
# Edit ossec.conf

<integration>
  <name>alienvault</name>
  <api_key><your-otx-api-key></api_key>
  <level>6</level>
  <alert_format>json</alert_format>
</integration>
```

Or use n8n enrichment node to:
1. Query OTX for indicator (IP, domain, hash)
2. Add pulse/reputation data to alert
3. Route accordingly

## Threat Intelligence: MISP

```javascript
// n8n MISP enrichment node
const indicator = $json.srcip || $json.file_hash;

const mispUrl = 'https://misp.example.com';
const mispKey = '<your-misp-api-key>';

const response = await fetch(`${mispUrl}/events/restSearch`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': mispKey
  },
  body: JSON.stringify({
    "returnFormat": "json",
    "value": indicator,
    "typeAttribute": ["ip-src", "md5", "domain"]
  })
});

const data = await response.json();
const events = data.response || [];

return {
  indicator,
  misp_events: events.length,
  threat_level: events[0]?.threat_level_id || 0,
  tags: events[0]?.Event?.Tag || []
};
```

## Multi-Account AWS Monitoring via n8n

For your 40+ AWS accounts, the Wazuh agentless CloudTrail integration should route to n8n for cross-account correlation:

```javascript
// n8n: Cross-account alert correlation
const alert = $json;

// Extract AWS account ID from Wazuh alert
const alertAccountId = alert.data?.aws_account_id;
const srcip = alert.src_ip;

// Get all alerts from same IP in last 24h (Wazuh query via API)
const wazuhApiUrl = 'https://wazuh-server:55000';
const credentials = { username: 'wazuh-api-user', password: 'xxx' };

// Query Wazuh for same source IP across all accounts
const queryResponse = await fetch(`${wazuhApiUrl}/alerts?q=srcip:${srcip}&from=now-24h`, {
  headers: { 'Authorization': `Basic ${Buffer.from(credentials).toString('base64')}` }
});
const crossAccountAlerts = await queryResponse.json();

// If IP seen across 3+ accounts, it's likely a compromised credential
if (crossAccountAlerts.total > 3) {
  return {
    severity: 'critical',
    cross_account: true,
    account_count: crossAccountAlerts.total,
    action: 'block_ip_create_ticket'
  };
}
```

## Integration Troubleshooting

```bash
# Test webhook delivery manually
curl -X POST https://<n8n-host>/webhook/wazuh-alerts \
  -H "Content-Type: application/json" \
  -d '{"test": "alert", "level": 8, "description": "test alert"}'

# View integration logs
tail -f /var/ossec/logs/ossec.log | grep integration

# Test alert generation manually
/var/ossec/bin/wazuh-logtest -t

# Check if integration is loaded
/var/ossec/bin/wazuh-control info | grep -i integration

# Verify API connectivity
curl -k https://<n8n-host>/webhook/wazuh-alerts -X GET
```

## Related

- [[Security/siem/wazuh/README|Wazuh]] — Overview
- [[Security/siem/wazuh/deployment/README|Deployment]] — Installing Wazuh
- [[Security/siem/wazuh/rules-decoders/README|Rules & Decoders]] — Custom rules
- [[Security/siem/wazuh/threat-hunting/README|Threat Hunting]] — Hunting queries