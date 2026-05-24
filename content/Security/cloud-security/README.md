---
title: Cloud Security
tags: [security, cloud, aws, azure, gcp]
date: 2025-05-24
description: Cloud security across AWS, Azure, and GCP - cloud-native security tools, configurations, and best practices for multi-account environments
---

# Cloud Security

Security coverage for multi-cloud environments — AWS, Azure, and GCP. Focuses on cloud-native tooling, identity management, logging, and network security.

## Sections

### AWS Security
- [[Security/cloud-security/aws/README|AWS Security Hub]] — Security Hub, GuardDuty, CloudTrail, IAM, multi-account strategies, SCPs, incident response

### Azure Security
- [[Security/cloud-security/azure/README|Azure Security Hub]] — Defender for Cloud, Entra ID, Azure policies, Azure Arc

### GCP Security
- [[Security/cloud-security/gcp/README|GCP Security Hub]] — Security Command Center, IAM, Chronicle

## Shared Cloud Security Principles

### 1. Identity as the Perimeter
Cloud IAM is primary access control. Every API call is an identity.

```bash
# AWS: Least privilege IAM role example
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:GetObject"],
    "Resource": "arn:aws:s3:::my-bucket/*",
    "Condition": {
      "IpAddress": {"aws:SourceIp": "10.0.0.0/8"}
    }
  }]
}
```

### 2. Logging as the Foundation
Enable cloud-native logging before anything else.

```bash
# AWS: Enable CloudTrail in all accounts via AWS Org
aws cloudtrail create-trail \
  --name org-trail \
  --is-organization-trail \
  --s3-bucket-name my-trail-bucket \
  --is-multi-region-trail

# Azure: Enable Azure Activity Log
az monitor activity-log alert create \
  --name "Security Alert" \
  --resource-group my-rg
```

### 3. Network Segmentation
VPCs, security groups, NSGs, firewall rules.

```bash
# AWS: Security group with least privilege
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxx \
  --protocol tcp \
  --port 443 \
  --cidr 10.0.0.0/8
```

### 4. Encryption
At rest (KMS), in transit (TLS), key management.

```bash
# AWS: S3 SSE-KMS encryption
aws s3api put-bucket-encryption \
  --bucket my-bucket \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms","KMSMasterKeyID":"key-id"}}]}'
```

## Multi-Account Security Strategy

For your 40+ AWS accounts:

1. **AWS Organizations** — Centralize logging and SCPs
2. **Security Hub** — Aggregate findings across all accounts
3. **GuardDuty** — Threat detection in every account
4. **CloudTrail** — API activity in every account
5. **SCP** — Prevent risky actions org-wide

```
Root (Master Account)
  │
  ├── Security Account
  │     ├── Security Hub aggregator
  │     ├── GuardDuty master
  │     └── CloudTrail log aggregation
  │
  ├── Prod OU
  │     ├── Account 1 (Security Hub member)
  │     ├── Account 2
  │     └── SCP: deny risky actions
  │
  └── Dev OU
        ├── Account N
        └── SCP: allow dev resources only
```

## Related

- [[Security/siem/README|SIEM]] — Cloud log aggregation via Wazuh
- [[Security/incident-response/README|Incident Response]] — Cloud incident response
- [[Security/kubernetes-security/README|Kubernetes Security]] — EKS security