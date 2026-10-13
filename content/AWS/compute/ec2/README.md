---
title: "Amazon EC2"
description: "Launch and operate a sandbox VM with IMDSv2, scoped access, lifecycle-aware storage and verified capacity/cost assumptions."
tags:
  - cloud/aws/compute
date: 2026-10-12
---

# Amazon EC2

EC2 provides virtual machines; you own guest OS patching, software, data and workload security. Choose it when you need OS/device/network control rather than automatically using it for every application.

## Select an instance and image

Compare CPU architecture, memory, network/storage limits, accelerators, licensing and representative load. Family names are examples, not a timeless current-generation catalog. Burstable T instances have size-specific baselines and Standard/Unlimited credit behavior; sustained demand can incur surplus-credit charges or reduced performance.

Select a supported AMI for the **target Region and architecture**. A Ubuntu apt script is not portable to Amazon Linux. Prefer Systems Manager access where supported rather than opening SSH to the world.

## Launch-template lab

Prerequisites: sandbox subnet/security group, supported AMI ID, an approved instance profile for SSM, and launch/PassRole permissions. Use private addressing with the necessary SSM endpoints/egress. Set a budget; EBS, public IPv4, logs and endpoints can be charged independently.

Save this as `launch-template.json`, replacing the AMI, group and profile with the sandbox values:

```json
{
  "ImageId": "ami-REPLACE_WITH_REGIONAL_AMI",
  "InstanceType": "t3.micro",
  "SecurityGroupIds": ["sg-REPLACE_WITH_SANDBOX_GROUP"],
  "IamInstanceProfile": { "Name": "REPLACE_WITH_SANDBOX_PROFILE" },
  "MetadataOptions": {
    "HttpTokens": "required",
    "HttpEndpoint": "enabled"
  },
  "TagSpecifications": [
    {
      "ResourceType": "instance",
      "Tags": [{ "Key": "Purpose", "Value": "wiki-ec2-lab" }]
    }
  ]
}
```

```bash
aws ec2 create-launch-template \
  --launch-template-name wiki-ec2-lab \
  --launch-template-data file://launch-template.json
aws ec2 run-instances \
  --launch-template LaunchTemplateName=wiki-ec2-lab,Version=1 \
  --subnet-id "$EC2_LAB_SUBNET_ID" --min-count 1 --max-count 1
```

Record the returned instance ID. Wait for running and status checks; confirm subnet, role, metadata requirements and attached volumes with describe-instances. Connect with Session Manager after the agent is online.

On that instance, use IMDSv2:

```bash
EC2_IMDS_TOKEN=$(curl -fsS -X PUT \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" \
  http://169.254.169.254/latest/api/token)
curl -fsS -H "X-aws-ec2-metadata-token: $EC2_IMDS_TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id
```

Expected: the recorded instance ID. An unauthenticated metadata request should fail when tokens are required. Never print role credentials or place secrets in user data.

## Lifecycle and recovery

Stopping an EBS-backed instance normally stops compute billing, not volume/snapshot/address charges. Instance-store data is ephemeral; inspect root and additional-volume DeleteOnTermination settings before terminating. Do not recommend termination as a universal way to remove every EBS volume.

User-data execution depends on the OS/agent configuration; cloud-init's initial execution is not a repeat-on-every-reboot guarantee. Use a managed configuration workflow for recurring changes.

Checkpoint: stop/start the sandbox instance, confirm retained EBS data and changed/non-retained addressing assumptions. Terminate only the lab instance, wait for terminated, inspect/delete approved leftover volumes, release dedicated addresses and delete the lab launch template. Preserve snapshots needed for recovery.

## Scaling and purchasing

Use [[AWS/compute/auto-scaling|Auto Scaling]] for fleet lifecycle, health replacement and instance refresh. Prefer diversified mixed-instance capacity and interruption-aware work for Spot. A two-minute interruption notice is not a guaranteed grace period for every interruption type; checkpoint and test recovery.

EC2 capacity quotas are usually vCPU-based by purchase/family category, not a universal twenty-instance limit. Check account/Region quota and actual capacity separately. A granted quota does not guarantee launch capacity.

