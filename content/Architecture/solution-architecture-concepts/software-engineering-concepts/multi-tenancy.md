---
title: Multi-Tenant Software Architecture & Data Isolation Patterns
description: Comprehensive architectural guide to multi-tenancy — Database-per-Tenant, Schema-per-Tenant, Shared Schema with PostgreSQL Row-Level Security (RLS), and noisy neighbor mitigation
tags:
  - architecture
  - software-engineering
  - multi-tenancy
  - database
  - postgres
  - rls
---

# Multi-Tenant Software Architecture & Data Isolation Patterns

**Multi-Tenancy** is an architectural pattern in software engineering where a single instance of a software application serves multiple distinct customer organizations (tenants), while providing each tenant with the illusion that they are operating a dedicated system.

---

## 1. The Three Data Isolation Models

The central decision in multi-tenant engineering is how tenant data is physically and logically partitioned in the database layer:

```
Pattern 1: Database-per-Tenant
┌────────────────────┐   ┌────────────────────┐   ┌────────────────────┐
│ Tenant A Database  │   │ Tenant B Database  │   │ Tenant C Database  │
└────────────────────┘   └────────────────────┘   └────────────────────┘

Pattern 2: Schema-per-Tenant (Shared DB)
┌──────────────────────────────────────────────────────────────────────┐
│ Single PostgreSQL Database                                           │
│  ├── Schema: tenant_a (tables: users, orders, invoices)              │
│  ├── Schema: tenant_b (tables: users, orders, invoices)              │
└──────────────────────────────────────────────────────────────────────┘

Pattern 3: Shared Schema with Tenant Discriminator Column (Shared DB & Tables)
┌──────────────────────────────────────────────────────────────────────┐
│ Table: orders                                                        │
│  id | tenant_id | customer_id | amount | status                      │
│   1 | acme_corp | usr_10      | 450.00 | completed                   │
│   2 | beta_labs | usr_22      | 120.00 | pending                     │
└──────────────────────────────────────────────────────────────────────┘
```

### Trade-Off Comparison

| Metric                     | Database-per-Tenant                    | Schema-per-Tenant                   | Shared Table (RLS)                       |
| :------------------------- | :------------------------------------- | :---------------------------------- | :--------------------------------------- |
| **Data Isolation**         | **Maximum (Physical)**                 | High (Logical)                      | Moderate (Enforced by code/policy)       |
| **Operational Overhead**   | Catastrophic at scale (10k migrations) | High (PostgreSQL connection limits) | **Lowest (Single migration script)**     |
| **Resource Efficiency**    | Very Low (Idle DB overhead)            | Moderate                            | **Maximum (Optimal connection pooling)** |
| **Cross-Tenant Analytics** | Very Difficult (Requires ETL/FDown)    | Difficult                           | **Trivial (`GROUP BY tenant_id`)**       |
| **Compliance (HIPAA/Gov)** | Frequently Mandated                    | Acceptable                          | Requires rigorous verification           |

---

## 2. Hardening Shared Schemas with PostgreSQL Row-Level Security (RLS)

In a shared schema, relying on developers to append `WHERE tenant_id = ?` to every SQL query inevitably causes data leaks when someone forgets.

**PostgreSQL Row-Level Security (RLS)** enforces tenant isolation at the database engine level:

```sql
-- 1. Enable RLS on the table
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- 2. Define Policy using application session variable
CREATE POLICY tenant_isolation_policy ON orders
    FOR ALL
    USING (tenant_id = current_setting('app.current_tenant', true))
    WITH CHECK (tenant_id = current_setting('app.current_tenant', true));

-- 3. Application sets the tenant ID before executing queries in connection:
SET LOCAL app.current_tenant = 'acme_corp';

-- 4. Even if the developer runs:
SELECT * FROM orders;
-- PostgreSQL automatically filters exclusively for rows where tenant_id = 'acme_corp'!
```

---

## 3. The Noisy Neighbor Problem & Mitigations

When Tenant A triggers a massive batch export, they must not starve Tenant B of database connections or CPU cycles.

### Architectural Mitigations:

1. **Per-Tenant Rate Limiting:** Enforce requests-per-second ceilings per tenant at the API Gateway.
2. **Fair-Queue Background Workers:** In Celery/Sidekiq, partition background queues by tenant (`queue_tenant_a`, `queue_tenant_b`) or use a Round-Robin multiplexer so one tenant cannot monopolize worker threads.
3. **VIP Tenant Pods:** Allow enterprise tier tenants to run on isolated Kubernetes node groups while standard tier tenants share pooled pods.
