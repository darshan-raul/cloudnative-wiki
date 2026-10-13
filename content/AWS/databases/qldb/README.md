---
title: Amazon QLDB (retired)
description: Historical QLDB journal and document semantics, retirement status and requirements for selecting a supported audit-data architecture.
tags:
  - cloud/aws/databases
  - cloud/aws/legacy
date: 2026-10-12
---

# Amazon QLDB (retired)

Amazon QLDB reached end of support on **July 31, 2025**. Do not recommend creating a ledger or running legacy deployment commands. This note retains concepts for understanding old designs and migration requirements.

## Journal versus current documents

QLDB supported PartiQL INSERT, UPDATE and DELETE on documents. The append-only journal recorded revisions; journal immutability did not make the current document view INSERT-only. Inserting a second document with the same application-level ID was not a substitute for updating the existing document.

A cryptographic digest/proof checks journal history against a trusted digest. Verification must be performed; retaining a digest is not automatic validation of every query or a proof of business correctness. Auditability, authorization, retention and deletion requirements are distinct.

## Choosing a replacement

Do not assume a general relational database automatically offers QLDB-equivalent verifiability. Document access patterns, transaction boundaries, historical reconstruction, retention/redaction requirements and independently retained verification evidence.

Possible designs combine [[AWS/databases/rds/README|RDS]] or [[AWS/databases/aurora/README|Aurora]] with application-managed audit events and immutable object retention in [[AWS/storage/s3/README|S3]]. Evaluate the actual guarantees and regulatory requirements; S3 Object Lock is not a transactional database journal.

Exercise: for a financial record with three updates and a reversal, specify current balance, retained history, authorization, event identifiers and evidence needed to detect tampering. Compare correction-by-new-event with destructive modification. No retired-service account is required.

## Historical architecture: mutable view, immutable journal

The following describes QLDB's historical model, not a supported service to deploy now.

```text
Application PartiQL transaction
  → current document revisions
  → append-only journal history
  → cryptographic digest/proof
  → independent verification and separately retained evidence
```

The materialized/current document view could be updated and deleted through supported PartiQL operations. The underlying journal retained revision history. These are different statements: an immutable journal does not imply “UPDATE and DELETE were unsupported.”

| Historical QLDB concept | Meaning                                               | Migration implication                                                  |
| ----------------------- | ----------------------------------------------------- | ---------------------------------------------------------------------- |
| Ledger                  | Administrative boundary for document/journal data     | Map ownership, access and retention, not just a table name.            |
| Table/document revision | Current/queryable document state with prior revisions | Preserve IDs, version/history and application mutation semantics.      |
| Journal                 | Ordered immutable history                             | A target SQL table alone does not reproduce this guarantee.            |
| Digest/proof            | Cryptographic evidence for verification               | Export/retain trusted evidence and define a verifier before migration. |
| Amazon Ion              | Typed structured representation                       | Preserve type/decimal/timestamp semantics during conversion.           |
| PartiQL transactions    | Supported document querying/mutation                  | Translate supported statements and transaction behavior deliberately.  |

Historical PartiQL operations such as UPDATE Account SET balance = 90 WHERE id = 'ACC001' produced new journal revisions rather than destructively rewriting history. Query/mutation syntax and proof APIs were distinct contracts; migration should preserve required revision semantics instead of replacing an update with an unrelated insert.

## Verification and migration walkthrough

A stored digest is not itself proof that every application's data was automatically checked. Historical verification required the actual supported digest/block/revision proof contracts and cryptographic verification against trusted evidence. Do not label a simplified linear hash sketch as the complete implementation.

1. Inventory ledgers, tables, document IDs, revision/history queries and authorization.
2. Preserve available exports, evidence/digests and the application records needed for audit.
3. Select a supported target such as a justified relational store, evaluating transactional and audit requirements independently.
4. Translate Ion types and application queries; define how updates/deletes/history map to the new model.
5. Implement target audit/retention/verification controls where required—these are not automatically inherited from Aurora PostgreSQL.
6. Reconcile current state plus required historical evidence and test representative application transactions.
7. Keep a retention/compliance-approved migration record and validate the recovery/cutover decision.

## Historical use cases and limits of substitution

Financial history, inventory changes or regulated audit data can motivate tamper-evident records, but “ledger” is not a synonym for a decentralized blockchain or legal compliance. Independent backup, identity controls and verification workflows still matter.

A conventional database with an audit table may provide useful traceability but not identical immutability/cryptographic guarantees. Conversely, maintaining the exact old API surface is not necessary if business/evidence requirements can be met by a supported architecture. Treat migration as a requirements/test exercise, not a drop-in engine rename. Historical pricing/quotas are not current planning inputs because support ended July 31, 2025.

## References

- [AWS services in full shutdown](https://docs.aws.amazon.com/general/latest/gr/full_shutdown_services.html).
- [Retained QLDB authorization actions, including PartiQLUpdate and PartiQLDelete](https://docs.aws.amazon.com/service-authorization/latest/reference/list_qldb.html).
- [Original AWS QLDB walkthrough](https://aws.amazon.com/blogs/aws/now-available-amazon-quantum-ledger-database-qldb/) — historical context, not current deployment instructions.
