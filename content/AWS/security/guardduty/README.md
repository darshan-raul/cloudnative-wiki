---
title: AWS GuardDuty
description: AWS GuardDuty — intelligent threat detection. CloudTrail, DNS, VPC Flow, S3, EKS, and malware protection. Findings, severity levels, automated remediation, and GuardDuty Enterprise.
tags:
  - aws
  - security
  - guardduty
---

# AWS GuardDuty

GuardDuty is an intelligent threat detection service that continuously analyzes AWS logs (CloudTrail, DNS, VPC Flow Logs, S3, EKS) using machine learning to identify suspicious activity.

## Data Sources

```
GuardDuty analyzes:
  │
  ├── CloudTrail Management Events — API calls (who did what)
  ├── CloudTrail S3 Data Events — S3 object operations
  ├── VPC Flow Logs — network traffic (who talked to whom)
  ├── DNS Logs — DNS queries from within VPC
  ├── EKS Audit Logs — Kubernetes API activity
  └── RDS Login Activity — database login attempts (Aurora, RDS)
```

## Findings

### Severity Levels

| Severity | Score | Example |
|----------|-------|---------|
| HIGH | 7.0-8.9 | Cryptocurrency mining, data exfiltration |
| MEDIUM | 4.0-6.9 | Compromised IAM user, unusual API call |
| LOW | 1.0-3.9 | Policy change, root login |

### Finding Types

```
Discovery:
  - ReconnaissanceDiscovery — unusual enumeration activity

Compromise:
  - IAMUser/CompromisedCredentials — leaked access keys
  - EC2/ compromisedInstance — EC2 instance compromised
  - Container/compromisedWorkload — Kubernetes compromise

Exfiltration:
  - Data exfiltration via S3 or DNS
  - Large S3 data transfer

Cryptocurrency:
  - EC2/CryptocurrencyExecution — crypto mining
  - Container/CryptocurrencyExecution — crypto in containers
```

### Finding Example

```json
{
  "AccountId": "123456789012",
  "Partition": "aws",
  "Region": "us-east-1",
  "Type": "UnauthorizedAccess:IAMUser/ConsoleLogin",
  "Severity": {
    "Score": 7.5,
    "Label": "HIGH"
  },
  "Title": "Root user sign-in from a new IP address.",
  "Description": "A root user console login from a new IP address was detected.",
  "Resources": [{
    "AccountId": "123456789012",
    "Type": "AwsIamUser",
    "IamUserArn": "arn:aws:iam::123456789012:root"
  }],
  "Service": {
    "Action": {
      "ConsoleLoginAction": {
        "ActionType": "REMOTE_LOGIN"
      }
    },
    "Actor": {
      "RemoteIpDetails": {
        "IpAddressV4": "203.0.113.10",
        "Country": {"Name": "Russia"},
        "City": {"Name": "Moscow"}
      }
    },
    "LastSeen": "2024-01-15T10:30:00Z"
  }
}
```

## Enabling GuardDuty

```bash
# Enable GuardDuty
aws guardduty enable-detector \
  --region us-east-1 \
  --finding-publishing-frequency ONE_HOUR  # or FIFTEEN_MINUTES, ONE_HOUR, SIX_HOURS

# Enable S3 protection (logs S3 data events)
aws guardduty update-detector \
  --detector-id xxxxx \
  --enable \
  --finding-publishing-frequency ONE_HOUR \
  --data-sources '{
    "S3Logs": {"Enable": true}
  }'

# Enable EKS protection
aws guardduty update-detector \
  --detector-id xxxxx \
  --data-sources '{
    "EKSAuditLogs": {"Enable": true}
  }'
```

## Managing Findings

```bash
# List findings
aws guardduty list-findings \
  --detector-id xxxxx \
  --finding-criteria '{
    "Criterion": {
      "severity": {"Eq": ["HIGH"]},
      "service.archived": {"Eq": ["false"]}
    }
  }'

# Get finding details
aws guardduty get-findings \
  --detector-id xxxxx \
  --finding-ids xxxxx-xxxxx-xxxxx

# Archive finding (when false positive)
aws guardduty archive-findings \
  --detector-id xxxxx \
  --finding-ids xxxxx-xxxxx-xxxxx
```

## Automated Response with EventBridge

```bash
# Create EventBridge rule
aws events put-rule \
  --name guardduty-high-severity \
  --event-pattern '{
    "source": ["aws.guardduty"],
    "detail": {
      "severity": [{"numeric": [">=", 7]}]
    }
  }'

# Add Lambda target
aws events put-targets \
  --rule guardduty-high-severity \
  --targets '[{
    "Id": "my-lambda",
    "Arn": "arn:aws:lambda:us-east-1:123456789012:function:guardduty-response"
  }]'
```

