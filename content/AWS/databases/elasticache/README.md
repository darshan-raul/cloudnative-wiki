---
title: "Amazon ElastiCache"
description: "ElastiCache offers Valkey, Redis OSS and Memcached-compatible caching."
tags:
  - aws/databases
date: 2026-10-12
---

# Amazon ElastiCache

ElastiCache offers Valkey, Redis OSS and Memcached-compatible caching. Select engine and deployment mode from data structures, availability, persistence/replication behavior and client compatibility. Prerequisites: [[AWS/databases/README|database selection]], [[AWS/networking/README|networking]] and [[AWS/security/iam/README|IAM]].

## Cache design and failure behavior

Cache-aside reads the authoritative database on a miss and populates the cache; write-through updates cache during writes; TTL and invalidation define staleness. Neither strategy makes the cache automatically authoritative. Design cache outage/miss storms so the database is not overwhelmed.

Valkey/Redis OSS support richer data structures and applicable replication/failover/clustered modes. Memcached has different distribution/availability semantics. Cluster-mode clients must handle topology changes and redirects; adding nodes does not remove the need for compatible client behavior.

## Provisioned and Serverless

Provisioned deployments bill nodes plus applicable transfer/backups. Serverless bills stored GB-hours and ElastiCache Processing Units (ECPUs), with engine/minimum-storage and operation-size/compute distinctions—not one invented rate per request.

Serverless limits use cache-usage-limits with DataStorage and ECPUPerSecond structures. Provisioned auth changes use the supported ModifyReplicationGroup AuthToken/AuthTokenUpdateStrategy workflow where applicable; users/user groups and IAM authentication differ by engine/version. Never mix an invented reset-password operation with a real deployment tutorial.

Online shard changes use the documented shard-configuration operation, with client and engine constraints. TLS, restricted security groups, secret management and least privilege remain necessary even inside a VPC.

## Cache-failure exercise

Prerequisites: a budgeted disposable cache, an authoritative test datastore, supported client and private reachability. Write/read a small key with a TTL, then confirm expiry and database fallback. For Valkey/Redis OSS, test a hash/list only if the application's access pattern needs it.

Deny an unauthorized client and confirm authentication/network failure. Simulate a sandbox cache outage or flush only disposable keys; the expected application behavior is controlled fallback, not data loss. Load-test hit ratio, latency, evictions, memory and database load. Use snapshots/restores only where supported and verify their recovery semantics.

Remove disposable cache resources, user groups and reviewed snapshots after testing. A live endpoint continues to incur cost even when no client sends requests.

## Cost comparison

Use equal data size, request size/rate, availability and elapsed time. One million requests multiplied by a per-million rate is not one billion requests. For Serverless, discover measured GB-hours/ECPUs and the selected engine's current Region rate; for provisioned nodes, sum node-hours and related dimensions. Learn [[AWS/reliability/backup-and-recovery|recovery boundaries]] before treating snapshots as a source-of-truth strategy.

## Engine and topology comparison

| Capability decision  | Valkey / Redis OSS                                      | Memcached                                        |
| -------------------- | ------------------------------------------------------- | ------------------------------------------------ |
| Data structures      | Supported strings, hashes, lists, sets and sorted sets  | Simpler key/value cache interface                |
| Replication/failover | Supported replication groups/engine modes               | Different node-loss/client distribution behavior |
| Sharding             | Supported cluster-mode topology and redirects           | Client/auto-discovery distribution               |
| Recovery             | Supported snapshots/persistence features depend on mode | Do not assume Redis-style persistence            |
| Client               | Engine/version/topology/TLS/auth-compatible             | Compatible discovery/hash/connection behavior    |

```text
Cluster-mode replication group (illustrative):
 shard A: primary + replica(s)
 shard B: primary + replica(s)
 shard C: primary + replica(s)

3 shards × (1 primary + 2 replicas) = 9 nodes
```

This is topology arithmetic, not a universal recommendation or three replicas per shard. Replica placement, Multi-AZ and automatic failover need explicit supported settings. A node name alone does not reveal whether the client is using a primary, reader or configuration endpoint.

## Useful data-structure operations

These are Redis/Valkey interactive protocol examples, not Bash commands:

```text
SET sandbox:greeting hello
GET sandbox:greeting
HSET sandbox:user-hash:123 name Alice
HGETALL sandbox:user-hash:123
LPUSH sandbox:tasks task-1
LRANGE sandbox:tasks 0 -1
SADD sandbox:tags cache redis
SMEMBERS sandbox:tags
ZADD sandbox:leaderboard 100 alice 200 bob
ZREVRANGE sandbox:leaderboard 0 9 WITHSCORES
```

