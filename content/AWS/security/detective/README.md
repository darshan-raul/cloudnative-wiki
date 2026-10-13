---
title: AWS Detective
description: AWS Detective — graph-based security investigation. Visualizes GuardDuty, CloudTrail, and VPC Flow data to help you investigate security findings across accounts.
tags:
  - aws/security
date: 2026-10-12
---

# AWS Detective

Prerequisites: [[AWS/security/iam/README|IAM roles and least privilege]] and the [[AWS/security/README|security evidence/response model]].

Detective supports security investigation with a behavior graph derived from documented source packages. It provides context, not universal operating-system process or CPU telemetry.

## Evidence and boundaries

Supported source packages determine which activity and findings are visible. Foundation inputs are ingested directly by the service, not from your configured CloudTrail S3 trail or flow-log destination. Do not invent synthetic finding names or infer process execution from an API/network record.

A behavior graph has an administrator and enrolled member accounts, with Organizations enrollment rules. The current member-account limit is 1,200; verify the owning quota for your deployment. Source data is retained up to one year; export/report preservation requirements need their own workflow.

## Investigation lab

Use a sandbox graph or an existing graph you are authorized to read. Enabling ingestion is billable; a trial has Region/source-package scope.

1. Start with a [[AWS/security/guardduty/README|GuardDuty]] sample/existing finding and record its principal/resource and time window.
2. In Detective, pivot to the corresponding entity, narrow the window and inspect documented API/network relationships. Separate observed evidence from hypotheses.
3. Compare normal and suspicious activity, record related identities/resources and verify an alternative explanation. Absence of a source package/data does not prove inactivity.
4. Correlate a supported event with [[AWS/security/cloudtrail/README|CloudTrail]] evidence and retain an investigation timeline without copying secrets or personal data unnecessarily.
5. Exercise containment as an approved runbook decision—not a Detective permission implied by viewing the graph.

If the sandbox lacks matching data, use the owning tutorial/examples rather than generating live attacks. Do not promise CPU/process views unless an explicit integrated data source supplies them.

## Cleanup and pricing

Remove only the disposable graph/enrollments or restore previous package settings after preserving required evidence. Do not unenroll production members as a cost experiment.

The current N. Virginia owning example uses ingestion tiers: first 1,000 GB at \$2/GB, next 4,000 at \$1, next 5,000 at \$0.50 and excess at \$0.25. Trials are thirty days per eligible Region/source package. Verify date/Region/package before applying these figures.

Dimensional arithmetic matters: at a hypothetical \$0.10/GB, 10 GB/day for thirty days is \$30—not \$900. That hypothetical tariff is not the actual first-tier rate above; do not mix the two in a budget.

## Behavior-graph and source-package model

```text
supported direct service source packages → behavior graph
                      ↓                       ├─ entities/relationships
              coverage/ingestion state        ├─ time-window context
                                              └─ finding-led investigation
```

| Entity/question      | Evidence to seek                                  | Boundaries                                    |
| -------------------- | ------------------------------------------------- | --------------------------------------------- |
| Principal/session    | Supported API activity and related resources      | Not full guest process/CPU telemetry          |
| EC2/network identity | Supported network/API relationships               | Flow records are not packet payload           |
| Finding              | Related entities/timing/anomalies                 | Severity is not proof of compromise           |
| Account/package      | Enrollment, active ingestion and covered interval | Missing source data does not prove inactivity |

Source packages, Region and data period determine what can be investigated. Existing S3 trail/VPC flow destinations are not the direct ingestion inputs; their enablement cannot be used as the only readiness test.

## Graph/member API walkthrough

With an approved read/create sandbox role and current graph ownership:

```bash
aws detective list-graphs
aws detective list-members --graph-arn GRAPH_ARN
aws detective get-members --graph-arn GRAPH_ARN --account-ids MEMBER_ACCOUNT_ID
```

Graph creation, member invitations/acceptance and Organizations enablement are mutations with administrator/member roles and quotas. Use the documented console/contract and confirm package/member status; do not invent an enable-organization API that auto-enrolls every account without settings/eligibility.

## Worked investigation narrative

A GuardDuty sample points to a role session at time T. Start from the finding and preserve ID/account/Region/time; inspect the entity's normal-versus-observed API/network context around T. Identify affected resources and related accounts, then correlate CloudTrail-supported events and configuration changes.

Form two hypotheses (credential misuse versus approved deployment activity). Obtain the deployment/session owner, request IDs and resource-change evidence to distinguish them. Label observation, inference and missing data separately; a graph edge alone does not prove the principal read confidential bytes.

If evidence supports containment, route to an authorized incident runbook with narrow role/resource changes and recovery validation. Detective read permission itself does not authorize terminating instances or disabling identities.

## Console, retention and cost operations

Choose a narrow time window and verify its covered interval. Export/report only approved metadata; protect personal/network data and preserve required evidence beyond the service's retention.

Ingestion GB tiers are source-package/Region scoped; do not confuse a 30-day trial with permanent free behavior graphs. Add up each tier's marginal volume before calculating the bill. At the cited first-tier \$2/GB example, 300 GB costs \$600 before trial/other eligible treatment—not 300 × an invented \$0.10 universal rate.

After a disposable drill remove owned invitations/members/graph only under the documented lifecycle and preserve investigation evidence. Do not delete the administrator's shared graph to stop one test client.

References: [graph/membership](https://docs.aws.amazon.com/detective/latest/userguide/detective-managing-accounts.html), [source data](https://docs.aws.amazon.com/detective/latest/userguide/detective-source-data-about.html), [investigation](https://docs.aws.amazon.com/detective/latest/userguide/detective-investigation-about.html), [ListGraphs](https://docs.aws.amazon.com/cli/latest/reference/detective/list-graphs.html).

## References

- [Source packages and retention](https://docs.aws.amazon.com/detective/latest/userguide/detective-source-data-about.html)
- [Region/quotas](https://docs.aws.amazon.com/detective/latest/userguide/regions-limitations.html)
- [Investigation guide](https://docs.aws.amazon.com/detective/latest/userguide/detective-investigation-about.html)
- [Pricing](https://aws.amazon.com/detective/pricing/)
