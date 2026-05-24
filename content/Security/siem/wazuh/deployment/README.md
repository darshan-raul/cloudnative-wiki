---
title: Wazuh Deployment
tags: [wazuh, siem, deployment, installation, agents]
date: 2025-05-24
description: Wazuh deployment modes - single-node for homelab, distributed for production, agents and agentless collection, and post-install hardening
---

# Wazuh Deployment

## Deployment Modes

### 1. Single-Node (Homelab/Development)

All components on one server. Good for < 50 agents.

**Hardware minimum:**
- 4 CPU cores
- 8 GB RAM
- 50 GB SSD

**Installation (Docker Compose):**

```bash
# Create deployment directory
sudo mkdir -p /opt/wazuh
cd /opt/wazuh

# Generate certificates
docker run --rm -ti \
  -v $(pwd)/certs:/certs \
  wazuh/wazuh-indexer:4.12.0 \
  /usr/share/wazuh-indexer/plugins/install_demo/configuration.sh

# docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3'
services:
  wazuh.indexer:
    image: wazuh/wazuh-indexer:4.12.0
    hostname: wazuh.indexer
    environment:
      - INDEXER_NAME=wazuh-indexer
      - NODE_NAME=node-1
      - BOOTSTRAP=true
      - DISABLE_INSTALL_DEMO_CONFIG=true
    volumes:
      - indexer-data:/var/lib/wazuh-indexer
      - ./certs:/certs
    ports:
      - "9200:9200"
    mem_limit: 4g

  wazuh.manager:
    image: wazuh/wazuh-manager:4.12.0
    hostname: wazuh.manager
    environment:
      - INDEXER_USERNAME=admin
      - INDEXER_PASSWORD=password
      - INDEXER_HOSTS=https://wazuh.indexer:9200
    volumes:
      - manager-data:/var/ossec/data
      - ./rules:/var/ossec/etc/rules
      - ./decoders:/var/ossec/etc/decoders
    ports:
      - "1514:1514"  # Agent communication
      - "1515:1515"  # Agent enrollment
      - "514:514/udp"  # Syslog
    mem_limit: 2g

  wazuh.dashboard:
    image: wazuh/wazuh-dashboard:4.12.0
    hostname: wazuh.dashboard
    environment:
      - OPENSEARCH_HOSTS=https://wazuh.indexer:9200
      - OPENSEARCH_USERNAME=admin
      - OPENSEARCH_PASSWORD=password
      - SERVER_NAME=wazuh
      - WAZUH_API_URL=https://wazuh.manager
    depends_on:
      - wazuh.indexer
      - wazuh.manager
    ports:
      - "443:5601"
    mem_limit: 2g

volumes:
  indexer-data:
  manager-data:

network:
  name: wazuh-net
  driver: bridge
EOF

docker-compose up -d

# Access dashboard at https://localhost
# Default creds: admin / password
```

**Installation (Packages - Ubuntu/Debian):**

```bash
# Add Wazuh repository
wget https://packages.wazuh.com/4.x/apt/wazuh-release.gpg -O /etc/apt/trusted.gpg.d/wazuh.gpg
echo "deb https://packages.wazuh.com/4.x/apt stable main" > /etc/apt/sources.list.d/wazuh.list
apt update

# Install all-in-one
apt install wazuh-indexer wazuh-manager wazuh-dashboard

# Start services
systemctl enable wazuh-indexer wazuh-manager wazuh-dashboard
systemctl start wazuh-indexer wazuh-manager wazuh-dashboard
```

---

### 2. Distributed (Production)

Separate nodes for scalability and resilience.

**Recommended architecture:**
- 3x Indexer nodes (cluster)
- 2x Manager nodes (active-active load balanced)
- 1-2x Dashboard nodes
- Load balancer (nginx) in front of managers

**Indexers (3-node cluster):**

