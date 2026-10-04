---
title: Rate Limiting Algorithms, Distributed Architecture & HTTP 429
description: Comprehensive architectural guide to rate limiting — Token Bucket, Leaky Bucket, Sliding Window Counter, atomic Redis Lua scripts, and client jitter algorithms
tags:
  - architecture
  - performance
  - rate-limiting
  - redis
  - algorithms
---

# Rate Limiting Algorithms, Distributed Architecture & HTTP 429

**Rate limiting** controls the rate at which requests are accepted by an API or network service. It prevents denial-of-service (DoS) attacks, brute-force credential stuffing, API scraping, and protects downstream databases from cascading thundering herds.

---

## 1. The 5 Core Rate Limiting Algorithms

```
1. Token Bucket:
   Bucket fills at fixed rate. Requests consume tokens.
   Permits traffic bursts up to bucket capacity.

2. Leaky Bucket:
   Requests enter bucket; bucket leaks at constant rate.
   Smooths out traffic; drops excess when bucket overflows.

3. Fixed Window Counter:
   Count requests per minute/hour.
   FLAW: 100 requests at 11:59 + 100 requests at 12:00 = 200 requests within 2 seconds!

4. Sliding Window Log:
   Store timestamp of every request in sorted set.
   Accurate, but consumes massive memory at high volume.

5. Sliding Window Counter (Best Practice):
   Weighted sum of current window and previous window:
   Count = (Previous Window Count * Overlap Ratio) + Current Window Count
   Low memory footprint + eliminates boundary burst vulnerabilities.
```

---

## 2. Distributed Rate Limiting with Redis & Lua

In multi-instance microservices, rate limits must be synchronized globally. Naive `GET` then `SET` queries suffer from race conditions.

Use an **Atomic Redis Lua Script** executing a Token Bucket:

```lua
-- KEYS[1]: Token bucket key (e.g. rate:user:123)
-- ARGV[1]: Bucket capacity
-- ARGV[2]: Refill rate per second
-- ARGV[3]: Current timestamp (seconds)
-- ARGV[4]: Requested tokens (usually 1)

local key = KEYS[1]
local capacity = tonumber(ARGV[1])
local refill_rate = tonumber(ARGV[2])
local now = tonumber(ARGV[3])
local requested = tonumber(ARGV[4])

local data = redis.call("HMGET", key, "tokens", "last_updated")
local tokens = tonumber(data[1])
local last_updated = tonumber(data[2])

if tokens == nil then
    tokens = capacity
    last_updated = now
else
    local elapsed = now - last_updated
    tokens = math.min(capacity, tokens + elapsed * refill_rate)
    last_updated = now
end

if tokens >= requested then
    tokens = tokens - requested
    redis.call("HMSET", key, "tokens", tokens, "last_updated", last_updated)
    redis.call("EXPIRE", key, math.ceil(capacity / refill_rate))
    return {1, tokens} -- Allowed
else
    return {0, tokens} -- Rejected
end
```

---

## 3. Standard HTTP Rate Limiting Headers (RFC 6585)

When a client breaches rate limits, return **HTTP 429 Too Many Requests** with standard IETF headers:

```http
HTTP/1.1 429 Too Many Requests
Content-Type: application/json
Retry-After: 30
RateLimit-Limit: 100
RateLimit-Remaining: 0
RateLimit-Reset: 30

{
  "error": "rate_limit_exceeded",
  "message": "Too many requests. Please retry in 30 seconds."
}
```

---

## 4. Client Resiliency: Exponential Backoff with Full Jitter

When receiving an HTTP 429, naive clients retry simultaneously, crashing the recovering API again. Clients **MUST** use **Exponential Backoff with Full Jitter**:

```python
import random
import time

def calculate_backoff(attempt: int, base: float = 0.5, cap: float = 30.0) -> float:
    # Full Jitter formula (AWS Architecture Recommended)
    temp = min(cap, base * (2 ** attempt))
    sleep_duration = random.uniform(0, temp)
    return sleep_duration
```
