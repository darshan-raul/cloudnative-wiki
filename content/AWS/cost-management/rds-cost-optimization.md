---
title: RDS Cost Optimization
description: Amazon RDS and Aurora cost optimization — instance right-sizing, Aurora Serverless v2, stopping idle dev databases, and Reserved Instances
tags:
  - aws
  - cost-management
  - rds
  - aurora
  - database
date: 2026-10-04
---

# Amazon RDS Cost Optimization

Relational databases are frequently among the largest line items in an enterprise AWS bill. Optimizing RDS and Aurora requires addressing compute instance sizing, high-availability licensing, storage growth, and commitment discounts.

---

## 1. Instance Right-Sizing & Graviton Migration

- **Migrate to Graviton (e.g. `db.r7g` / `db.m7g`):** Delivers up to 20% better performance at 10% lower cost compared to equivalent x86 instances.
- **CPU & Memory Sizing:** Use Amazon CloudWatch and Performance Insights to identify instances with `< 15%` average CPU and generous memory headroom. Downgrade by one instance size.

---

## 2. Dev/Test Environment Cost Reduction

1. **Disable Multi-AZ for Non-Production:** Multi-AZ doubles instance and storage costs. Dev/test databases should run Single-AZ with automated daily snapshots.
2. **Automated Stop/Start:** Non-production databases rarely need to run overnight or on weekends. Stopping instances for 12 hours a day and all weekend reduces compute costs by **~65%**:
   ```python
   # Lambda function to stop dev RDS instances at 7 PM
   import boto3
   rds = boto3.client('rds')
   rds.stop_db_instance(DBInstanceIdentifier='dev-postgres-db')
   ```
   _(Note: Stopped RDS instances automatically restart after 7 days if not re-stopped)._

---

## 3. Aurora Serverless v2 Optimization

For variable or sporadic workloads, Aurora Serverless v2 scales dynamically in fine-grained increments of 0.5 ACU (Aurora Capacity Units).

- Set **Minimum ACU** to 0.5 in dev/test to minimize baseline idling cost.
- Set **Maximum ACU** cap to prevent runaway scaling during unindexed queries or runaway batch jobs.

---

## 4. Storage Auto-Scaling & IOPS Selection

- **gp3 Storage:** Migrate from `gp2` or `io1` to `gp3`. `gp3` provides a baseline 3,000 IOPS and 125 MB/s throughput for free, with storage cost 20% lower than gp2.
- **Storage Auto-Scaling:** Enable storage auto-scaling with a sensible threshold to avoid pre-provisioning terabytes of unallocated disk.
