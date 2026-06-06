---
title: AWS Config
description: AWS Config — resource inventory, change tracking, and compliance. Config rules, conformance packs, timeline of resource changes, and multi-account aggregation.
tags:
  - aws
  - security
  - config
---

# AWS Config

Config provides a detailed inventory of all AWS resources and tracks every configuration change over time. It's the foundation for compliance monitoring, security analysis, and change auditing.

## Core Concepts

```
Config records:
  │
  ├── Resource inventory (all resources in account)
  │     ├── EC2 instances (type, AMI, SG, VPC)
  │     ├── S3 buckets (policy, versioning, encryption)
  │     ├── IAM policies (versions, attachments)
  │     └── RDS databases (engine, storage, backup)
  │
  ├── Configuration timeline
  │     └── Every change with who/when/what/old/new
  │
  └── Compliance evaluation
        └── Config rules evaluate resources against desired state
```

## Enabling Config

```bash
# Enable Config (recorder)
aws configservice start-configuration-recorder \
  --configuration-recorder '{
    "name": "default",
    "roleARN": "arn:aws:iam::123456789012:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"
  }'

# Enable delivery channel (S3)
aws configservice put-delivery-channel \
  --delivery-channel '{
    "name": "default",
    "s3BucketName": "my-config-bucket",
    "s3KeyPrefix": "config/",
    "configFileDeliveryFrequency": "One_Hour"
  }'

# Enable global services (IAM, etc.)
aws configservice put-configuration-recorder \
  --configuration-recorder '{
    "name": "default",
    "roleARN": "arn:aws:iam::123456789012:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig",
    "recordingGroup": {
      "allSupported": true,
      "includeGlobalResourceTypes": true
    }
  }'
```