```bash
# /etc/wazuh-indexer/opensearch.yml (on each node)
network.host: 0.0.0.0
node.name: node-1
cluster.name: wazuh-cluster
cluster.initial_master_nodes: ["node-1", "node-2", "node-3"]
discovery.seed_hosts: ["10.0.1.10", "10.0.1.11", "10.0.1.12"]
plugins.security.enabled: true
plugins.security.ssl.transport.enabled: true
plugins.security.ssl.transport.pemkey_filepath: /certs/node-1-key.pem
plugins.security.ssl.transport.pemcert_filepath: /certs/node-1.pem
plugins.security.ssl.transport.pemcas_filepath: /certs/root-ca.pem
plugins.security.ssl.http.enabled: true
plugins.security.ssl.http.pemkey_filepath: /certs/node-1-key.pem
plugins.security.ssl.http.pemcert_filepath: /certs/node-1.pem
plugins.security.ssl.http.pemcas_filepath: /certs/root-ca.pem
plugins.security.authcz.admin_dn: ["CN=admin,O=Wazuh,OU=Wazuh"]
opensearch.java.opts: -Xms8g -Xmx8g
```

**Manager (active-active):**

```bash
# /var/ossec/etc/ossec.conf
<ossec_config>
  <cluster>
    <name>wazuh-cluster</name>
    <node_name>manager-1</node_name>
    <node_ip>10.0.1.20</node_ip>
    <nodes>
      <node>10.0.1.20</node>  <!-- manager-1 -->
      <node>10.0.1.21</node>  <!-- manager-2 -->
    </nodes>
    <key>your-32-char-cluster-key-here</key>
  </cluster>
</ossec_config>

# Register with cluster
/var/ossec/bin/cluster_control -r
```

**Dashboard:**

```bash
# /etc/wazuh-dashboard/opensearch_dashboards.yml
server.name: wazuh-dashboard
server.host: 0.0.0.0
opensearch.hosts: ["https://10.0.1.10:9200", "https://10.0.1.11:9200", "https://10.0.1.12:9200"]
opensearch.ssl.no_verify: false
opensearch.username: admin
opensearch.password: password
```

---

### 3. Agent Installation

#### Linux (rpm/deb)

```bash
# RHEL/CentOS
curl -o wazuh-agent.rpm https://packages.wazuh.com/4.x/yum5/wazuh-agent-4.12.0-1.x86_64.rpm
rpm -ivh wazuh-agent.rpm

# Ubuntu/Debian
wget https://packages.wazuh.com/4.x/apt/wazuh-agent_4.12.0-1_amd64.deb
dpkg -i wazuh-agent_4.12.0-1_amd64.deb

# Configure manager
sed -i 's/MANAGER_IP/10.0.1.100/' /var/ossec/etc/ossec.conf

# Start
/var/ossec/bin/wazuh-control start

# Verify
/var/ossec/bin/wazuh-control info
```

#### Windows

```powershell
# Download and install
Invoke-WebRequest -Uri https://packages.wazuh.com/4.x/windows/wazuh-agent-4.12.0-1.msi -OutFile wazuh-agent.msi
Start-Process msiexec.exe -ArgumentList "/i wazuh-agent.msi /qn" -Wait

# Configure
&C:\Program Files\ossec-agent\win32ui.exe  # GUI configurator
# Or edit C:\Program Files\ossec-agent\ossec.conf

# Start service
Start-Service Wazuh
```

#### macOS

```bash
curl -o wazuh-agent.pkg https://packages.wazuh.com/4.x/macos/wazuh-agent-4.12.0-1.pkg
installer -pkg wazuh-agent.pkg -target /

# Configure
/var/ossec/bin/wazuh-control start
```

#### Auto-Registration (Manager side)

```bash
# /var/ossec/etc/ossec.conf
<ossec_config>
  <client>
    <server>
      <address>10.0.1.100</address>
      <port>1514</port>
      <protocol>tcp</protocol>
    </server>
    <protocol>tcp</protocol>
    <crypto_method>aes</crypto_method>
    <enrollment>
      <enabled>yes</enabled>
      <manager_ip>10.0.1.100</manager_ip>
      <port>1515</port>
      <key>YOUR_AGENT_KEY</key>
    </enrollment>
  </client>
</ossec_config>
```

---

### 4. Agentless Collection

For devices where you can't install an agent (network gear, cloud services, legacy systems).

#### SSH Agentless

