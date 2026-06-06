---
title: Amazon EC2
description: Amazon EC2 — virtual servers in the cloud. Instance types, AMIs, key pairs, security groups, networking, storage, auto scaling, lifecycle, and pricing models.
tags:
  - aws
  - compute
  - ec2
---

# Amazon EC2 (Elastic Compute Cloud)

EC2 provides resizable compute capacity in AWS. You launch virtual machines (instances) from AMIs, configure networking and storage, and pay based on usage. Full control over the operating system — you're responsible for patching, security, and application-level management.

## Core Concepts

### Instance Lifecycle

```
Pending → Running → Stopping → Stopped → Shutting-down → Terminated
                  ↓
              Rebooting
```

- **Pending:** Launching (provisioning, not billable)
- **Running:** Active (billable)
- **Stopping/Stopped:** Instance stopped (not billable, but EBS storage still costs)
- **Terminated:** Deleted (cannot recover)

### Instance Types

```
t3.micro      → t (Burstable), 2 vCPU, 1 GB RAM
m6i.xlarge    → m (General), 4 vCPU, 16 GB RAM
c6i.2xlarge   → c (Compute), 8 vCPU, 16 GB RAM
r6i.xlarge    → r (Memory), 4 vCPU, 32 GB RAM
g5.xlarge     → g (GPU), 4 vCPU, 16 GB RAM, NVIDIA A10G
inf2.xlarge   → inf (Inferentia), 4 vCPU, 16 GB RAM, AWS ML chips
```

### Instance Families

| Family | Characteristic | Best For |
|--------|--------------|----------|
| T | Burstable CPU (baseline + credits) | Dev/test, low-traffic web |
| M | Balanced (CPU/memory) | General purpose |
| C | High CPU | Media encoding, CI/CD |
| R | High memory | Databases, caches |
| X | Very high memory | SAP, SAP HANA |
| I | High disk IOPS | NoSQL, data warehousing |
| D | High disk throughput | HDFS, MapReduce |
| G | GPU (graphics/ML) | ML inference, gaming |
| P | GPU (parallel) | ML training |
| Inf | ML inferentia chip | Low-cost ML inference |
| Hpc | High performance CPU | Scientific computing |

### Current Generation vs Previous

```
Current → t3, m6i, c6i, r6i, g5, p4d
Previous → t2, m5, c5, r5, g4, p3
```

Current gen has better price/performance. Always use current generation for new workloads.

## Launching an Instance

### Via Console

1. Choose AMI (Amazon Linux 2, Ubuntu, Windows, etc.)
2. Choose instance type (t3.micro, m6i.xlarge, etc.)
3. Configure networking (VPC, subnet, security group)
4. Add storage (EBS volumes)
5. Add tags (Name, Environment, etc.)
6. Configure security (key pair)
7. Launch

### Via CLI

```bash
aws ec2 run-instances \
  --image-id ami-0abcdef1234567890 \
  --instance-type t3.micro \
  --key-name my-key-pair \
  --security-group-ids sg-xxxxx \
  --subnet-id subnet-xxxxx \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=my-instance}]' \
  --user-data '#!/bin/bash
apt update && apt install -y nginx'
```

## Networking

### Security Groups

```bash
# Create security group
aws ec2 create-security-group \
  --group-name my-sg \
  --description "My security group" \
  --vpc-id vpc-xxxxx

# Add inbound rule (HTTP)
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

# Add inbound rule (SSH from specific IP only)
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp \
  --port 22 \
  --cidr 203.0.113.0/32
```

### Elastic IP

```bash
# Allocate Elastic IP
aws ec2 allocate-address

# Associate with instance
aws ec2 associate-address \
  --instance-id i-xxxxx \
  --allocation-id eipalloc-xxxxx

# Disassociate and release
aws ec2 disassociate-address --association-id eipassoc-xxxxx
aws ec2 release-address --allocation-id eipalloc-xxxxx
```

### ENI (Elastic Network Interface)

```bash
# Create ENI
aws ec2 create-network-interface \
  --subnet-id subnet-xxxxx \
  --description "my-eni" \
  --groups sg-xxxxx

# Attach to instance
aws ec2 attach-network-interface \
  --network-interface-id eni-xxxxx \
  --instance-id i-xxxxx \
  --device-index 1
```

## Storage

### EBS Volumes

```bash
# Create volume
aws ec2 create-volume \
  --volume-type gp3 \
  --size 100 \
  --availability-zone us-east-1a

# Attach
aws ec2 attach-volume \
  --volume-id vol-xxxxx \
  --instance-id i-xxxxx \
  --device /dev/sdf

# Detach
aws ec2 detach-volume --volume-id vol-xxxxx
```

### Instance Store

Instance store is local disk (NVMe) attached to the host — very fast but ephemeral (data lost on stop/termination).

```bash
# Launch with instance store (some instance types)
aws ec2 run-instances \
  --image-id ami-0abcdef1234567890 \
  --instance-type m5d.xlarge  # m5d has instance store
```

## Auto Scaling

### Launch Template

