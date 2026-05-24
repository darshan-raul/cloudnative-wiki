---
title: Wazuh
tags: [siem, wazuh, security, xdr, open-source]
date: 2025-05-24
description: Wazuh open-source SIEM and XDR platform - architecture, deployment, rules, integrations, and threat hunting for multi-account AWS and Kubernetes environments
---

# Wazuh

[Wazuh](https://wazuh.com/) is an open-source security platform providing SIEM (Security Information and Event Management) and XDR (Extended Detection and Response) capabilities. It provides log analysis, threat detection, incident response, and compliance monitoring.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        WAZUH CLUSTER                             │
│                                                                  │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │  Indexer    │    │  Indexer    │    │  Indexer    │         │
│  │  (Node 1)   │◄──►│  (Node 2)   │◄──►│  (Node 3)   │         │
│  │  Elasticsearch│   │              │    │              │         │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘         │
│         │                  │                  │                 │
│         └──────────────────┼──────────────────┘                 │
│                            │                                    │
│                     ┌──────┴──────┐                            │
│                     │  Dashboard  │                            │
│                     │  (Kibana)   │                            │
│                     └─────────────┘                            │
│                                                                  │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │  Manager    │    │  Manager    │    │  Manager    │         │
│  │  (Wazuh)    │◄──►│  (Wazuh)    │◄──►│  (Wazuh)    │         │
│  │             │    │             │    │             │         │
│  │ - Rules     │    │ - Rules     │    │ - Rules     │         │
│  │ - Decoders  │    │ - Decoders  │    │ - Decoders  │         │
│  │ - Agents    │    │ - Agents    │    │ - Agents    │         │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘         │
│         │                  │                  │                 │
└─────────┼──────────────────┼──────────────────┼─────────────────┘
          │                  │                  │
    ┌─────┴─────┐      ┌─────┴─────┐      ┌─────┴─────┐
    │  Agents   │      │  Agents   │      │ Agentless │
    │ (Linux)   │      │ (Windows) │      │ (AWS)    │
    └───────────┘      └───────────┘      └───────────┘
```

## Core Components

### Indexer
Search and analytics engine storing all security events. Single-node or cluster (3 nodes recommended for production). Supports index lifecycle management (ILM) for data retention.

### Dashboard
Kibana-based UI for security dashboards, alerts visualization, and configuration. Connect via reverse proxy (nginx/apache) with SSL termination.

### Manager
Central log analysis engine. Collects, parses, and analyzes logs from agents and agentless sources. Applies rules and generates alerts.

### Agents
Lightweight endpoint software for Linux, Windows, macOS, and Solaris. Provides file integrity monitoring (FIM), rootkit detection, registry monitoring (Windows), and log collection.

### Agentless
Direct log collection from systems without installing an agent — via SSH, syslog, or API integrations. Used for network devices, cloud services (AWS CloudTrail, GuardDuty), and legacy systems.

## Deployment Modes

### Single-Node (Homelab)
All-in-one deployment for testing and small environments.

```bash
# Docker Compose - single node
# /opt/wazuh/docker-compose.yml

version: '3'
services:
  wazuh.indexer:
    image: wazuh/wazuh-indexer:4.12.0
    environment:
      - INDEXER_NAME=wazuh-indexer
      - NODE_NAME=node-1
      - BOOTSTRAP=true
    volumes:
      - indexer-data:/var/lib/wazuh-indexer
      - ./certs.yml:/usr/share/wazuh-indexer/config.yml
    ports:
      - "9200:9200"

  wazuh.manager:
    image: wazuh/wazuh-manager:4.12.0
    environment:
      - INDEXER_USERNAME=admin
      - INDEXER_PASSWORD=password
    volumes:
      - manager-data:/var/ossec/data
      - ./rules:/var/ossec/etc/rules
      - ./decoders:/var/ossec/etc/decoders

  wazuh.dashboard:
    image: wazuh/wazuh-dashboard:4.12.0
    environment:
      - OPENSEARCH_HOSTS=https://wazuh.indexer:9200
    depends_on:
      - wazuh.indexer
    ports:
      - "443:5601"
```

### Distributed (Production)
Separate nodes for indexer, manager, and dashboard. Scale horizontally for multi-account AWS orgs.

**Recommended minimum:**
- 3x Indexer nodes (cluster)
- 2x Manager nodes (active-passive)
- 1x Dashboard node (or 2x for HA)

### Cloud (Wazuh Cloud)
Managed SaaS option — no infrastructure management. Good for teams wanting managed SIEM without self-hosting.

### Kubernetes
Helm chart available for cloud-native deployments. Use persistent volumes for indexer data.

```bash
helm repo add wazuh https://wazuh.github.io/wazuh-helm-chart
helm install wazuh wazuh/wazuh -n wazuh --create-namespace
```

## AWS Multi-Account Monitoring

For your 40+ AWS accounts org, Wazuh can centralize security monitoring:

### Agentless (CloudTrail, GuardDuty)

```bash
# Wazuh manager - configure agentless collection
# /var/ossec/etc/ossec.conf

<ossec_config>
  <agentless>
    <entry name="aws-master-account">
      <type>aws</type>
      <aws_region>us-east-1</aws_region>
      <iam_role_arn>arn:aws:iam::123456789012:role/WazuhCloudTrailReader</iam_role_arn>
      <s3_bucket_name>my-org-cloudtrail-logs</s3_bucket_name>
      <s3_prefix>AWSLogs/</s3_prefix>
      <only_logs_after>2025-01-01T00:00:00Z</only_logs_after>
    </entry>
  </agentless>
</ossec_config>
```

### Architecture for Multi-Account

```
AWS Org
  ├── Master Account (CloudTrail aggregated to S3)
  │       └── S3 bucket → Wazuh (agentless)
  ├── Security Tooling Account
  │       └── GuardDuty findings → S3 → Wazuh
  └── 40+ Member Accounts
          └── CloudTrail → Master account S3 bucket
```

### Required IAM Role for CloudTrail

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "s3:GetObject",
      "s3:ListBucket"
    ],
    "Resource": [
      "arn:aws:s3:::my-org-cloudtrail-logs/*",
      "arn:aws:s3:::my-org-cloudtrail-logs"
    ]
  }]
}
```

### GuardDuty Integration

```bash
# Enable GuardDuty findings export to S3
aws guardduty update-organization-configuration \
  --detector-id <detector-id> \
  --auto-enable
```

## Kubernetes (EKS) Integration

### Wazuh Agent on EKS Nodes

```yaml
# DaemonSet for Wazuh agent on EKS
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: wazuh-agent
  namespace: wazuh
spec:
  selector:
    matchLabels:
      app: wazuh-agent
  template:
    metadata:
      labels:
        app: wazuh-agent
    spec:
      nodeSelector:
        eks.amazonaws.com/compute-type: standard
      initContainers:
        - name: init
          image: busybox
          command: ['sh', '-c', 'wget https://packages.wazuh.com/4.x/yum5/wazuh-agent-4.12.0-1.x86_64.rpm -O /tmp/wazuh-agent.rpm']
      containers:
        - name: wazuh
          image: amazonlinux:2
          command: ['sh', '-c', 'yum install -y /tmp/wazuh-agent.rpm && /var/ossec/bin/wazuh-control start']
          securityContext:
            privileged: true  # Required for syscalls
          env:
            - name: WAZUH_MANAGER
              value: "10.0.1.100"  # Wazuh manager IP
```

### IRSA for Wazuh Agent (EKS)

```yaml
# IRSA for Wazuh agent (if running on EKS with IRSA)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: wazuh-agent
  namespace: wazuh
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/WazuhAgentRole
```

## Custom Rules for AWS

```xml
<!-- AWS CloudTrail: Console login from unexpected location -->
<rule id="100101" level="8">
  <if_sid>aws-cloudtrail</if_sid>
  <field name="eventName">ConsoleLogin</field>
  <field name="responseElements.consoleLogin">Failure</field>
  <description>AWS Console login failed</description>
  <group>aws,cloudtrail,authentication_failure</group>
</rule>

<!-- AWS: New IAM user created -->
<rule id="100102" level="6">
  <if_sid>aws-cloudtrail</if_sid>
  <field name="eventName">CreateUser</field>
  <description>New IAM user created</description>
  <group>aws,cloudtrail,persistence</group>
</rule>
```

## Wazuh → n8n → Planio Integration

Your n8n + Planio incident response setup maps well to Wazuh:

```
Wazuh Alert (level >= 8)
    │
    ▼ HTTP POST webhook
n8n Workflow
    │
    ├── Slack notification
    ├── PagerDuty incident (critical only)
    │
    ▼
Planio Ticket (created automatically)
    │
    ▼
IR team investigates
```

## Agents vs Agentless

| Feature | Agent | Agentless |
|---------|-------|-----------|
| Platform | Linux, Windows, macOS | Any (SSH/syslog/API) |
| Data collected | Logs, FIM, registry, syscalls | Log files, JSON, API |
| Deployment complexity | Medium | Low |
| CloudTrail | No (needs agent on EC2) | Yes (S3 polling) |
| Real-time | Yes (syscall) | No (polling) |
| Resource usage | ~1-2% CPU | Minimal |

## Why Wazuh (vs Elastic Security, Splunk)

**Advantages:**
- Open source, no licensing cost
- Native AWS CloudTrail, GuardDuty support (agentless)
- Built-in active response (block IP)
- Single pane for agents + cloud logs
- Your existing n8n + Planio workflow integration

**Considerations:**
- Elastic has better performance at scale (10B+ events/day)
- Splunk has better enterprise features (SPL, ES)
- Wazuh is best for 1000-5000 agents, moderate log volume

## Performance Sizing

| Agents | Daily Log Volume | Indexer Nodes | Manager Nodes |
|--------|-----------------|---------------|---------------|
| < 100 | < 1GB/day | 1 (4CPU, 8GB RAM) | 1 |
| 100-500 | 1-10GB/day | 3 (4CPU, 16GB RAM) | 2 |
| 500-2000 | 10-50GB/day | 3 (8CPU, 32GB RAM) | 2 |
| 2000+ | 50GB+/day | 5+ (custom) | 3+ |

## Data Retention

| Tier | Duration | Use Case |
|------|----------|----------|
| Hot | 7 days | Real-time alerts, dashboards |
| Warm | 30 days | Investigation, medium-term alerts |
| Cold | 90 days | Compliance, forensics |
| Frozen | 1 year+ | Long-term audit (custom) |

Configure in indexer ILM policies.

## Related

- [[Security/siem/README|SIEM Overview]]
- [[Security/siem/wazuh/deployment/README|Deployment]] — Installation guides
- [[Security/siem/wazuh/rules-decoders/README|Rules & Decoders]] — Custom detection rules
- [[Security/siem/wazuh/integrations/README|Integrations]] — n8n, PagerDuty, Slack
- [[Security/siem/wazuh/threat-hunting/README|Threat Hunting]] — Hunting queries