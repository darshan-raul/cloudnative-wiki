---
title: Wazuh Production Execution Plan
tags: [wazuh, siem, production, aws, multi-org, execution-plan]
date: 2025-05-24
description: Complete phased execution plan for deploying Wazuh SIEM production stack across multi-org AWS environment — 200 agents, 40+ accounts, 2GB/day CloudTrail, Keycloak SSO, n8n IR automation
---

# Wazuh Production Execution Plan

**Scope**: 200 agents (Linux + Windows), 40+ AWS accounts across multiple orgs, 2GB/day CloudTrail ingestion, Keycloak SSO, n8n → Planio incident response automation.

**Current state**: Single t3.large Wazuh manager on AWS (cloud deployment), not yet integrated with Keycloak or n8n.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    AWS Security Tooling Account                      │
│                         (Account A)                                  │
│                                                                     │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │
│  │  Manager-1  │  │  Manager-2   │  │   Indexer Cluster (3)   │  │
│  │  t3.large   │  │  t3.large    │  │   t3.xlarge each         │  │
│  │  (active)   │  │  (passive)   │  │   100GB gp3 EBS          │  │
│  └──────┬──────┘  └──────┬───────┘  └───────────┬──────────────┘  │
│         │                 │                       │                  │
│         └────────────┬────┘                       │                  │
│                      │ NLB (TCP 1514/1515)          │                  │
│                      └──────────────────────────────                  │
│                                    │                                   │
│                         ┌──────────┴──────────┐                      │
│                         │  Dashboard (t3.large) │                      │
│                         │  + nginx (TLS term)  │                      │
│                         └───────────────────────┘                      │
│                                    │                                   │
│                         Keycloak SSO (OIDC)                           │
└─────────────────────────────────────────────────────────────────────┘
                      │                    │
         ┌────────────┘                    └────────────┐
         │ Cross-account IAM STS assume                  │
         ▼                                                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│   Org-Alpha     │  │   Org-Beta      │  │   Org-Gamma     │
│   (111111111111)│  │   (222222222222)│  │   (333333333333)│
│ cloudtrail-*    │  │ cloudtrail-*    │  │ cloudtrail-*    │
└─────────────────┘  └─────────────────┘  └─────────────────┘
         ▲                    ▲                    ▲
         │                    │                    │
    40+ AWS Accounts    40+ AWS Accounts    40+ AWS Accounts
```

---

## Index Lifecycle Management (ILM)

2GB/day × 365 = ~730GB/year raw. ILM prevents index bloat:

```
Hot (7 days)  →  Warm (30 days)  →  Cold (90 days)  →  Delete
   7GB              60GB               180GB              0GB
```

Applied via Indexer ILM policy in `security-audit-logs` index template.

---

## Phases at a Glance

| Phase | Name | Duration | Owner |
|-------|------|----------|-------|
| 0 | Foundation | Week 1-2 | Security Eng |
| 1 | Existing Stack Cleanup | Week 2-3 | Security Eng |
| 2 | Distributed Deployment | Week 3-5 | Security Eng |
| 3 | Multi-Org CloudTrail | Week 4-6 | Security Eng |
| 4 | Agent Deployment | Week 5-8 | Infra Eng |
| 5 | n8n + Planio IR | Week 7-9 | Security Eng |
| 6 | Detection as Code | Week 8-12 | Security Eng |
| 7 | Production Hardening | Week 10-12 | All |

---

## Phase 0 — Foundation

**Goal**: Establish the infrastructure and access patterns before touching Wazuh.

### 0.1 — Account Mapping

Before any config, enumerate your orgs. Create a manifest:

```yaml
# wazuh-production-plan/org-manifest.yaml
orgs:
  - name: org-alpha
    id: "o-a1b2c3"
    cloudtrail_account: "111111111111"
    cloudtrail_bucket: "cloudtrail-org-alpha-logs"
    regions: ["us-east-1", "eu-west-1"]
    contact: "security-alpha@company.com"

  - name: org-beta
    id: "o-d4e5f6"
    cloudtrail_account: "222222222222"
    cloudtrail_bucket: "cloudtrail-org-beta-logs"
    regions: ["us-east-1"]
    contact: "security-beta@company.com"

  - name: org-gamma
    id: "o-g7h8i9"
    cloudtrail_account: "333333333333"
    cloudtrail_bucket: "cloudtrail-org-gamma-logs"
    regions: ["us-east-1", "ap-southeast-1"]
    contact: "security-gamma@company.com"
```

> **Fill in your actual orgs and buckets here.** This manifest drives all Terraform and CloudFormation generation.

### 0.2 — SSL/TLS Infrastructure

**Internal certs** (for agent ↔ manager, inter-node communication):
```bash
# On any Linux machine with openssl
mkdir -p /opt/wazuh/ssl/{ca,manager,agent}
cd /opt/wazuh/ssl

# 1. Create internal CA
openssl genrsa -out ca/ca.key 4096
openssl req -x509 -new -nodes -key ca/ca.key \
  -sha256 -days 3650 \
  -subj "/O=COMPANY/OU=Security/CN=Internal-CA" \
  -out ca/ca.crt

