---
title: Migration Evaluator
description: AWS Migration Evaluator — generates TCO reports and right-sizing recommendations for AWS migration, assessment creation, and data collection methods
tags:
  - aws/migration
date: 2026-10-12
---

# Migration Evaluator

Prerequisites: [[AWS/security/iam/README|temporary-credential IAM roles]], [[AWS/networking/vpc/README|VPC routing]] and the [[AWS/migration/README|migration acceptance/rollback plan]].

Migration Evaluator builds a data-informed migration business case. Its agentless assessment covers supported physical/virtual Windows and Linux profiles, including SQL Server discovery; it is not a VMware-only agent installation service.

## Scope and distinctions

Do not conflate the Migration Evaluator Collector with Application Discovery's Agentless Collector, Discovery Agent or historical Connector. Evaluator assessment/sizing outputs support a business case; they do not automatically choose a workload's migration strategy or replace application-owner dependency analysis.

Inventory licensing, peak utilization, memory pressure, storage throughput/IOPS, support deadlines, network connectivity and migration effort. A low average CPU value alone is not a safe downsizing decision.

## Assessment exercise

1. Define the business question, source scope, data classification and representative observation period. Identify data owners and obtain collection authorization.
2. Follow the owning request/collector workflow; validate hypervisor/physical source support, read-only credentials, connectivity and collection permissions. Alternatively use the supported data-import process for an eligible dataset.
3. Compare collected server counts and observation periods with authoritative inventory. Investigate missing hosts and collection failures before calculating savings.
4. Review current-state and proposed-state assumptions with finance and application owners: licensing model, Region, target instance family, storage, operational overlap and commitments.
5. Create two scenarios (conservative baseline and optimized), record assumptions and uncertainty, and compare peak-capacity requirements. Do not use an invented CLI namespace/assessment command or fictional CSV schema.
6. Stop/remove the disposable collector and revoke its collection credentials when finished. Preserve approved business-case artifacts under the organization's retention rules.

## Output quality

A defensible TCO includes infrastructure, licenses, labor/operations, network, disaster recovery and migration overlap. Separate observed usage from projected savings and commitment risk; a modeled discount is not a guaranteed invoice.

Translate findings into [[AWS/migration/README|seven-R decisions]] and migration waves. Pair this work with source-specific dependency discovery rather than claiming the evaluator supplies detailed process/network telemetry.

## Cost and lifecycle

Review current service eligibility and assessment terms before starting. The business-case tool's terms do not make collection hosts, migration staging or target resources free. Reference current AWS pricing inputs rather than retaining stale universal instance rates.

## Assessment architecture and evidence model

```text
authorized physical/virtual inventory + representative utilization
                 ↓
agentless collector / supported imported assessment data
                 ↓
quality checks → licensing/capacity assumptions → AWS scenarios
                 ↓
business-case report → owner/finance review → migration strategy
```

| Evidence            | Question                                          | Incorrect shortcut                                 |
| ------------------- | ------------------------------------------------- | -------------------------------------------------- |
| Inventory/support   | Which systems/versions/owners are in scope?       | Assume VMware-only or every OS is supported        |
| CPU/memory profiles | What peaks/headroom must the target absorb?       | Size from CPU average alone                        |
| Storage/network     | What capacity/IOPS/throughput/latency are needed? | Compare only RAM and vCPU                          |
| Licensing           | What contracts/mobility/SQL options apply?        | Apply one blanket OS discount                      |
| Dependencies        | What must move together or remain reachable?      | Infer complete topology from a sizing report       |
| Observation quality | Which windows/hosts are missing?                  | Treat an incomplete collector run as the portfolio |

## Server-level recommendation walkthrough

For one synthetic server record, keep observed and projected values separate. Suppose average CPU is 10% but p95 is 70%, memory peak is 14 GB and a batch window is latency-sensitive. A candidate target must satisfy CPU architecture/performance, memory headroom, disk/network and support/license requirements. “10% CPU therefore one tenth the vCPU” is not a defensible sizing rule.

Compare an initial compatible configuration, a right-sized configuration and a managed-platform alternative at equal availability. State confidence and missing measurement. Test the candidate using representative application/batch data before accepting the report's estimate.

## Business-case worksheet and dimensional example

| Cost row   | Current state                                   | AWS scenario                            | Evidence                               |
| ---------- | ----------------------------------------------- | --------------------------------------- | -------------------------------------- |
| Compute    | Owned/leased capacity and remaining commitments | Running hours/purchase model/Region/OS  | Utilization plus current scoped tariff |
| Storage    | Capacity, performance, backup and support       | Volumes, I/O, snapshots/copies/restore  | Retention and measured demand          |
| Software   | Existing licenses/support                       | BYOL/managed/licensed options           | Contract and support eligibility       |
| Network    | Circuits/firewalls/egress                       | Transfer, gateways/endpoints/circuits   | Direction, GB and hours                |
| Operations | Current people/tooling                          | Migration/steady-state responsibilities | Explicit ownership                     |
| Overlap    | Existing environment                            | Staging/test/parallel-running period    | Cutover/decommission timeline          |

At hypothetical \$0.20/hour, twenty instances for 730 hours are \$2,920 before dependencies—not twenty × \$0.20 as a monthly estimate. A claimed 30% savings applies only to the cost rows actually reduced; it does not discount license/support/network automatically. Calculate baseline/scenario totals and show the assumption change.

## Assessment variants and migration handoff

A preliminary business case can use approved imported inventory; a measured assessment improves evidence but still needs quality checks. These are engagement/data-quality stages, not an invented agent-based versus VMware-only product catalog.

Validate licensing, criticality, effort and dependency requirements with owners before seven-R classification. Record assessment revision, data period, assumptions, recommended tests and unresolved systems. Feed the approved evidence into a supported tracking workflow; do not invent export-to-Migration-Hub API calls.

Stop/revoke disposable collection after completion, retain approved reports and remove sensitive raw exports according to policy. Target/staging and any collector hosting resources remain separate cost dimensions.

References: [Evaluator capabilities](https://docs.aws.amazon.com/prescriptive-guidance/latest/migration-tools/discovery-migration-evaluator.html), [Evaluator resources](https://aws.amazon.com/migration-evaluator/resources/), [migration business case](https://docs.aws.amazon.com/prescriptive-guidance/latest/strategy-migration/business-case.html).

## References

- [AWS tool capability matrix](https://docs.aws.amazon.com/prescriptive-guidance/latest/migration-tools/discovery-migration-evaluator.html)
- [Migration Evaluator](https://aws.amazon.com/migration-evaluator/)
- [Migration assessment guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/migration-tools/discovery-migration-evaluator.html)
