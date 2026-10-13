---
title: DynamoDB Cost Optimization
description: Billing models, trade-offs, safe workflows and scoped examples for dynamodb cost optimization.
tags:
  - aws/cost-management
date: 2026-10-12
---

# DynamoDB Cost Optimization

Price exercises use hypothetical us-east-1 (US East, N. Virginia) rates for study on 2026-10-12, not current tariffs, unless explicitly identified as a dated published fee.

DynamoDB costs depend on request/capacity mode, item sizes, consistency, indexes, storage, backups and optional features. There is no special 6–12-month On-Demand billing delay.

## Request sizing

A strongly consistent read of an item up to 4 KB consumes one read capacity unit per second; an eventually consistent read consumes half that. Larger items round to 4-KB units. Transactions consume twice the corresponding capacity. Writes round to 1-KB units, with transaction overhead separately accounted for.

For 50 million **strongly consistent reads of items up to 4 KB per day**, average required capacity is approximately 50,000,000 ÷ 86,400 = 579 RCUs before peaks. A 100-RCU table cannot sustain that load. Eventual consistency would average about 289.4 RCUs; uneven keys and bursts still matter.

Provisioned mode bills allocated capacity; On-Demand bills requests. Compare actual regional units, peak-to-average ratio and autoscaling lag. Provisioned minimums/targets must avoid throttling; On-Demand still has throughput/ramp and quota considerations.

## Index and query economics

GSIs have their own storage and provisioned/on-demand request costs. Only writes affecting an index's entries consume its write work; sparse indexes do not charge every base-table write automatically. LSIs share the table's capacity but consume storage and can add fetch/read work.

Filters, projections and `Select=COUNT` do not make scanned/read items free. Prefer key-based Query and access-pattern design over repeated Scan. Keep item size and duplicated index attributes small where requirements permit.

## Caches and backups

DAX is billed for running nodes, not per-request markup or invented 30-day reservations. A single-node cluster is possible; production availability generally calls for multiple nodes. Applications must use a compatible DAX client/endpoint. Strongly consistent reads are forwarded to DynamoDB instead of served from the DAX cache.

DynamoDB backup/PITR charges follow DynamoDB pricing, not direct S3 storage-class rates. Global tables, Streams consumers, exports and replicated writes can add charges. TTL deletion has service-specific replication effects.

## Drill

Given item sizes, read consistency, writes and index participation, calculate request units and compare modes. Model average and peak separately, then document the cache hit-rate needed to offset DAX node costs. Validate latency/correctness before adding a cache.

## Capacity-mode and autoscaling comparison

| Choice                 | Good fit                           | What to model                                       |
| ---------------------- | ---------------------------------- | --------------------------------------------------- |
| On-Demand              | Variable/uncertain request volume  | Request size/consistency, ramp behavior and quotas  |
| Provisioned            | Predictable sustained traffic      | Minimum/maximum capacity, targets, lag and hotspots |
| Reserved capacity      | Eligible provisioned baseline      | Service/Region rules and unused purchased capacity  |
| Database Savings Plans | Eligible usage under current terms | Discounted-rate hourly commitment and eligibility   |

Provisioned autoscaling uses target utilization and bounds; it is not instantaneous protection against every sudden spike or hot partition. GSI capacity must be evaluated independently. Provisioned reserved capacity does not universally cover On-Demand requests or every table feature.

## Full read/write worked example

Assume a steady table with 20 million strongly consistent reads/day of 3-KB items, one million writes/day of 1.5-KB items, and no transactions. Reads round to one 4-KB unit; writes round to two 1-KB units:

```text
average reads = 20,000,000 / 86,400 ≈ 231.48 RCU
average writes = 1,000,000 × 2 / 86,400 ≈ 23.15 WCU
at an illustrative 70% target: 330.69 RCU and 33.07 WCU
rounded planning baseline: 331 RCU and 34 WCU
```

This average-based worksheet does not guarantee peak capacity. A twofold peak, uneven keys and autoscaling reaction can need additional headroom.

For hypothetical us-east-1 exercise rates on 2026-10-12, use \$0.10/million read units and \$0.50/million write units: a 30-day On-Demand request subtotal is 600 million × \$0.10 + 60 million × \$0.50 = \$90. Compare provisioned cost using selected RCU-hour/WCU-hour rates over the same hours. Include GSI writes, storage and feature charges rather than equating “requests” with every billed unit.

## Index, cache and backup exercise

An index containing only items with a status attribute is sparse. Evaluate which inserts/updates/deletes affect its entries and projected attributes. A Scan plus filter still reads examined items; rewriting to key-based Query can reduce work if the access pattern supports it.

Estimate a DAX break-even using **avoided billable reads**, cacheable eventual-read hit rate, node hours and availability topology. Requests forwarded through DAX can still incur DynamoDB cost. Include application integration and stale-read acceptance.

For backups/PITR, compare retained data, recovery window and restores with DynamoDB pricing. Exports or global-table replication have their own costs; do not price DynamoDB backups as S3 Glacier storage.

## References

- [Read/write capacity modes](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/read-write-operations.html)
- [DynamoDB pricing](https://aws.amazon.com/dynamodb/pricing/)
- [DAX behavior](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/DAX.concepts.html)
- [GSI throughput considerations](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GSI.html)
