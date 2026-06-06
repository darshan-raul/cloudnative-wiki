---
title: Amazon ElastiCache
description: Amazon ElastiCache — managed in-memory caching. Redis vs Memcached comparison, clusters, replication groups, engine commands, auto scaling, and serverless.
tags:
  - aws
  - databases
  - cache
  - elasticache
  - redis
  - memcached
---

# Amazon ElastiCache

ElastiCache provides managed in-memory caching: **Redis** (advanced, supports data structures, replication, clustering) and **Memcached** (simple, pure key-value).

## Redis vs Memcached

| Feature | Redis | Memcached |
|---------|-------|-----------|
| Data structures | Strings, Lists, Sets, Hashes, Sorted Sets, Streams | Strings only |
| Replication | Yes (read replicas) | No (single node only) |
| Clustering | Yes (up to 90 shards) | Yes (auto-discovery) |
| Persistence | RDB + AOF snapshots | No |
| Pub/Sub | Yes | No |
| Transactions | Yes (MULTI/EXEC) | No |
| Sorted sets | Yes | No |
| Geospatial | Yes | No |
| Lua scripting | Yes | No |
| TLS | Yes | Yes |
| Auth | Yes (AUTH + ACLs) | Yes (SASL) |
| Use case | Rich data, pub/sub, sessions | Simple key-value cache |

## Redis: Key Concepts

### Cluster Mode

```
┌──────────────────────────────────────────────────┐
│  Redis Cluster (Cluster Mode Enabled)             │
│                                                   │
│  Shard 1          Shard 2          Shard 3      │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐  │
│  │ Primary  │     │ Primary  │     │ Primary  │  │
│  │  ├─ Rep1 │     │  ├─ Rep1 │     │  ├─ Rep1 │  │
│  │  └─ Rep2 │     │  └─ Rep2 │     │  └─ Rep2 │  │
│  └──────────┘     └──────────┘     └──────────┘  │
│                                                   │
│  3 shards × 3 replicas = 9 nodes                 │
│  Each shard: 1 primary + 2 read replicas         │
└──────────────────────────────────────────────────┘
```

### Creating a Redis Cluster

```bash
# Create replication group (Redis)
aws elasticache create-replication-group \
  --replication-group-id my-redis \
  --engine redis \
  --engine-version 7.0 \
  --replication-group-description "My Redis cluster" \
  --num-cache-clusters 3 \
  --cache-node-type cache.r6g.large \
  --cache-subnet-group-name my-subnet-group \
  --security-group-ids sg-xxxxx \
  --automatic-failover-enabled \
  --multi-az-enabled \
  --at-rest-encryption-enabled \
  --transit-encryption-enabled \
  --auth-token-enabled
```

## Memcached: Key Concepts

### Auto-Discovery

Memcached clusters automatically update node addresses:

```
┌─────────────────────────────────────┐
│  Memcached Cluster                   │
│                                      │
│  ┌──────────┐ ┌──────────┐          │
│  │  Node 1  │ │  Node 2  │  ...    │
│  └──────────┘ └──────────┘          │
│                                      │
│  Client connects to config endpoint  │
│  Config endpoint auto-updates        │
│  as nodes scale                      │
└─────────────────────────────────────┘
```

### Creating a Memcached Cluster

```bash
aws elasticache create-cache-cluster \
  --cache-cluster-id my-memcached \
  --engine memcached \
  --engine-version 1.6.12 \
  --cache-node-type cache.t4g.micro \
  --num-cache-nodes 2 \
  --cache-subnet-group-name my-subnet-group \
  --security-group-ids sg-xxxxx \
  --auto-minor-version-upgrade
```

## Common Operations

### Connecting

```bash
# Get endpoint
aws elasticache describe-replication-groups \
  --replication-group-id my-redis \
  --query 'ReplicationGroups[0].MemberClusters'

# Connect with redis-cli
redis-cli -h my-redis.xxxxx.use1.cache.amazonaws.com -p 6379

# TLS connect
redis-cli -h my-redis.xxxxx.use1.cache.amazonaws.com -p 6379 --tls
```

### Redis Commands

```bash
# String operations
SET mykey "hello"
GET mykey
INCR counter
DECR counter

# Hash operations
HSET user:123 name "Alice" email "alice@example.com"
HGET user:123 name
HGETALL user:123

# List operations
LPUSH mylist "item1"
RPUSH mylist "item2"
LRANGE mylist 0 -1

# Set operations
SADD tags "redis" "cache"
SMEMBERS tags
SISMEMBER tags "redis"

# Sorted Set (leaderboard)
ZADD leaderboard 100 "alice"
ZADD leaderboard 200 "bob"
ZREVRANGE leaderboard 0 9 WITHSCORES
```

### Cache Strategies

**Cache-Aside (Lazy Loading):**

```python
def get_user(user_id):
    # 1. Check cache first
    user = redis.get(f"user:{user_id}")
    if user:
        return json.loads(user)
    
    # 2. Cache miss — load from DB
    user = db.query("SELECT * FROM users WHERE id = ?", user_id)
    
    # 3. Write to cache
    redis.setex(f"user:{user_id}", 3600, json.dumps(user))
    
    return user
```

**Write-Through:**