# 2. Create manager CSR (on each manager node)
openssl genrsa -out manager/manager-node1.key 2048
openssl req -new -key manager/manager-node1.key \
  -subj "/O=COMPANY/OU=Security/CN=wazuh-manager-1.internal" \
  -out manager/manager-node1.csr

# 3. Sign manager cert with internal CA
openssl x509 -req -in manager/manager-node1.csr \
  -CA ca/ca.crt -CAkey ca/ca.key \
  -CAcreateserial -days 365 -sha256 \
  -out manager/manager-node1.crt

# 4. Bundle CA + manager cert for agent trust
cat manager/manager-node1.crt ca/ca.crt > manager/manager-node1-bundle.crt
```

**External certs** (for dashboard — use Let's Encrypt):
```bash
# On dashboard node
apt install certbot nginx
certbot certonly --nginx -d wazuh.internal.yourdomain.com
# Auto-renews via /etc/cron.d/certbot
```

### 0.3 — Keycloak OIDC Setup

1. **Create Realm**: `wazuh-security`
2. **Create Client**: `wazuh-dashboard`
   - Client Protocol: `openid-connect`
   - Access Type: `confidential`
   - Valid Redirect URIs: `https://wazuh.internal.yourdomain.com/*`
   - Roles: `wazuh-admin`, `wazuh-analyst`, `wazuh-viewer`
3. **Create Role Mapper**: Map OIDC groups to Wazuh roles
4. **Note**: Client Secret → store in AWS Secrets Manager: `wazuh/keycloak-client-secret`

Wazuh dashboard will authenticate via:
```
https://wazuh.internal.yourdomain.com/_oauth?realm=wazuh-security
```

### 0.4 — Secrets in AWS Secrets Manager

```bash
# Store all secrets in Account A (Security Tooling)
aws secretsmanager create-secret \
  --name wazuh/keycloak-client-secret \
  --secret-string '{"clientId":"wazuh-dashboard","clientSecret":"<secret>"}'

aws secretsmanager create-secret \
  --name wazuh/indexer-admin \
  --secret-string '{"username":"admin","password":"<strong-password>"}'

aws secretsmanager create-secret \
  --name wazuh/n8n-webhook-key \
  --secret-string '<random-32-char-key>'
```

### 0.5 — VPC / Networking

Wazuh nodes should be in **private subnets** with outbound via NAT Gateway:

```
Public Subnet (NATGW) ← Private Subnet (Wazuh nodes)
         ↑
    Internet (for yum/apt downloads)
```

Security groups required:
- **Wazuh Manager SG**: TCP 1514/1515 (agents), TCP 55000 (API), UDP 514 (syslog) — from agent networks only
- **Wazuh Indexer SG**: TCP 9200/9300 — from manager and dashboard subnets only
- **Wazuh Dashboard SG**: TCP 443 (HTTPS) — from corporate network only

---

## Phase 1 — Existing Stack Cleanup

**Goal**: Harden the current t3.large manager before adding new components.

### 1.1 — Backup Existing Configuration

```bash
# On existing manager
sudo tar czvf /tmp/wazuh-backup-$(date +%Y%m%d).tar.gz \
  /var/ossec/etc/ossec.conf \
  /var/ossec/etc/decoders/ \
  /var/ossec/etc/rules/ \
  /var/ossec/etc/shared/ \
  /var/ossec/queue/

# Copy backup to S3
aws s3 cp /tmp/wazuh-backup-*.tar.gz s://your-backup-bucket/wazuh/
```

### 1.2 — Harden ossec.conf

