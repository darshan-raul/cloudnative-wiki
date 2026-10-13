---
title: AWS KMS
description: AWS KMS — managed encryption keys. CMK types (symmetric/asymmetric), key policies, grants, rotation, envelope encryption, and CloudTrail integration.
tags:
  - aws/security
date: 2026-10-12
---

# AWS KMS (Key Management Service)

Prerequisites: [[AWS/security/iam/README|IAM roles and least privilege]] and the [[AWS/security/README|security evidence/response model]].

KMS manages cryptographic keys and authorized cryptographic operations. Current terminology is KMS key, not the older customer master key/CMK. Encryption does not replace access control or backups.

## Key and permission model

Symmetric encryption keys are the usual integration choice. Asymmetric keys have algorithm-specific encryption or signing uses; not every RSA/ECC key supports every operation. HMAC keys generate/verify MACs. CloudHSM is a separate service with a different ownership/cost model.

A key policy is central to authorization; the account principal statement can enable delegation to IAM policies, not merely allow the root user's interactive use. Grants authorize scoped operations, often for service integrations. Cross-account usage needs appropriate key and caller policies. See [[AWS/security/iam/policy-evaluation|policy evaluation]].

Envelope encryption uses GenerateDataKey to obtain a plaintext data key and encrypted copy. Encrypt data locally, erase the plaintext key, and retain only the encrypted data key with ciphertext. Never log plaintext keys or secrets.

## Reversible cryptographic lab

Use a sandbox Region and a role authorized for CreateKey, scoped Encrypt/Decrypt, DescribeKey and ScheduleKeyDeletion. Creating a customer-managed key incurs charges. The create-key policy flag is --policy, not --key-policy; the CLI default policy delegates permissions as documented.

```bash
aws kms create-key --description "Disposable wiki lab" --key-usage ENCRYPT_DECRYPT
```

Record KeyMetadata.KeyId. Save non-sensitive plaintext to a local file using your editor. Use `aws kms encrypt --key-id KEY_ID --plaintext fileb://fixture.txt --encryption-context Purpose=wiki-lab`. The response CiphertextBlob is base64 text; decode it to a binary ciphertext file before passing fileb:// to decrypt.

Decrypt with the same encryption context. Expected: the original plaintext after decoding the response. Try a different Purpose context and expect failure; encryption context is authenticated metadata, not confidential storage.

## Rotation, deletion and cost

Rotation eligibility and schedules depend on key type/origin; do not promise automatic rotation for imported/asymmetric keys. Rotation preserves decryptability of older ciphertext. Multi-Region keys are related regional resources, not a universal single global key or automatic replication of all policies.

Schedule deletion only for the lab key, with the documented minimum waiting period; deletion after that window is irreversible and can make dependent ciphertext unrecoverable. Check aliases/grants/service dependencies first and cancel deletion if mistaken.

Estimate key-months and operation-specific request charges. At a purely illustrative \$0.03/10,000 requests, one million encrypts plus one million decrypts per day over thirty days is sixty million requests and \$180 before allowances/key charges—not \$6. Verify current regional operation pricing before using this assumption.

## Key catalogue and envelope architecture

| Kind                          | Typical use                              | Compatibility/ownership                                      |
| ----------------------------- | ---------------------------------------- | ------------------------------------------------------------ |
| Symmetric encryption          | Supported service at-rest integration    | Selected key origin/store and operation constraints          |
| Asymmetric encryption/signing | Outside-service encryption or signatures | Algorithm/usage must match; not every integration accepts it |
| HMAC                          | Message authentication codes             | GenerateMac/VerifyMac, not Encrypt/Decrypt                   |
| AWS-managed key               | Service-managed use                      | Policy/lifecycle controls differ from customer-managed keys  |
| Customer-managed key          | Explicit policy/grants/lifecycle         | Key-months and applicable request costs                      |
| CloudHSM/custom store         | Specific control/compliance needs        | Additional service/availability/operator responsibilities    |

```text
GenerateDataKey → plaintext data key ── local authenticated encryption → ciphertext
       └─────── encrypted data key ─────────── stored with ciphertext
decrypt encrypted data key → authorized local decrypt → plaintext application data
```

KMS Encrypt has input/algorithm size limits; it is not a bulk-file encryption upload API. The data key encrypts the object locally. Authentication context belongs to the cryptographic request; never put confidential values in it because audit evidence may expose it.

## Complete teaching key policy and grants

