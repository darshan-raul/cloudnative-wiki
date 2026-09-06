---
title: Google Cloud Firestore
description: Cloud Firestore architecture — Native vs Datastore mode, document-collection hierarchy, real-time listeners, composite indexes, and ACID transactions.
tags:
  - gcp
  - databases
  - firestore
  - nosql
  - serverless
  - mobile
---

# Google Cloud Firestore 📄🔥

Google Cloud Firestore is a serverless, horizontally scalable NoSQL document database engineered for automatic scaling, real-time data synchronization, and offline client support. Backed by multi-region Paxos replication, Firestore delivers **ACID transactions, rich hierarchical queries, and a 99.999% availability SLA**.

---

## Architecture & Mental Model

### Document-Collection Hierarchy & Multi-Region Quorum

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Firestore Database Instance                     │
│                                                                        │
│   Collection: "users"                                                  │
│   ├── Document: "user_alice"                                           │
│   │   ├── Fields: { name: "Alice", email: "alice@co.com", role: "admin"}│
│   │   │                                                                │
│   │   └── Sub-Collection: "orders" (Hierarchical Sub-Tree)             │
│   │       ├── Document: "order_901" ──► { total: 150.00, status: "PAID"}│
│   │       └── Document: "order_902" ──► { total: 45.50, status: "PEND"}│
│   │                                                                    │
│   └── Document: "user_bob"                                             │
│       └── Fields: { name: "Bob", email: "bob@co.com" }                 │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Synchronous Paxos Quorum
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│             Multi-Region High Availability Fabric (e.g. nam5)          │
│                                                                        │
│   Primary Region 1        Primary Region 2        Witness Region       │
│   (Iowa: us-central1)     (S. Carolina: us-east1) (N. Virginia)        │
│   [Storage + Leader]      [Storage + Replica]     [Witness Quorum]     │
└────────────────────────────────────────────────────────────────────────┘
```

* **Shallow Queries by Default:** Querying a collection (e.g. `/users`) fetches only the matching user documents; it **never automatically downloads sub-collections** (`/orders`), preventing unintended bandwidth and memory exhaustion.

---

## Core Concepts

### 1. Native Mode vs. Datastore Mode

When provisioning a Firestore database, you must select one of two mutually exclusive modes:

| Dimension | Firestore in Native Mode (Recommended) | Firestore in Datastore Mode |
| :--- | :--- | :--- |
| **Target Audience** | Web, mobile, serverless apps, and microservices | Server-only architectures, legacy App Engine Datastore |
| **Client Support** | Client SDKs (iOS, Android, Web) + Server SDKs | **Server SDKs exclusively** (No mobile/web direct client SDKs) |
| **Real-Time Listeners**| **Supported (`onSnapshot`):** Instant live websocket updates | Not supported |
| **Offline Sync** | **Supported:** Automatic local cache and sync | Not supported |
| **Security Rules** | Declarative client security rules (`firestore.rules`) | Standard GCP IAM exclusively |
| **Max Write Rate** | 10,000 writes/sec initial (scales automatically) | Scales immediately to millions of writes/sec |

### 2. ACID Multi-Document Transactions

Firestore supports full ACID transactions across multiple documents:
* **Optimistic Concurrency Control (OCC):** Read operations are performed first, followed by atomic writes.
* If any document read during the transaction is modified by a concurrent client before the commit completes, Firestore automatically retries the entire transaction.

```python
# Python ACID Multi-Document Transaction Example:
@firestore.transactional
def transfer_funds(transaction, source_ref, dest_ref, amount):
    snapshot_source = source_ref.get(transaction=transaction)
    snapshot_dest = dest_ref.get(transaction=transaction)

    source_balance = snapshot_source.get("balance")
    if source_balance < amount:
        raise ValueError("Insufficient funds")

    transaction.update(source_ref, {"balance": source_balance - amount})
    transaction.update(dest_ref, {"balance": snapshot_dest.get("balance") + amount})
```

### 3. Single-Field vs. Composite Indexes

* **Single-Field Indexes (Automatic):** Firestore automatically indexes every single field in every document (both ascending and descending).
* **Composite Indexes (Manual):** Queries that filter or sort on multiple fields (e.g. `WHERE status = 'PAID' ORDER BY created_at DESC`) require an explicit composite index defined in `firestore.indexes.json`.

---

## Production `gcloud` CLI Commands

### 1. Provisioning a Multi-Region Firestore Database in Native Mode

```bash
gcloud firestore databases create \
  --location=nam5 \
  --type=firestore-native
