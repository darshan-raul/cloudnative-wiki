---
title: AWS Secrets Manager
description: AWS Secrets Manager — secrets rotation and management. API keys, passwords, database credentials, Lambda rotation functions, multi-region secrets, and integration with RDS, Redshift, DocumentDB.
tags:
  - aws
  - security
  - secrets-manager
---

# AWS Secrets Manager

Secrets Manager stores and rotates secrets (database credentials, API keys, OAuth tokens) securely. It integrates with RDS, Aurora, Redshift, DocumentDB, and generic secrets, with automatic rotation using Lambda functions.

## Core Concepts

```
Application
  │
  │  API: GetSecretValue
  ▼
Secrets Manager
  │
  ├── Secret: "prod/db-credentials"
  │     ├── Version 1 (old): username=admin, password=oldpass
  │     ├── Version 2 (current): username=admin, password=newpass ★
  │     └── Version 3 (pending): username=admin, password=pending
  │
  └── Rotation Lambda
        (rotates credentials in DB)
```

## Creating a Secret

```bash
# Create a generic secret
aws secretsmanager create-secret \
  --name prod/db-credentials \
  --secret-string '{"username": "admin", "password": "MySecretPassword123!"}' \
  --tags '[{"Key": "Environment", "Value": "production"}]'

# Create with ARN reference
aws secretsmanager create-secret \
  --name prod/api-key \
  --secret-string "sk-xxxxx-xxxxx-xxxxx"
```

## Using Secrets in Applications

### Python (boto3)

```python
import boto3
import json

def get_db_credentials():
    client = boto3.client('secretsmanager')
    response = client.get_secret_value(SecretId='prod/db-credentials')
    
    # For JSON secrets, parse the string
    if 'SecretString' in response:
        return json.loads(response['SecretString'])
    
    # For binary secrets
    return response['SecretBinary']

# Usage
creds = get_db_credentials()
# {'username': 'admin', 'password': 'newpass'}
```

### Java (AWS SDK)

```java
import com.amazonaws.secretsmanager.model.*;
import com.amazonaws.*;

SecretsManagerClient client = SecretsManagerClient.builder().build();

GetSecretValueRequest request = GetSecretValueRequest.builder()
    .secretId("prod/db-credentials")
    .build();

GetSecretValueResponse response = client.getSecretValue(request);
String secret = response.secretString(); // or response.secretBinary()
```

### AWS CLI

```bash
# Get secret value
aws secretsmanager get-secret-value --secret-id prod/db-credentials

# List secrets
aws secretsmanager list-secrets
```

## Automatic Rotation

### Enable Rotation for RDS/Aurora

```bash
# Enable rotation (Secrets Manager creates the Lambda automatically for RDS)
aws secretsmanager rotate-secret \
  --secret-id prod/db-credentials \
  --rotation-lambda-arn arn:aws:lambda:us-east-1:123456789012:function:rotation-function \
  --rotation-rules '{"AutomaticallyAfterDays": 30}'
```

### Rotation for Generic Secrets (Custom Lambda)

```bash
# Create rotation Lambda
aws lambda create-function \
  --function-name my-rotation-function \
  --runtime python3.11 \
  --handler rotation-function.handler \
  --role arn:aws:iam::123456789012:role/rotation-role \
  --zip-file fileb://rotation-function.zip

# Enable rotation with custom Lambda
aws secretsmanager rotate-secret \
  --secret-id prod/api-key \
  --rotation-lambda-arn arn:aws:lambda:us-east-1:123456789012:function:my-rotation-function \
  --rotation-rules '{"AutomaticallyAfterDays": 90}'
```

### Rotation Lambda Template

