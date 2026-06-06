---
title: Application Migration Service (MGN)
description: AWS MGN — lift-and-shift service for Windows and Linux servers, continuous replication, wave management, cutover workflow, and post-launch validation
tags:
  - aws
  - migration
---

# Application Migration Service (MGN)

MGN is AWS's modern lift-and-shift (rehost) service. It continuously replicates your on-premises servers to AWS, allowing you to cut over with minimal downtime. It replaces the older Server Migration Service (SMS).

## How It Works

```
Source Server                    MGN Service                   Target AWS
(Windows/Linux)                  (managed)                    (EC2)
    │                                │                            │
    ├─ Install MGN Agent ──────────→ │                            │
    │                                │                            │
    ├─ Continuous Replication ──────→ │ (S3 staging + EBS snapshots)
    │                                │                            │
    │                                │─── Test Launch ────────────→│ (validation)
    │                                │                            │
    │                                │─── Final Cutover ─────────→│ (production)
```

**Replication process:**
1. Install MGN agent on source server
2. Agent continuously replicates block-level changes to a staging area in your AWS account (S3 bucket + EBS snapshots)
3. When ready, initiate test launch or final cutover
4. MGN converts the replicated disk to an EC2 instance and boots it

## Key Concepts

### Source Server

A source server is a server (physical or virtual) that you've registered with MGN. Each source server has:
- **Replication configuration:** VPC, subnet, security group for the replicated instance
- **Agent status:** Online/Offline, last sync time
- **Lifecycle:** `PENDING`, `TESTING`, `MIGRATING`, `CUTOVER`, `CUTOVER_COMPLETE`

### Wave

A wave is a group of source servers that you migrate together as a unit. Waves let you coordinate cutover for multi-server applications.

```bash
# Create a wave
aws mgn create-wave \
  --account-id 123456789012 \
  --name "web-tier-wave-1" \
  --description "Web tier servers, cutover planned for Friday night"

# Add servers to wave
aws mgn add-source-servers-to-wave \
  --wave-id w-1234567890abcdef0 \
  --source-server-ids s-1234567890abcdef0 s-0987654321fedcba0

# Track wave status
aws mgn describe-waves --wave-id w-1234567890abcdef0
```

### Cutover Modes

- **Test launch:** Non-destructive launch of the replicated server. You can boot it, validate it works, then terminate. Original server keeps replicating.
- **Final cutover:** Actual production cutover. After cutover, the original server is shut down and replication stops.

## Installing the Agent

### Linux

```bash
# Download the agent installer
# Get the installer URL from: MGN Console → Source Servers → Install Agent
wget https://aws-mgn-agent-bucket.s3.amazonaws.com/latest/linux/aws-replication-installer.ini

# Edit the installer config
# Add your AWS region and source server ID from the MGN console
cat > aws-replication-installer.ini << 'EOF'
[DEFAULT]
aws_region = us-east-1
source_server_id = s-1234567890abcdef0
bandwidth_throttle = 0
use_public_ip = false
EOF

# Run the installer
sudo ./aws-replication-installer.py
```

### Windows

1. Download the agent installer (.msi) from MGN console
2. Run the installer on the Windows server
3. Enter the Source Server ID and AWS region when prompted
4. The agent runs as a Windows service (`AWSReplicationService`)

### Agent Configuration

```bash
# Check agent status on Linux
sudo systemctl status aws-replication-agent

# Check agent logs
sudo tail -f /var/log/aws-replication-agent.log

# Pause/resume replication (for maintenance windows)
sudo /aws-replication-agen pause
sudo /aws-replication-agen resume

# Uninstall agent (after cutover complete)
sudo /aws-replication-agen uninstall
```

## Replication Settings

```bash
# Configure replication (e.g., throttle bandwidth to 50 Mbps)
aws mgn update-source-server-replication-configuration \
  --source-server-id s-1234567890abcdef0 \
  --replication-configuration '{
    "bandwidthThrottling": 50,
    "dataReplicationRootHash": null,
    "enableReBoot": true,
    "replicatedServerDisks": [{
      "diskTag": "C:",
      "diskPadding": 0
    }],
    "replicationServerSecurityGroupIds": ["sg-0123456789abcdef0"],
    "replicationServerSubnetId": "subnet-0123456789abcdef0",
    "replicationServerSecurityGroupIds": ["sg-0123456789abcdef0"],
    "serverId": "s-1234567890abcdef0",
    "targetInstanceTypeRightSizingMethod": "AUTO"
  }'
```

**Key settings:**
- `bandwidthThrottling`: Limit replication bandwidth (0 = unlimited)
- `enableReBoot`: MGN can reboot the source if needed for replication (Windows only)
- `targetInstanceTypeRightSizingMethod`: `AUTO` = right-size based on utilization, `MANUAL` = specify type

## Cutover Workflow