### Example Response Lambda

```python
import boto3

def lambda_handler(event, context):
    finding = event['detail']
    finding_type = finding['type']
    actor_ip = finding['service']['actor']['remoteIpDetails']['ipAddressV4']
    
    # Block IP in security group
    ec2 = boto3.client('ec2')
    
    # Create SG rule to block
    ec2.authorize_security_group_ingress(
        GroupId='sg-xxxxx',
        IpProtocol='tcp',
        FromPort=443,
        ToPort=443,
        CidrIp=f"{actor_ip}/32"
    )
    
    # Notify security team
    sns = boto3.client('sns')
    sns.publish(
        TopicArn='arn:aws:sns:us-east-1:123456789012:security-alerts',
        Message=f"GuardDuty HIGH: {finding_type} from {actor_ip}"
    )
```

## GuardDuty Enterprise

Add centralized threat detection across all accounts:

```bash
# Enable GuardDuty in master account
aws guardduty enable-organization-configuration \
  --detector-id xxxxx \
  --autoEnable

# Member accounts automatically enrolled
```

## Malware Protection

```bash
# Enable malware protection
aws guardduty update-detector \
  --detector-id xxxxx \
  --data-sources '{
    "MalwareProtection": {
      "ScanEc2InstanceWithFindings": {"Ec2InstanceYam": {"Enable": true}},
      "ServiceRoleArn": "arn:aws:iam::123456789012:role/GuardDuty MalwareProtection"
    }
  }'
```

When GuardDuty detects a compromised EC2 instance, it can initiate a malware scan.

## Monitoring

```bash
# CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/GuardDuty \
  --metric-name FindingCount \
  --dimensions Name=ThreatPurpose,Value=UnauthorizedAccess
```

## Pricing

| Component | Cost |
|-----------|------|
| CloudTrail events analyzed | Free (10M events/month free tier) |
| DNS Logs | $0.60/million DNS queries |
| VPC Flow Logs | $0.75/million flow log entries |
| S3 Data Events | $1.00/million S3 events |
| EKS Audit Logs | $1.00/million EKS audit events |
| Malware Protection (EC2) | $1.00/GB scanned |

## Limits

| Resource | Limit |
|----------|-------|
| Detectors | 1 per region |
| Findings | 1000 per page (list), 50 per batch (get) |
| IP sets | 100 per detector |
| Threat lists | 30 (for threat purposes) |

## References

- **Homepage:** https://aws.amazon.com/guardduty/
- **Documentation:** https://docs.aws.amazon.com/guardduty/
- **Pricing:** https://aws.amazon.com/guardduty/pricing/

## Pricing Examples

**Scenario 1:** A small account (50 users, moderate activity). CloudTrail events: 5M/month. DNS queries: 10M/month × $0.60/M = $6/month. VPC Flow: 100GB/month × $0.75/M = $0.075/month. S3 events: disabled. Total: ~$6/month.

**Scenario 2:** A large enterprise (500 users, heavy activity). CloudTrail events: 100M/month (free). DNS queries: 1B/month × $0.60/M = $600/month. VPC Flow: 10TB/month × $0.75/M = $7.50/month. S3 events: 1B × $1.00/M = $1,000/month. That's $1,607/month — S3 data events are expensive at scale. Disable for non-critical buckets.

## Nuggets & Gotchas

- **GuardDuty is a detection service, not prevention — it doesn't block anything:** GuardDuty identifies threats and generates findings. You must build automated responses (EventBridge + Lambda) or manually respond. Enable GuardDuty + response automation together.
- **S3 data events in GuardDuty ($1/million) can get expensive fast:** Each S3 PUT/GET generates 2 CloudTrail events (control + data). For a busy S3 bucket (1M GETs/day), that's 60M events/month × $1/M = $60/month. Start with just management events + DNS + VPC Flow.
- **GuardDuty findings auto-expire after 90 days — export important findings to S3 or Security Hub:** If you need long-term retention, create an EventBridge rule to capture HIGH severity findings to S3 or SIEM.
- **GuardDuty RDS protection only covers Aurora and RDS (not DocumentDB, Neptune, etc.):** If you use DocumentDB or Neptune, GuardDuty won't log database login attempts for those engines. Use database-native audit logging for those.
- **GuardDuty malware protection requires GuardDuty to have an IAM role that can access EC2 instances — enable via `ServiceRoleArn`:** Without this role, the malware scan won't run even if enabled.