```xml
<!-- /var/ossec/etc/ossec.conf — production hardened -->
<ossec_config>
  <!-- Cluster (add when second manager is ready) -->
  <cluster>
    <name>wazuh-production</name>
    <node_name>manager-1</node_name>
    <node_ip>10.0.1.20</node_ip>
    <nodes>
      <node>10.0.1.20</node>  <!-- manager-1 -->
      <node>10.0.1.21</node>  <!-- manager-2 (add in Phase 2) -->
    </nodes>
    <key>CHANGE-TO-32-CHAR-UNIQU-KEY</key>
  </cluster>

  <!-- Global settings -->
  <global>
    <jsonout_output>yes</jsonout_output>
    <email_notification>yes</email_notification>
    <email_to>security-alerts@company.com</email_to>
    <email_maxperhour>100</email_maxperhour>
    <log_level>1</log_level>
  </global>

  <!-- Alerts -->
  <alerts>
    <email_to>security-alerts@company.com</email_to>
    <rule_id>100000+</rule_id>
    <level>6</level>
  </alerts>

  <!-- Active response (disable if not tested) -->
  <active-response>yes</active-response>
  <commands>
    <command>
      <name>host-deny</name>
      <executable>host-deny.sh</executable>
      <expect>srcip</expect>
      <timeout_enabled>yes</timeout_enabled>
    </command>
  </commands>

  <!-- Syscheck (FIM) — critical paths -->
  <syscheck>
    <disabled>no</disabled>
    <frequency>300</frequency>  <!-- Scan every 5 minutes -->
    <scan_on_start>yes</scan_on_start>
    <!-- Linux critical paths -->
    <directories check_all="yes" realtime="yes">/etc,/usr/bin,/usr/sbin,/bin,/sbin</directories>
    <directories check_all="yes">/var/log</directories>
    <!-- Ignore noisy paths -->
    <ignore>/var/log/journal</ignore>
    <ignore>/var/log/sa</ignore>
    <!-- Windows critical paths -->
    <registry>HKEY_LOCAL_MACHINE\Software\Classes\*</registry>
    <registry>HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services</registry>
  </syscheck>

  <!-- Rootcheck -->
  <rootcheck>
    <disabled>no</disabled>
    <check_files>yes</check_files>
    <check_trojans>yes</check_trojans>
    <check_dev>yes</check_dev>
    <check_sys>yes</check_sys>
    <check_pids>yes</check_pids>
    <check_ports>yes</check_ports>
    <check_if>yes</check_if>
    <frequency>3600</frequency>
  </rootcheck>

  <!-- OpenSCAP (vulnerability auditing) -->
  <open-scap>
    <disabled>yes</disabled>  <!-- Enable after baseline established -->
    <interval>604800</interval>  <!-- Weekly -->
  </open-scap>

  <!-- Agentless -->
  <agentless>
    <!-- CloudTrail entries added in Phase 3 -->
  </agentless>

  <!-- Integrations -->
  <integration>
    <name>wazuh-n8n</name>
    <hook_url>https://n8n.internal/webhook/wazuh-alerts</hook_url>
    <level>6</level>
    <alert_format>json</alert_format>
  </integration>

  <!-- Remote (for agent syslog if needed) -->
  <remote>
    <connection>secure</connection>
    <port>1514</port>
    <protocol>tcp</protocol>
    <queue_size>131072</queue_size>
  </remote>

  <!-- Logging -->
  <logging>
    <log_level>1</log_level>
    <log_format>json</log_format>
  </logging>
</ossec_config>
```

### 1.3 — Enable TLS for Agent Communication

```bash
# On manager — generate cluster key
openssl rand -hex 16  # Use output as <key> in cluster block above

# On manager — enable SSL for agent connection
# Add to /var/ossec/etc/ossec.conf:
sed -i 's/<ssl_agents>no<\/ssl_agents>/<ssl_agents>yes<\/ssl_agents>/' /var/ossec/etc/ossec.conf

# Copy CA cert to manager for agent verification
cp /opt/wazuh/ssl/ca/ca.crt /var/ossec/etc/ssl/ca.crt
chown ossec:ossec /var/ossec/etc/ssl/ca.crt
chmod 640 /var/ossec/etc/ssl/ca.crt

# Restart
/var/ossec/bin/wazuh-control restart
```

### 1.4 — Verify Manager Health

```bash
# Check manager is up
/var/ossec/bin/wazuh-control info
/var/ossec/bin/wazuh-control status

# Check cluster (will show single node until Phase 2)
/var/ossec/bin/cluster_control -l

# Check API
curl -k -u admin:password https://localhost:55000/manager/status?pretty
```

---

## Phase 2 — Distributed Deployment

**Goal**: Replace single-node with a proper 3-tier distributed stack.

### 2.1 — New Node Specifications

| Component | Instance | EBS | Purpose |
|-----------|----------|-----|---------|
| Indexer-1 | t3.xlarge | 100GB gp3 (3000 IOPS) | Search + storage |
| Indexer-2 | t3.xlarge | 100GB gp3 | Search + storage |
| Indexer-3 | t3.xlarge | 100GB gp3 | Search + storage |
| Dashboard-1 | t3.large | 50GB gp3 | Visualization |
| Manager-2 | t3.large | 50GB gp3 | Failover manager |

**Why gp3 3000 IOPS**: Indexer is I/O heavy during writes and searches. t3.xlarge provides burstable 6750 IOPS — enough for 2GB/day.

### 2.2 — Network Load Balancer (TCP 1514/1515)

Agents must connect via NLB to get high availability:

```bash
# Create NLB for agent communication
aws elbv2 create-load-balancer \
  --name wazuh-agent-nlb \
  --type network \
  --scheme internal \
  --subnets subnet-abc123 subnet-def456 \
  --tags Key=Name,Value=wazuh-agent-nlb

# Create target group (port 1514)
aws elbv2 create-target-group \
  --name wazuh-agents-1514 \
  --protocol TCP \
  --port 1514 \
  --target-type instance \
  --vpc-id vpc-abc123 \
  --health-check-protocol TCP \
  --health-check-port 1514 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3

# Register managers
aws elbv2 register-targets \
  --target-group-arn arn:aws:elasticloadbalancing:... \
  --targets InstanceId=i-manager1 InstanceId=i-manager2

# Create HTTPS listener for dashboard (443 → 5601)
aws elbv2 create-listener \
  --load-balancer-arn arn:aws:elasticloadbalancing:... \
  --protocol HTTPS --port 443 \
  --certificates CertificateArn=arn:aws:acm:... \
  --default-actions Type=forward,TargetGroupArn=...
```

### 2.3 — Indexer Cluster Configuration

**On each indexer node** (`/etc/wazuh-indexer/opensearch.yml`):

