---
title: AWS Systems Manager
description: AWS Systems Manager — operational management for EC2 fleets and hybrid environments. Run Command, Session Manager, Patch Manager, Parameter Store, State Manager, and Inventory.
tags:
  - aws
  - management
  - systems-manager
---

# AWS Systems Manager (SSM)

Systems Manager provides centralized operational management for your EC2 instances and on-premises servers (via the SSM Agent). It covers patch management, configuration management, command execution, and session management — all without needing SSH access to servers.

## Core Components

### SSM Agent

The SSM Agent is software installed on EC2 instances (and on-premises servers) that communicates with the Systems Manager service. Amazon Linux 2 and recent Windows AMIs have it pre-installed.

```bash
# Check if SSM Agent is running (Linux)
systemctl status amazon-ssm-agent

# Check if SSM Agent is running (Windows)
Get-Service -Name "Amazon SSM Agent"
```

### Prerequisites for SSM to Work

1. **SSM Agent installed and running** on the instance
2. **Internet access or VPC endpoint** for the instance to reach Systems Manager
3. **IAM role** with `AmazonSSMManagedInstanceCore` policy (or equivalent)
4. **Instance in a supported region** (all commercial regions)

### Communication Options

```
Instance → Systems Manager (via internet):
  - Public IP + internet gateway (no VPC endpoint needed)
  - NAT Gateway + internet (for private subnets)

Instance → Systems Manager (via VPC endpoint):
  - SSM VPC Endpoint in the subnet (PrivateLink)
  - Instance uses the VPC endpoint DNS to reach Systems Manager
```

## Run Command

Run Command executes scripts on managed instances without SSH:

```bash
# Run a shell command on all Linux instances
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets '[{"Key":"tag:Environment","Values":["Production"]}]' \
  --parameters '{"commands":["df -h", "free -m"]}'

# Run a PowerShell command on Windows instances
aws ssm send-command \
  --document-name "AWS-RunPowerShellScript" \
  --targets '[{"Key":"InstanceIds","Values":["i-xxxxx"]}]' \
  --parameters '{"commands":["Get-Service"]}'
```

### SSM Documents

SSM Documents define the commands or scripts to run. AWS provides pre-built documents:

| Document | Use |
|----------|-----|
| AWS-RunShellScript | Run shell commands on Linux |
| AWS-RunPowerShellScript | Run PowerShell on Windows |
| AWS-RunScript | Run any shell/PowerShell |
| AWS-UpdateSSMAgent | Update SSM Agent |
| AWS-RunPatchBaseline | Run patch baseline |
| AWS-RestartInstance | Reboot instance |

### Command Output

```bash
# Get command output
aws ssm get-command-invocation \
  --command-id "xxxxx" \
  --instance-id "i-xxxxx"
```

Output is stored in S3 or as part of the command result (for small outputs). Configure the output location in the Run Command invocation.

## Session Manager

Session Manager provides browser-based shell access to instances without SSH:

```bash
# Start a session (CLI)
aws ssm start-session --target i-xxxxx

# Via Console: Systems Manager → Session Manager → Start session
```

Benefits:
- **No SSH port 22** — no inbound access needed
- **No bastion hosts** — reduces attack surface
- **Full session logging** — logs to CloudWatch Logs or S3
- **IAM-based access** — not SSH keys
- **Works with on-premises servers** via SSM Agent

### Session Manager Configuration

Enable session logging to CloudWatch:

```json
{
  "sessionPreferences": {
    "cloudWatchLogGroup": "arn:aws:logs:us-east-1:123456789012:log-group:/aws/ssm/sessions",
    "s3BucketName": "my-session-logs",
    "s3KeyPrefix": "sessions",
    "s3EncryptionEnabled": true
  }
}
```

## Patch Manager

Patch Manager automates the patching of EC2 instances:

```bash
# Create a patch baseline (define which patches are approved)
aws ssm create-patch-baseline \
  --name "Production-Patches" \
  --operating-system AMAZON_LINUX_2 \
  --approval-rules '[{"PatchFilterGroup":{"PatchFilters":[{"Key":"PRODUCT","Values":["AmazonLinux2023"]}]},"ApproveAfterDays": 7}]'

# Register a patch group
aws ssm register-default-patch-baseline --baseline-id "pb-xxxxx"

# Run patching immediately
aws ssm send-command \
  --document-name "AWS-RunPatchBaseline" \
  --targets '[{"Key":"tag:Environment","Values":["Production"]}]'
```

### Patch Baselines

A patch baseline defines which patches to auto-approve:

```
Approve patches with:
  - Severity: Critical, Important
  - Classification: SecurityUpdates, BugFixUpdates
  - Product: AmazonLinux2023, AmazonLinux2
  - After X days: 7 (auto-approve patches 7 days after release)
```

### Maintenance Windows

Schedule patching during maintenance windows:

