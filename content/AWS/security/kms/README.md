---
title: AWS KMS
description: AWS KMS — managed encryption keys. CMK types (symmetric/asymmetric), key policies, grants, rotation, envelope encryption, and CloudTrail integration.
tags:
  - aws
  - security
  - kms
  - encryption
---

# AWS KMS (Key Management Service)

KMS provides managed encryption keys (CMKs) used by virtually every AWS service for data at rest encryption. KMS keys are the foundation of encryption in AWS — S3, RDS, DynamoDB, EBS, Lambda, and many others use KMS for encryption.

## Key Types

### Symmetric CMK (Most Common)

- 256-bit AES-GCM encryption
- Single key used for encrypt/decrypt
- Used by almost all AWS services
- Hardware-backed (HSM)

### Asymmetric CMK

- RSA or ECC key pairs
- Public key encrypts, private key decrypts
- Use for: API signing, TLS, encrypt outside AWS
- Not used by most AWS services natively

### CloudHSM (Dedicated Hardware)

- You manage keys on your own hardware
- FIPS 140-2 Level 3 validated HSM
- Higher compliance requirements
- Higher cost

## Creating a CMK

```bash
# Create symmetric CMK (default)
aws kms create-key \
  --description "My app encryption key" \
  --key-usage ENCRYPT_DECRYPT \
  --origin AWS_KMS \
  --tags '[{"TagKey": "Environment", "TagValue": "production"}]'

# Response
{
  "KeyMetadata": {
    "KeyId": "xxxxx-xxxxx-xxxxx",
    "Arn": "arn:aws:kms:us-east-1:123456789012:key/xxxxx",
    "KeyState": "Enabled"
  }
}
```

### Create with Key Policy

```bash
aws kms create-key \
  --description "My app encryption key" \
  --key-policy '{
    "Version": "2012-10-17",
    "Id": "key-policy",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::123456789012:root"},
      "Action": "kms:*",
      "Resource": "*"
    }]
  }'
```

## Key Policies

### Default Key Policy (implicit)

If you don't specify a key policy, the default allows the root user full access. This is fine for most use cases.

### Custom Key Policy

```json
{
  "Version": "2012-10-17",
  "Id": "key-policy",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::123456789012:root"},
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow use of key for Lambda",
      "Effect": "Allow",
      "Principal": {"Service": "lambda.amazonaws.com"},
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*"
      ],
      "Resource": "*"
    }
  ]
}
```

## Grants (Fine-Grained Delegation)

Grants are an alternative to key policies for temporary, revokable access:

```bash
# Create grant for Lambda
aws kms create-grant \
  --key-id xxxxx-xxxxx-xxxxx \
  --grantee-principal arn:aws:lambda:us-east-1:123456789012:function:my-function \
  --operations '[Encrypt, Decrypt, ReEncryptFrom, ReEncryptTo, GenerateDataKey, DescribeKey]' \
  --name my-lambda-grant

# Lambda retrieves the grant automatically via service role
```

Grants are useful when you can't modify the key policy (e.g., cross-account access).

## Envelope Encryption

KMS encrypts data keys, not large objects directly:

```
Application Data (100 MB)
    │
    │  KMS.GenerateDataKey
    ▼
Data Key (DEK) ──► KMS.Encrypt ──► Encrypted Data Key
    │
    ▼
AES-256 Encrypt (local)
    │
    ▼
Encrypted Data + Encrypted Data Key
```

```python
# Python example (boto3)
import boto3
import base64

kms = boto3.client('kms')

# Generate data key
response = kms.generate_data_key(
    KeyId='xxxxx-xxxxx-xxxxx',
    KeySpec='AES-256'  # 256-bit
)

# Use the plaintext key locally
plaintext_key = response['Plaintext']  # Use this to encrypt
encrypted_key = response['CiphertextBlob']  # Store this

# Encrypt data locally (use plaintext_key with crypto library)
# Store encrypted_key with encrypted data
```

## Key Rotation

### Automatic Rotation

```bash
# Enable automatic rotation (every year)
aws kms enable-key-rotation --key-id xxxxx-xxxxx-xxxxx

# Check rotation status
aws kms get-key-rotation-status --key-id xxxxx-xxxxx-xxxxx
```

Automatic rotation is enabled for symmetric CMKs by default (AWS-managed keys). For customer-managed keys, rotation is optional.

### Manual Rotation (for asymmetric or custom key material)

You can't rotate asymmetric CMKs automatically. For CMKs with imported key material, you must re-import.

## Using KMS with AWS Services