```yaml
# /etc/wazuh-indexer/opensearch.yml — Indexer node config
network.host: 0.0.0.0
node.name: indexer-1           # increment for node-2, node-3
node.roles: [data, ingest]   # all nodes are data nodes
cluster.name: wazuh-cluster
cluster.initial_master_nodes:
  - indexer-1
  - indexer-2
  - indexer-3
discovery.seed_hosts:
  - 10.0.1.30   # indexer-1
  - 10.0.1.31   # indexer-2
  - 10.0.1.32   # indexer-3
plugins.security.enabled: true
plugins.security.ssl.transport.enabled: true
plugins.security.ssl.transport.pemkey_filepath: /etc/ssl/private/wazuh-indexer.key
plugins.security.ssl.transport.pemcert_filepath: /etc/ssl/certs/wazuh-indexer.crt
plugins.security.ssl.transport.pemcas_filepath: /etc/ssl/certs/root-ca.crt
plugins.security.ssl.http.enabled: true
plugins.security.ssl.http.pemkey_filepath: /etc/ssl/private/wazuh-indexer.key
plugins.security.ssl.http.pemcert_filepath: /etc/ssl/certs/wazuh-indexer.crt
plugins.security.ssl.http.pemcas_filepath: /etc/ssl/certs/root-ca.crt
plugins.security.authcz.admin_dn:
  - "CN=admin,O=COMPANY,OU=Security"
opensearch.java.opts: -Xms4g -Xmx4g   # 50% of RAM
action.auto_create_index: false
indices.fielddata.cache.size: 15%
indices.memory.index_buffer_size: 20%
```

**Start indexer**:
```bash
systemctl enable wazuh-indexer
systemctl start wazuh-indexer

# Verify cluster
curl -k -u admin:password https://localhost:9200/_cluster/health?pretty
curl -k -u admin:password https://localhost:9200/_cat/nodes?v
```

### 2.4 — Index Lifecycle Management (ILM) Policy

Apply via API after indexer cluster is up:

```bash
# Create ILM policy
curl -k -u admin:password -X PUT "https://indexer-1:9200/_ilm/policy/security-audit-logs" \
  -H 'Content-Type: application/json' \
  -d @- << 'EOF'
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_size": "5GB",
            "max_age": "7d"
          },
          "set_priority": { "priority": 100 }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "shrink": { "number_of_shards": 1 },
          "forcemerge": { "max_num_segments": 1 },
          "set_priority": { "priority": 50 }
        }
      },
      "cold": {
        "min_age": "30d",
        "actions": {
          "set_priority": { "priority": 0 },
          "freeze": {}
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
EOF

# Create index template with ILM attached
curl -k -u admin:password -X PUT "https://indexer-1:9200/_index_template/security-audit-template" \
  -H 'Content-Type: application/json' \
  -d @- << 'EOF'
{
  "index_patterns": ["wazuh-alerts-*", "wazuh-archives-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1,
      "index.lifecycle.name": "security-audit-logs",
      "index.routing.allocation.include._tier_preference": "data:hot"
    }
  }
}
EOF
```

### 2.5 — Dashboard Node

```bash
# /etc/wazuh-dashboard/opensearch_dashboards.yml
server.name: wazuh-dashboard
server.host: 0.0.0.0
server.port: 5601
opensearch.hosts:
  - https://10.0.1.30:9200
  - https://10.0.1.31:9200
  - https://10.0.1.32:9200
opensearch.ssl.no_verify: false
opensearch.username: admin
opensearch.password: <from-secrets-manager>
opensearch.requestHeadersAllowlist:
  - authorization
  - x-proxy-user
  - x-proxy-roles
  - x-forwarded-for
```

### 2.6 — nginx Reverse Proxy (TLS Termination for Dashboard)

```nginx
# /etc/nginx/sites-available/wazuh-dashboard
upstream wazuh_dashboard {
    server 127.0.0.1:5601;
}

server {
    listen 443 ssl;
    server_name wazuh.internal.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/wazuh.internal.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/wazuh.internal.yourdomain.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    access_log /var/log/nginx/wazuh-dashboard-access.log;
    error_log /var/log/nginx/wazuh-dashboard-error.log;

    location / {
        proxy_pass http://wazuh_dashboard;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header Authorization "";
    }

    location ~ ^/(_oauth|_oidc|_log) {
        proxy_pass http://wazuh_dashboard;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name wazuh.internal.yourdomain.com;
    return 301 https://$host$request_uri;
}
```

### 2.7 — Keycloak OIDC Integration with Dashboard

In Wazuh Dashboard → Settings → Security → OpenSearch Security:
1. Go to OpenSearch Dashboard security settings
2. Enable OIDC
3. Configure:
   - Relying Party (Client) ID: `wazuh-dashboard`
   - Relying Party (Client) Secret: from Secrets Manager
   - Discover URL: `https://keycloak.internal/auth/realms/wazuh-security/.well-known/openid-configuration`

Apply via securityadmin script:
```bash
cd /usr/share/wazuh-indexer/plugins/opensearch-security/tools
./securityadmin.sh \
  -icl \
  -nd \
  -hn wazuh-indexer-1.internal \
  -p 9200 \
  -cacert /etc/ssl/certs/root-ca.crt \
  -cert /etc/ssl/certs/admin.crt \
  -key /etc/ssl/private/admin.key \
  -f /path/to/config.yml
```

