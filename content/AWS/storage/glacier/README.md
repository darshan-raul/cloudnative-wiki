---
title: "S3 Glacier archival storage"
description: "For current object-archive designs, use S3 Glacier Instant Retrieval, Flexible Retrieval or Deep Archive inside an S3 bucket."
tags:
  - aws/storage
date: 2026-10-12
---

# S3 Glacier archival storage

For current object-archive designs, use S3 Glacier Instant Retrieval, Flexible Retrieval or Deep Archive inside an [[AWS/storage/s3/README|S3 bucket]]. They are storage classes, not vaults. Standalone Amazon Glacier uses a separate vault/archive API and closed access to new customers on December 15, 2025; existing vault customers remain supported. Do not substitute glacier CLI commands for S3 object operations.

## Retention versus restoration

Instant Retrieval supports immediate access. Flexible Retrieval requires a restore and offers expedited, standard and bulk retrieval; Deep Archive has longer standard/bulk restore times. Available speeds, quotas and expedited capacity depend on the class and request. Flexible/Instant Retrieval have 90-day minimum billing duration; Deep Archive has 180 days. Early deletion can incur the remaining-duration charge.

A restore creates a temporarily accessible copy; it does not permanently change the archived object's class. Retrieval, requests and temporary restored storage can add costs. Design the retrieval tier and accessible-copy duration from the application's RTO, not only its storage rate.

## Compliance boundaries

S3 Object Lock requires versioning and applies retention/legal holds to object versions. Governance mode has a privileged bypass path; compliance mode is materially stricter. Legal holds and timed retention are distinct. Restrict retention permissions and rehearse policies on disposable data: irreversible retention can prevent cleanup and extend charges.

Standalone Glacier Vault Lock is a different historical workflow. InitiateVaultLock returns a lock ID; CompleteVaultLock must complete within 24 hours or the in-progress policy is removed. It does not auto-lock after seven days. A read-only Allow statement alone does not enforce retention against archive deletion.

## Sandbox restore exercise

Prerequisites: an authorized disposable bucket, IAM/KMS permissions, a small object in Flexible Retrieval or Deep Archive, and a budget for minimum-duration and retrieval charges. Do not impose long compliance retention on a learning bucket.

```bash
aws s3api restore-object --bucket example-unique-bucket --key archive.txt \
  --restore-request '{"Days":1,"GlacierJobParameters":{"Tier":"Standard"}}'
aws s3api head-object --bucket example-unique-bucket --key archive.txt
```

Wait for the Restore metadata to show completion before downloading. An immediate GET before completion should fail with the archive-access state, not prove the object is missing. Record actual elapsed restoration time, compare it to the target RTO and confirm the restored copy's expiry. Deleting sandbox data may still incur minimum-duration charges; retention-protected versions cannot be deleted until permitted.

## Cost reasoning

Using an illustrative rate of \$0.00099/decimal GB-month, 10 TB is 10,000 GB: \$9.90/month and \$831.60 for 84 months before requests/retrieval. This arithmetic is not a current regional quote. Include restore storage, data transfer, metadata overhead and minimum billing conditions before choosing an archival class.

## Retrieval decision table and restore sequence

| Storage choice                                | Access pattern                           | Recovery design                                                        |
| --------------------------------------------- | ---------------------------------------- | ---------------------------------------------------------------------- |
| Glacier Instant Retrieval                     | Rare access needing milliseconds         | Direct reads with applicable retrieval costs.                          |
| Glacier Flexible Retrieval                    | Archive tolerates a restore              | Choose supported expedited/standard/bulk; plan restored-copy lifetime. |
| Glacier Deep Archive                          | Very long retention with longer recovery | Restore using supported tier, allow time and budget temporary copy.    |
| Standalone Glacier vault (existing customers) | Historical archive ID/vault API          | Distinct jobs/inventory/access policy; not an S3 bucket.               |

```text
Archived S3 object
  → restore request accepted
  → restore in progress
  → temporary accessible copy
  → copy expiration; archived object remains under its lifecycle/retention
```

HeadObject restore metadata and actual GET success are stronger evidence than a submitted request. Track restore completion with a bounded observation workflow; a long archive restore is not an API timeout to fix by repeatedly creating jobs. Choose the accessible-copy duration long enough for readers and downstream processing.

## Compliance lifecycle and immutable history

Timed Object Lock retention applies to versions. A legal hold is independent and persists until an authorized removal. Governance bypass authority must be tightly controlled; compliance retention is intentionally hard to shorten/remove. Version deletion, lifecycle expiration and retention enforcement interact, so test on short-lived disposable data before production.

For historical standalone Vault Lock, initiation and completion are separate. The lock policy must actually restrict deletion/retention-sensitive actions; an Allow for reads does not do this. Losing the lock ID or missing the 24-hour completion window is not automatic finalization. Permanent lock/deletion constraints require legal/security review.

## Cost walkthrough

Write quantities with units before pricing:

```text
retained GB × storage rate per GB-month × retained months
+ restore request count × request rate
+ bytes retrieved × retrieval rate
+ temporary restored GB × accessible-copy duration × applicable rate
+ applicable network and metadata/minimum charges
```

A seven-year retention term is 84 months; apply it once to a monthly storage subtotal. Compare retrieval frequency and RTO under at least two scenarios (normal audit and bulk disaster recovery). A very low storage tariff can be dominated by requests/restore/network during a large recovery event. Do not treat a successful archive job as evidence that legal retention or recovery correctness was tested.

## References

- [S3 archive restoration](https://docs.aws.amazon.com/AmazonS3/latest/userguide/restoring-objects.html)
- [S3 Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html)
- [Standalone Glacier availability](https://docs.aws.amazon.com/amazonglacier/latest/dev/introduction.html)
- [CompleteVaultLock contract](https://docs.aws.amazon.com/cli/latest/reference/glacier/complete-vault-lock.html)
- [S3 pricing](https://aws.amazon.com/s3/pricing/)
