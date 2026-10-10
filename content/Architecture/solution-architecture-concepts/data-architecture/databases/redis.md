---
title: Redis
tags: [architecture, databases, redis, cache, in-memory]
date: 2026-10-10
description: Redis as an in-memory data-structure server — the data types and what each is for, the single-threaded model, persistence and durability, eviction, caching patterns and their failure modes, replication, Sentinel and Cluster, and operational pitfalls.
---

# Redis

Redis is an in-memory data store. Calling it a cache undersells it: the values are **data structures** — strings, hashes, lists, sets, sorted sets, streams — with commands that operate on them atomically on the server. That is why it shows up as a cache, a session store, a rate limiter, a leaderboard, a queue and a lock service, sometimes all in one system.

Its speed comes from two choices: everything lives in memory, and commands execute on a single thread, one at a time.

> **Licensing.** Redis moved away from an open-source licence in 2024, which led to the **Valkey** fork under the Linux Foundation; Redis later added an AGPL option. Valkey is protocol-compatible and is what several cloud providers now offer by default. Everything here applies to both.

## Data types

| Type                     | Think of it as                          | Typical use                                                  | Key commands                    |
| :----------------------- | :-------------------------------------- | :----------------------------------------------------------- | :------------------------------ |
| **String**               | Bytes, or a number                      | Cached objects, counters, flags                              | `GET` `SET` `INCR` `SETEX`      |
| **Hash**                 | A small map of fields                   | An object whose fields are updated separately                | `HSET` `HGET` `HINCRBY`         |
| **List**                 | A linked list                           | Simple queues, recent-items lists                            | `LPUSH` `RPOP` `BLPOP` `LTRIM`  |
| **Set**                  | Unique, unordered members               | Tags, unique visitors, membership tests                      | `SADD` `SISMEMBER` `SINTER`     |
| **Sorted set**           | Members ordered by a score              | Leaderboards, priority queues, sliding-window rate limits    | `ZADD` `ZRANGE` `ZRANGEBYSCORE` |
| **Stream**               | An append-only log with consumer groups | Event queues with acknowledgement                            | `XADD` `XREADGROUP` `XACK`      |
| **Bitmap / HyperLogLog** | Bit arrays; probabilistic counters      | Feature flags per user; approximate distinct counts in 12 kB | `SETBIT` `PFADD` `PFCOUNT`      |
| **Geospatial**           | Points on a sphere                      | "Nearby" queries                                             | `GEOADD` `GEOSEARCH`            |
| **Pub/Sub**              | Fire-and-forget broadcast               | Live notifications; no persistence, no delivery guarantee    | `PUBLISH` `SUBSCRIBE`           |

Choosing the right type usually removes application code. A leaderboard is one `ZADD` per score and one `ZREVRANGE` per page, not a query and a sort.

## The single-threaded model

Commands are executed sequentially by one thread (network I/O may use additional threads). Consequences:

- **Every command is atomic.** `INCR` needs no lock.
- **One slow command blocks everyone.** `KEYS *`, `SMEMBERS` on a set with millions of members, or a large `DEL` stalls every client for its duration. Use `SCAN` to iterate and `UNLINK` to delete asynchronously.
- **Throughput scales by sharding**, not by adding cores to one instance.

For multi-step atomic operations there are two tools: `MULTI`/`EXEC` transactions, which queue commands and run them without interleaving (there is no rollback), and **Lua scripts or functions**, which run entirely on the server as one unit.

**Pipelining** — sending many commands without waiting for each reply — removes network round trips and is the simplest large performance win.

## Persistence

In-memory does not have to mean volatile.

| Mode              | How                                                   | Data lost on crash                           | Notes                                      |
| :---------------- | :---------------------------------------------------- | :------------------------------------------- | :----------------------------------------- |
| None              | Nothing written                                       | Everything                                   | Fine for a pure cache                      |
| **RDB snapshots** | A point-in-time dump, produced by a forked child      | Everything since the last snapshot           | Compact, fast restart                      |
| **AOF**           | Every write appended to a log, periodically rewritten | Up to one second with `appendfsync everysec` | Larger files; `always` is durable but slow |
| Both              | AOF for durability, RDB for backups                   | Up to one second                             | The usual choice when the data matters     |

Snapshots use `fork()` and copy-on-write. During a snapshot under heavy writes, memory use can approach double. Size instances accordingly and make sure the host's overcommit settings permit the fork — see [[Linux/security/sysctl|sysctl]].

Even with AOF, treat Redis as holding data you could rebuild, unless you have designed carefully for the alternative. It is not a substitute for a transactional [[Architecture/solution-architecture-concepts/data-architecture/databases/README|system of record]].

## Memory and eviction

Set `maxmemory` explicitly. Without it, Redis grows until the operating system kills it. When the limit is reached, the eviction policy decides:

| Policy                          | Behaviour                                            | Use for                               |
| :------------------------------ | :--------------------------------------------------- | :------------------------------------ |
| `noeviction`                    | Writes fail with an error                            | Data that must not disappear silently |
| `allkeys-lru` / `allkeys-lfu`   | Evict the least recently / least frequently used key | A cache                               |
| `volatile-lru` / `volatile-ttl` | Evict only among keys that have an expiry            | Mixed cache and persistent data       |

Mixing cache data and must-keep data in one instance is a common mistake: under memory pressure something gives. Use separate instances with different policies.

Always set a **TTL** on cache keys. Expired keys are removed lazily on access and by periodic sampling, so memory is not freed the instant a key expires.

