---
title: AWS Security
tags: [security, aws, cloud, security-hub, guardduty, cloudtrail]
date: 2025-05-24
description: AWS security tooling - Security Hub, GuardDuty, CloudTrail, SCPs, multi-account monitoring with Wazuh
---

# AWS Security ☁️🔐

AWS-native security services and your multi-account monitoring setup.

## Core Services

| Service | Purpose | Your Use |
|---------|---------|----------|
| **Security Hub** | Centralize findings across AWS services | Aggregates GuardDuty, Config, Inspector |
| **GuardDuty** | Threat detection (malware, cryptomining, credential access) | Your 40+ account org |
| **CloudTrail** | API activity audit log | Agentless → S3 → Wazuh |
| **Config** | Resource inventory and compliance | SCP evaluation |
| **Inspector** | Vulnerability scanning (EC2, ECR, lambda) | Part of Security Hub |
| **IAM Access Analyzer** | Find externally accessible resources | Regular audits |

## Multi-Account Architecture

```
AWS Org (Master)
  ├── Security Tooling Account
  │     ├── GuardDuty delegated admin
  │     ├── Security Hub aggregated
  │     └── CloudTrail centralized
  │
  └── 40+ Member Accounts
        ├── GuardDuty findings → Security Tooling Account
        ├── CloudTrail → S3 → Wazuh (agentless)
        └── Config → S3 → Wazuh
```

## Service Control Policies (SCPs)

SCPs enforce guardrails at the organizational level:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyPublicAccessToS3",
    "Effect": "Deny",
    "Action": ["s3:*"],
    "Resource": ["arn:aws:s3:::*"],
    "Condition": {
      "Bool": {"aws:ViaAWSService": "false"}
    }
  }]
}
```

## Wazuh Agentless for AWS

```bash
# CloudTrail agentless collection
<ossec_config>
  <agentless>
    <entry name="aws-org">
      <type>aws</type>
      <aws_region>us-east-1</aws_region>
      <iam_role_arn>arn:aws:iam::123456789012:role/WazuhCloudTrailReader</iam_role_arn>
      <s3_bucket_name>my-org-cloudtrail-logs</s3_bucket_name>
      <s3_prefix>AWSLogs/</s3_prefix>
    </entry>
  </agentless>
</ossec_config>
```

## Related

- [[Security/cloud-security/README|Cloud Security Hub]]
- [[Security/siem/wazuh/README|Wazuh]]