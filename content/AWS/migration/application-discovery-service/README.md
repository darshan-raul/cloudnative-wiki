---
title: Application Discovery Service
description: AWS Application Discovery Service — discovers on-premises infrastructure (servers, dependencies, utilization) via agentless and agent-based collectors, exports data for migration planning
tags:
  - aws
  - migration
---

# Application Discovery Service

Application Discovery Service (ADS) helps you discover and understand your on-premises environment before migration. It collects infrastructure data (servers, utilization, network dependencies) that feeds into Migration Hub for planning and tracking.

## Discovery Methods

### Agentless Discovery (VMware)

No software installed on source servers — a collector VM interrogates vCenter:

```bash
# Start an agentless collector scan
aws discovery start-agentless-collector-scan \
  --region us-east-1 \
  --collectors ['arn:aws:discovery:us-east-1:123456789012:agentless-collector/collector-abcdef0']

# Describe collectors
aws discovery list-agents --region us-east-1

# Get discovered servers
aws discovery list-servers --region us-east-1

# Get server details
aws discovery describe-agents --agent-ids arn:aws:discovery:us-east-1:123456789012:agent/agent-abcdef0
```

**What it collects:**
- VM name, guest OS, version
- vCPU, memory, disk sizes
- Network configuration (IP addresses, MAC addresses)
- Resource utilization (CPU, memory, disk over time)
- VMware cluster and resource pool membership

### Agent-Based Discovery

Install the discovery agent on each server for deeper visibility:

```bash
# Download and install the agent (Linux)
wget https://s3.amazonaws.com/aws-discovery-agent/linux/latest/aws-discovery-agent.tar.gz
tar -xzf aws-discovery-agent.tar.gz
sudo ./install

# Configure the agent
sudo /opt/aws/discovery agent configure --region us-east-1

# Check agent status
sudo /opt/aws/discovery/bin/AWSDiscoveryAgent status

# Check logs
sudo tail -f /var/log/aws/discovery/discovery-agent.log
```

**What it collects (beyond agentless):**
- Running processes and services
- Application names and versions
- Network connections between servers (dependency mapping)
- User accounts on the server
- More detailed performance metrics

## Agent Deployment

### VMware Agentless Collector

```bash
# 1. Download the collector OVA from ADS console
# 2. Deploy in VMware (2 vCPU, 8GB RAM, 100GB disk)
# 3. Configure with your AWS credentials (IAM role or access key)
# 4. Configure vCenter credentials (read-only is sufficient)
# 5. Let it run — it will continuously collect for 2-4 weeks
```

**Requirements:**
- Outbound HTTPS to AWS (port 443)
- Access to vCenter API (read-only)
- NTP configured (accurate timestamps are important)

### Linux Agent

```bash
# Install on RHEL/CentOS/Amazon Linux
sudo yum install ./aws-discovery-agent.rpm

# Install on Ubuntu/Debian
sudo dpkg -i ./aws-discovery-agent.deb

# Configure after install
sudo /opt/aws/discovery/bin/configure.py \
  --region us-east-1 \
  --agent-id my-agent-group-1
```

### Windows Agent

1. Download the installer from ADS console
2. Run the installer (MSI package)
3. Open Services → AWSDiscoveryAgent → set to Automatic
4. Edit config at `C:\Program Files\AWS\AWSDiscoveryAgent\config.ini` with your region

## Data Collected

### Server Information

```json
{
  "serverId": "server-abc123",
  "hostname": "web-prod-01",
  "osVersion": "RHEL 8.5",
  "osArchitecture": "x86_64",
  "cpuCores": 8,
  "memorySizeMB": 16384,
  "diskSizeMB": 512000,
  "ipAddresses": ["10.0.1.50", "192.168.1.100"],
  "macAddresses": ["00:0C:29:AB:CD:EF"],
  "vmwareConfig": {
    "clusterName": "production",
    "resourcePool": "web-tier",
    "vCenterId": "vc-12345"
  }
}
```