### S3 Encryption

```bash
# SSE-KMS (KMS-managed key)
aws s3api put-object \
  --bucket my-bucket \
  --key my-file.txt \
  --body my-file.txt \
  --ssekms-key-id xxxxx-xxxxx-xxxxx

# SSE-KMS with S3-managed key (S3-SSE-KMS)
aws s3api put-object \
  --bucket my-bucket \
  --key my-file.txt \
  --body my-file.txt \
  --server-side-encryption aws:kms \
  --ssekms-key-id xxxxx-xxxxx-xxxxx
```

### EBS Encryption (automatic)

```bash
# Create encrypted EBS volume
aws ec2 create-volume \
  --size 100 \
  --encrypted \
  --kms-key-id xxxxx-xxxxx-xxxxx \
  --availability-zone us-east-1a
```

### RDS Encryption

```bash
# RDS encryption is enabled at creation
aws rds create-db-instance \
  --db-instance-identifier my-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --allocated-storage 100 \
  --storage-encrypted \
  --kms-key-id xxxxx-xxxxx-xxxxx
```

## Encryption Context

Additional authenticated data (AAD) that binds encryption to context:

```python
# Encrypt with context
response = kms.encrypt(
    KeyId='xxxxx-xxxxx-xxxxx',
    Plaintext='my-secret-data',
    EncryptionContext={
        'service': 'payments',
        'customer_id': 'CUST-123'
    }
)

# Decrypt with SAME context (if context differs, decryption fails)
response = kms.decrypt(
    CiphertextBlob=response['CiphertextBlob'],
    EncryptionContext={
        'service': 'payments',
        'customer_id': 'CUST-123'
    }
)
```

## CloudTrail Integration

Every KMS operation is logged to CloudTrail:

```bash
# Look up KMS API calls
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=Encrypt
```

## Pricing

| Component | Cost |
|-----------|------|
| Customer managed keys (CMK) | $1.00/month |
| AWS managed keys | Free (used by other services) |
| API calls (cryptographic) | $0.03/10,000 calls |
| Key rotation | Free (automatic) |
| Custom key store (CloudHSM) | $1.45/hour (~$1,044/month) |

## Limits

| Resource | Limit |
|----------|-------|
| CMKs per region | 100,000 |
| Grants per CMK | 10,000 |
| Key policies | 20 KB |
| Encryption context pairs | 8 |
| Encryption context key length | 256 bytes |
| Plaintext size (Encrypt API) | 4 KB |
| Ciphertext size (Encrypt API) | 4 KB (same key type) |

## References

- **Homepage:** https://aws.amazon.com/kms/
- **Documentation:** https://docs.aws.amazon.com/kms/
- **Pricing:** https://aws.amazon.com/kms/pricing/

## Pricing Examples

**Scenario 1:** An application encrypting 1M records/day with KMS. 1M encrypts + 1M decrypts = 2M API calls/month. 2M × $0.03/10K = $6/month. Plus 1 CMK = $1/month. Total: ~$7/month. Compare to CloudHSM ($1,044/month). KMS is 99.3% cheaper for most use cases.

**Scenario 2:** 10 S3 buckets encrypted with CMK (SSE-KMS). 10 CMKs × $1/month = $10/month. Plus API calls (S3 makes KMS calls for each object). For 1M objects/month: 1M × $0.03/10K = $3/month. Total: ~$13/month. With S3-SSE-KMS (AWS managed), no CMK cost (but less control).

## Nuggets & Gotchas

- **KMS has a 4KB limit on Encrypt API — for larger data, use envelope encryption:** Encrypt a data key with KMS, then use that key locally to encrypt the large object. This is how S3, EBS, and RDS handle encryption automatically.
- **CMK deletion requires waiting 7-30 days (configurable) — you can't delete immediately:** If you delete a CMK, any data encrypted with it is unrecoverable. AWS enforces a waiting period. Use `PendingDeletionWindowInDays` to set 7-30 days.
- **Key rotation doesn't re-encrypt existing data — it creates a new key version:** Old data encrypted with the old key version is still decryptable with the old key. Only new data uses the new key. This is efficient but means old keys must remain available.
- **KMS grants are ideal for Lambda — they allow temporary access without modifying key policy:** Lambda functions are stateless, so each invocation needs access. Grants auto-revoke when the grantee principal (Lambda) is deleted.
- **EncryptionContext is public metadata — don't store secrets there:** The context is visible in CloudTrail logs. Use it for authentication/authorization (e.g., "this key was used for this specific customer"), not for secrets.