```bash
aws ec2 create-launch-template \
  --launch-template-name my-lt \
  --image-id ami-0abcdef1234567890 \
  --instance-type t3.micro \
  --key-name my-key-pair

# Version
aws ec2 create-launch-template-version \
  --launch-template-id lt-xxxxx \
  --source-version 1 \
  --launch-template-data '{"ImageId": "ami-new"}'
```

### Auto Scaling Group

```bash
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name my-asg \
  --launch-template '{"LaunchTemplateId": "lt-xxxxx", "Version": "1"}' \
  --min-size 2 \
  --max-size 10 \
  --desired-capacity 4 \
  --vpc-zone-identifier "subnet-xxxxx,subnet-yyyyy" \
  --availability-zones us-east-1a us-east-1b
```

### Scaling Policies

```bash
# Target tracking (CPU at 70%)
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name my-asg \
  --policy-name cpu-70 \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "TargetValue": 70,
    "PredefinedMetricSpecification": {"PredefinedMetricType": "ASGAverageCPUUtilization"}
  }'

# Step scaling (scale out on alarm)
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name my-asg \
  --policy-name scale-out \
  --policy-type StepScaling \
  --adjustment-type PercentChangeInCapacity \
  --step-adjustments '{"MetricIntervalLowerBound": 0, "ScalingAdjustment": 50}'
```

## Pricing Models

| Model | Description | Use Case | Savings vs On-Demand |
|-------|-------------|----------|---------------------|
| On-Demand | Pay per second/minute | Short, unpredictable | 0% |
| Reserved | 1 or 3 year commitment | Baseline workloads | Up to 70% |
| Savings Plans | Flexible commitment | Any compute | Up to 60% |
| Spot | Interruptible, cheap | Fault-tolerant batch | 70-90% |
| Dedicated | Physical server | Compliance, licensing | Varies |

### Spot Instances

```bash
# Request spot fleet
aws ec2/request-spot-fleet \
  --spot-fleet-request-config '{
    "SpotPrice": "0.03",
    "TargetCapacity": 10,
    "IamInstanceProfile": {"Arn": "arn:aws:iam::123456789012:instance-profile/my-role"},
    "LaunchSpecifications": [{
      "InstanceType": "m5.xlarge",
      "ImageId": "ami-0abcdef1234567890",
      "SubnetId": "subnet-xxxxx",
      "WeightedCapacity": 2
    }]
  }'
```

## Instance Metadata

```bash
# Get instance ID
curl http://169.254.169.254/latest/meta-data/instance-id

# Get public IP
curl http://169.254.169.254/latest/meta-data/public-ipv4

# Get IAM role (if attached)
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/

# Get user-data (launch script)
curl http://169.254.169.254/latest/user-data/
```

## Systems Manager (SSM)

```bash
# Connect without SSH (Session Manager)
aws ssm start-session --target i-xxxxx

# Run command on instance
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets '[{"Key":"InstanceIds","Values":["i-xxxxx"]}]' \
  --parameters '{"commands":["df -h", "free -m"]}'
```

## Limits

| Resource | Limit |
|----------|-------|
| Instances per region (default) | 20 |
| Elastic IPs per region | 5 |
| Security groups per VPC | 500 |
| Rules per security group | 60 (inbound) + 60 (outbound) |
| Launch templates per region | 100 |

## References

- **Homepage:** https://aws.amazon.com/ec2/
- **Documentation:** https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/
- **Pricing:** https://aws.amazon.com/ec2/pricing/

## Pricing Examples

**Scenario 1:** A t3.micro running continuously for a dev environment. On-Demand: $0.0104/hr × 24 × 30 = $7.49/month. With Reserved Instance (1 year, no upfront): $0.006/hr effective = $4.32/month. Savings: 42%.

**Scenario 2:** A batch processing job using Spot instances. On-Demand m5.xlarge: $0.192/hr × 100 instances × 8 hours = $153.60/job. Spot (70% savings): $0.058/hr × 100 × 8 = $46.40/job. 10 jobs/month = $464 vs $1,536. At $0.058/hr Spot, the same budget processes 3.3x more work.

## Nuggets & Gotchas

- **T3 instances have a burst credit system — CPU is baseline 10% with bursts to 100%:** If you run at > 10% CPU consistently, you'll burn through credits and performance drops to 5%. For consistently > 30% CPU, use M5 or C5 instead.
- **EBS volumes attached to stopped instances still cost money — only stop when needed:** A 100GB gp3 volume costs $8/month whether the instance is running or stopped. Terminate unused instances to stop paying for EBS.
- **Spot instances can be interrupted with 2-minute notice — never run stateful workloads without checkpoints:** For databases, use a persistent launch template with restart on interruption. For batch jobs, enable checkpointing to S3.
- **The default limit is 20 instances per region — request increase for production:** If you try to launch > 20 instances, you'll get `MaxInstanceCountExceeded`. Request via AWS console or CLI before deploying.
- **Instance user-data runs once at first launch — it does not re-run on reboot:** To re-run a script, use cloud-init with `runcmd` or Systems Manager State Manager. User-data is for initial setup only.