```bash
# Create a maintenance window
aws ssm create-maintenance-window \
  --name "Production-Patching" \
  --schedule "cron(0 0 2 ? * 7)" \
  --duration 4 \
  --cutoff 1

# Register targets (instances with a specific tag)
aws ssm register-target-with-maintenance-window \
  --window-id mw-xxxxx \
  --resource-type "INSTANCE" \
  --targets '[{"Key":"tag:Environment","Values":["Production"]}]'

# Register a task (patch baseline run)
aws ssm register-task-with-maintenance-window \
  --window-id mw-xxxxx \
  --task-type "RUN_COMMAND" \
  --task-arn "AWS-RunPatchBaseline"
```

## Parameter Store

Parameter Store stores configuration data (secrets, connection strings, license keys) as parameters:

```bash
# Store a plain-text parameter
aws ssm put-parameter \
  --name "/app/database/connection-string" \
  --value "Server=mydb.example.com;Database=myapp;User=admin;Password=secret" \
  --type String

# Store a secret (encrypted with KMS)
aws ssm put-parameter \
  --name "/app/secrets/db-password" \
  --value "my-secret-password" \
  --type SecureString \
  --key-id alias/aws/ssm

# Get a parameter
aws ssm get-parameter --name "/app/database/connection-string"

# Get with decryption (for SecureString)
aws ssm get-parameter --name "/app/secrets/db-password" --with-decryption

# Get multiple parameters
aws ssm get-parameters --names "/app/database/connection-string" "/app/secrets/db-password"
```

### Hierarchy

```
/app
  /database
    connection-string
    port
  /secrets
    db-password
    api-key
  /config
    environment
    log-level
```

## Inventory

Inventory collects metadata from managed instances:

```bash
# Configure inventory collection
aws ssm put-inventory \
  --instance-id "i-xxxxx" \
  --items '[{"TypeName":"AWS:Application","SchemaVersion":"1.0"}]'

# List installed software
aws ssm list-inventory-entries --instance-id "i-xxxxx" --type-name "AWS:Application"
```

## State Manager

State Manager ensures instances are in a defined state (e.g., always have a specific configuration):

```bash
# Associate a configuration document with an instance
aws ssm create-association \
  --name "AWS-ConfigureS3BucketLogging" \
  --targets '[{"Key":"tag:Environment","Values":["Production"]}]'
```

## hybrid Environments (SSM Agent on Premises)

For on-premises servers and edge devices, install the SSM Agent and create a hybrid activation:

```bash
# Create activation (get activation code and ID)
aws ssm create-activation \
  --registration-limit 5 \
  --expiration-in-seconds 86400

# Install SSM Agent on on-prem server using the code and ID
sudo amazon-ssm-agent -register -code "activation-code" -id "activation-id" -region "us-east-1"
```

## References

- **Homepage:** https://aws.amazon.com/systems-manager/
- **Documentation:** https://docs.aws.amazon.com/systems-manager/
- **Pricing:** https://aws.amazon.com/systems-manager/pricing/ (free for most features, Run Command and Session Manager are free for EC2)

## Pricing Examples

**Scenario 1:** A production fleet of 100 EC2 instances patched weekly via Patch Manager. Patch Manager is free. Maintenance windows are free. The Run Command invocations for patching are free. Total: $0/month for Systems Manager on EC2.

**Scenario 2:** A hybrid environment with 20 on-premises servers managed via Systems Manager. For on-premises (non-EC2), Systems Manager charges $0.008/instance-hour for the hybrid activation. 20 instances × 24hr × 30 days = 14,400 instance-hours × $0.008 = $115/month. Compare to setting up SSH bastion hosts for each server: 20 × $0.02/hr (t3.medium) = $288/month. Hybrid SSM is 60% cheaper and provides better management capabilities.

## Nuggets & Gotchas

- **SSM Agent must be running for Systems Manager to work:** If SSM Agent crashes or is stopped, the instance becomes "unmanaged" and Run Command, Session Manager, and Patch Manager all fail. Monitor SSM Agent health via CloudWatch metrics.
- **Private subnets need VPC endpoints for Systems Manager:** Instances in private subnets without NAT Gateway cannot reach Systems Manager over the internet. You must create VPC endpoints for `ssm`, `ssmmessages`, and `ec2messages` in the private subnet.
- **Parameter Store has a 4KB default limit for standard parameters:** 4KB is enough for most secrets and connection strings. For larger secrets (certificates, keys), use advanced parameters ($0.05/parameter/month for >4KB).
- **Session Manager logs can cost money if not managed:** If you enable Session Manager logging to CloudWatch Logs, every session (bash command, output) is logged. A busy team with 50 sessions/day × 30 days × 1MB/session = 1.5GB/month ingested. CloudWatch Logs ingestion: $0.50/GB = $0.75/month. Manageable but track it.
- **Run Command rate limits to 100 concurrent executions:** If you target 1000 instances with Run Command, only 100 execute at once. The rest queue. This prevents accidental overload but means large fleet operations take time.