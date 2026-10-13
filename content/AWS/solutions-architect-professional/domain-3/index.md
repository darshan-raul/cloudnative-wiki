---
title: "Domain 3: Continuous Improvement for Existing Solutions"
tags:
  - aws/certification/sap-c02/domain-3
date: 2026-10-12
description: Domain 3 task map, integrated scenario and study drills for SAP-C02.
---

# Domain 3: Continuous Improvement for Existing Solutions

This domain accounts for 25% of scored content in the current [official exam guide](https://docs.aws.amazon.com/aws-certification/latest/solutions-architect-professional-02/solutions-architect-professional-02.html). Improve an existing workload using evidence, controlled changes and before/after validation. The pages are sourced revision lessons, not a comprehensive course or a guarantee of an exam result.

## Prerequisites

Review [[AWS/cost-management/README|cost analysis]], [[AWS/management-governance/systems-manager/README|operations]] and the Domain 2 design lessons. Explain the service contracts before attempting the integrated scenario.

## Task lessons

- [[AWS/solutions-architect-professional/domain-3/3.1-operational-excellence|3.1 Operational Excellence]]
- [[AWS/solutions-architect-professional/domain-3/3.2-security-improvement|3.2 Security Improvement]]
- [[AWS/solutions-architect-professional/domain-3/3.3-performance-improvement|3.3 Performance Improvement]]
- [[AWS/solutions-architect-professional/domain-3/3.4-reliability-improvement|3.4 Reliability Improvement]]
- [[AWS/solutions-architect-professional/domain-3/3.5-cost-optimization-opportunities|3.5 Cost Optimization Opportunities]]

Each task lesson maps to its official task and includes a distinct scenario, rationale, rejected alternatives and a proposed drill.

## Key areas and evidence

| Task            | Evidence to produce                                         |
| --------------- | ----------------------------------------------------------- |
| 3.1 Operations  | Correlated telemetry and an actionable runbook              |
| 3.2 Security    | Ranked findings, patch/rotation controls and recovery       |
| 3.3 Performance | Stage-level bottleneck and representative before/after test |
| 3.4 Reliability | Dependency graph and failed-AZ capacity calculation         |
| 3.5 Cost        | Reconciled bill, owner and net avoidable cost               |

Use one controlled change at a time where possible. A resize can worsen latency; stricter access can break recovery; reduced retention can destroy compliance. Show evidence that the chosen improvement did not merely move the problem into another task.

## Integrated scenario

An established checkout service has slow tail latency, rising bills and unpatched instances. Prioritize changes using impact, evidence and reversibility. Reject a simultaneous fleet resize, database migration and security-policy overhaul: confounding changes make failures and savings difficult to attribute.

## Domain drill

Build a five-item improvement backlog with owner, baseline, hypothesis, risk, acceptance metric and rollback. Rank one operational, security, performance, reliability and cost change. Explain why the first change is worth doing now and how its outcome will be measured without weakening another objective. The exercise is tabletop/design work; deployments or disruptive tests require a separate authorized sandbox and cost controls.

## References and review

- [Official Domain 3 knowledge and skills](https://docs.aws.amazon.com/aws-certification/latest/solutions-architect-professional-02/solutions-architect-professional-02-domain3.html)
- [Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html)

Return to [[AWS/solutions-architect-professional/index|SAP-C02 study overview]]. Review task references for current quotas, service eligibility and pricing rather than memorizing unsourced numerical tables.
