---
title: AWS Migration
description: AWS migration services — DMS for database migration, DataSync for file transfer, Application Migration Service (MGN) for lift-and-shift, Migration Evaluator, and Application Discovery Service
tags:
  - aws/migration
date: 2026-10-12
---

# AWS Migration

Migration is a business and data-consistency program, not just a copy job. Inventory dependencies, choose a strategy per workload, rehearse recovery and prove the cutover's acceptance criteria.

## Service map and lifecycle

| Need                      | Lesson                                                                        | Boundary                                               |
| ------------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------ |
| Discovery                 | [[AWS/migration/application-discovery-service/README\|Application Discovery]] | Closed to new customers; collector capabilities differ |
| Business case             | [[AWS/migration/migration-evaluator/README\|Migration Evaluator]]             | Agentless assessment, not automatic strategy approval  |
| Server replication        | [[AWS/migration/application-migration-service/README\|AWS Transform MGN]]     | Staging EC2/EBS and customer-owned cutover             |
| Database migration        | [[AWS/migration/dms/README\|DMS]]                                             | Engine-specific source/CDC/schema prerequisites        |
| File/object transfer      | [[AWS/migration/datasync/README\|DataSync]]                                   | Transfer and verification, not format conversion       |
| Historical server tooling | [[AWS/migration/server-migration-service/README\|SMS archive]]                | Retired; not a new deployment path                     |

## Seven migration strategies

Rehost moves a workload with limited application changes. Replatform changes selected platform components. Refactor/re-architect changes the application design. Repurchase adopts another product. Relocate moves an environment without redesigning each application. Retain defers migration; Retire removes the workload.

Do not choose a strategy from CPU utilization alone. Consider licensing, data residency, dependency latency, operational skills, business deadlines and support. Migration Hub/assessment dashboards can track evidence where available but do not decide consistency or accept the workload.

## Cutover and rollback exercise

1. Inventory owners, application/network/database dependencies, identity and certificates. Measure baseline capacity and establish RPO/RTO.
2. Rehearse in an isolated target network; prevent duplicate schedulers, outbound notifications or writes from test clones.
3. Agree the source-write freeze, final replication/CDC lag threshold, validation queries and business acceptance. Near-zero downtime is conditional, not a universal promise.
4. Shift traffic deliberately and observe metrics/logs/user transactions. Define the rollback trigger, deadline and what happens to writes accepted on the target.
5. Finalize replication only after approval. Source shutdown/decommissioning, backups and resource cleanup remain explicit actions.

Link migration validation to [[AWS/reliability/backup-and-recovery|backup, restore and disaster recovery]]; a replicated mistake is not a safe backup. Capture runbook evidence and residual risks.

## Cost planning

Include discovery, staging/test/target infrastructure, storage, replication network, database capacity, source overlap and transfer verification. MGN's service free period does not make EC2/EBS free. DMS provisioned runtime is metered by running hours, not a mandatory full-month migration tariff. DataSync has mode/operation-specific rates rather than an invented universal stepped price.

## End-to-end migration architecture and strategy matrix

```text
portfolio inventory → dependency/business assessment → seven-R decision
         ↓                       ↓                         ↓
data classification       cost/license/support        wave/cutover plan
         └──────── discovery evidence ────────────────┘
                                 ↓
                 replicated/test target + schema conversion
                                 ↓
                write freeze → lag/validation → traffic switch
                                 ↓
             business acceptance → finalize → decommission
                          └─ failed acceptance → rollback/reconcile
```

| Strategy   | Example                                    | Validation beyond copying                                      |
| ---------- | ------------------------------------------ | -------------------------------------------------------------- |
| Rehost     | Supported server replication to EC2        | Boot, licensing, identity, storage, application dependencies   |
| Replatform | Move database to managed compatible engine | Parameters/extensions, HA, connection/backup behavior          |
| Refactor   | Split processing behind events/APIs        | Contract/idempotency/data consistency and operator ownership   |
| Repurchase | Adopt SaaS                                 | Export/import, identity, retention and termination obligations |
| Relocate   | Move a supported environment/platform      | Platform compatibility, connectivity and licensing             |
| Retain     | Keep a constrained dependency              | Explicit future review and hybrid operational cost             |
| Retire     | Decommission unused workload               | Dependency confirmation, legal retention and access removal    |

A migration wave groups dependencies/owners for coordinated rehearsal and acceptance. A tool's wave status is not the business decision. Include batch windows, identity, DNS, certificates, external endpoints, license servers, file shares and stateful write ownership—not just server CPU.

## Discovery, import and assessment worksheet

Inventory IDs, application owner, environment, source support deadline, data residency, peak/average demand, memory pressure, storage capacity/IOPS/throughput, network flows and licensing. Cross-check CMDB/collector/imported records and observation windows; missing hosts or a quiet weekend can bias sizing.

