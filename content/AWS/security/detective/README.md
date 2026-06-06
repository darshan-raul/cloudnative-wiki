---
title: AWS Detective
description: AWS Detective — graph-based security investigation. Visualizes GuardDuty, CloudTrail, and VPC Flow data to help you investigate security findings across accounts.
tags:
  - aws
  - security
  - detective
---

# AWS Detective

Detective automatically ingests and analyzes data from GuardDuty, CloudTrail, and VPC Flow Logs, then builds a graph database to help you investigate security findings. Instead of manually searching logs, you can visually explore relationships between resources, IP addresses, and actors.

## How It Works

```
Data Sources:
  ├── GuardDuty Findings
  ├── CloudTrail Management Events
  ├── CloudTrail S3 Data Events
  └── VPC Flow Logs
       │
       ▼
  Detective Analysis Engine
       │
       ├── Builds behavior graph
       ├── Links related entities
       └── Calculates statistical profiles
       │
       ▼
  Visual Investigation Interface
  (Who talked to what, from where, when)
```

## Enabling Detective

```bash
# Enable in master account
aws detective enable --account-id 123456789012

# Accept membership invitation from member account
aws detective create-members \
  --account-ids 123456789012 \
  --email-addresses alice@example.com

# Enable for organization (auto-enrolls all accounts)
aws detective enable-organization-configuration \
  --auto-enable
```

## Investigation Workflow

### Step 1: Start from a Finding

When GuardDuty generates a HIGH severity finding (e.g., `UnauthorizedAccess:IAMUser/ConsoleLogin`), open it in Detective.

### Step 2: Explore the Graph

Detective shows:
- **Who** — IAM user, role, or service that performed the action
- **What** — Which API was called, with what parameters
- **Where** — Source IP, geographic location
- **When** — Timeline of events

### Step 3: See Related Activity

```
Graph visualization:
  Alice (IAM User)
    │
    ├──► 203.0.113.10 (Source IP)
    │         │
    │         ├──► ConsoleLogin (SUCCESS)
    │         ├──► GetSecretValue (Secrets Manager)
    │         └──► DescribeInstances (EC2)
    │
    └──► my-ec2-instance (EC2)
              │
              ├──► 10.0.1.100 (Internal IP)
              └──► Port 22 (SSH from external)
```

## Finding Types Analyzed

| Finding | What Detective Shows |
|---------|---------------------|
| IAMUser/ConsoleLogin | Timeline, source IP, geo-location, subsequent API calls |
| EC2/compromisedInstance | Network activity, processes, DNS queries, outgoing connections |
| S3/data-exfiltration | Access patterns, data transfers, bucket policies |
| Crypto-mining | Network activity, unusual processes, CPU spike correlation |

## Using the Console

```
Detective Console:
  │
  ├── Investigation Profile
  │     ├── Entity (IP, User, Resource)
  │     ├── Activity Profile (what did it do?)
  │     └── Risk Score (is this suspicious?)
  │
  ├── Timeline View
  │     └── All events in chronological order
  │
  ├── Graph View
  │     ├── Visual relationship map
  │     └── Click to expand entities
  │
  └── Related Findings
        └── Other GuardDuty findings involving the same entity
```

## Pricing

| Component | Cost |
|-----------|------|
| Per GB of data ingested | $0.10/GB |
| Data retained (30-90 days) | Included |
| Data retained (91-365 days) | $0.05/GB |

First 10GB/month free per account.

## Limits

| Resource | Limit |
|----------|-------|
| Member accounts per master | 50 |
| Data retention | 365 days |
| Max investigation time | Unlimited |

## References

- **Homepage:** https://aws.amazon.com/detective/
- **Documentation:** https://docs.aws.amazon.com/detective/
- **Pricing:** https://aws.amazon.com/detective/pricing/

## Nuggets & Gotchas

- **Detective only shows data AFTER it's enabled — it can't look into the past:** Unlike CloudTrail (90-day history) or Security Hub (90-day findings), Detective only has data from when it was enabled. Enable it early in your security journey.
- **Detective ingests a LOT of data — expect significant costs at scale:** CloudTrail + VPC Flow + GuardDuty findings for a busy account can be 10GB+/day. At $0.10/GB, that's $900/month for data ingestion alone.
- **Detective is for investigation, not prevention — it doesn't block or remediate:** Use GuardDuty + EventBridge for automated response. Detective is the "what happened?" tool after GuardDuty flags something.
- **Detective membership must be accepted in the member account — the master can't auto-enroll without consent:** Each member account gets an invitation email. For organization-wide setup, use `enable-organization-configuration` for auto-enrollment.