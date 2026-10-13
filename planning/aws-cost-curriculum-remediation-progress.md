# AWS cost and curriculum remediation progress

Scope: 20 cost-management notes, the cost concept view, and all 25 SAP-C02 pages. No deployment, purchase, commit or push is performed.

## Implementation queue

- Cost foundations and visibility: F01–F06, F10–F13, F16–F17, S06–S07, S20–S22; pending allocation, governance and reporting models.
- Service cost notes: F07–F09, F14–F15, S17–S19, S24, S33–S37; pending storage/network/database and automation defects.
- Curriculum: official task mapping and references for 20 tasks; unique prerequisite/scenario/rationale/rejected-alternative/drill material; all five indexes; task-specific defects in the findings report.

Status: scoped implementation complete. Sources are recorded in the source decisions and audit files, with primary references in every rewritten note. Prices in exercises are assumptions, not current quotes. Exercises are proposed, not executed labs.

## Resolved findings

| Finding group             | Implementation                                                                                                                                                                                                                                       |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| F01–F02                   | Activated/generated tags, historical backfill and missing-tag enforcement limits corrected                                                                                                                                                           |
| F03–F06                   | CAD eligibility, timing, alert semantics and CE history/forecast corrected                                                                                                                                                                           |
| F07–F09                   | Guest memory, recommendation samples and discount-aware estimates corrected                                                                                                                                                                          |
| F10–F12                   | Member benefit sharing, payer/chargeback distinctions and supported Windows billing corrected                                                                                                                                                        |
| F13–F17                   | Compute, EBS, schedule, Savings Plans and RI arithmetic rebuilt with explicit units                                                                                                                                                                  |
| S06–S07                   | Four plan types and account-cohort Free Tier distinctions included                                                                                                                                                                                   |
| S17–S19                   | Lambda invented ENI/NAT fees, provisioned-concurrency model and memory/duration arithmetic removed/corrected                                                                                                                                         |
| S20–S22                   | Eligible regional size flexibility, normalization, benefit order and discounted-rate hourly commitment explained                                                                                                                                     |
| S24, S33–S37              | RDS/EBS gp3 separated; unsupported EBS values/io3 removed; DynamoDB request, index, cache and backup models corrected; fleet-hours corrected                                                                                                         |
| Pending cost candidates   | Allocation/governance, CUR 2.0, storage tiers/retention, network paths, safe automation, RI sale/sharing and stopped-resource costs corrected or replaced with source-linked bounded workflows                                                       |
| SAP task-specific defects | Current service/lifecycle distinctions, DNS rollback limits, FIFO/quotas, DAX integration, placement scope, Session Manager audit limits, Inspector Classic retirement, performance inference, WAF/static ingress and storage-table errors corrected |
| Curriculum coverage       | All 20 tasks have official task mapping, prerequisites, individual scenario/rationale, rejected alternatives, practical drill and task-specific references; four domain indexes and landing page have integrated exercises and sourced weights       |

Additional current-source checks resolved CodeCommit reopening (AWS announcement November 24, 2025), Budgets pricing, and same-Organization shared security-group restrictions. Unsupported deployment/pricing snippets were not retained as runnable code.

## Path coverage ledger

- `content/AWS/cost-management/`: all 20 Markdown notes rewritten, including README, pricing models, Savings Plans, RIs, RI management, allocation tags, Organizations, CE, Budgets, CAD, CUR, EC2/EBS/EFS/RDS/DynamoDB/network/S3/Lambda costs and automation.
- `content/AWS/concepts/cost-management.md`: canonicalized as a short sourced exam decision view linking the cost hub.
- `content/AWS/solutions-architect-professional/domain-1/`: index and tasks 1.1–1.5 (6 pages).
- `content/AWS/solutions-architect-professional/domain-2/`: index and tasks 2.1–2.6 (7 pages).
- `content/AWS/solutions-architect-professional/domain-3/`: index and tasks 3.1–3.5 (6 pages).
- `content/AWS/solutions-architect-professional/domain-4/`: index and tasks 4.1–4.4 (5 pages).
- `content/AWS/solutions-architect-professional/index.md`: sourced overview/capstone, preserved landing alias (1 page).

Total: 46 content pages (20 cost, 1 concept, 25 SAP). Existing cross-wiki footers were preserved where present. Tags are hierarchical. No other content groups, Obsidian metadata, resources, commits or pushes were changed by this agent.

## Verification and remaining limits

- Scoped content validator: zero errors, zero warnings.
- All 25 SAP pages counted; all 20 task pages checked for required instructional sections.
- Owned paths formatted with Prettier.
- Initial HTTP/reference check: 125 unique referenced URLs returned success without a page-not-found marker. Two additional verified references were added afterward (CodeCommit reopening and security-group sharing). This is availability checking, not certification that every source sentence supports every claim.
- Two retained CLI examples are read-only (Cost Explorer query and EBS inventory), linked to their owning contracts; no API calls against an AWS account were executed. No labs, capacity purchases, migrations or destructive actions were performed.
- Whole-site build/rendering, global navigation and cross-agent consistency are owned by the main agent. Exact regional prices, optional features/quotas and account eligibility must be rechecked before any actual deployment. No unresolved scoped implementation item remains, but this pass is not an execution-certified deployment test.