### S3 Bucket Policy for Config

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Service": "config.amazonaws.com"},
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::my-config-bucket/AWSLogs/123456789012/Config/*"
    },
    {
      "Effect": "Allow",
      "Principal": {"Service": "config.amazonaws.com"},
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::my-config-bucket"
    }
  ]
}
```

## Querying Resource Inventory

```bash
# List all EC2 instances
aws configservice select-resource-config \
  --expression "SELECT * WHERE resourceType = 'AWS::EC2::Instance'"

# List all S3 buckets without versioning
aws configservice select-resource-config \
  --expression "SELECT * WHERE resourceType = 'AWS::S3::Bucket' AND configuration.versioningConfiguration.status != 'Enabled'"

# List all security groups with port 22 open to 0.0.0.0/0
aws configservice select-resource-config \
  --expression "SELECT * WHERE resourceType = 'AWS::EC2::SecurityGroup' AND configuration.ipPermissions[?toPort==22].cidrIp CONTAINS '0.0.0.0/0'"
```

## Config Rules

### Managed Rules

```bash
# Enable managed Config rules
aws configservice put-config-rule \
  --config-rule '{
    "ConfigRuleName": "s3-bucket-versioning-enabled",
    "Source": {
      "Owner": "AWS",
      "SourceIdentifier": "S3_BUCKET_VERSIONING_ENABLED"
    },
    "Scope": {
      "ComplianceResourceTypes": ["AWS::S3::Bucket"]
    }
  }'

# Enable encryption rule
aws configservice put-config-rule \
  --config-rule '{
    "ConfigRuleName": "s3-bucket-server-side-encryption-enabled",
    "Source": {
      "Owner": "AWS",
      "SourceIdentifier": "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
    },
    "Scope": {
      "ComplianceResourceTypes": ["AWS::S3::Bucket"]
    }
  }'
```

### Custom Lambda Rules

```python
def lambda_handler(event, context):
    # Invoked by Config rules
    invoking_event = json.loads(event['invokingEvent'])
    configuration_item = invoking_event['configurationItem']
    
    resource_id = configuration_item['resourceId']
    resource_type = configuration_item['resourceType']
    config = configuration_item['configuration']
    
    # Evaluate: check if EC2 instance is encrypted
    if resource_type == 'AWS::EC2::Volume':
        encrypted = config.get('encrypted', False)
        return {
            'compliance_type': 'COMPLIANT' if encrypted else 'NON_COMPLIANT',
            'annotation': 'Volume is encrypted' if encrypted else 'Volume is NOT encrypted'
        }
```

## Conformance Packs

Deploy a collection of Config rules as a single unit:

```yaml
# conformance-pack.yaml
Resources:
  - ConfigRule:
      ConfigRuleName: iam-password-policy
      Source:
        Owner: AWS
        SourceIdentifier: IAM_PASSWORD_POLICY
      InputParameters:
        RequireUppercaseCharacters: true
        RequireLowercaseCharacters: true
        RequireSymbols: true
        RequireNumbers: true
        MinimumPasswordLength: 14

  - ConfigRule:
      ConfigRuleName: ec2-instance-managed-by-systems-manager
      Source:
        Owner: AWS
        SourceIdentifier: EC2_INSTANCE_MANAGED_BY_SSM
```

```bash
# Deploy conformance pack from S3
aws configservice put-conformance-pack \
  --conformance-pack-name operational-best-practices \
  --template-s3-uri s3://my-config-bucket/conformance-packs/operational-best-practices.yaml
```

## Change Timeline

```bash
# Get configuration history for a resource
aws configservice get-resource-config-history \
  --resource-type AWS::EC2::Instance \
  --resource-id i-xxxxx

# Get specific time range
aws configservice get-resource-config-history \
  --resource-type AWS::S3::Bucket \
  --resource-id my-bucket \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-15T00:00:00Z
```

## Multi-Account Aggregation

```bash
# aggregator account: authorize
aws configservice put-aggregation-authorization \
  --authorized-account-id 123456789012

# aggregator account: create aggregator
aws configservice put-config-rule \
  --config-rule '{
    "ConfigRuleName": "multi-account-aggregator",
    "Source": {
      "Owner": "CUSTOM_LAMBDA",
      "SourceIdentifier": "arn:aws:lambda:us-east-1:123456789012:function:aggregator"
    }
  }'
```

## Pricing

| Component | Cost |
|-----------|------|
| Config rules (first 50 rules evaluated) | Free |
| Config rules (additional rules) | $0.001/rule evaluation |
| Conformance packs | Included |
| Configuration history | Free (S3 storage at $0.023/GB) |

## Limits

| Resource | Limit |
|----------|-------|
| Config rules per region | 150 |
| Conformance packs per account | 75 |
| Configuration items per region | 100,000 |
| Aggregators | 50 per account |

## References

- **Homepage:** https://aws.amazon.com/config/
- **Documentation:** https://docs.aws.amazon.com/config/
- **Pricing:** https://aws.amazon.com/config/pricing/

## Nuggets & Gotchas

- **Config records configuration state, not API calls — it's not a replacement for CloudTrail:** Config shows WHAT changed on a resource (security group modified, bucket policy changed). CloudTrail shows WHO made the API call. Use both together.
- **Config's S3 bucket must be in the SAME region as Config recording — cross-region requires aggregator:** If you have Config in us-west-2 writing to an S3 bucket in us-east-1, you need to set up an aggregator and cross-region configuration.
- **Config rule evaluation is triggered by configuration changes — NOT on a schedule by default:** If a resource is already non-compliant and you don't change it, Config won't re-evaluate. Use the `MaximumExecutionFrequency` to evaluate periodically (e.g., daily).
- **Config's `select-resource-config` SQL is limited — no JOINs, no subqueries:** You can query individual resource types but can't correlate across resources (e.g., "find all EC2 instances with SGs that allow port 22"). For that, use Athena with CloudTrail logs.
- **Config recording of global resource types (IAM) requires `includeGlobalResourceTypes: true`:** IAM resources are global. If you don't enable this, IAM changes won't appear in Config.