```python
import json
import boto3
import base64
import os

def handler(event, context):
    """Rotation Lambda for generic secrets."""
    
    secret_arn = event['SecretId']
    step = event['Step']  # createSecret, setSecret, testSecret, finishSecret
    
    client = boto3.client('secretsmanager')
    
    if step == 'createSecret':
        # Generate new secret
        new_password = generate_password()
        client.put_secret_value(
            SecretId=secret_arn,
            SecretString=json.dumps({'password': new_password}),
            VersionStages=['AWSPENDING']
        )
    
    elif step == 'setSecret':
        # Apply new secret to the service (e.g., rotate API key)
        pass  # Custom logic here
    
    elif step == 'testSecret':
        # Verify the new secret works
        pass  # Custom logic here
    
    elif step == 'finishSecret':
        # Mark the new secret as current
        metadata = client.describe_secret(SecretId=secret_arn)
        for version in metadata.get('VersionIdsToStages', {}):
            if 'AWSPENDING' in metadata['VersionIdsToStages'][version]:
                client.update-secret-version-stage(
                    SecretId=secret_arn,
                    VersionStage='AWSCURRENT',
                    MoveToVersionId=version
                )
                break

def generate_password(length=32):
    import secrets
    import string
    alphabet = string.ascii_letters + string.digits + '!@#$%^&*'
    return ''.join(secrets.choice(alphabet) for _ in range(length))
```

## Multi-Region Secrets

```bash
# Replicate a secret to another region
aws secretsmanager replicate-secret-to-regions \
  --secret-id prod/db-credentials \
  --add-replica-regions '[{"Region": "us-west-2"}]'

# List replica regions
aws secretsmanager describe-secret --secret-id prod/db-credentials
```

## Resource Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::123456789012:root"},
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "*"
    },
    {
      "Effect": "Deny",
      "Principal": {"AWS": "arn:aws:iam::123456789012:user/bob"},
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/db-credentials"
    }
  ]
}
```

## Pricing

| Component | Cost |
|-----------|------|
| Secret storage | $0.40/month per secret |
| API calls | $0.05 per 10,000 API calls |
| Cross-region replication | $0.15/month per replica |
| Rotation Lambda | Standard Lambda pricing |

## Limits

| Resource | Limit |
|----------|-------|
| Secrets per region | 100,000 |
| Secret size | 65,536 bytes |
| Version history | 100 versions |
| Labels per version | 20 |
| API rate | 1000/second |

## References

- **Homepage:** https://aws.amazon.com/secrets-manager/
- **Documentation:** https://docs.aws.amazon.com/secretsmanager/
- **Pricing:** https://aws.amazon.com/secrets-manager/pricing/

## Pricing Examples

**Scenario 1:** An application with 10 secrets (DB credentials, API keys, OAuth tokens). 10 × $0.40 = $4/month. API calls: 100K/month × $0.05/10K = $0.50/month. Total: $4.50/month.

**Scenario 2:** A microservice architecture with 100 services, each with 2 secrets (DB + API key). 200 secrets × $0.40 = $80/month. Multi-region replication to 2 additional regions: 200 × 2 × $0.15 = $60/month. Total: $140/month.

## Nuggets & Gotchas

- **Secrets Manager pricing is per SECRET, not per version — 1 secret with 10 versions costs $0.40/month, not $4:** Version history doesn't multiply cost. But each rotation creates a new version. After 100 versions, old versions are deleted automatically.
- **Rotation Lambda must follow the 4-step pattern (createSecret → setSecret → testSecret → finishSecret):** The Lambda is called 4 times per rotation. If you skip the test step, bad credentials go live without verification.
- **Secrets Manager doesn't encrypt secrets at the application level — the secret IS the plaintext:** When you call `GetSecretValue`, Secrets Manager decrypts and returns the plaintext. Your application is responsible for protecting that plaintext (don't log it, don't hardcode it).
- **Cross-region replication is one-way (primary → replica) — you can't promote a replica to primary:** If you need multi-region active-active secrets, you need separate secrets in each region and a custom sync mechanism.
- **Rotation Lambda needs `secretsmanager:PutSecretValue` and `secretsmanager:DescribeSecret` permissions:** If your rotation Lambda fails with access denied, check both the execution role AND the secret resource policy (if one exists, it may deny the Lambda).