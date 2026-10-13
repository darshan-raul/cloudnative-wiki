---
title: "Domain 4: Accelerate Workload Migration and Modernization"
tags:
  - aws/certification/sap-c02/domain-4
date: 2026-10-12
description: Domain 4 task map, integrated scenario and study drills for SAP-C02.
---

# Domain 4: Accelerate Workload Migration and Modernization

This domain accounts for 20% of scored content in the current [official exam guide](https://docs.aws.amazon.com/aws-certification/latest/solutions-architect-professional-02/solutions-architect-professional-02.html). Choose migration waves and target architectures, then modernize where benefits justify change. The pages are sourced revision lessons, not a comprehensive course or a guarantee of an exam result.

## Prerequisites

Review [[AWS/migration/README|migration tools]], [[AWS/storage/README|storage contracts]] and [[AWS/databases/README|database compatibility]]. Explain the service contracts before attempting the integrated scenario.

## Task lessons

- [[AWS/solutions-architect-professional/domain-4/4.1-migration-assessment|4.1 Migration Assessment]]
- [[AWS/solutions-architect-professional/domain-4/4.2-migration-approach|4.2 Migration Approach]]
- [[AWS/solutions-architect-professional/domain-4/4.3-new-architecture-for-migrated-workloads|4.3 New Architecture for Migrated Workloads]]
- [[AWS/solutions-architect-professional/domain-4/4.4-modernization-and-enhancements|4.4 Modernization and Enhancements]]

Each task lesson maps to its official task and includes a distinct scenario, rationale, rejected alternatives and a proposed drill.

## Key areas and evidence

| Task                    | Evidence to produce                                     |
| ----------------------- | ------------------------------------------------------- |
| 4.1 Assessment          | Owner-approved 7R choices, dependencies and TCO         |
| 4.2 Transfer            | Throughput, lag, validation and cutover gates           |
| 4.3 Target architecture | Protocol, licensing and runtime compatibility matrix    |
| 4.4 Modernization       | Bounded component/data change with benefit and rollback |

Separate data-center exit from long-term refactoring where the deadline requires it. A successful server boot is not proof the database, identity, file permissions or business process migrated correctly. Sign off business invariants before finalizing source decommissioning.

## Integrated scenario

A data-center exit has a fixed deadline, one tightly coupled legacy database and several independently deployable applications. Assess dependencies, pick staged migration strategies and retain a tested rollback boundary. Reject refactoring everything before exit; reject moving live data without write fencing and reconciliation.

## Domain drill

Create a portfolio/wave plan, transfer-time estimate, target compatibility matrix and modernization proposal. Identify source and target owners, licensing constraints, cutover criteria and the point after which reverse synchronization is needed. Check current service lifecycle/customer eligibility before proposing a deployment. The exercise is tabletop/design work; deployments or disruptive tests require a separate authorized sandbox and cost controls.

## References and review

- [Official Domain 4 knowledge and skills](https://docs.aws.amazon.com/aws-certification/latest/solutions-architect-professional-02/solutions-architect-professional-02-domain4.html)
- [Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html)

Return to [[AWS/solutions-architect-professional/index|SAP-C02 study overview]]. Review task references for current quotas, service eligibility and pricing rather than memorizing unsourced numerical tables.
