---
title: Idempotency
tags: [architecture, reliability, api-design]
date: 2025-05-24
description: Designing APIs and operations that are safe to retry
---

# Idempotency

An operation is **idempotent** if calling it once or multiple times produces the **same result**.

```
f(x) = f(f(x)) = f(f(f(x)))  ← always true for idempotent ops
```

Critical for **distributed systems** where network failures cause unexpected retries.

---

## Why It Matters

```
Client API DB
  │ ──── POST /order ──▶ │                    │
  │                      │ ──── INSERT ──────▶ │
  │ ◄─── 500 Timeout ─── │ │
  │                      │                    │
  │ (did it succeed?)    │                    │
  │                      │                    │
  │ ──── POST /order ──▶ │ │
  │                      │ ──── INSERT ──────▶ │
  │ ◄─── 201 Created ─── │  ← DUPLICATE!      │
```

Without idempotency, retries create **duplicate records, charges, or side effects**.

---

## Idempotent by HTTP Method

| Method | Idempotent? | Notes                           |
| ------ | ----------- | ------------------------------- |
| GET    | ✅ Yes      | Read-only                       |
| HEAD   | ✅ Yes      | Read-only                       |
| PUT    | ✅ Yes      | Same state regardless of repeat |
| DELETE | ✅ Yes      | Deleting twice = already gone   |
| POST   | ❌ No       | Creates new resource each time  |
| PATCH  | ❌ No       | Depends on implementation       |

---

## Techniques

### 1. Idempotency Keys (Client-Generated)

Client generates a unique key per logical operation. Server deduplicates.

```
Client Server
  │ │
  │ ─ POST /payment ────────────── │
  │   Idempotency-Key: abc123 │
  │                                │
  │ ◄── 201 Created ───────────── │
  │                                │
  │ (retry with same key)          │
  │ ─ POST /payment ────────────── │
  │   Idempotency-Key: abc123      │
  │                                │
  │ ◄── 201 Created ───────────── │  ← same result, no duplicate
```

**Implementation:**

```python
# Server-side idempotency check
async def create_payment(request: PaymentRequest):
    key = request.headers["Idempotency-Key"]

    # Check if already processed
    existing = await redis.get(f"idempotency:{key}")
    if existing:
        return json.loads(existing)  # return cached response

    result = await db.insert_payment(request)

    # Cache response with TTL (e.g., 24h)
    await redis.setex(f"idempotency:{key}", 86400, json.dumps(result))
    return result
```

###2. PUT with Deterministic IDs

If the resource ID is deterministic (e.g., `user_id`), PUT naturally deduplicates.

```python
# PUT is idempotent — same ID, same state
PUT /orders/ord-12345
{
  "amount": 99.99,
  "status": "confirmed"
}
```

### 3. DELETE with Graceful Handling

```python
# Deleting twice — second call returns 404, which is correct
async def delete_resource(resource_id: str):
    deleted = await db.delete(resource_id)
    if not deleted:
        raise ResourceNotFoundError(resource_id)
    return {"deleted": True}
```

### 4. Optimistic Concurrency Control

Use a version number or ETag to detect conflicting writes.

```python
# Client sends current version
PUT /orders/ord-12345
If-Match: "v3"
{
  "status": "shipped"
}

# Server checks version before writing
async def update_order(order_id, data, expected_version):
    current = await db.get_order(order_id)
    if current.version != expected_version:
        raise ConflictError("Version mismatch")
    await db.update_order(order_id, data, version=expected_version + 1)
```

---

## Quick Checklist

```
□ POST endpoints have Idempotency-Key header support
□ Idempotency keys stored in Redis with TTL
□ PUT/PATCH use ETag / If-Match for concurrency
□ DELETE handles "already gone" gracefully
□ Side-effect-free operations (GET, HEAD) clearly marked
□ API docs document idempotency behavior
```

---

## Common Pitfalls

| Pitfall                        | Problem                        | Fix                                            |
| ------------------------------ | ------------------------------ | ---------------------------------------------- |
| No idempotency key on payment  | Double charge on retry         | Add key header                                 |
| Short TTL on idempotency cache | Late retry fails               | Match business SLA (e.g., 7 days for payments) |
| PATCH without version check    | Lost update on concurrent edit | ETag +409 Conflict                             |
| DELETE without 404 handling    | Client treats 500 as error     | Return 204 or 404 for already-deleted          |

---

## Source

- [Stripe API — Idempotency](https://stripe.com/docs/idempotency)
- [Google API Design Guide — Errors](https://googleapis.github.io/api-design-guide/)
