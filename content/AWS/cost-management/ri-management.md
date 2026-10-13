---
title: Reserved Instance Management
description: Accurate billing models, decision workflows and scoped examples for ri management.
tags:
  - aws/cost-management
date: 2026-10-12
---

# Reserved Instance Management

Price exercises in this note use hypothetical us-east-1 (US East, N. Virginia) rates for study on 2026-10-12, unless explicitly identified as a dated published fee. They are assumptions, not current tariffs; exclusions remain material.

Manage commitments as a portfolio, not a collection of isolated purchases. Start with [[AWS/cost-management/reserved-instances|RI scope rules]] and [[AWS/cost-management/savings-plans|Savings Plans]].

## Utilization versus coverage

Utilization asks how much purchased benefit was used. Coverage asks how much eligible running usage received a benefit. High coverage can coexist with unused commitments; high utilization can coexist with uncovered peaks.

Inventory purchases by owner, service, Region, platform, tenancy, scope, payment option, start/end date and hourly obligation. Consolidated billing can share member-account benefits where preferences permit. Zonal EC2 capacity remains scoped to its owner/AZ; discount sharing is not shared capacity.

## Operating cycle

1. Compare actual hourly usage against benefits and scheduled shutdowns.
2. Recalculate the baseline after rightsizing, migrations and architecture changes.
3. Review reservation expiration dates separately from dollar budget thresholds.
4. Evaluate permitted Standard modifications or Convertible exchanges before buying replacements.
5. Consider eligible Standard EC2 resale only after reviewing Marketplace restrictions and likely proceeds.
6. Stage renewals rather than automatically renewing the previous fleet.

ASG instance replacement does not require a new RI when replacement usage still matches. Conversely, switching family, Region, platform or tenancy can leave benefits idle. A reservation does not prevent an instance from being stopped.

## Example: evaluate a change

An illustrative \$980 all-upfront, three-year reservation amortizes to about \$0.03729/hour using 26,280 hours. The amortized price is useful for cost allocation, but stopping an instance does not refund this sunk payment. Compare **incremental future cost** of the proposed replacement and residual usable benefit, not an invented cancellation credit.

If a migration needs new On-Demand compute while the RI becomes unused, show both obligations. Do not count the old RI as avoidable savings unless an eligible modification, exchange, sharing or realized sale actually recovers value.

## Safe practice

Use read-only reservation inventory and billing reports. Build an expiry calendar and a per-hour utilization chart. Document the selected accounting view (unblended, amortized or net amortized), so upfront purchases do not appear to be a workload spike.

## Coverage and utilization worksheet

Restrict this exercise to compatible, equal-size EC2 RI-equivalent hours. For a 24-hour day, purchase ten units, run eight continuously, and cover all eight:

```text
purchased benefit-hours = 10 × 24 = 240
running matching hours  = 8 × 24 = 192
used benefit-hours      = 192
coverage = 192 / 192 = 100%
utilization = 192 / 240 = 80%
```

If twelve units run all day with the same purchase, coverage becomes 240/288 = 83.33%, while utilization becomes 100%. Neither metric shows guest CPU efficiency. Use the correct normalized-hour/service dimensions in real reports; Savings Plans coverage uses its own cost-based definition.

## Expiry and chargeback operating model

| Review                 | Evidence                                        | Possible action                                             |
| ---------------------- | ----------------------------------------------- | ----------------------------------------------------------- |
| Low utilization        | Matching usage, attributes and sharing settings | Rightsize renewal; assess sharing or permitted modification |
| Coverage drop          | New family/Region, expiration or traffic change | Investigate before buying more                              |
| Approaching expiry     | Purchase end timestamps                         | Reforecast and obtain purchase approval                     |
| Migration              | Residual commitment and target costs            | Model overlap; assess valid exchange or Standard sale       |
| Shared-account benefit | Actual allocation and net/amortized cost        | Apply documented showback/chargeback policy                 |

Create an inventory-driven 90/60/30-day internal review schedule. These are proposed governance intervals, not guaranteed AWS email behavior or a native Budgets expiry trigger.

Chargeback can allocate unused commitment to its purchaser or a shared platform pool, but this is a business policy. Do not use an invented CUR `reserved_instance_hours` column or compare aliases in the same SQL projection to label utilization. Inspect actual export fields or use the service's utilization report.

## Sale proceeds are not guaranteed

For a hypothetical us-east-1 exercise dated 2026-10-12, buy an eligible Standard RI for \$980 and assume an actual later gross sale of \$650. A 12% fee on that sale's upfront amount is \$78; net proceeds are \$572 and remaining purchase cost is \$408, before other charges. Without a realized sale, do not book \$650 as savings. Convertible RIs cannot use this Marketplace route. Country, bank-account and ownership restrictions can make a seller ineligible.

## Read-only review lab

Use Cost Explorer commitment reports and authorized purchase inventory to build a renewal list. Verify every candidate against current matching rules and a workload owner's future plan. Submit the proposed portfolio and accounting view for review; do not modify, exchange or list a reservation during the lab.

## References

- [RI utilization reports](https://docs.aws.amazon.com/cost-management/latest/userguide/ce-ri.html)
- [EC2 RI application](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/concepts-reserved-instances-application.html)
- [Marketplace eligibility](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ri-market-general.html)