Substitute the sandbox account and application role before creating a disposable symmetric key with --policy file://key-policy.json:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EnableAccountIAMDelegation",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::111122223333:root" },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "ApplicationUseForLabContext",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::111122223333:role/WikiApplication" },
      "Action": ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"],
      "Resource": "*",
      "Condition": {
        "StringEquals": { "kms:EncryptionContext:Purpose": "wiki-lab" }
      }
    }
  ]
}
```

In a key policy, Resource \* refers to the attached key; this is not an identity policy granting every key. The account statement enables IAM delegation; caller identity policies/guardrails still matter. Production administration, separation of duties and cross-account policies require a reviewed design.

A grant is delegated authorization to a grantee principal, not an implicit Lambda auto-discovery feature:

```bash
aws kms create-grant --key-id KMS_LAB_KEY_ID \
  --grantee-principal APPLICATION_ROLE_ARN --operations Encrypt Decrypt \
  --constraints '{"EncryptionContextEquals":{"Purpose":"wiki-lab"}}'
aws kms list-grants --key-id KMS_LAB_KEY_ID
```

Record GrantId/GrantToken without exposing credentials. Eventual consistency can require the returned token for immediately authorized calls. Retire/revoke only the lab grant using the documented role-dependent operation; do not remove service grants blindly.

## SDK encryption-context walkthrough

This complete small-payload example uses a pre-existing lab key and verified SDK credentials; it prints no plaintext/ciphertext:

```python
import os
import boto3

kms = boto3.client("kms")
key_id = os.environ["KMS_LAB_KEY_ID"]
context = {"Purpose": "wiki-lab"}
encrypted = kms.encrypt(
    KeyId=key_id,
    Plaintext=b"synthetic-fixture",
    EncryptionContext=context,
)["CiphertextBlob"]
decrypted = kms.decrypt(
    KeyId=key_id,
    CiphertextBlob=encrypted,
    EncryptionContext=context,
)["Plaintext"]
assert decrypted == b"synthetic-fixture"
```

For bulk encryption use a maintained AWS Encryption SDK/authenticated-encryption workflow that manages framing, data keys and integrity. Python deletion of a variable is not guaranteed cryptographic memory erasure.

## Service integration, rotation and troubleshooting

SSE-S3 and SSE-KMS are distinct choices. Select a supported customer-managed key and service resource policy/role permissions; uploading to S3 does not automatically grant another account decrypt. EBS encryption defaults are regional configuration; RDS encryption and restore/migration have engine/resource lifecycle constraints.

Automatic rotation eligibility, configurable periods and on-demand/manual alternatives depend on key origin/type. Rotation preserves old-material decryptability; replacing a key/alias requires data migration/access planning and does not rewrite every ciphertext.

Inspect key state, policy/grants, encryption context, Region/partition, algorithm and throttling before broadening permissions. Preserve CloudTrail KMS evidence; metadata/key usage is not confidential payload access. Before deletion inventory all dependent encrypted resources and test restore with the intended key identity; deletion after the waiting period is irreversible.

References: [grants](https://docs.aws.amazon.com/kms/latest/developerguide/grants.html), [encryption context](https://docs.aws.amazon.com/kms/latest/developerguide/encrypt_context.html), [key rotation](https://docs.aws.amazon.com/kms/latest/developerguide/rotate-keys.html), [Encrypt contract](https://docs.aws.amazon.com/kms/latest/APIReference/API_Encrypt.html).

## Cross-wiki comparisons

- [[Azure/security/key-vault/README|Azure Key Vault Architecture, Managed HSM, and Cryptographic Governance]] — key management (Azure)

## References

- [KMS concepts](https://docs.aws.amazon.com/kms/latest/developerguide/concepts.html)
- [CreateKey CLI](https://docs.aws.amazon.com/cli/latest/reference/kms/create-key.html)
- [Key policies](https://docs.aws.amazon.com/kms/latest/developerguide/key-policies.html)
- [Deletion safeguards](https://docs.aws.amazon.com/kms/latest/developerguide/deleting-keys.html)
- [Pricing](https://aws.amazon.com/kms/pricing/)

## Across the wiki

- [[GCP/security/kms/README|Cloud KMS, Cloud HSM, and CMEK Envelope Encryption]]
- [[Architecture/solution-architecture-concepts/cryptography/README|Cryptography]]
- [[Kubernetes/concepts/L07-security/03-encryption-identity/13-etcd-encryption|etcd Encryption]]