### 2.8 — Manager Cluster (2 Managers)

On Manager-2, join the cluster:
```bash
# /var/ossec/etc/ossec.conf on manager-2
<ossec_config>
  <cluster>
    <name>wazuh-production</name>
    <node_name>manager-2</node_name>
    <node_ip>10.0.1.21</node_ip>
    <nodes>
      <node>10.0.1.20</node>  <!-- manager-1 (existing) -->
      <node>10.0.1.21</node>  <!-- manager-2 (new) -->
    </nodes>
    <key>same-32-char-key-as-manager-1</key>
  </cluster>
</ossec_config>

systemctl restart wazuh-manager

# Verify
/var/ossec/bin/cluster_control -l
```

---

## Phase 3 — Multi-Org CloudTrail Ingestion

**Goal**: Get CloudTrail logs flowing from all orgs into Wazuh.

### 3.1 — Per-Org IAM Role Setup (CloudFormation)

> See: [[Security/siem/wazuh/production-plan/cloudformation/iam-roles.yaml]]

Each org account needs:
1. `WazuhCrossAccountRead` IAM role in the CloudTrail account
2. Trust policy allowing Wazuh Security Tooling Account to assume it

### 3.2 — wodle aws-s3 Configuration

On both managers, add to `ossec.conf`:

```xml
<!-- wodle aws-s3: Multi-org CloudTrail ingestion -->
<wodle name="aws-s3">
  <disabled>no</disabled>
  <interval>5m</interval>
  <run_on_start>yes</run_on_start>

  <!-- Org-Alpha -->
  <bucket type="cloudtrail">
    <name>cloudtrail-org-alpha-logs</name>
    <iam_role_arn>arn:aws:iam::111111111111:role/WazuhCrossAccountRead</iam_role_arn>
    <skip_on_error>yes</skip_on_error>
    <only_logs_after>2025-01-01T00:00:00Z</only_logs_after>
  </bucket>

  <!-- Org-Beta -->
  <bucket type="cloudtrail">
    <name>cloudtrail-org-beta-logs</name>
    <iam_role_arn>arn:aws:iam::222222222222:role/WazuhCrossAccountRead</iam_role_arn>
    <skip_on_error>yes</skip_on_error>
    <only_logs_after>2025-01-01T00:00:00Z</only_logs_after>
  </bucket>

  <!-- Org-Gamma -->
  <bucket type="cloudtrail">
    <name>cloudtrail-org-gamma-logs</name>
    <iam_role_arn>arn:aws:iam::333333333333:role/WazuhCrossAccountRead</iam_role_arn>
    <skip_on_error>yes</skip_on_error>
    <only_logs_after>2025-01-01T00:00:00Z</only_logs_after>
  </bucket>

  <!-- GuardDuty findings (if using GuardDuty) -->
  <service type="guardduty">
    <iam_role_arn>arn:aws:iam::111111111111:role/WazuhCrossAccountRead</iam_role_arn>
    <only_logs_after>2025-01-01T00:00:00Z</only_logs_after>
    <regions>us-east-1,eu-west-1</regions>
  </service>
</wodle>
```

### 3.3 — CloudTrail Decoders

> See: [[Security/siem/wazuh/production-plan/configs/cloudtrail-decoders.xml]]

Wazuh ships built-in CloudTrail decoders (rule ID 80000-80999). Add custom decoders for multi-org enrichment:

```xml
<!-- /var/ossec/etc/decoders/0500-aws-cloudtrail-org.xml -->
<decoder name="aws-cloudtrail-multi-org">
  <program_name>aws-cloudtrail</program_name>
  <prematch>^{\"eventVersion\"</prematch>
  <json/>
  <order>src_ip, user, action, result, aws_account_id, aws_region</order>
  <description>AWS CloudTrail Multi-Org JSON logs</description>
</decoder>

<!-- Org enrichment decoder — adds org name based on bucket name via rule -->
<decoder name="cloudtrail-org-enrich" parent="aws-cloudtrail-multi-org">
  <prematch>cloudtrail-org-alpha</prematch>
  <regex>.*</regex>
  <order>aws_org_name</order>
  <description>Org-Alpha CloudTrail</description>
</decoder>
```

### 3.4 — Phase 3 Baseline Alert Rules (High Priority Only)