Cost = running instance time × the selected Region/OS/purchase tariff + storage/IO + public addresses + network + telemetry. RIs/SPs provide billing benefits with conditions; capacity reservations and discounts are not synonyms. See [[AWS/cost-management/pricing-models|pricing models]].

## Instance choices and architecture

Use the instance-family comparison to select a starting point. Compare an actual size and Region before committing because generations and available shapes change.

| Family      | Typical strength                              | First workload to evaluate                     |
| ----------- | --------------------------------------------- | ---------------------------------------------- |
| T           | Burstable CPU with credit accounting          | Intermittent development services              |
| M           | Balanced CPU and memory                       | General application servers                    |
| C           | More CPU relative to memory                   | Encoding and build workers                     |
| R           | More memory relative to CPU                   | In-memory processing and databases             |
| I / D       | Local storage optimized for I/O or throughput | Temporary high-I/O data or distributed storage |
| G / P / Inf | Accelerator-specific compute                  | Graphics, model training or inference          |

An EBS-backed instance can stop and start while its volume persists; an instance-store volume cannot be treated as a durable backup. A stopped instance can still incur EBS and other charges. A security group controls ENI traffic, the subnet's route table controls the path, and an Elastic IP or public IPv4 address only supplies an address. Test all three when troubleshooting reachability.

```text
AMI + instance type + subnet + security group + role
                 ↓ launch template
              EC2 instance
       ├─ EBS root/data volumes → snapshots or backup
       ├─ ENI → route table → gateway/endpoint
       └─ instance profile → temporary role credentials
```

## Operating a fleet

For a persistent service, put the launch template behind an Auto Scaling group across suitable subnets. Set minimum, desired and maximum capacity from actual availability needs; a target tracking policy adjusts desired capacity, while health checks and instance refresh address failed or outdated members. Step scaling requires a separately configured alarm. When a load balancer is involved, attach the target group and verify the health check before shifting traffic. The [[AWS/compute/auto-scaling|Auto Scaling lesson]] contains the full exercise.

Use Spot for interruption-tolerant work with checkpointing and retry. Check the instance's purchase option, capacity-optimized placement, and termination behavior before treating Spot as interchangeable with On-Demand. For a single host, Session Manager requires an online SSM Agent, instance permissions, and network access to the service; its absence does not imply an SSH firewall problem.

## Diagnose and recover

1. Record the instance ID, instance state and both status checks. A running state alone does not mean the guest is healthy.
2. For failed network access, inspect subnet association, longest-prefix route, public/private address, SG inbound and outbound rules, NACL return traffic, DNS and process listener.
3. For storage failure, inspect attached EBS volume state, OS mount/filesystem state, available space and backup age. A snapshot is not a mounted replacement volume; test restoration in a separate instance.
4. Before changing instance type, check the AMI architecture, virtualization, ENA/device requirements and workload licensing. Benchmark the replacement against the same load.
5. After recovery, confirm application behavior and clean up old volumes, snapshots or addresses according to retention policy.

For a cost comparison, use a worksheet with `instance hours × regional OS/type price`, plus EBS GB-month and provisioned performance, snapshots, public IPv4, transfer and monitoring. State utilization and interruption assumptions when comparing Savings Plans, Reserved Instances or Spot. A percentage discount by itself does not establish a lower total workload cost.

## References

- [Launch-template contract](https://docs.aws.amazon.com/cli/latest/reference/ec2/create-launch-template.html).
- [IMDSv2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html).
- [Instance lifecycle](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-lifecycle.html).
- [EC2 quotas](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-resource-limits.html).
- [Burstable CPU credits](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/burstable-performance-instances.html).
- [Current pricing](https://aws.amazon.com/ec2/pricing/).

## Across the wiki

- [[Azure/compute/vm|Azure Virtual Machines & Scale Sets (VMSS)]] — virtual machines (Azure)
- [[GCP/compute/gce|GCP Compute Engine (GCE)]] — virtual machines (GCP)
- [[Linux/virtualization/hypervisors|Hypervisors]] — virtual machines (Linux)
- [[GCP/compute/gce/migs|GCP Managed Instance Groups (MIGs)]] — virtual machines (GCP)
