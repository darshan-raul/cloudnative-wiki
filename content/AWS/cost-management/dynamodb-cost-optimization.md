---
title: DynamoDB Cost Optimization
description: DynamoDB cost optimization — On-Demand vs Provisioned, Auto Scaling, Reserved Capacity, DAX, GSI/LSI cost implications, and data transfer
tags:
  - aws
  - cost-management
  - databases
---

# DynamoDB Cost Optimization

DynamoDB pricing has two capacity modes and a separate accelerator layer. Getting the capacity model right is the biggest lever — wrong mode means you're either over-paying for unused capacity or getting throttled at peak traffic.

## On-Demand vs Provisioned

**On-Demand:**
- Pay per request: $1.25 per million write request units, $0.25 per million read request units
- No capacity planning required
- Scales instantly to any traffic level

**Provisioned:**
- You reserve WCU (Write Capacity Units) and RCU (Read Capacity Units)
- 1 WCU = 1 write per second for items up to 1KB
- 1 RCU = 2 reads per second for items up to 1KB
- Charged per WCU/RCU per hour

**Which to use:**
- On-Demand: New tables, unpredictable traffic, development, traffic spikes
- Provisioned: Stable predictable traffic where you can commit to capacity

**Cost comparison:**
```
1,000 writes/second average, 1KB items, 30-day month:
On-Demand: 1,000 × 60 × 60 × 24 × 30 = 2.59B writes/month
           2.59B / 1M × $1.25 = $3,237/month

Provisioned: 1,000 WCU × $0.00065/hour × 24 × 30 = $468/month
```

Provisioned is ~85% cheaper at sustained 1,000 writes/second. But if traffic drops to 100 writes/second, you're still paying for 1,000 WCU.

**Hybrid approach:** Start with On-Demand for new tables. Switch to Provisioned once you understand the traffic pattern. Use Auto Scaling to handle traffic variation without manual capacity management.

## Auto Scaling

DynamoDB Auto Scaling adjusts provisioned capacity automatically based on CloudWatch metrics. You set:
- **Minimum:** Floor capacity (never goes below this)
- **Maximum:** Ceiling (never goes above this)
- **Target utilization:** ~70% — when utilization exceeds this, scale up

**Behavior:**
- Scales up when consumed capacity exceeds 70% of provisioned for 2 consecutive minutes
- Scales down when consumed capacity is below 60% of provisioned for 15 consecutive minutes
- Has a scaling cooldown period (60 seconds up, 300 seconds down)

**Limitation:** Auto Scaling can't respond to sudden traffic spikes fast enough. A traffic pattern that doubles in 5 minutes will get throttled because Auto Scaling has a 2-minute trigger. For spiky workloads, On-Demand or a much higher maximum is safer.

## Reserved Capacity

DynamoDB Reserved Capacity lets you commit to a specific WCU/RCU amount for 1 or 3 years, in exchange for up to 60% savings vs on-demand provisioned pricing.

**Use when:**
- You have predictable, sustained traffic
- You're migrating from on-premises and know the exact capacity requirements
- You want cost predictability for budgeting

**How it works:**
- You buy "units" of reserved capacity (e.g., 100 WCU reserved)
- Any usage above reserved is billed at normal provisioned rates
- Unused reserved capacity is wasted — you paid for it whether you use it or not

**Calculation:**
```
100 WCU reserved for 3-year = $0.00045/WCU/hour × 100 × 24 × 365 × 3 = $1,183
On-demand equivalent: $0.00065/WCU/hour × 100 × 24 × 365 × 3 = $1,708
Savings: 30%
```

## DAX (DynamoDB Accelerator)

DAX is an in-memory cache that sits in front of DynamoDB. It caches reads (eventual consistency) and reduces read request costs by ~85%.

**Cost model:**
- Node instance hours (similar to ElastiCache)
- Per request markup on top of DynamoDB read costs

**When DAX saves money:**
- High read-to-write ratio (90% reads, 10% writes)
- Hot key patterns (same key accessed frequently)
- Applications that need sub-millisecond read latency

**When DAX doesn't help:**
- Write-heavy workloads
- Strongly consistent reads (DAX only supports eventual consistency)
- Random access patterns where caching doesn't help

## GSI and LSI Cost Implications

