---
title: AWS IAM
description: AWS IAM — identity and access management. Users, groups, roles, policies (JSON), identity federation, SCPs, permission boundaries, service control policies, and AWS SSO.
tags:
  - aws
  - security
  - iam
---

# AWS IAM (Identity and Access Management)

IAM is the foundation of AWS security — it controls WHO can access WHAT resources. Every AWS action is authorized by IAM (unless the resource policy allows anonymous access).

## Core Concepts

### Users, Groups, Roles

| Entity | Purpose | Credential Type |
|--------|---------|----------------|
| IAM User | Long-term credentials for humans | Access keys, passwords, MFA |
| IAM Group | Collection of users with shared permissions | N/A (groups don't have credentials) |
| IAM Role | Temporary credentials for services/users | No long-term credentials — assume role |
| Service Role | Role used by an AWS service | EC2, Lambda, etc. |

### Access Types

```
Programmatic access (API/CLI)
  → Access Key ID + Secret Access Key (long-term, rotatable)

Console access
  → Username + Password + MFA (long-term)

Role-based access (temporary)
  → STS AssumeRole → Temporary credentials (1-12 hours)
```

## JSON Policy Structure

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",          // Allow or Deny
      "Action": [                  // Which actions
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": [                // Which resources
        "arn:aws:s3:::my-bucket/*"
      ],
      "Condition": {               // Optional conditions
        "IpAddress": {
          "aws:SourceIp": "203.0.113.0/24"
        }
      }
    }
  ]
}
```

### Wildcards in Actions

```json
"Action": [
  "s3:*"                    // All S3 actions
  "s3:Get*"                 // All S3 GET actions
  "iam:PassRole"            // Specific action
  "logs:DescribeLogGroups"   // Describe (not list)
  "logs:*LogGroup*"          // Any action with LogGroup in name
]
```

## Creating Users and Groups

```bash
# Create user
aws iam create-user --user-name alice

# Create group
aws iam create-group --group-name developers

# Add user to group
aws iam add-user-to-group --user-name alice --group-name developers

# Create login profile (console access)
aws iam create-login-profile \
  --user-name alice \
  --password 'MySecurePassword123!' \
  --password-reset-required

# Enable MFA
aws iam create-virtual-mfa-device \
  --virtual-mfa-device-name alice-mfa \
  --outfile ./qr.png
