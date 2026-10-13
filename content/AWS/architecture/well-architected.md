---
title: "AWS Well-Architected review"
description: "Evaluate a workload across six pillars with measurable requirements, evidence, risk prioritization and explicit trade-offs."
tags:
  - cloud/aws/architecture
date: 2026-10-12
---

# AWS Well-Architected review

Well-Architected is a framework for discussing architecture trade-offs, not a compliance certification or automatic guarantee. Begin with [[AWS/foundations/README|foundations]] and review one bounded workload with its owner.

## Six pillars and evidence

| Pillar                 | Question                                                 | Useful evidence                                                          |
| ---------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------ |
| Operational excellence | Can the team safely change and operate the workload?     | Deployment rollback, ownership, runbooks, incident learning              |
| Security               | Who can access what, and how is misuse detected?         | Identity/policy review, key ownership, audit events, response test       |
| Reliability            | Can the workload meet its recovery objectives?           | Failure tests, restore drills, dependency limits                         |
| Performance efficiency | Does resource choice meet workload demand?               | Representative load tests, p95/p99 latency, bottleneck analysis          |
| Cost optimization      | Are costs allocated and proportional to value?           | Unit cost, metered dimensions, utilization, commitment risk              |
| Sustainability         | Is resource demand reduced without violating objectives? | Utilization, idle reduction, data retention, managed-resource efficiency |

Do not optimize one pillar in isolation. A single-AZ database may cost less but fail the stated availability requirement; longer retention can improve recovery while increasing storage and privacy exposure.

## Review exercise

Consider a document-upload API with Lambda, S3 and SQS. Record confidentiality, maximum acceptable processing latency, durability, peak requests, RPO/RTO, operational ownership and cost-per-document target.

For each pillar, identify one risk, the evidence needed to assess it, and a proposed improvement. Examples: replay a duplicate queue event, simulate an unavailable dependency, restore a deleted test object, and measure processing lag during a burst. Assign an owner, acceptance test and review date to each change.

Choose the first three actions by impact and urgency, not by a count of best-practice checkboxes. Explain one rejected alternative and what requirement would change the choice.

## Operations handoff

Store the resource inventory, architecture decisions, cost assumptions, alarms and restore procedure with the workload. Re-review after major changes or incidents. A successful deployment is not proof that access, rollback and recovery work.

## References and next steps

- [Framework and review approach](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html).
- [Six pillars](https://docs.aws.amazon.com/wellarchitected/latest/framework/the-pillars-of-the-framework.html).
- Next: [[AWS/reliability/backup-and-recovery|recovery drills]], [[AWS/monitoring/tracing-and-observability|observability]] and [[AWS/cost-management/README|cost decisions]].
