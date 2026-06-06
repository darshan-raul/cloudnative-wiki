---
title: AWS Inspector
description: AWS Inspector — automated vulnerability scanning for EC2, ECR, and Lambda. Network reachability, CVE scanning, CIS benchmarks, security assessments, and findings integration with Security Hub.
tags:
  - aws
  - security
  - inspector
---

# AWS Inspector

Inspector scans EC2 instances, container images in ECR, and Lambda functions for software vulnerabilities and network exposure. It integrates with Security Hub for centralized findings.

## What Inspector Scans

```
Inspector scans:
  │
  ├── EC2 Instances
  │   ├── Network Reachability (ports open to internet?)
  │   ├── Agent-based scans (requires SSM agent)
  │   └── CVE vulnerabilities in packages
  │
  ├── ECR Container Images
  │   └── Image scanning (CVE, OS packages, dependencies)
  │
  └── Lambda Functions
      └── Package vulnerabilities in Lambda layers and deployment package
```

## Inspector vs GuardDuty vs Macie

| Service | What it Detects | How |
|---------|-----------------|-----|
| GuardDuty | Threats (compromised credentials, crypto mining, data exfiltration) | ML on CloudTrail/DNS/VPC Flow |
| Inspector | Vulnerabilities (CVEs, missing patches, network exposure) | Agent + network probes |
| Macie | Sensitive data exposure (PII, credentials in S3) | ML on S3 data classification |

## Enabling Inspector

```bash
# Enable Inspector (requires SSM for EC2 agent scans)
aws inspector2 enable \
  --account-ids 123456789012

# Enable ECR scanning
aws inspector2 enable \
  --resource-types ECR

# Enable Lambda scanning
aws inspector2 enable \
  --resource-types LAMBDA

# Enable all
aws inspector2 enable \
  --resource-types EC2 ECR LAMBDA
```

## SSM Agent for EC2

Inspector uses the SSM agent for deep package scanning:

```bash
# Check if SSM agent is running on EC2
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=i-xxxxx"

# Install SSM agent (if missing)
aws ssm send-command \
  --instance-ids i-xxxxx \
  --document-name AWS-ConfigureAWSPackage \
  --parameters '{"action": ["Install"], "packageName": ["AmazonCloudWatchAgent"]}'
```

## Creating Assessment Targets

```bash
# Create a target (EC2 instances with tag)
aws inspector2 create-filter \
  --filter-action FINDINGS \
  --filter-criteria '{
    "resourceTags": [{"compare": "EQUALS", "key": "Environment", "value": "production"}]
  }'
```

## Assessment Templates

```bash
# Create template (Inspector v1 - deprecated)
aws inspector create-assessment-template \
  --assessment-target-arn arn:aws:inspector:us-east-1:123456789012:target/0-xxxxx \
  --template-name "weekly-ec2-scan" \
  --duration-in-seconds 3600 \
  --rules-package-arns "arn:aws:inspector:us-east-1:758058086616:rulespackage/0-xxxxx"
```

Inspector v2 doesn't use templates — it continuously scans all enabled resources.

## Viewing Findings

```bash
# List findings
aws inspector2 list-findings \
  --filter-criteria '{
    "severity": [{"comparison": "EQUALS", "value": "HIGH"}],
    "resourceType": [{"comparison": "EQUALS", "value": "AWS_EC2_INSTANCE"}]
  }'

# Get finding details
aws inspector2 describe-findings \
  --finding-arns arn:aws:inspector2:us-east-1:123456789012:findings/i-xxxxx
```

### Finding Example

```json
{
  "findingArn": "arn:aws:inspector2:us-east-1:123456789012:findings/i-xxxxx",
  "findingType": "PACKAGE_VULNERABILITY",
  "severity": "HIGH",
  "title": "CVE-2023-44487 - HTTP/2 Rapid Reset Attack (Apache HTTP Server)",
  "description": "The Apache HTTP Server project identified a vulnerability...",
  "resource": {
    "resourceId": "i-xxxxx",
    "type": "AWS_EC2_INSTANCE",
    "details": {
      "awsEc2Instance": {
        "amiId": "ami-xxxxx",
        "instanceId": "i-xxxxx",
        "tags": {"Name": "web-server-01"}
      }
    }
  },
  "vulnerability": {
    "cvss": [{"version": "V3", "score": 7.5, "baseScore": 7.5}],
    "relatedVulnerabilities": ["CVE-2023-44487"],
    "packageVulnerabilityDetails": {
      "packagePath": "lib/httpd",
      "packageVersion": "2.4.6",
      "fixedInVersion": "2.4.7"
    }
  }
}
```