```bash
# 1. Check replication status (should be "Live" before cutover)
aws mgn describe-source-servers \
  --filters "Name=source-server-id,Values=s-1234567890abcdef0"
# Look for: lastSyncedTime, estimatedSyncDuration, volumeStatus

# 2. Initiate test launch
aws mgn start-test-launch \
  --source-server-id s-1234567890abcdef0 \
  --target-instance '{
    "instanceType": "t3.medium",
    "vpcSecurityGroupIds": ["sg-0123456789abcdef0"],
    "subnetId": "subnet-0123456789abcdef0"
  }'

# 3. Wait for instance to boot (check status)
aws mgn describe-source-servers --source-server-id s-1234567890abcdef0
# Lifecycle should show: TESTING

# 4. Validate the test instance (application works, connectivity OK)
# 5. Terminate test instance when validation done
aws mgn terminate_target_instance \
  --source-server-id s-1234567890abcdef0

# 6. When ready for final cutover
aws mgn start-cutover \
  --source-server-id s-1234567890abcdef0 \
  --target-instance '{
    "instanceType": "t3.medium",
    "vpcSecurityGroupIds": ["sg-0123456789abcdef0"],
    "subnetId": "subnet-0123456789abcdef0"
  }'

# 7. Verify cutover complete
aws mgn describe-source-servers --source-server-id s-1234567890abcdef0
# Lifecycle should show: CUTOVER_COMPLETE
```

## Wave Cutover

For multi-server applications, cut over the entire wave at once:

```bash
# Start wave cutover
aws mgn start-wave-cutover \
  --wave-id w-1234567890abcdef0 \
  --target-instance '{
    "targetInstanceTypeRightSizingMethod": "AUTO"
  }'

# Monitor wave cutover progress
aws mgn describe-wave-cutovers --wave-id w-1234567890abcdef0

# Check individual server status
aws mgn describe-source-servers --filters "Name=wave-id,Values=w-1234567890abcdef0"
```

## Post-Launch Validation

MGN can run validation scripts after launch to verify the server is working:

```bash
# Create a post-launch validation template
aws mgn create-launch-configuration-template \
  --post-launch-configuration '{
    "targetInstance": {
      "instanceType": "t3.medium",
      "vpcSecurityGroupIds": ["sg-0123456789abcdef0"],
      "subnetId": "subnet-0123456789abcdef0"
    },
    "validation": {
      "commands": ["powershell -File C:\\validate.ps1"]
    }
  }'

# Or run validation via Lambda after cutover
# MGN can trigger a Lambda on cutover completion for custom validation
```

## Monitoring

```bash
# CloudWatch metrics for MGN
# - Progress (percentage of replication complete)
# - DataTransferred (bytes replicated)
# - Lag (time behind source in seconds)
# - DiskUtilization (source disk usage)
# - NetworkBandwidthThrottle (actual bandwidth used)

# Check replication lag
aws mgn describe-source-server-replication-configuration \
  --source-server-id s-1234567890abcdef0
# Look at: lastSyncedTime, lagDuration
```

**If lag is growing (not shrinking):**
- Network bandwidth is too low for the rate of data change
- Increase `bandwidthThrottling` limit
- Consider compressing replication traffic (enable `compression` in config)

## Network Requirements

For MGN agent to work:
- Outbound HTTPS (443) to MGN service endpoints
- Outbound HTTPS to S3 endpoints (for staging data)
- Inbound from replication server (for initial data transfer)

**Ports required:**
- TCP 443 (HTTPS) — to AWS services
- TCP 1500 — replication data transfer from source to replication server
- UDP 1500 — heartbeat (optional, for faster failover)

## Staging Area

MGN uses an S3 bucket and EBS snapshots as a staging area:
- Replication data goes to S3 (encrypted with KMS)
- EBS snapshots are created from S3 data
- Staging area is cleaned up automatically after cutover

You can customize the staging area location (dedicated S3 bucket per account for cost tracking).

## Cost

- **Per-source server per hour:** ~$0.026/hr (varies by region)
- **S3 and EBS costs:** For the staging area (temporary, deleted after cutover)
- **EBS snapshot costs:** Until snapshots are deleted post-cutover

**Cost tip:** After cutover is complete, immediately clean up:
```bash
# Delete source server from MGN (stops billing)
aws mgn delete-source-server --source-server-id s-1234567890abcdef0

# Delete staging S3 bucket contents (stops S3 charges)
aws s3 rm s3://mgn-staging-bucket --recursive
```

## Limitations

- **Supported sources:** Physical servers, VMware ESXi, Hyper-V, AWS (EC2-to-EC2 migration), Azure VMs, Google Cloud VMs
- **Windows versions:** 2008 R2, 2012, 2012 R2, 2016, 2019, 2022
- **Linux versions:** RHEL, CentOS, Ubuntu, Debian, SUSE, Oracle Linux
- **Maximum source disks:** 20 per server
- **Maximum source disk size:** 16TB per disk
- **Replication to different VPC/Region:** Not directly supported — replicate to same region first, then use VM Import/Export or create AMI and copy

## Comparison: MGN vs SMS

| Feature | MGN | SMS (deprecated) |
|---------|-----|------------------|
| Continuous replication | Yes | Yes |
| Wave management | Yes | No |
| Test launch | Yes | No |
| Agent-based | Yes | Agent-based |
| Status | Active development | No new features, eventually retired |
| Cutover modes | Test + Final | Direct cutover only |