```bash
# /var/ossec/etc/ossec.conf - Manager config
<ossec_config>
  <agentless>
    <entry name="router-01">
      <type>ssh</type>
      <frequency>3600</frequency>
      <host>192.168.1.1</host>
      <state>active</state>
      <arguments>tail -n 100 /var/log/syslog</arguments>
    </entry>
  </agentless>
</ossec_config>
```

#### AWS CloudTrail (Agentless)

```bash
# /var/ossec/etc/ossec.conf
<ossec_config>
  <agentless>
    <entry name="aws-cloudtrail">
      <type>aws</type>
      <aws_region>us-east-1</aws_region>
      <iam_role_arn>arn:aws:iam::123456789012:role/WazuhCloudTrailReader</iam_role_arn>
      <s3_bucket_name>my-cloudtrail-bucket</s3_bucket_name>
      <s3_prefix>AWSLogs/123456789012/CloudTrail/</s3_prefix>
      <only_logs_after>2025-01-01T00:00:00Z</only_logs_after>
      <frequency>300</frequency>  <!-- Check every 5 min -->
    </entry>
  </agentless>
</ossec_config>
```

#### Syslog Agentless

```bash
# Enable syslog listener
# /var/ossec/etc/ossec.conf
<ossec_config>
  <remote>
    <connection>syslog</connection>
    <port>514</port>
    <protocol>udp</protocol>
    <allowed-ips>10.0.0.0/8</allowed-ips>
  </remote>
</ossec_config>

# Restart
/var/ossec/bin/wazuh-control restart
```

---

## Post-Install Hardening

### TLS Configuration

```bash
# Generate SSL cert for dashboard
openssl req -x509 -newkey rsa:4096 -keyout /etc/ssl/private/wazuh.key \
  -out /etc/ssl/certs/wazuh.crt -days 365 -nodes \
  -subj "/CN=wazuh-dashboard/O=Wazuh"

# Configure nginx reverse proxy with SSL
# /etc/nginx/conf.d/wazuh-ssl.conf
```

### Firewall Rules

```bash
# UFW example (Ubuntu)
ufw allow 22/tcp    # SSH (limited)
ufw allow 1514/tcp  # Agent to manager
ufw allow 1515/tcp  # Agent enrollment
ufw allow 514/udp   # Syslog (if using agentless)
ufw allow 443/tcp   # Dashboard (from internal only)
ufw deny 9200/tcp   # Block indexer from external
```

### Agent Hardening

```bash
# /var/ossec/etc/ossec.conf - Agent config
<ossec_config>
  <client>
    <notify_time>10</notify_time>
    <time-reconnect>60</time-reconnect>
    <auto_restart>yes</auto_restart>
    <crypto_method>aes</crypto_method>
  </client>

  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/messages</location>
  </localfile>

  <rootcheck>
    <frequency>3600</frequency>  <!-- Hourly scan -->
    <scan_on_start>yes</scan_on_start>
  </rootcheck>
</ossec_config>
```

---

## Migration from Existing SIEM

### From Elastic Security

Wazuh can receive Elastic Beats data via syslog:
```bash
# Configure Filebeat to send to Wazuh
filebeat.inputs:
- type: syslog
  host: 10.0.1.100
  port: 514
```

### From Splunk

Use Splunk forwarder to send to Wazuh:
```bash
# outputs.conf on Splunk forwarder
[tcpout]
defaultGroup = wazuh-indexer

[tcpout:wazuh-indexer]
server = 10.0.1.100:1514
```

---

## Verification

```bash
# Check manager status
/var/ossec/bin/wazuh-control info
/var/ossec/bin/wazuh-control status

# Check agents
curl -k -u admin:password https://localhost:55000/agents?pretty

# Check indexer health
curl -k -u admin:password https://localhost:9200/_cluster/health?pretty

# Check dashboard
curl -k https://localhost:5601/api/status
```

## Related

- [[Security/siem/wazuh/README|Wazuh]] — Overview
- [[Security/siem/wazuh/rules-decoders/README|Rules & Decoders]] — Custom rules
- [[Security/siem/wazuh/integrations/README|Integrations]] — n8n, PagerDuty