**GSI (Global Secondary Index):**
- You define a separate partition key and sort key
- Writes to the base table also write to the GSI (consumed WCU)
- Reads from GSI consume RCU on the GSI
- **Cost trap:** If you project attributes into a GSI and then filter them out with `Select=SPECIFIC_ATTRIBUTES`, DynamoDB still reads the full index item

**LSI (Local Secondary Index):**
- Same partition key as base table, different sort key
- Shares the base table partition key — no additional read/write capacity cost
- Only available at table creation time (can't add later)

**Cost optimization:**
- Avoid over-indexing. Every GSI adds write overhead to every item write
- Use `Select=COUNT` for debugging instead of fetching full items
- Delete unused GSIs — they cost money even if not queried

## Data Transfer Costs

DynamoDB has no data transfer charge between DynamoDB and EC2 in the same region. Cross-region replication and Global Tables incur standard inter-region data transfer rates.

**DAX data transfer:** If DAX and your application are in the same AZ, no transfer charge. Cross-AZ adds standard AZ-to-AZ charges.

## On-Demand Backup and Point-in-Time Recovery

On-demand backups (manual) and point-in-time recovery (PITR) both store data in S3. S3 costs apply.

- PITR: ~$0.20 per GB-month (S3 Intelligent-Tiering)
- On-demand backup: S3 Standard pricing (~$0.023/GB-month)

For tables with large item sizes, this adds up. Consider backup frequency and retention — daily backups for 30 days costs less than hourly backups for 7 days.

## Cost Optimization Checklist

```
□ Switch from Provisioned to On-Demand for new/migrating tables
□ Configure Auto Scaling for provisioned tables
□ Buy Reserved Capacity for stable baseline traffic
□ Consider DAX for read-heavy workloads (> 80% reads)
□ Review GSI count — delete unused indexes
□ Check for tables with high WCU but low write traffic (over-provisioned)
□ Use on-demand backup instead of PITR for infrequent backup needs
```

## References

- **Homepage:** https://aws.amazon.com/dynamodb/pricing/
- **Documentation:** https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/
- **Pricing:** https://aws.amazon.com/dynamodb/pricing/

## Pricing Examples

**Scenario 1:** A growing API with DynamoDB handling 50M reads/day and 10M writes/day. On-Demand:50M RCU × $0.00025 +10M WCU × $0.000125 = $12.50 + $1.25 = $13.75/day = ~$412/month. Provisioned (2x peak for safety): 100 RCU, 20 WCU = $50 + $10 = $60/month. Auto Scaling keeps it at $60-120/month. Savings vs On-Demand: ~$300-350/month.

**Scenario 2:** A DynamoDB table with 15 GSI indexes, but only 3 are actively queried. The other 12 GSIs accumulate write costs from every write to the base table (base table writes = base table RCU/WCU + all GSI writes). Each GSI adds1-2 WCU per base table write. 12 extra GSIs × 10M writes/day = 120M extra WCU billed. Monthly cost of unused GSIs: ~$15/month. Delete unused GSIs and save $180/year.

## Nuggets & Gotchas

- **DynamoDB On-Demand has a 6-12 month lag before peak pricing applies:** AWS averages your peak RCU/WCU consumption over the last 30 minutes. If you have a sudden traffic spike (10x normal), DynamoDB doesn't immediately bill at the peak rate — it gradually scales. After 6-12 months of consistent high usage, you're billed at the higher rate.
- **GSI write costs can exceed base table costs:** Every write to the base table also writes to every GSI. A table with 5 GSIs and 1M writes/day might have 5M GSI writes/day billed separately. Design GSI count carefully.
- **DAX has a minimum of 3 nodes and minimum 30-day reservation:** DAX is not pay-per-use. You pay for the nodes regardless of actual usage. For read-heavy workloads that justify the cost, DAX saves on RCU costs. For spiky workloads, the minimum DAX cost might exceed the RCU savings.
- **DynamoDB auto scaling has a 4-minute CloudWatch metric delay:** The auto scaling adjustment takes effect after CloudWatch detects the utilization change (4-minute metric resolution) plus the scaling action time. For very spiky workloads, On-Demand might be more cost-effective than Provisioned with Auto Scaling.
- **Reserved Capacity requires 1-year or 3-year commitment:** You can buy Reserved Capacity for RCU and WCU separately. If your traffic is predictable and stable, this saves 50-70% vs On-Demand. But if traffic drops, the reserved capacity is still charged — there's no refund.