```xml
<!-- /var/ossec/etc/rules/local_rules.xml — CloudTrail priority rules -->

<!-- CRITICAL: Console login failure from external IP -->
<rule id="100101" level="8">
  <if_sid>aws-cloudtrail</if_sid>
  <field name="eventName">ConsoleLogin</field>
  <field name="responseElements.consoleLogin">Failure</field>
  <description>AWS Console login failed</description>
  <group>aws,cloudtrail,authentication_failure</group>
  <mitre>
    <id>T1078.004</id>
  </mitre>
</rule>

<!-- CRITICAL: Root console login -->
<rule id="100102" level="8">
  <if_sid>aws-cloudtrail</if_sid>
  <field name="eventName">ConsoleLogin</field>
  <field name="responseElements.consoleLogin">Success</field>
  <field name="userIdentity.type">Root</field>
  <description>AWS Root account console login</description>
  <group>aws,cloudtrail,privileged_account</group>
  <mitre>
    <id>T1078.004</id>
  </mitre>
</rule>

<!-- CRITICAL: Admin policy attached -->
<rule id="100103" level="10">
  <if_sid>aws-cloudtrail</if_sid>
  <field name="eventName">AttachUserPolicy</field>
  <regex>AdministratorAccess</regex>
  <description>Administrator policy attached to user</description>
  <group>aws,cloudtrail,privilege_escalation</group>
  <mitre>
    <id>T1098</id>
  </mitre>
</rule>

<!-- HIGH: New IAM user created -->
<rule id="100104" level="6">
  <if_sid>aws-cloudtrail</if_sid>
  <field name="eventName">CreateUser</field>
  <description>New IAM user created</description>
  <group>aws,cloudtrail,persistence</group>
  <mitre>
    <id>T0859</id>
  </mitre>
</rule>

<!-- HIGH: S3 bucket made public -->
<rule id="100105" level="10">
  <if_sid>aws-cloudtrail</if_sid>
  <field name="eventName">PutBucketAcl</field>
  <regex>ALLUSERS|authenticated-read</regex>
  <description>S3 bucket ACL modified — possible public access</description>
  <group>aws,cloudtrail,s3,data_exposure</group>
  <mitre>
    <id>T0899</id>
  </mitre>
</rule>

<!-- HIGH: VPC Flow — port scan detection -->
<rule id="100106" level="7">
  <if_sid>vpc-flowlogs</if_sid>
  <field name="action">REJECT</field>
  <same_field srcip>30</same_field>
  <time_frame>5m</time_frame>
  <description>Potential port scan detected (30+ rejected connections)</description>
  <group>aws,vpc,reconnaissance</group>
  <mitre>
    <id>T1046</id>
  </mitre>
</rule>
```

### 3.5 — Verify CloudTrail Ingestion

```bash
# Check wodle is running
/var/ossec/bin/wazuh-control info | grep -i aws

# View recent CloudTrail alerts
curl -k -u admin:password "https://localhost:55000/alerts?q=rule.groups:cloudtrail&from=now-1h&limit=20"

# Check which accounts are represented
curl -k -u admin:password "https://localhost:55000/alerts?q=rule.groups:cloudtrail&from=now-1h&limit=100" | \
  jq '.data[].data.aws_account_id' | sort | uniq -c | sort -rn
```

---

## Phase 4 — Agent Deployment

**Goal**: Deploy Wazuh agents to 200 Linux and Windows endpoints.

### 4.1 — Agent Groups Strategy

Group agents by org and criticality for targeted rule application:

| Group | Purpose | Agents |
|-------|---------|--------|
| `linux-prod` | Production Linux servers | ~120 |
| `linux-dev` | Dev/test Linux | ~30 |
| `windows-prod` | Production Windows servers | ~40 |
| `windows-dev` | Dev/test Windows | ~10 |

Configure groups in ossec.conf:
```xml
<agent-config>
  <agent-group>linux-prod</agent-group>
  <crypto_method>aes</crypto_method>
  <notify_time>10</notify_time>
  <time-reconnect>60</time-reconnect>
  <auto_restart>yes</auto_restart>
</agent-config>
```

### 4.2 — Linux Agent Deployment (Ansible)

> See: [[Security/siem/wazuh/production-plan/ansible/linux-agent.yml]]

```bash
# ansible playbook for Linux agents
ansible linux_servers -m yum -a "name=wazuh-agent-4.12.0" -b
ansible linux_servers -m lineinfile \
  -a "path=/var/ossec/etc/ossec.conf line='<address>wazuh-manager-1.internal</address>'" -b
ansible linux_servers -m systemd -a "name=wazuh-agent state=restarted" -b
```

### 4.3 — Windows Agent Deployment (SSM)

> See: [[Security/siem/wazuh/production-plan/ansible/windows-agent-ssm.json]]

```bash
# Create SSM Command Document for Windows agent install
aws ssm create-document \
  --name "WazuhAgentInstall-Windows" \
  --content file://configs/windows-agent-ssm.json \
  --document-type Command \
  --document-format JSON

# Run on Windows fleet
aws ssm send-command \
  --document-name "WazuhAgentInstall-Windows" \
  --targets '[{"Key":"tag:Environment","Values":["Production"]}]' \
  --parameters '{"WAZUH_MANAGER":["10.0.1.20"],"WAZUH_AGENT_GROUP":["windows-prod"]}' \
  --timeout-seconds 600
```

### 4.4 — FIM Baseline (First 2 Weeks)

```xml
<!-- Phase 4 initial FIM — less aggressive, reduce noise -->
<syscheck>
  <!-- Start with these critical paths only -->
  <directories check_all="yes" realtime="yes" report_changes="yes">
    /etc/passwd
    /etc/shadow
    /etc/group
    /etc/gshadow
    /etc/sudoers
    /etc/sudoers.d/
    /usr/bin/sudo
    /bin/su
    /bin/bash
    /bin/sh
  </directories>

  <!-- Windows critical paths -->
  <registry>HKEY_LOCAL_MACHINE\SAM</registry>
  <registry>HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services</registry>
  <registry>HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run</registry>

  <!-- Frequency: daily during baseline, increase after -->
  <frequency>86400</frequency>
</syscheck>
```