ADS new-customer closure and retired Connector mean new learners must use currently eligible discovery/Transform workflows. Evaluator is agentless business-case assessment, not an automatic seven-R classifier. Keep observed evidence and assumptions separate, and ask application owners to validate dependencies.

Import only the documented tool/schema, with ownership and data classification. Use only the selected tool's documented import/API contract. A spreadsheet can serve as the exercise's portfolio contract without pretending it is an AWS API.

## Schema conversion and database compatibility

Schema conversion and DMS data movement are separate. AWS SCT and supported DMS schema-conversion workflows have source/target/feature constraints. First assess unsupported types, procedural SQL, extensions, sequences, indexes, permissions and application queries. Review conversion action items; apply to a disposable target, then run application tests.

For homogeneous moves, compatibility still depends on versions/extensions/collation/settings; same engine does not make every object migrate automatically. For heterogeneous moves, select explicit equivalence tests (decimal rounding, timestamps/timezones, null/empty strings, text encoding and transaction isolation).

## Wave rehearsal and cutover runbook

| Phase     | Go/no-go evidence                                                   | Failure/rollback action                                         |
| --------- | ------------------------------------------------------------------- | --------------------------------------------------------------- |
| Prepare   | Roles, network, target capacity, backup/restore and owners          | Stop before source mutation if access/restore is unproven       |
| Replicate | Healthy source logging/agent, measured lag and retained source logs | Correct permission/capacity; do not ignore skipped tables/files |
| Test      | Isolated clone; data/application/performance checks                 | Terminate only test targets and repeat rehearsal                |
| Freeze    | Approved write stop and final catch-up                              | Keep source authoritative until agreed cutover boundary         |
| Switch    | DNS/client/config revision and business transaction evidence        | Revert within the documented write-reconciliation plan          |
| Finalize  | Acceptance, recovery copy, audit and ownership handoff              | Do not finalize/decommission the only recoverable source early  |

Row counts alone miss corrupted values, missing updates/deletes and broken constraints. Use checksums/business invariants plus transaction tests and service-level performance. MGN launch state, DMS task running or DataSync SUCCESS is only one layer of evidence.

Document target-side writes accepted after switching. Simply pointing DNS back can lose/diverge those writes; decide whether to reverse-replicate, replay, reconcile or stop the target before rollback. DNS caching and long-lived client connections affect measured convergence.

## Worked TCO and resource-overlap example

A migration runs source and target in parallel for fourteen days. If the target compute is hypothetically \$2/hour and staging \$0.40/hour, 14 × 24 × (\$2 + \$0.40) = \$806.40 **before** source cost, storage, licenses, transfer, validation, operations and cleanup. This is dimensional reasoning, not an AWS tariff.

Compare baseline, rehost and optimized scenarios with the same availability/performance and observation period. Add commitment risk only after eligible usage stabilizes. DMS running capacity is not a mandatory whole-month charge; a task stop may leave replication infrastructure billed. MGN service allowance does not remove EC2/EBS/egress charges. DataSync mode/task/byte pricing must use matching units.

## Handoff and post-migration optimization

Record inventory/IDs, schema/config revision, business acceptance, alarm/runbook owners, backup/restore evidence and decommission deadlines. Review right-sizing, obsolete endpoints, logging/retention, encryption access, licensing and source cleanup after—not instead of—acceptance.

Track waves through a currently eligible tool or an auditable workflow; do not invent status-update APIs. Preserve old SMS information as history, keep its runtime commands non-operational, and point execution to the current MGN/DMS/DataSync lessons.

References: [large-migration foundation](https://docs.aws.amazon.com/prescriptive-guidance/latest/strategy-migration/migration-process.html), [SCT](https://docs.aws.amazon.com/SchemaConversionTool/latest/userguide/CHAP_Welcome.html), [DMS schema conversion](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_SchemaConversion.html), [migration validation](https://docs.aws.amazon.com/prescriptive-guidance/latest/large-migration-guide/migration-strategies.html).

## References

- [Seven Rs](https://docs.aws.amazon.com/prescriptive-guidance/latest/large-migration-guide/migration-strategies.html)
- [MGN cost planning](https://docs.aws.amazon.com/mgn/latest/ug/migration_at_scale.html)
- [AWS migration lifecycle](https://docs.aws.amazon.com/prescriptive-guidance/latest/strategy-migration/migration-process.html)

## Across the wiki

- [[Architecture/solution-architecture-concepts/migration-patterns/README|Migration Patterns]]
- [[Architecture/solution-architecture-concepts/migration-patterns/data-migration|Data Migration Patterns]]
- [[Architecture/solution-architecture-concepts/migration-patterns/change-data-capture|Change Data Capture (CDC)]]
- [[Architecture/solution-architecture-concepts/migration-patterns/strangler-fig|Strangler Fig Pattern]]