```

* `nam5`: Google's multi-region dual-primary location spanning `us-central1` and `us-east1`, backed by a 99.999% uptime SLA.

### 2. Deploying Composite Indexes via `firestore.indexes.json`

```json
{
  "indexes": [
    {
      "collectionGroup": "orders",
      "queryScope": "COLLECTION",
      "fields": [
        {"fieldPath": "status", "order": "ASCENDING"},
        {"fieldPath": "total", "order": "DESCENDING"}
      ]
    }
  ],
  "fieldOverrides": []
}
```

```bash
# Deploy composite index using firebase-tools CLI
firebase deploy --only firestore:indexes
```

### 3. Deploying Granular Security Rules (`firestore.rules`)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // User profile documents: Only the authenticated owner can write
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
      
      // Nested sub-collection: Orders
      match /orders/{orderId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
    }
  }
}
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Max document size** | 1 MiB (1,048,576 bytes) | Store large images/PDFs in Cloud Storage |
| **Max write rate to a single document**| **1 write per second** | **Critical:** Avoid single-document counter anti-pattern |
| **Max transaction duration** | 270 seconds | Keep transactions fast and non-blocking |
| **Max documents per batch write** | 500 documents | Split bulk operations into 500-item chunks |
| **Max sub-collection depth** | 100 levels | Typical architectures rarely exceed 3–4 levels |

---

## References

* **Firestore Documentation:** https://cloud.google.com/firestore/docs
* **Native vs Datastore Mode Guide:** https://cloud.google.com/firestore/docs/choosing-a-database-mode
* **Security Rules Reference:** https://firebase.google.com/docs/firestore/security/get-started
* **Pricing:** https://cloud.google.com/firestore/pricing

---

## Pricing Examples

### Scenario 1: Collaborative Mobile Application (Native Mode)
* 50,000 daily active mobile users syncing data via live WebSocket listeners.
* Operations:
  * Document Reads: 15 million reads / month.
  * Document Writes: 3 million writes / month.
  * Document Deletes: 500,000 deletes / month.
* Storage: 25 GB of JSON document data.
* Billing calculation (us-central1 multi-region):
  * Reads (after 1.5M free): 13.5M × $0.06 / 100k = **$8.10**.
  * Writes (after 600k free): 2.4M × $0.18 / 100k = **$4.32**.
  * Deletes: 500k × $0.02 / 100k = **$0.10**.
  * Storage: 25 GB × $0.18 / GB = **$4.50**.
* **Total Monthly Database Cost:** **~$17.02 / month** (Serving 50k users with real-time sync).

### Scenario 2: High-Volume Analytics Event Ingestion (Datastore Mode)
* 100 million event documents written per month by backend worker services.
* Billable writes: 100M × $0.18 / 100k = **$180.00 / month**.
* 100 GB storage retained: $18.00 / month.
* **Total Monthly Bill:** **~$198.00 / month**.

---

## Nuggets & Gotchas

1. **The 1-Write-Per-Second Single Document Bottleneck:** Firestore is sharded at the document level. If an application updates a **single document** more than once per second (e.g. incrementing a global `viewCount` counter on every page visit), writes will fail with `DEADLINE_EXCEEDED` or cause severe latency spikes. To implement high-frequency counters, use **Distributed Counters** (sharding the counter across 20 sub-documents and summing them on read).
2. **Missing Composite Index Link in Query Errors:** If your code executes a query that requires an un-provisioned composite index, Firestore fails the query with an error message containing a **direct, clickable URL** in the error payload! Clicking the generated URL opens the Google Cloud Console with the index pre-filled, allowing you to create the exact missing index with one click.
3. **Sub-Collections Are NOT Deleted When Parent Document Is Deleted:** If you delete document `/users/alice`, any sub-collections underneath it (e.g. `/users/alice/orders/order_1`) **continue to exist as orphaned documents**! Deleting a parent document does not cascade delete child sub-collections; your application must recursively delete sub-collection documents.
4. **Offline Cache Stale Overwrites:** When mobile clients operate offline, writes are queued in local IndexedDB / SQLite. If Client A goes offline for 3 days and comes online, its stale local writes will blindly overwrite newer changes made by Client B on the server unless your logic uses transactions or server timestamps (`FieldValue.serverTimestamp()`).
5. **Collection Group Queries Require Indexing:** A Collection Group query searches across all sub-collections with the same name across all parent documents (e.g. querying all `orders` sub-collections across all `users`). Collection group queries **require an explicit Collection Group Index**; without it, the query will be rejected immediately.