### Network Dependencies

```json
{
  "sourceServerId": "server-abc123",
  "connections": [
    {
      "destinationIp": "10.0.1.100",
      "destinationPort": 3306,
      "protocol": "TCP",
      "processName": "mysqld"
    },
    {
      "destinationIp": "10.0.1.101",
      "destinationPort": 6379,
      "protocol": "TCP",
      "processName": "redis-server"
    }
  ]
}
```

This dependency map is critical for understanding what must be migrated together and what the blast radius is when cutting over.

### Utilization Data

```json
{
  "serverId": "server-abc123",
  "utilizationSamples": [
    {
      "timestamp": "2024-06-15T00:00:00Z",
      "cpuPercent": 35.2,
      "memoryPercent": 72.1,
      "diskReadBytesPerSec": 125000,
      "diskWriteBytesPerSec": 85000,
      "networkInBytesPerSec": 2500000,
      "networkOutBytesPerSec": 3500000
    }
  ]
}
```

This data feeds into Migration Evaluator for right-sizing recommendations.

## Exporting Data

```bash
# Export all discovered data as CSV
aws discovery get-discovered-resource-summary --region us-east-1

# Export to S3
aws discovery export-descriptions \
  --output-format CSV \
  --s3-destination '{
    "Bucket": "my-discovery-data",
    "Prefix": "export/2024-06/"
  }'

# List exports
aws discovery list-export-configurations --region us-east-1
```

## Integration with Migration Hub

Discovered servers can be imported into Migration Hub as applications:

```bash
# Register an application
aws migrationhub create-application \
  --name "order-service" \
  --description "Order processing service"

# Associate discovered servers with application
aws discovery associate-discovered-resource \
  --identifier '{"source": "AWSApplicationDiscoveryService", "id": "server-abc123"}' \
  --destination-region us-east-1
```

This gives you a migration plan with all servers tracked in Migration Hub, ready for MGN or DMS migration.

## Querying Discovery Data

```bash
# List all servers
aws discovery list-servers

# Filter by OS
aws discovery query \
  --expression "SELECT * FROM AWSDISCOVERY WHERE osType = 'RHEL'"

# Get servers with high CPU utilization
aws discovery query \
  --expression "SELECT serverId, hostname, cpuCores FROM AWSDISCOVERY WHERE cpuCores > 4"

# Get network dependencies for a specific server
aws discovery list-server-neighbors \
  --server-id server-abc123 \
  --region us-east-1
```

**Important:** The query API uses SQL-like syntax against your discovery data stored in AWS (not a real SQL database — just a query interface).

## Monitoring

```bash
# Check agent status
aws discovery describe-agents --agent-ids agent-abc123

# CloudWatch metrics for ADS
# - HostAgentHeartbeat (is the agent communicating)
# - DataSize (how much discovery data is being collected)
```

## Limitations

- **Agentless:** VMware only (no Hyper-V, physical, other hypervisors)
- **Agent:** Supports Windows Server and Linux (RHEL, CentOS, Ubuntu, SUSE, Debian)
- **Data retention:** Discovery data retained for 90 days (can export before deletion)
- **No migration execution:** ADS only discovers, doesn't migrate. Use MGN, DMS, DataSync for actual migration.
- **AWS regions:** Discovery data can only be exported to the same region where it was collected

## Use in Migration Planning

```
Phase 1: Discovery (ADS)
  → Collect server inventory, utilization, dependencies

Phase 2: Assessment (Migration Evaluator)
  → Analyze discovery data, generate TCO report, right-sizing recommendations

Phase 3: Planning (Migration Hub)
  → Group servers into applications, assign migration strategy

Phase 4: Execution (MGN, DMS, DataSync)
  → Execute the migration per plan

Phase 5: Validation
  → Verify applications work post-migration
```

ADS is the starting point. Without knowing what you have, you can't plan the migration or build an accurate business case.