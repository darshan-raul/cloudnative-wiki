---
title: Amazon QLDB
description: Amazon QLDB — immutable, cryptographically verifiable ledger database. Perfect for financial transactions, audit trails, and compliance. Append-only journal, SHA-256 digest verification.
tags:
  - aws
  - databases
  - qldb
  - ledger
  - compliance
---

# Amazon QLDB (Quantum Ledger Database)

QLDB is an immutable, append-only ledger database. It's used when you need a complete, tamper-evident audit trail with cryptographic verification. Unlike a traditional database where you can UPDATE or DELETE, QLDB only allows INSERT — once written, data cannot be modified or deleted.

## Core Concepts

### How QLDB Works

```
Application
  │
  ▼
QLDB Ledger (Journal)
  │
  ├── Block 1: { data: { user: "Alice", balance: 100 }, hash: SHA256(Block 0 + data) }
  ├── Block 2: { data: { user: "Alice", balance: 90 }, hash: SHA256(Block 1 + data) }
  └── Block 3: { data: { user: "Bob", balance: 10 }, hash: SHA256(Block 2 + data) }
        │
        ▼
  Digest (cryptographic hash of entire history)
  Stored in Amazon S3 (proof)
```

The journal is the heart of QLDB — it's an immutable, sequenced log of all changes. Each block's hash includes the previous block's hash, creating a chain.

### Immutable vs Traditional DB

| | Traditional DB | QLDB |
|--|--|--|
| UPDATE | Allowed | Not allowed (append new revision) |
| DELETE | Allowed | Not allowed (soft delete only) |
| History | Overwritten | Preserved (full audit trail) |
| Tamper detection | Application-level | Built-in (SHA-256 chain) |
| Verification | Manual (application) | Automatic (digest comparison) |

## Creating a Ledger

```bash
aws qldb create-ledger \
  --ledger-name my-financial-ledger \
  --tags '[{"Key": "Environment", "Value": "production"}]' \
  --permissions-mode ALLOW_ALL \
  --deletion-protection
```

### Deletion Protection

QLDB has deletion protection by default — you cannot delete a ledger without first disabling it:

```bash
# Disable deletion protection
aws qldb update-ledger \
  --ledger-name my-financial-ledger \
  --no-deletion-protection

# Now delete
aws qldb delete-ledger --ledger-name my-financial-ledger
```

## Using the Document API

QLDB uses a document model (PartiQL — SQL-like query language):

### Insert

```python
from qldb import QldbDriver

driver = QldbDriver(ledger_name='my-financial-ledger')

def create_transaction(txn):
    result = txn.execute_statement(
        "INSERT INTO Transactions VALUE {'account_id': 'ACC001', 'amount': 100, 'type': 'credit', 'timestamp': '2024-01-15T10:00:00'}"
    )
    return result

with driver.get_session() as session:
    session.execute_lambda(create_transaction)
```

### Query

```python
def get_transactions(txn):
    result = txn.execute_statement(
        "SELECT * FROM Transactions WHERE account_id = 'ACC001' ORDER BY timestamp ASC"
    )
    return list(result)

with driver.get_session() as session:
    transactions = session.execute_lambda(get_transactions)
```

### Update (via INSERT with revision)

In QLDB, "updates" are new documents with the same ID:

```python
def update_balance(txn):
    # Insert new revision (previous balance is preserved)
    result = txn.execute_statement(
        "INSERT INTO Account VALUE {'id': 'ACC001', 'balance': 90, 'updated_at': '2024-01-15T11:00:00'}"
    )
    return result

# Previous {'id': 'ACC001', 'balance': 100} is still in the journal
```

## Verifying Data Integrity

### Generate Digest

```bash
# Get digest (hash of entire journal)
aws qldb get-digest \
  --ledger-name my-financial-ledger
```

Returns:
```json
{
  "Digest": {
    "ledgerName": "my-financial-ledger",
    "digest": "BASE64_HASH_OF_ALL_HISTORY",
    "blockAddress": {
      "strandId": "xxxxx",
      "sequenceNo": 12345
    }
  }
}
```

### Verify a Document

```bash
# Verify the entire history of a document
aws qldb get-revisions \
  --ledger-name my-financial-ledger \
  --table-name Transactions \
  --document-id doc-xxxxx \
  --revision-filter "ALL"
```

### Python Verification

```python
from qldb.verification import Verify

# Verify document history hasn't been tampered
verifier = Verify('my-financial-ledger')

# Get document history
history = verifier.get_document_history(
    table_name='Transactions',
    document_id='doc-xxxxx'
)

# Verify each revision is in the chain
for block in history:
    assert verifier.verify_block(block), "Tampering detected!"
```

## Journal Export to S3