## Caching patterns

| Pattern           | How                                                            | Trade-off                                                                     |
| :---------------- | :------------------------------------------------------------- | :---------------------------------------------------------------------------- |
| **Cache-aside**   | Read cache; on a miss read the database and populate the cache | Simple and resilient; first read is slow; staleness until TTL or invalidation |
| **Write-through** | Write to cache and database together                           | Cache always fresh; slower writes; caches data nobody reads                   |
| **Write-behind**  | Write to cache, flush to the database asynchronously           | Fast writes; data loss if the cache dies first                                |

Three failure modes to design for:

| Problem               | What happens                                                        | Mitigation                                                      |
| :-------------------- | :------------------------------------------------------------------ | :-------------------------------------------------------------- |
| **Cache stampede**    | A hot key expires; hundreds of requests recompute it at once        | A per-key lock or request coalescing; refresh before expiry     |
| **Cache avalanche**   | Many keys expire together, or the cache restarts empty              | Jitter on TTLs; warm-up; the database must survive a cold cache |
| **Cache penetration** | Repeated lookups for keys that do not exist always hit the database | Cache negative results briefly; a Bloom filter                  |

The last point in the avalanche row is the important one: if the system cannot function without the cache, the cache is not a cache, it is a critical dependency. More in [[Architecture/solution-architecture-concepts/caching|caching]].

## Other common uses

**Rate limiting.** A fixed window is `INCR` plus `EXPIRE`; a sliding window uses a sorted set of timestamps; a token bucket is a short Lua script. See [[Architecture/solution-architecture-concepts/performance/rate-limiting|rate limiting]].

**Distributed locks.** `SET lock:order:42 <random-token> NX PX 30000` acquires a lock with an expiry; release it with a script that deletes only if the token matches. This is adequate for _efficiency_ (avoiding duplicate work). It is **not** sufficient for _correctness_: a paused process can outlive its lock and act anyway. When correctness matters, add a fencing token checked by the resource, or use a consensus system — [[Architecture/solution-architecture-concepts/cluster-management/README|cluster management]].

**Queues.** Lists with `BLPOP` are simple but lose a job if the worker dies after popping it. **Streams** with consumer groups add acknowledgement, pending-entry tracking and redelivery. For durable, replayable event logs across many consumers, use [[Architecture/solution-architecture-concepts/event-driven-architecture/kafka/README|Kafka]].

**Sessions.** A hash per session with a TTL, which keeps application servers [[Architecture/solution-architecture-concepts/api-design/stateful-vs-stateless|stateless]].

## Replication and high availability

| Topology        | What it gives                                                                                   | Limits                                                       |
| :-------------- | :---------------------------------------------------------------------------------------------- | :----------------------------------------------------------- |
| **Replication** | One primary, asynchronous replicas for reads and redundancy                                     | No automatic failover by itself                              |
| **Sentinel**    | Monitoring processes that detect primary failure and promote a replica                          | Still one primary for writes; clients must be Sentinel-aware |
| **Cluster**     | Data sharded over 16,384 hash slots across several primaries, each with replicas, with failover | Multi-key operations must stay within one slot               |

Replication is **asynchronous**: a write acknowledged by the primary can be lost if it fails before the replica receives it. `WAIT` reduces the window; it does not make Redis strongly consistent.

In Cluster mode, keys used together must hash to the same slot. A **hash tag** forces that: `{user:42}:cart` and `{user:42}:profile` share a slot because only the part in braces is hashed.

Managed options — [[AWS/databases/elasticache/README|ElastiCache]] and MemoryDB, Azure Cache for Redis, Google Memorystore — handle failover, patching and scaling. MemoryDB adds a durable transaction log for use as a primary database.

## Operational pitfalls

| Pitfall                                                | Why it hurts                                                    |
| :----------------------------------------------------- | :-------------------------------------------------------------- |
| `KEYS`, `FLUSHALL`, unbounded `LRANGE` in production   | Blocks the single thread                                        |
| **Big keys** (a hash or list with millions of entries) | Slow to read, serialise, replicate and delete                   |
| **Hot keys**                                           | One shard saturated while others idle                           |
| No `maxmemory`                                         | The OOM killer chooses for you                                  |
| No authentication, bound to a public address           | A frequent source of data breaches and cryptomining compromises |
| A new connection per request                           | Connection set-up dominates latency — use a pool                |
| Treating Pub/Sub as reliable                           | Messages to disconnected subscribers are simply dropped         |

Diagnose with `SLOWLOG GET`, `LATENCY DOCTOR`, `INFO memory`, `redis-cli --bigkeys` and `--hotkeys`. Watch memory fragmentation, evictions, replication lag and connected clients. Secure it with TLS, ACL users, and network isolation in private subnets behind [[AWS/networking/vpc/security-groups|security groups]].

## Related

- [[Architecture/solution-architecture-concepts/data-architecture/databases/README|Databases]]
- [[Architecture/solution-architecture-concepts/data-architecture/hashing|Hashing]] — consistent hashing and hash slots
- [[Architecture/solution-architecture-concepts/reliability/idempotency|Idempotency]] — often implemented with Redis keys
- [[Azure/databases/redis/README|Azure Cache for Redis]]
- [Redis documentation](https://redis.io/docs/latest/) · [Valkey](https://valkey.io/)

## Across the wiki

- [[GCP/databases/memorystore/README|GCP Memorystore (Managed Redis & Memcached)]] — in-memory caches (GCP)