```

## Creating Policies

### Inline Policy

```bash
aws iam put-user-policy \
  --user-name alice \
  --policy-name allow-s3-read \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::my-bucket/*"
    }]
  }'
```

### Managed Policy

```bash
aws iam create-policy \
  --policy-name allow-s3-read \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::my-bucket/*"
    }]
  }'

# Attach to group
aws iam attach-group-policy \
  --group-name developers \
  --policy-arn arn:aws:iam::123456789012:policy/allow-s3-read
```

## IAM Roles

### Trust Policy (who can assume the role)

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": "ec2.amazonaws.com"
    },
    "Action": "sts:AssumeRole"
  }]
}
```

### Creating a Role

```bash
# Create role for EC2
aws iam create-role \
  --role-name ec2-s3-read \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ec2.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# Attach managed policy
aws iam attach-role-policy \
  --role-name ec2-s3-read \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
```

### Instance Profile (EC2)

```bash
# Create instance profile
aws iam create-instance-profile --instance-profile-name my-ec2-role

# Add role to instance profile
aws iam add-role-to-instance-profile \
  --instance-profile-name my-ec2-role \
  --role-name ec2-s3-read

# Attach to EC2 instance
aws ec2 run-instances \
  --iam-instance-profile '{"Name": "my-ec2-role"}'
```

## Cross-Account Access

### Trusting Account (Account B grants Account A access)

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"AWS": "arn:aws:iam::111122223333:root"},
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": {"aws:RequestedRegion": ["us-east-1", "us-west-2"]}
    }
  }]
}
```

```bash
# In Account A (assume the role)
aws sts assume-role \
  --role-arn arn:aws:iam::111122223333:role/cross-account-access \
  --role-session-name alice-prod-access

# Returns: AccessKeyId, SecretAccessKey, SessionToken
# Use these to access Account B resources
```

## Service Control Policies (SCPs)

SCPs are applied at the Organization or OU level:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Deny",
    "Action": [
      "s3:PutBucketPublicAccessBlock",
      "iam:CreateUser",
      "iam:DeleteUser"
    ],
    "Resource": "*"
  }]
}
```

SCP blocks all accounts in the OU from:
- Disabling public access blocks
- Creating IAM users

## Permission Boundaries

Limit what a role/user can do, even if other policies grant more:

```bash
# Create a permissions boundary
aws iam create-policy \
  --policy-name developer-boundary \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["s3:*", "ec2:Describe*"],
      "Resource": "*"
    }]
  }'

# Attach boundary to user
aws iam put-user-permissions-boundary \
  --user-name alice \
  --permissions-boundary arn:aws:iam::123456789012:policy/developer-boundary
```

Even if Alice has a policy allowing `*`, the boundary limits her to S3 + EC2 Describe only.

## Access Advisor

```bash
# See what permissions a user has used
aws iam generate-credential-report
aws iam get-credential-report

# See service last accessed
aws iam list-policies-granting-service-access \
  --arn arn:aws:iam::123456789012:user/alice \
  --service-namespaces s3
```

## AWS SSO

```bash
# Configure SSO (AWS IAM Identity Center)
aws sso-admin list-permission-sets \
  --instance-arn arn:aws:sso:::instance/ssoins-xxxxx

# Assign access
aws sso-admin create-permission-set \
  --name DeveloperAccess \
  --instance-arn arn:aws:sso:::instance/ssoins-xxxxx \
  --permission-set '{
    "SessionDuration": "PT8H",
    "Policies": {"AWSManaged": "arn:aws:iam::aws:policy/ReadOnlyAccess"}
  }'
```

## Security Best Practices

| Practice | Description |
|----------|-------------|
| Enable MFA | On root account and all users |
| Use roles | Don't share access keys |
| Least privilege | Grant minimum permissions needed |
| Rotate credentials | Access keys every 90 days |
| Use groups | Assign permissions to groups, not users |
| Regular audits | Use Access Advisor to remove unused permissions |
| No root | Use root only for initial setup |
| SCPs | Apply at Organization level for guardrails |

## Limits

| Resource | Limit |
|----------|-------|
| Users per account | 5000 |
| Groups per user | 10 |
| Roles per account | 1000 |
| Policies per role | 10 |
| Policy size | 6,144 characters (IAM), 5,120 (service role) |
| Attached policies per entity | 10 (managed) |

## References

- **Homepage:** https://aws.amazon.com/iam/
- **Documentation:** https://docs.aws.amazon.com/IAM/
- **Pricing:** https://aws.amazon.com/iam/pricing/

## Pricing Examples

**Scenario 1:** An organization with 100 developers, each needing S3 + EC2 read access. Without groups: 100 inline policies. With groups: 1 group with 1 managed policy = $0 + $0. Groups save management overhead and are free.

**Scenario 2:** A cross-account access pattern where Account A (dev) needs read access to Account B (prod) S3. Option 1: IAM user in B with access key. Option 2: Role in B, STS assume from A. Role + STS is more secure (no long-term credentials), recommended. STS assume role cost: $0.00 (first 1000/day), $0.0000012/after.

## Nuggets & Gotchas

- **IAM roles don't have passwords — you can't "log in" to a role:** Users log in with IAM users or SSO. Roles are assumed via STS (programmatic or via web login). If you see "login to role" — that's STS federation, not a traditional login.
- **An explicit DENY always wins — Deny > Allow regardless of other policies:** If you have `Allow *` in one policy and `Deny s3:*` in another, the Deny wins. Deny is final.
- **IAM policy wildcards in Resource are evaluated strictly — `Resource: "arn:aws:s3:::bucket/*"` doesn't include bucket-level actions:** You need `Resource: "arn:aws:s3:::bucket"` for `s3:ListBucket`, and `Resource: "arn:aws:s3:::bucket/*"` for `s3:GetObject`.
- **Service-linked roles are pre-created by AWS — you can't delete them:** Roles like `AWSServiceRoleForAutoScaling` are managed by AWS. If you delete the service, the role is deleted automatically.
- **IAM Access Analyzer doesn't analyze inline policies — only managed policies attached to resources:** If you use inline policies extensively, Access Analyzer won't flag overly permissive rules. Consider converting inline policies to managed policies for better visibility.