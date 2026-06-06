---
title: Migration Evaluator
description: AWS Migration Evaluator — generates TCO reports and right-sizing recommendations for AWS migration, assessment creation, and data collection methods
tags:
  - aws
  - migration
---

# Migration Evaluator

Migration Evaluator (formerly TSO Logic) is an assessment tool that analyzes your on-premises environment and generates a Total Cost of Ownership (TCO) comparison with AWS. It helps build the business case for migration by showing cost savings over time.

## What It Provides

- **Current state inventory:** Servers, utilization, workloads
- **AWS recommendation per server:** Instance type, storage, estimated monthly cost
- **3-year TCO comparison:** On-premises cost vs AWS cost over 3 years
- **Migration strategy per server:** Rehost (MGN), replatform (RDS), refactor (Lambda)
- **Right-sizing recommendations:** Based on actual utilization, not over-provisioned specs

## Core Concepts

### Assessment

An assessment is a collection of on-premises data analyzed to generate migration recommendations. Assessments can be created from:

- **Agentless collector:** A lightweight VM deployed in your environment that scans VMware
- **AWS Agentless Discovery Connector:** The same collector, installed via OVA/VMWare template
- **Import data:** CSV/JSON import from existing CMDB or discovery tools

### Data Collection

```bash
# Create an assessment (via console or CLI)
aws migrationevaluator create-assessment \
  --name "prod-environment-assessment" \
  --s3-bucket-config '{
    "Bucket": "my-assessments-bucket",
    "KeyPrefix": "assessments/prod/",
    "ServiceRoleArn": "arn:aws:iam::123456789012:role/MigrationEvaluatorRole"
  }'

# Download the collector OVA from Migration Evaluator console
# Deploy in VMware, configure with your AWS credentials
# Collector scans VMware and uploads data to S3

# Import data from existing CMDB
aws migrationevaluator import-data \
  --data-source "CMDB" \
  --s3-bucket "my-assessments-bucket" \
  --s3-key "import/server-inventory.csv"
```

### Collector Deployment

The agentless collector is a VMware VM that:
1. Connects to your vCenter
2. Discovers all VMs and their resource utilization
3. Collects performance metrics over a period (typically 2-4 weeks)
4. Uploads anonymized data to your S3 bucket
5. Migration Evaluator processes the data and generates the TCO report

**Deployment steps:**
1. Download OVA from Migration Evaluator console
2. Deploy in VMware (2 vCPU, 4GB RAM)
3. Configure vCenter credentials
4. Configure S3 bucket for data upload
5. Configure AWS credentials (for uploading data)
6. Let it run for 2-4 weeks to capture realistic utilization patterns

## TCO Report Contents

### Server-Level Recommendations

For each discovered server, the report provides:

```
Server: web-prod-01
  Current specs: 4 vCPU, 16GB RAM, 500GB SSD
  Avg utilization: 35% CPU, 8GB RAM used
  →
  AWS recommendation: t3.medium ($0.041/hr = ~$30/month)
  Storage: gp3 500GB ($50/month)
  Total AWS: ~$80/month vs on-prem: ~$200/month (amortized hardware)
```

### Right-Sizing Logic

Migration Evaluator right-sizes based on **actual utilization**, not raw specs:
- A server with 4 vCPU specs but 10% average utilization → recommended t3.small
- A server with 16GB RAM specs but 8GB used → recommended instance type with 16GB

This avoids the common mistake of migrating a 4-socket monster to a 4xlarge EC2 when it's actually using resources of a medium instance.

### Migration Strategy Classification

Each server gets classified into one of the 6 Rs:

- **Rehost:** Lift-and-shift via MGN. For servers where refactoring cost > migration cost.
- **Replatform:** Minor changes (e.g., migrate to RDS, move to EFS). For database servers.
- **Refactor:** Re-architect to managed services. For apps where cloud-native fits better.
- **Retire:** Decommission instead of migrate. For underutilized or redundant servers.
- **Retain:** Keep on-premises for now. For regulatory or strategic reasons.
- **Repurchase:** Move to SaaS. For standard software with SaaS equivalents.

## Assessment Types

### Initial Assessment (no agent)

Quick assessment based on VMware inventory data without deep performance metrics:
- Lower cost, faster to complete
- Less accurate utilization data (uses spec vs actual)
- Good for initial business case and rough estimates

### Agent-Based Assessment

Deploy collector agents on servers for accurate performance data:
- More accurate utilization metrics (CPU, memory, disk over time)
- Process-level visibility (which processes are running)
- Network dependency mapping
- Recommended for production migration planning

### Import Assessment

Import data from existing tools:
- CMDB exports (ServiceNow, BMC, etc.)
- Cloudhealth or other cloud management platforms
- Azure Migrate assessments
- Google Cloud assessments

## Business Case Report

The TCO report generates a 3-year cost comparison:

```
3-Year TCO Comparison:
  On-premises: $1.2M (hardware, power, cooling, staff, maintenance)
  AWS: $680K (EC2, storage, networking, data transfer, staff savings)
  Net savings: $520K over 3 years (~43% reduction)

Annual breakdown:
  Year 1: -$180K (migration costs offset initial savings)
  Year 2: +$220K savings
  Year 3: +$280K savings
```

## Integration with Migration Hub

Migration Evaluator exports recommendations to Migration Hub:

```bash
# Export assessment to Migration Hub
aws migrationevaluator export-assessment \
  --assessment-id assess-1234567890abcdef0 \
  --export-format MIGRATION_HUB

# In Migration Hub, the exported servers appear as applications
# You can then use MGN to migrate them
```

This lets you go from assessment → planning → execution using AWS native tools.

## Cost

- **Migration Evaluator itself:** Free for data collection and assessment generation
- **Agentless collector:** Runs as a small VM (no AWS charge for the collector itself)
- **S3 costs:** For storing assessment data (minimal, < 1GB per assessment)

## Limitations

- **VMware only** for agentless collection (no Hyper-V, physical, or other hypervisors)
- **Utilization data:** Best accuracy requires 2-4 weeks of collection
- **Not real-time:** Assessment is a point-in-time analysis, not ongoing monitoring
- **Estimates, not contracts:** AWS pricing in the report is indicative, not guaranteed pricing

## When to Use

### Use Migration Evaluator when:
- Building a business case for migration to present to leadership
- Trying to understand how much you could save
- Right-sizing before migration (avoid over-provisioning AWS resources)
- Planning a large-scale migration and need to prioritize

### Don't use for:
- Day-to-day cost optimization of existing AWS environment (use Cost Explorer)
- Real-time monitoring (CloudWatch is better)
- Detailed migration execution (use MGN, DMS, DataSync for that)