### 4.5 — Agent Verification

```bash
# From manager — list all agents and their status
/var/ossec/bin/agent_control -l

# Check agent connectivity
/var/ossec/bin/agent_control -ls

# Force agent check-in
/var/ossec/bin/agent_control -r -u <agent_id>

# Verify FIM DB is populated
sqlite3 /var/ossec/queue/fim/db/agent*.db ".tables"
```

---

## Phase 5 — n8n + Planio IR Automation

**Goal**: Route Wazuh alerts through n8n to create Planio tickets and Slack notifications.

### 5.1 — n8n Deployment (Docker on EC2)

```bash
# /opt/n8n/docker-compose.yml
version: '3'
services:
  n8n:
    image: n8nio/n8n:latest
    restart: always
    ports:
      - "5678:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=<from-secrets-manager>
      - N8N_HOST=n8n.internal.yourdomain.com
      - N8N_PROTOCOL=https
      - N8N_PORT=5678
      - WEBHOOK_URL=https://n8n.internal.yourdomain.com/
      - EXECUTIONS_DATA_SAVE_ON_ERROR=all
      - EXECUTIONS_DATA_SAVE_ON_SUCCESS=all
      - EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=true
      - GENERIC_TIMEZONE=UTC
    volumes:
      - n8n-data:/home/node/.n8n
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 5

volumes:
  n8n-data:
```

### 5.2 — n8n Workflow: Wazuh → Enrich → Route → Planio/Slack

> See: [[Security/siem/wazuh/production-plan/n8n/wazuh-alert-workflow.json]]

Workflow logic:
```
Webhook (POST /webhook/wazuh-alerts)
  │
  ▼
Code: Normalize alert fields
  │
  ▼
Switch: alert.level
  ├── level >= 12 (critical) → Planio ticket + Slack #security-critical + PagerDuty
  ├── level >= 8  (high)    → Planio ticket + Slack #security-high
  ├── level >= 6  (medium)  → Slack #security-medium (no ticket)
  └── level < 6   (low)     → Log only
  │
  ▼
Code: Enrich with threat intel (AlienVault OTX) — critical/high only
  │
  ▼
Planio: Create ticket via REST API
  │
  ▼
Slack: Send formatted message
```

### 5.3 — Wazuh → n8n Webhook Config

```xml
<!-- /var/ossec/etc/ossec.conf — on both managers -->
<integration>
  <name>wazuh-n8n</name>
  <hook_url>https://n8n.internal.yourdomain.com/webhook/wazuh-alerts</hook_url>
  <level>6</level>
  <alert_format>json</alert_format>
  <timeout>30</timeout>
  <retry_attempts>3</retry_attempts>
</integration>
```

### 5.4 — Active Response: Block IP via AWS Security Group

```bash
# n8n Code node — AWS SG block
const srcip = $json.srcip;
const securityGroupId = 'sg-0123456789abcdef0';  // Wazuh blocked SG
const region = 'us-east-1';

return {
  action: 'block_ip',
  aws_region: region,
  security_group_id: securityGroupId,
  cidr_ip: `${srcip}/32`,
  description: `Wazuh alert: ${$json.rule.description}`,
  alert_id: $json.id,
  timestamp: new Date().toISOString()
};
```

Then use AWS CLI node in n8n to call:
```bash
aws ec2 authorize-security-group-ingress \
  --group-id sg-0123456789abcdef0 \
  --ip-permissions '[{"IpProtocol": "-1", "IpRanges": [{"CidrIp": "1.2.3.4/32"}]}]'
```

---

## Phase 6 — Detection as Code

**Goal**: Build a complete, tested rule library with MITRE ATT&CK coverage.

### 6.1 — Full CloudTrail Rule Set

> See: [[Security/siem/wazuh/production-plan/configs/cloudtrail-rules.xml]]

| Category | MITRE | Rule IDs |
|----------|-------|----------|
| Privilege Escalation | T1098, T0859 | 100103, 100104, 100500-100509 |
| Lateral Movement | T1021 | 100510-100519 |
| Credential Access | T1552 | 100520-100529 |
| Defense Evasion | T1070 | 100530-100539 |
| Persistence | T1053, T1106 | 100540-100549 |
| Exfiltration | T1047 | 100550-100559 |
| Impact | T0899 | 100560-100569 |

### 6.2 — Linux Detection Rules

> See: [[Security/siem/wazuh/production-plan/configs/linux-rules.xml]]

```
T1070.002 (Log deletion)        → rule 100306
T1548.003 (Sudoers mod)         → rule 100304
T1053 (Cron persistence)        → rule 100303
T1110 (Brute force SSH)         → rule 100400-100402
```

### 6.3 — Windows Detection Rules

```
T1059.001 (PowerShell exec)     → rule 100600
T1543.003 (New service)         → rule 100601
T1112 (Registry mod)            → rule 100602
T1055 (Process injection)       → rule 100603
```

### 6.4 — Weekly Automated Hunting (n8n Cron)

