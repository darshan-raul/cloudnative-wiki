---
title: Blue-Green Deployments
---

# Blue-Green Deployments

Blue-green deployment is a release strategy that maintains two identical production environments — blue (current live) and green (new version) — and switches traffic between them instantly. The goal is zero-downtime deployment with instant rollback capability.

## How It Works

```
Normal operation:
 User Traffic → Blue Environment (v1) → Database
  Green Environment (v2, idle)

Deploy:
  1. Deploy v2 to Green environment (no traffic)
2. Run smoke tests against Green
  3. Switch load balancer → Green (v2 now live)
  4. Monitor for issues
  5. Decommission Blue (or keep as rollback target)

Rollback:
  Switch load balancer → Blue (instant, v1 back live)
```

## Infrastructure Requirements

Blue-green requires:
- **Two identical environments** — same compute, same database, same configuration
- **Shared database** — both environments point to the same data store (no separate DB per environment)
- **Load balancer or DNS switch** — ability to redirect all traffic instantly
- **Sufficient infrastructure** — double the compute during deployment window

### Database Complication

The shared database is the hardest part. Both environments must be compatible with the current schema AND the new schema simultaneously:

```
v1 code:   SELECT id, name, email FROM users
v2 code:   SELECT id, name, email, phone FROM users  (new column)

If phone column doesn't exist yet → v2 code breaks
```

Solutions:
- **Expand-contract pattern** — add column as nullable first, deploy v2, backfill, drop old column
- **Feature flags** — v2 code paths are gated until schema is ready
- **Database migration tooling** — migrations run before switch, both code versions tolerate the schema

## Deployment Procedure

```bash
# 1. Deploy v2 to green environment (blue still serving traffic)
kubectl apply -f green-deployment.yaml

# 2. Verify green is healthy
kubectl rollout status deployment/api-green

# 3. Smoke test against green
curl -H "Host: api.example.com" https://green.api.example.com/healthz

# 4. Switch traffic (Nginx example)
kubectl scale deployment/api-blue --replicas=0   # drain blue
kubectl scale deployment/api-green --replicas=N  # scale green to full

# Or via service selector swap:
kubectl patch service api -p '{"spec":{"selector":{"version":"green"}}}'

# 5. Monitor for 5-15 minutes
# 6. Blue becomes rollback target (keep at0 replicas until needed)
```

## Rollback

```bash
# Instant rollback: switch back to blue
kubectl patch service api -p '{"spec":{"selector":{"version":"blue"}}}'
# Traffic back to v1 in seconds
```

Rollback is instantaneous because:
- Blue environment still exists (at0 replicas, but the pods/images are preserved)
- Database state is unchanged (blue and green share the same DB)
- No data migration to reverse

## Route53 DNS Failover

For DNS-based switching:

```bash
# Pre-deployment: blue = A record for1.2.3.4, green = A record for 5.6.7.8
# Deployment: update A record

# Update DNS TTL to 60 seconds (5 minutes before deployment)
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890 \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.example.com",
        "Type": "A",
        "TTL": 60,
        "ResourceRecords": [{"Value": "5.6.7.8"}]
      }
    }]
  }'
```

> **Warning:** DNS TTL must be low (60s or less) before deployment. If TTL is 24 hours, DNS rollback takes24 hours.

## Database Schema Changes with Blue-Green

Blue-green + schema changes require careful sequencing:

```
Phase 1: Expand (no downtime)
 1. Add phone column as nullable to users table
  2. Deploy v2 code that writes phone (but tolerates NULL)
  3. Both blue and green work with the new schema

Phase 2: Migrate
4. Backfill phone data for existing users
  5. v2 code now expects phone to be populated

Phase 3: Contract (next release)
  6. Drop the old columns/tables that v1 needed
  7. This is a separate deployment, not this one
```

See [[expand-contract|Expand-Contract Pattern]] for full schema migration pattern.

## Blue-Green for Databases

For database-level blue-green (separate DB per environment):

```
Blue DB (v1 data) ←→ Green DB (v2 data)
       ↑
 Replicate changes from Blue to Green (one-way)

After switch:
  Writes go to Green DB
  Read replicas of Green serve reads
 Blue DB is decommissioned
```

This requires **dual-write** during the transition window — writes go to both DBs until switch is complete. Complex and error-prone. Prefer shared DB + expand-contract for most cases.

## Traffic Shaping (Canary + Blue-Green Hybrid)

Instead of full100% traffic switch, route a percentage to green first:

```yaml
# Kubernetes with weighted service
apiVersion: v1
kind: Service
metadata:
  name: api
spec:
  selector:
    version: blue
---
# Use Istio or AWS ALB weighted routing for gradual traffic shift
# 1% →5% → 25% → 50% → 100% over time
```

Benefits:
- Catch issues with 1% of traffic before full rollout
- Monitor error rates, latency on small subset
- Rollback only affects small percentage

## When to Use Blue-Green

| Use case | Blue-green appropriate? |
|---|---|
| Stateless application (no DB) | Yes, straightforward |
| Shared database, schema-compatible | Yes, with expand-contract |
| Separate database per environment | Complex, consider other patterns |
| Frequent small deployments | High infrastructure cost, consider rolling |
| Database migrations (large) | Consider feature flags instead |
| State services (Redis, sessions) | Session state sync required |

## Advantages

- **Instant rollback** — switch back in seconds, no redeployment
- **Zero downtime** — traffic switch is near-instantaneous
- **Full pre-production testing** — green is a real production environment with real data
- **Simple mental model** — easy to understand, explain, and audit

## Disadvantages

- **Double infrastructure cost** — two full environments during deployment
- **Database complexity** — shared DB requires careful schema management
- **Session/state synchronization** — stateful services need shared stores
- **Environment parity** — drift between blue and green is a risk

## Related

- [[expand-contract|Expand-Contract Pattern]] — safe database schema changes
- [[strangler-fig|Strangler Fig Pattern]] — incremental migration from legacy systems
- [[data-migration|Data Migration Patterns]] — bulk data movement strategies
