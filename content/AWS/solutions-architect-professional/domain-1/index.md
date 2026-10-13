---
title: "Domain 1: Design Solutions for Organizational Complexity"
tags:
  - aws/certification/sap-c02/domain-1
date: 2026-10-12
description: Domain 1 task map, integrated scenario and study drills for SAP-C02.
---

# Domain 1: Design Solutions for Organizational Complexity

This domain accounts for 26% of scored content in the current [official exam guide](https://docs.aws.amazon.com/aws-certification/latest/solutions-architect-professional-02/solutions-architect-professional-02.html). Design boundaries across teams, networks and accounts before choosing individual services. The pages are sourced revision lessons, not a comprehensive course or a guarantee of an exam result.

## Prerequisites

Review [[AWS/networking/README|networking]], [[AWS/security/README|security]] and [[AWS/management-governance/organizations/README|Organizations]]. Explain the service contracts before attempting the integrated scenario.

## Task lessons

- [[AWS/solutions-architect-professional/domain-1/1.1-network-connectivity|1.1 Architect Network Connectivity Strategies]]
- [[AWS/solutions-architect-professional/domain-1/1.2-prescribe-security-controls|1.2 Prescribe Security Controls]]
- [[AWS/solutions-architect-professional/domain-1/1.3-reliable-and-resilient-architectures|1.3 Design Reliable and Resilient Architectures]]
- [[AWS/solutions-architect-professional/domain-1/1.4-multi-account-aws-environment|1.4 Design a Multi-Account AWS Environment]]
- [[AWS/solutions-architect-professional/domain-1/1.5-cost-optimization-and-visibility|1.5 Cost Optimization & Visibility]]

Each task lesson maps to its official task and includes a distinct scenario, rationale, rejected alternatives and a proposed drill.

## Key areas and evidence

| Task              | Evidence to produce                                           |
| ----------------- | ------------------------------------------------------------- |
| 1.1 Connectivity  | Address/route/DNS matrix with failure paths                   |
| 1.2 Security      | Cross-account identity, resource and key-policy evaluation    |
| 1.3 Resilience    | Recovery timeline and recovery-point verification             |
| 1.4 Multi-account | Account/OU ownership and protected logging flow               |
| 1.5 Visibility    | Allocation, utilization and post-rightsizing commitment model |

The acquisition exercise is complete only when shared ERP remains reachable through approved paths, research stays isolated and audit/cost ownership survives account onboarding. A working network cannot compensate for an incorrect trust policy or inaccessible recovery key.

## Integrated scenario

An acquired business must join shared ERP without exposing research workloads or losing audit ownership. Combine route segmentation, federated roles, account boundaries, recovery objectives and cost allocation. Reject a single shared administrator account and a flat transitive network: both obscure ownership and expand the blast radius.

## Domain drill

Produce an account tree, allowed-traffic matrix, cross-account access worksheet, recovery timeline and cost-ownership model. For each, name the decision owner and a rejected design. Check that the network, identity and recovery plans agree rather than optimizing each in isolation. The exercise is tabletop/design work; deployments or disruptive tests require a separate authorized sandbox and cost controls.

## References and review

- [Official Domain 1 knowledge and skills](https://docs.aws.amazon.com/aws-certification/latest/solutions-architect-professional-02/solutions-architect-professional-02-domain1.html)
- [Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html)

Return to [[AWS/solutions-architect-professional/index|SAP-C02 study overview]]. Review task references for current quotas, service eligibility and pricing rather than memorizing unsourced numerical tables.