Export the entire journal to S3 for external verification or long-term storage:

```bash
# Create export job
aws qldb create-journal-export \
  --ledger-name my-financial-ledger \
  --s3-export-configuration '{
    "Bucket": "my-qldb-exports",
    "Prefix": "exports/2024-01/",
    "EncryptionConfiguration": {"KmsKeyArn": "arn:aws:kms:us-east-1:123456789012:key/xxxxx"}
  }' \
  --inclusive-start-time 2024-01-01T00:00:00Z \
  --exclusive-end-time 2024-02-01T00:00:00Z
```

Journal exports are stored in S3 as JSON files with block-level data.

## Ion Format

QLDB uses Amazon Ion (binary JSON) for data storage. The driver handles conversion:

```python
from amazon.ion.simpleion import loads

# Data is stored in Ion format
# Query returns Ion objects
result = txn.execute_statement("SELECT * FROM Transactions")

# Convert to Python dict
for row in result:
    ion_obj = loads(row)  # Convert Ion to Python
```

##PartiQL (Query Language)

QLDB usesPartiQL — a SQL-compatible language:

```sql
-- Insert
INSERT INTO Account VALUE {'id': 'ACC001', 'balance': 100}

-- Select
SELECT * FROM Account WHERE id = 'ACC001'

-- Update (new revision)
INSERT INTO Account VALUE {'id': 'ACC001', 'balance': 90}

-- History of a document
SELECT * FROM Account WHERE id = 'ACC001' HISTORY

-- Get revision at specific time
SELECT * FROM Account WHERE id = 'ACC001' AS OF '2024-01-15T10:00:00Z'
```

## Use Cases

| Use Case | Why QLDB |
|----------|---------|
| Financial transactions | Immutable, auditable, cryptographic proof |
| Supply chain | Full history of goods movement |
| Medical records | HIPAA compliance, tamper-evident |
| Legal documents | Immutable contract versions |
| HR/Payroll | Audit trail of employee changes |
| Government records | Regulatory compliance |

## Pricing

| Component | Cost |
|-----------|------|
| Journal storage | $0.50/GB/month |
| Indexed storage | $0.025/GB/month |
| Write I/O | $0.13 per million I/O |
| Read I/O | $0.02 per million I/O |
| Journal export | $0.025/GB (S3) |

## Limits

| Resource | Limit |
|----------|-------|
| Max ledger storage | 64 TB |
| Max document size | 64 KB |
| Max fields per document | 500 |
| Max field name length | 50 characters |
| Max concurrent transactions | 15 per ledger |
| Max query timeout | 30 seconds |

## References

- **Homepage:** https://aws.amazon.com/qldb/
- **Documentation:** https://docs.aws.amazon.com/qldb/
- **Pricing:** https://aws.amazon.com/qldb/pricing/

## Pricing Examples

**Scenario 1:** A financial ledger with 1M transactions/month. Storage: 10GB journal × $0.50 = $5/month. Indexed storage: 10GB × $0.025 = $0.25/month. Write I/O: 1M × $0.13/1M = $0.13/month. Total: ~$5.40/month. Compare to a traditional database with manual audit logging: same storage cost + engineering time to build tamper-proof logging.

**Scenario 2:** A supply chain ledger with heavy reads (100K reads/day). 100K × 30 days = 3M reads/month. Read I/O: 3M × $0.02/1M = $0.06/month. Storage: 50GB × $0.50 + 50GB × $0.025 = $26.25/month. Total: ~$26/month for full cryptographic audit trail.

## Nuggets & Gotchas

- **QLDB's "immutability" means you cannot UPDATE or DELETE documents — you insert new revisions:** The old revision stays in the journal. To "close" a record (e.g., a completed transaction), insert a new document with a `status: CLOSED` field. Don't expect traditional UPDATE semantics.
- **QLDB's query language isPartiQL — it's similar to SQL but not identical:** JOINs between tables are limited. `INSERT INTO ... VALUE` syntax differs from SQL's `INSERT INTO ... VALUES`. Test queries in the console first.
- **QLDB's Ion format is not JSON — you'll need the Ion reader/writer library:** When querying directly via API, you get Ion binary data. The Python/Java drivers handle this, but for raw API calls, use the Ion reader.
- **QLDB's cryptographic verification requires storing the digest in a safe place:** The digest is your proof of integrity. If you lose the digest, you can still query history, but you can't cryptographically prove it hasn't been tampered. Export the digest to S3 (immutable via Object Lock).
- **QLDB has a 15-concurrent-transaction limit per ledger — use client-side batching:** If you exceed 15 concurrent transactions, you'll get `TransactionLimitExceededException`. Use connection pooling or reduce concurrency.