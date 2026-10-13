---
title: Server Migration Service (retired)
description: Historical AWS SMS context and a decision checklist for moving server migration plans to Application Migration Service.
tags:
  - cloud/aws/migration
  - cloud/aws/legacy
date: 2026-10-12
---

# Server Migration Service (retired)

AWS Server Migration Service entered **full shutdown on April 1, 2023**. It is not a maintenance-mode service available for new or continuing migrations. The earlier March 31, 2022 discontinuation applied to AWS GovCloud (US); do not confuse that narrower announcement with the global shutdown.

## Historical context

SMS used a connector for agentless VM replication. It should not be described as an SMS agent installed alongside an MGN agent. Old SMS CLI commands and connector deployment instructions are historical artifacts, not a runnable migration path.

Use [[AWS/migration/application-migration-service/README|Application Migration Service (MGN)]] for supported lift-and-shift requirements after checking current source-platform, Region and network prerequisites. Evaluate [[AWS/migration/dms/README|DMS]] for database migration and [[AWS/migration/datasync/README|DataSync]] for file/object transfer; these solve different problems.

## Replanning a legacy migration

1. Inventory source systems, dependencies, licensing, support and required downtime.
2. Select the migration strategy; use the [[AWS/migration/README|migration overview]] rather than assuming every system should be rehosted.
3. Create a fresh supported migration plan. Historical SMS IDs and jobs are not MGN source-server registrations.
4. Validate replication, run isolated tests, reconcile application data and define rollback before scheduling cutover.
5. Control source writes during the approved cutover, validate the target, and clean up staging resources only after acceptance.

Exercise: take a hypothetical three-server application, identify the database dependency and design a test network that cannot send production email or process payments. Define measurable acceptance and rollback criteria. No retired service resources are needed.

## Historical connector architecture

This section is archival explanation only. SMS is retired globally (April 1, 2023); none of its old deployment/replication commands should be run as a current lab.

```text
historical supported hypervisor/source
          ↓
historical SMS connector and snapshot/image replication job
          ↓
AWS image/target launch → customer application validation
```

The connector-based model differed from MGN's source-installed continuous block replication into EC2/EBS staging. Image availability never guaranteed application-consistent transactions or successful DNS/identity/license behavior.

## SMS versus current MGN migration model

| Concern                | Historical SMS                                       | Current eligible MGN workflow                               |
| ---------------------- | ---------------------------------------------------- | ----------------------------------------------------------- |
| Collection/replication | Supported connector/source and replication-job model | Source replication agent and target staging servers/storage |
| Rehearsal              | Customer launches/tests replicated image             | Explicit test launch/validation/cleanup                     |
| Cutover                | Customer coordinates final source state and traffic  | Source-write freeze, lag acceptance, cutover and finalize   |
| Continued use          | Retired; no operational maintenance recipe           | Verify current source/Region support and service costs      |
| Cleanup                | Archived evidence/old artifacts under ownership      | Explicit agent/source/test/staging decommissioning          |

Do not equate old source IDs with MGN IDs or promise that two source replication tools can coexist without validating their supported installation/resource behavior. An old AMI/image may be recovery evidence, but support and application compatibility still require tests.

## Historical API-to-modern runbook map

| Original command purpose     | Preserve as history                 | Current learning destination                  |
| ---------------------------- | ----------------------------------- | --------------------------------------------- |
| List source servers          | Inventory/provenance concept        | MGN/Transform inventory or approved CMDB      |
| Create/start replication job | Snapshot/job-state concept          | Current MGN replication installation/settings |
| Inspect image/job            | Verify materialized target evidence | MGN jobs/EC2 launch/application validation    |
| Delete replication job       | Dependency-aware cleanup concept    | Approved modern source/staging/test cleanup   |

No current SMS API availability or fake retirement date is implied by this mapping. The retired CLI snippets were omitted intentionally rather than converted into runnable-looking “maintenance” commands.

## Recovery/modernization exercise

Using archived documentation/inventory only, record each old workload's owner, retained image/backup, source support status, network/identity/certificate dependencies and current business requirement. Decide Retire/Retain or a supported migration strategy.

For a retained image, restore only into an approved isolated environment and validate OS/security/application support before any traffic switch. For new replication use [[AWS/migration/application-migration-service/README|MGN's current runbook]], with source-write quiescence, rollback reconciliation and customer-owned cleanup. Preserve legal/audit recovery artifacts; old-service deletion is not an excuse to remove the only approved backup.

References: [AWS service shutdown table](https://docs.aws.amazon.com/general/latest/gr/full_shutdown_services.html), [MGN workflow](https://docs.aws.amazon.com/mgn/latest/ug/migration-workflow-gs.html), [migration strategy](https://docs.aws.amazon.com/prescriptive-guidance/latest/large-migration-guide/migration-strategies.html).

## References

- [AWS services in full shutdown](https://docs.aws.amazon.com/general/latest/gr/full_shutdown_services.html).
- [Application Migration Service documentation](https://docs.aws.amazon.com/mgn/latest/ug/what-is-application-migration-service.html).