```javascript
// n8n Code: Weekly threat hunting report
const wazuhApi = 'https://wazuh.internal:55000';
const creds = Buffer.from('admin:<password>').toString('base64');

const queries = [
  { name: 'New IAM Users (7d)', q: 'eventName:CreateUser', level: 6 },
  { name: 'Failed Console Logins (24h)', q: 'eventName:ConsoleLogin AND consoleLogin:failure', level: 8 },
  { name: 'S3 Public Access', q: 'eventName:PutBucketAcl AND (ALLUSERS OR authenticated-read)', level: 10 },
  { name: 'Admin Policy Changes', q: 'eventName:AttachUserPolicy AND AdministratorAccess', level: 10 },
  { name: 'SSM Session Starts', q: 'eventName:StartSession', level: 7 },
  { name: 'Linux Failed SSH (brute force)', q: 'program_name:sshd AND action:failure', level: 6 },
];

const results = [];
for (const q of queries) {
  const res = await fetch(`${wazuhApi}/alerts?q=${encodeURIComponent(q.q)}&from=now-7d&limit=5`, {
    headers: { 'Authorization': `Basic ${creds}` }
  });
  const data = await res.json();
  results.push({ ...q, count: data.total, sample: data.data });
}

const summary = results.map(r =>
  `• *${r.name}*: ${r.count} alert${r.count !== 1 ? 's' : ''}`
).join('\n');

return {
  report: `*Weekly Threat Hunt Summary*\n\n${summary}`,
  detail: results
};
```

---

## Phase 7 — Production Hardening

### 7.1 — TLS Everywhere

- All inter-node communication (manager ↔ indexer ↔ dashboard) via TLS with internal CA
- Agent ↔ Manager: mutual TLS (agents verify manager cert against internal CA)
- Dashboard: Let's Encrypt + internal CA for API calls

### 7.2 — Backup Strategy

```bash
# Indexer snapshots to S3 (daily)
curl -k -u admin:password -X PUT "https://indexer-1:9200/_snapshot/wazuh-s3-repo" \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "s3",
    "settings": {
      "bucket": "wazuh-indexer-backups",
      "region": "us-east-1",
      "compress": true
    }
  }'

# Automated daily snapshot (retain 30 days)
curl -k -u admin:password -X PUT "https://indexer-1:9200/_slm/policy/daily-wazuh-backup" \
  -H 'Content-Type: application/json' \
  -d '{
    "schedule": "0 2 * * *",
    "name": "wazuh-daily",
    "repository": "wazuh-s3-repo",
    "retention": { "days": 30 }
  }'
```

### 7.3 — Runbook Checklist

| Check | Command |
|-------|---------|
| Manager cluster health | `/var/ossec/bin/cluster_control -l` |
| Indexer cluster health | `curl -k -u admin:password https://indexer:9200/_cluster/health?pretty` |
| Agent connectivity | `/var/ossec/bin/agent_control -ls` |
| CloudTrail ingestion | `/var/ossec/bin/wazuh-control info \| grep aws` |
| n8n workflow errors | Check n8n workflow error history |
| Index disk usage | `curl -k -u admin:password https://indexer:9200/_cat/allocation?v` |
| Alert backlog | `curl -k -u admin:password https://indexer:9200/_tasks?actions=wazuh-indexer` |

---

## Immediate Next Step

Before any of the above: **fill in your org manifest** (Phase 0.1).

The org manifest determines everything:
- How many `<bucket>` blocks go into ossec.conf
- How many CloudFormation IAM role templates to generate
- Which accounts need the cross-account role

```yaml
# Fill this in — I'll generate all per-org IAM CloudFormation from it
orgs:
  - name: "YOUR-ORG-1"
    cloudtrail_account: "ACCOUNT-ID-HERE"
    cloudtrail_bucket: "BUCKET-NAME-HERE"
    regions: ["us-east-1"]
  - name: "YOUR-ORG-2"
    cloudtrail_account: "ACCOUNT-ID-HERE"
    cloudtrail_bucket: "BUCKET-NAME-HERE"
    regions: ["us-east-1"]
  # ... add all your orgs
```

---

## Related Artifacts

| Artifact | Path |
|----------|------|
| CloudFormation IAM roles | [[Security/siem/wazuh/production-plan/cloudformation/iam-roles.yaml]] |
| Terraform infra (NLB, EC2s) | [[Security/siem/wazuh/production-plan/terraform/main.tf]] |
| ossec.conf (full config) | [[Security/siem/wazuh/production-plan/configs/ossec.conf]] |
| CloudTrail rules | [[Security/siem/wazuh/production-plan/configs/cloudtrail-rules.xml]] |
| Linux detection rules | [[Security/siem/wazuh/production-plan/configs/linux-rules.xml]] |
| Ansible Linux agent | [[Security/siem/wazuh/production-plan/ansible/linux-agent.yml]] |
| SSM Windows agent doc | [[Security/siem/wazuh/production-plan/ansible/windows-agent-ssm.json]] |
| n8n workflow JSON | [[Security/siem/wazuh/production-plan/n8n/wazuh-alert-workflow.json]] |
| Indexer ILM policy | [[Security/siem/wazuh/production-plan/configs/ilm-policy.json]] |
