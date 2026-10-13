---
title: "Domain 2: Design for New Solutions"
tags:
  - aws/certification/sap-c02/domain-2
date: 2026-10-12
description: Domain 2 task map, integrated scenario and study drills for SAP-C02.
---

# Domain 2: Design for New Solutions

This domain accounts for 29% of scored content in the current [official exam guide](https://docs.aws.amazon.com/aws-certification/latest/solutions-architect-professional-02/solutions-architect-professional-02.html). Translate a new workload's business requirements into a deployable, secure, measurable design. The pages are sourced revision lessons, not a comprehensive course or a guarantee of an exam result.

## Prerequisites

Review [[AWS/compute/README|compute]], [[AWS/storage/README|storage]], [[AWS/databases/README|databases]] and the Domain 1 boundary lessons. Explain the service contracts before attempting the integrated scenario.

## Task lessons

- [[AWS/solutions-architect-professional/domain-2/2.1-deployment-strategy|2.1 Deployment Strategy]]
- [[AWS/solutions-architect-professional/domain-2/2.2-business-continuity|2.2 Business Continuity]]
- [[AWS/solutions-architect-professional/domain-2/2.3-security-controls|2.3 Security Controls (New Solutions)]]
- [[AWS/solutions-architect-professional/domain-2/2.4-reliability-requirements|2.4 Reliability Requirements]]
- [[AWS/solutions-architect-professional/domain-2/2.5-performance-objectives|2.5 Performance Objectives]]
- [[AWS/solutions-architect-professional/domain-2/2.6-cost-optimization-strategy|2.6 Cost Optimization Strategy (New Solutions)]]

Each task lesson maps to its official task and includes a distinct scenario, rationale, rejected alternatives and a proposed drill.

## Key areas and evidence

| Task            | Evidence to produce                                      |
| --------------- | -------------------------------------------------------- |
| 2.1 Delivery    | Pipeline, rollout gates and state-aware rollback         |
| 2.2 Continuity  | Tested replication/restore and write-fencing design      |
| 2.3 Security    | Threat/control matrix and denied-request reasoning       |
| 2.4 Reliability | Backlog, idempotency, quota and surviving-capacity model |
| 2.5 Performance | Bottleneck measurements and cache-failure behavior       |
| 2.6 Economics   | Unit-aware storage/transfer and commitment comparison    |

For the booking launch, resolve contradictions explicitly: a cheaper cache cannot serve stale inventory if correctness forbids it, and an inexpensive archive cannot meet instant retrieval. Tie every selected service to a requirement and measurable acceptance test.

## Integrated scenario

A new booking platform expects launch-day bursts, sensitive customer data and a 30-minute regional recovery requirement. Design rollout, data recovery, security, queuing, performance and cost together. Reject a cheap single-AZ stack that violates recovery goals, and reject active/active complexity without a justified consistency design.

## Domain drill

Create a one-page requirement sheet with latency, availability, RTO/RPO, throughput, security and budget targets. Select a topology and rollout, then calculate surge backlog and recovery duration. Identify the requirement that disqualifies each rejected alternative; distinguish a forecast from a hard spending cap. The exercise is tabletop/design work; deployments or disruptive tests require a separate authorized sandbox and cost controls.

## References and review

- [Official Domain 2 knowledge and skills](https://docs.aws.amazon.com/aws-certification/latest/solutions-architect-professional-02/solutions-architect-professional-02-domain2.html)
- [Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html)

Return to [[AWS/solutions-architect-professional/index|SAP-C02 study overview]]. Review task references for current quotas, service eligibility and pricing rather than memorizing unsourced numerical tables.