## Network Reachability Findings

```json
{
  "findingType": "NETWORK_REACHABILITY",
  "title": "Port 22 is open to the internet",
  "severity": "MEDIUM",
  "description": "EC2 instance i-xxxxx has port 22 (SSH) accessible from 0.0.0.0/0",
  "networkReachability": {
    "openPortRange": {"begin": 22, "end": 22},
    "protocol": "TCP",
    "source": "0.0.0.0/0"
  }
}
```

## ECR Image Scanning

```bash
# Enable enhanced scanning (Inspector v2)
aws ecr put-image-scanning-configuration \
  --registry-id 123456789012 \
  --image-scanning-configuration '{
    "scanType": "ENHANCED",
    "rules": [{"scanFrequency": "CONTINUOUS_SCAN"}]
  }'

# Trigger manual scan
aws ecr start-image-scan \
  --repository-name my-repo \
  --image-digest sha256:xxxxx

# Get scan results
aws ecr describe-image-scan-findings \
  --registry-id 123456789012 \
  --repository-name my-repo \
  --image-digest sha256:xxxxx
```

## Lambda Scanning

```bash
# Inspector v2 automatically scans Lambda functions
# No manual scan needed

# List Lambda findings
aws inspector2 list-findings \
  --filter-criteria '{
    "resourceType": [{"comparison": "EQUALS", "value": "AWS_LAMBDA_FUNCTION"}]
  }'
```

## Pricing

| Resource Type | Cost |
|---------------|------|
| EC2 instance (per month) | $0.06 per instance |
| ECR image (per month) | $0.09 per image |
| Lambda function (per month) | $0.06 per function |
| Lambda layer (per month) | $0.006 per layer |

First 500 resources/month are free.

## Limits

| Resource | Limit |
|----------|-------|
| EC2 instances per account | Unlimited |
| ECR images per registry | 10,000 |
| Assessment runs (v1) | 500 per template |
| Concurrent scans | 500 (EC2), unlimited (ECR/Lambda) |

## References

- **Homepage:** https://aws.amazon.com/inspector/
- **Documentation:** https://docs.aws.amazon.com/inspector/
- **Pricing:** https://aws.amazon.com/inspector/pricing/

## Pricing Examples

**Scenario 1:** A fleet of 100 EC2 instances, 50 ECR images, 30 Lambda functions. EC2: 100 × $0.06 = $6/month. ECR: 50 × $0.09 = $4.50/month. Lambda: 30 × $0.06 = $1.80/month. Total: $12.30/month.

**Scenario 2:** A small startup with 10 EC2 instances, 5 ECR images, 5 Lambda functions. First 500 resources free. All resources within free tier = $0/month. Inspector is effectively free for small environments.

## Nuggets & Gotchas

- **Inspector requires SSM agent for deep EC2 package scans — without SSM agent, you only get network reachability:** If your EC2 instances don't have SSM agent running, Inspector can't scan for CVE vulnerabilities. Install SSM agent via AMI or user data.
- **Inspector v2 scans continuously — there's no manual "run scan" button like v1:** Inspector v2 (current) doesn't use assessment templates. It automatically scans all enabled resources continuously. New vulnerabilities are detected within 24-48 hours of CVE publication.
- **ECR enhanced scanning uses Inspector (not ECR's basic scan) and costs $0.09/image/month:** Basic ECR scanning (CVEs only, no Lambda dependencies) is free. Enhanced scanning (full dependency analysis) uses Inspector and costs money. Know which you're using.
- **Inspector findings don't auto-remediate — you need EventBridge + SSM for that:** Inspector identifies vulnerabilities but doesn't patch them. Build a pipeline: Inspector findings → Security Hub → EventBridge → SSM Patch Manager.
- **Lambda layer vulnerabilities are scanned separately from function code:** If your Lambda uses layers, both the function code AND each layer are scanned. A vulnerable layer = a finding on your function.