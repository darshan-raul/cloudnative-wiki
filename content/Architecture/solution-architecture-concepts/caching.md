---
title: Caching
tags: [architecture, performance, redis]
date: 2025-05-24
description: Caching strategies, patterns, and eviction policies
---

# Caching

Caching is the single highest-leverage performance optimization in most systems. Get it right and you can handle 10x traffic with the same infrastructure.

---

## The Cache Hit Pyramid

```
        ┌─────────────┐
        │   Memory │  ← fastest, smallest (MB)
        │ (L1/L2)   │
        └──────┬──────┘
 │
        ┌──────▼──────┐
        │    Redis    │  ← fast, small-to-medium (GB)
        │ Memcached  │
        └──────┬──────┘
               │
        ┌──────▼──────┐
        │     SSD     │  ← medium speed, large (TB)
        │ (local)   │
        └──────┬──────┘
               │
        ┌──────▼──────┐
        │    Disk │  ← slow, largest
        └─────────────┘

Cache hit ratio = (hits) / (hits + misses)
Target: >90% for hot data
```

---

## Cache Patterns

### 1. Cache-Aside (Lazy Loading)

```
App: GET user:42 ──────────────────────▶ Cache
                │ │
                │  miss ◀────────────────────────────┤
                ▼ │
          DB: SELECT * FROM users WHERE id=42        │
                │                                    │
                │ write result │
                ▼                                    │
          Cache: SET user:42 {data} (TTL: 1h) ◀──────┘
```

```python
def get_user(user_id):
    # 1. Check cache
    cached = redis.get(f"user:{user_id}")
    if cached:
        return json.loads(cached)

    # 2. Cache miss → DB
    user = db.query("SELECT * FROM users WHERE id = %s", user_id)

    # 3. Write to cache with TTL
    redis.setex(f"user:{user_id}", 3600, json.dumps(user))
    return user
```

**Pros:** Only caches what's actually read, DB stays fresh
**Cons:** First request always hits DB (cold start)

### 2. Write-Through

```
Write: App ──▶ Cache ──▶ DB (同步)
```

```python
def update_user(user_id, data):
    db.update(user_id, data)
    redis.setex(f"user:{user_id}", 3600, json.dumps(data))
```

**Pros:** Cache always consistent with DB
**Cons:** Write latency = cache + DB latency

### 3. Write-Behind (Write-Back)

```
Write: App ──▶ Cache ──▶ DB (async, batched)
```

**Pros:** Fast writes, reduces DB load
**Cons:** Data loss risk if cache fails before flush

### 4. Refresh-Ahead

Proactively refresh expiring entries before they expire.

```python
# Background job: refresh hot keys before TTL expires
def refresh_hot_keys():
    for key in redis.zrange("hot_keys", 0, -1):
        data = db.get(key)
        # Refresh only if key exists and is close to expiring
        ttl = redis.ttl(key)
        if ttl< 60:  # refresh if< 60s to live
            redis.setex(key, 3600, data)
```

---

## Eviction Policies

| Policy | What It Does | Use When |
|--------|-------------|----------|
| LRU (Least Recently Used) | Evict oldest accessed | General purpose |
| LFU (Least Frequently Used) | Evict least popular | Zipfian access patterns |
| TTL | Evict after time | Data that goes stale |
| Random | Evict random | Very uniform access |
| FIFO | Evict oldest written | Simple, predictable |

---

## Redis-Specific Patterns

### Distributed Lock

```python
# Simple lock
import redis, time

def acquire_lock(lock_name, timeout=10):
    acquired = redis.set(f"lock:{lock_name}", "1", nx=True, ex=timeout)
    return acquired

def release_lock(lock_name):
    redis.delete(f"lock:{lock_name}")

# Usage
if acquire_lock("process_orders"):
    try:
        process_orders()
    finally:
        release_lock("process_orders")
```

### Rate Limiting

```python
# Sliding window counter
def rate_limit(user_id, max_requests=100, window=60):
    key = f"ratelimit:{user_id}"
    current = redis.incr(key)
    if current == 1:
        redis.expire(key, window)
    return current <= max_requests
```

### Circuit Breaker

```python
# Circuit breaker state machine
CLOSED = "closed"  # normal operation
OPEN = "open"      # failing, reject requests
HALF_OPEN = "half_open"  # test if service recovered

def call_with_circuit_breaker(service, fallback):
    if state == OPEN:
        if time.time() - last_failure > recovery_timeout:
            state = HALF_OPEN
        else:
            return fallback()

    try:
        result = service()
        if state == HALF_OPEN:
            state = CLOSED
        return result
    except Exception:
        state = OPEN
        last_failure = time.time()
        return fallback()
```

---

## Cache Sizing

```
Rule of thumb: cache20% of hot data in 20% of memory

Hot data: data accessed >80% of the time
Working set: the subset of data actively in use

If your working set fits in Redis memory:
 → Cache hit ratio will be very high
  → DB will barely be touched

If working set > Redis memory:
  → LRU eviction kicks in
  → Cache hit ratio drops
  → Consider: sharding, compression, or tiered cache
```

---

## Quick Checklist

```
□ Cache-aside for read-heavy workloads
□ Write-through for small, frequently updated data
□ TTL on everything (no unbounded growth)
□ Bounded cache size (maxmemory + eviction policy)
□ Cache key naming: {service}:{entity}:{id}
□ Cache monitoring: hit ratio, memory usage, evictions
□ Graceful degradation: what happens when cache is unavailable?
□ No sensitive data in cache without encryption
```

---

## Source

- [ByteByteGo — Caching](https://www.bytebytego.com/)
- [Redis University — RC9](https://university.redis.com/)