```python
def save_user(user_id, data):
    # 1. Write to DB
    db.execute("UPDATE users SET ... WHERE id = ?", user_id)
    
    # 2. Update cache
    redis.setex(f"user:{user_id}", 3600, json.dumps(data))
```

## ElastiCache Serverless

No instance management — pay per request:

```bash
aws elasticache create-serverless-cache \
  --serverless-cache-name my-redis-serverless \
  --engine redis \
  --cache-usage-limit '{
    "Quantity": 100000,
    "Unit": "requests-per-second"
  }'
```

## Scaling

### Redis Scaling

```bash
# Add read replica
aws elasticache increase-replica-count \
  --replication-group-id my-redis \
  --apply-immediately \
  --new-replica-count 4

# Scale up (change node type)
aws elasticache modify-replication-group \
  --replication-group-id my-redis \
  --cache-node-type cache.r6g.xlarge

# Scale shards (Redis 7, cluster mode)
aws elasticache reshard \
  --replication-group-id my-redis \
  --node-group-count 4
```

### Memcached Scaling

```bash
# Add nodes
aws elasticache modify-cache-cluster \
  --cache-cluster-id my-memcached \
  --num-cache-nodes 4
```

## Redis AUTH and ACLs

```bash
# Enable AUTH
aws elasticache modify-replication-group \
  --replication-group-id my-redis \
  --auth-token-enabled \
  --auth-token-updates-require-reboot

# Set password
aws elasticache reset-auth-token \
  --replication-group-id my-redis
```

### Redis ACLs (Redis 6+)

```bash
# Create ACL
aws elasticache create-user \
  --user-id my-app-user \
  --engine redis \
  --access-string "on ~app:* +read +write +get +set +hget +hset -@all" \
  --auth-token-passwords "SecurePassword123"
```

## Monitoring

```bash
# Key metrics
# Redis: CPUUtilization, DatabaseMemoryUsagePercentage, CurrConnections
# Memcached: CPUUtilization, FreeableMemory, CurrItems

# Get metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ElastiCache \
  --metric-name DatabaseMemoryUsagePercentage \
  --dimensions Name=ReplicationGroupId,Value=my-redis
```

Key metrics:
- `DatabaseMemoryUsagePercentage` — memory pressure (keep < 80%)
- `CurrConnections` — connection count (spike = problem)
- `Evictions` — items evicted (need more memory)
- `ReplicationLag` — replica lag (keep < 1 second)

## Pricing

| Node Type | Cost/hr |
|-----------|---------|
| cache.t4g.micro | $0.016/hr (~$12/month) |
| cache.r6g.large | $0.096/hr (~$69/month) |
| cache.r6g.xlarge | $0.192/hr (~$138/month) |

Serverless: $0.00006 per request + $0.00012 per GB-hour.

## Use Cases

| Use Case | Best Engine | Example |
|----------|-------------|---------|
| Session store | Redis | Web user sessions |
| Leaderboard | Redis (Sorted Sets) | Gaming scores |
| Chat/messaging | Redis (Pub/Sub) | Real-time chat |
| Rate limiting | Redis | API rate limits |
| Full-page cache | Redis or Memcached | Static content |
| Distributed lock | Redis | Mutex, coordination |

## References

- **Homepage:** https://aws.amazon.com/elasticache/
- **Documentation:** https://docs.aws.amazon.com/elasticache/
- **Pricing:** https://aws.amazon.com/elasticache/pricing/

## Pricing Examples

**Scenario 1:** A session store with 3 cache.r6g.large nodes (Redis, Multi-AZ). $0.096/hr × 3 × 24 × 30 = $207/month. Compare to RDS for sessions (not ideal): db.r6g.large = $181/month. Redis is appropriate for sessions.

**Scenario 2:** A rate limiter using Redis serverless. 1000 requests/second × 2.6M seconds/month = 2.6B requests/month. 2.6B × $0.00006 = $156/month. Storage: 1GB × $0.00012 × 720 hr/month = $0.086/month. Total: ~$156/month. Compare to provisioned cache.r6g.large: $69/month (fixed). Serverless is 2.2x more expensive at this load.

## Nuggets & Gotchas

- **ElastiCache Redis `DatabaseMemoryUsagePercentage` at 100% triggers `evictions` metric — you need to scale or increase TTL:** When memory is full, Redis evicts items (LRU). Monitor `Evictions` metric and set appropriate TTL. Use `maxmemory-policy` to control eviction behavior.
- **Redis Cluster Mode Enabled requires Redis 3.2.10 or later and cluster-aware clients:** If you enable clustering, all keys are distributed across shards. Not all Redis commands work (e.g., `MGET` across keys in different slots fails). Test with cluster mode before committing.
- **Memcached has NO replication — each node is independent:** If a Memcached node fails, data on that node is lost. Use `autodiscovery` for client-side failover and set `expected-updates` correctly in your client. For HA, use Redis instead.
- **Redis `BGSAVE` and `AOF` rewrite use fork() — on large datasets, this can cause latency spikes:** The `fork()` operation copies the parent's page table. On a 100GB Redis instance, this can be several seconds of latency. Use `BGREWRITEAOF` during low-traffic periods or disable AOF with `appendonly no`.
- **ElastiCache nodes don't have public IPs — they must be accessed from within the VPC:** Your application (EC2, Lambda, ECS) must be in the same VPC and subnet group as the ElastiCache cluster. For local development, use a local Redis container instead.