Use TTLs for disposable keys and verify engine/client compatibility. Do not run a global FLUSHDB/FLUSHALL in a shared environment. TLS/auth choices and user ACLs are separate from the key prefix; a prefix does not automatically isolate tenants.

## Cache-aside example with explicit dependencies

This synchronous teaching function uses an injected compatible cache client and authoritative loader. It is not a hidden SQL driver or a complete production cache policy.

```python
import json

def get_user(user_id, cache, load_user):
    key = f"sandbox:user-json:{user_id}"
    cached = cache.get(key)
    if cached is not None:
        return json.loads(cached)
    value = load_user(user_id)
    if value is not None:
        cache.setex(key, 60, json.dumps(value))
    return value
```

Define what happens when cache access fails, when database data changes and when simultaneous misses stampede the loader. Write-through and invalidation can still race; no cache update makes two systems an automatic distributed transaction.

### Verify a miss, hit and invalidation

Run the function above with Python and the `redis` client installed, from a client permitted to reach the cache. Set CACHE_LAB_HOST to the actual TLS endpoint and configure a lab ACL user/password securely through CACHE_LAB_USER/CACHE_LAB_PASSWORD. Use only a dedicated lab key; no global flush is necessary.

```python
import os
import redis

cache = redis.Redis(
    host=os.environ["CACHE_LAB_HOST"], port=6379, ssl=True,
    username=os.environ["CACHE_LAB_USER"],
    password=os.environ["CACHE_LAB_PASSWORD"],
    decode_responses=True, socket_connect_timeout=5, socket_timeout=5,
)
loads = []

def load_user(user_id):
    loads.append(user_id)
    return {"id": user_id, "name": "Alice"}

lab_key = "sandbox:user-json:123"
cache.delete(lab_key)  # Only this reserved disposable key.
assert get_user("123", cache, load_user)["name"] == "Alice"
assert get_user("123", cache, load_user)["name"] == "Alice"
assert loads == ["123"]  # Miss, then hit; loader called once.
assert 0 < cache.ttl(lab_key) <= 60
cache.delete(lab_key)  # Model an explicit invalidation.
get_user("123", cache, load_user)
assert loads == ["123", "123"]
cache.delete(lab_key)
```

The hash exercise uses `sandbox:user-hash:123`, so it cannot collide with this string/JSON fixture. GET on a hash raises WRONGTYPE rather than returning a cache miss. Test denial with an ACL user lacking access to the JSON key; the exception must be visible. For a production fallback, catch the client's specific connection/timeout errors, use a bounded authoritative loader and measure fallback load; do not silently catch every exception or hide WRONGTYPE/schema bugs. [Valkey GET type contract](https://valkey.io/commands/get/), [AWS TLS client prerequisites](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/in-transit-encryption.html).

## Scaling and observability

For provisioned replication groups, change node/shard settings through supported operations and test client topology refresh. Serverless limit configuration is a different API path. Authentication updates must use the applicable engine/version contract, with credential rotation and client rollout considered together.

Track hit/miss ratio, evictions, memory, CPU, connections, replication/failover events and application latency. An apparent high hit ratio can still hide hot-key or slow-command problems. Test controlled fallback during outage and avoid saturating the authoritative database. Cleanup must stop/delete chargeable cache resources, not merely delete keys.

## References

- [ElastiCache engines](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/WhatIs.html)
- [Serverless cache usage-limit contract](https://docs.aws.amazon.com/cli/latest/reference/elasticache/modify-serverless-cache.html)
- [Replication-group auth modification](https://docs.aws.amazon.com/cli/latest/reference/elasticache/modify-replication-group.html)
- [Shard configuration contract](https://docs.aws.amazon.com/cli/latest/reference/elasticache/modify-replication-group-shard-configuration.html)
- [ElastiCache pricing](https://aws.amazon.com/elasticache/pricing/)

## Across the wiki

- [[Azure/databases/redis/README|Azure Cache for Redis Architecture, Clustering, and Enterprise Tiers]] — in-memory caches (Azure)
- [[GCP/databases/memorystore/README|GCP Memorystore (Managed Redis & Memcached)]] — in-memory caches (GCP)
- [[Architecture/solution-architecture-concepts/data-architecture/databases/redis|Redis]] — in-memory caches (Architecture)
- [[Architecture/solution-architecture-concepts/caching|Caching]] — in-memory caches (Architecture)
