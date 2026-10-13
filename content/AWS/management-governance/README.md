---
title: "AWS Management and Governance"
description: "Governance defines account boundaries and permissions ceilings; infrastructure as code creates resources; fleet tooling operates them."
tags:
  - aws/management-governance
date: 2026-10-12
---

# AWS Management and Governance

Governance defines account boundaries and permissions ceilings; infrastructure as code creates resources; fleet tooling operates them. Learn [[AWS/security/iam/README|IAM]] and [[AWS/foundations/README|AWS foundations]] before applying organization-wide changes.

## Learning path

| Lesson                                                                                | Responsibility                                                                        |
| ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| [[AWS/management-governance/organizations/README\|Organizations]]                     | Account/OU hierarchy, consolidated billing and policy ceilings.                       |
| [[AWS/management-governance/organizations/delegated-admin\|Delegated administration]] | Service-specific trusted access and scoped management outside the management account. |
| [[AWS/management-governance/control-tower/README\|Control Tower]]                     | Landing-zone/account enrollment and preventive/detective/proactive controls.          |
| [[AWS/management-governance/cli/README\|CLI]]                                         | Safe identity-aware inspection and API automation.                                    |
| [[AWS/management-governance/cloudformation/README\|CloudFormation]]                   | Templates, stack/change-set lifecycle, import, drift and StackSets.                   |
| [[AWS/management-governance/cdk/README\|CDK]]                                         | Code-based synthesis/testing over CloudFormation.                                     |
| [[AWS/management-governance/systems-manager/README\|Systems Manager]]                 | Inventory, sessions, commands and fleet state.                                        |
| [[AWS/management-governance/systems-manager/patch-manager\|Patch Manager]]            | OS-specific patch policies, rollout and compliance evidence.                          |

## Authority and operating model

The management account is an AWS account, the account root user is a principal, and the Organizations root is a container: do not call all three root. SCPs constrain member-account permissions but do not grant IAM access or constrain the management account.

Control Tower uses Organizations and controls with different enforcement mechanisms. CloudFormation StackSets use self-managed roles or Organizations service-managed trusted access, not AWS RAM as their permission prerequisite. CDK synthesizes templates; it does not bypass CloudFormation lifecycle or IAM checks.

Systems Manager managed nodes need supported agent, identity and endpoint connectivity. Runtime credentials can differ from an operator's CLI profile; verify the actual caller before changing production.

## Controlled rollout exercise

Design separate security/log-archive, infrastructure, workload and sandbox accounts/OUs. State where security policy is enforced and which role deploys/operates resources. Test an SCP/control on a small sandbox OU before broader attachment; maintain a documented rollback path and protect the management account separately.

Deploy one small stack, review its change set, observe drift and run a safe read-only fleet inventory. Capture evidence of both allowed and denied actions. Set budgets for created services/logging and remove test stacks/policies/resources only after dependency review. Do not treat account deletion or control removal as routine cleanup.

## Multi-account operating architecture

```text
Organizations root container
  ├─ Security OU: audit / log archive / security tooling
  ├─ Infrastructure OU: network / shared services
  ├─ Workload OUs: production / nonproduction
  └─ Sandbox OU: constrained experimentation

Control Tower: supported enrollment/baselines/controls
CloudFormation/CDK: reviewed resource lifecycle
CLI/roles: authorized API operations
Systems Manager: managed-node operations and evidence
```

An OU is a policy/organizational container, not a subnet or authentication realm. Accounts isolate resources and identities; cross-account access requires explicit trust/authorization. The management account should remain narrowly used, while supported service operations can be delegated to appropriate member accounts.

## Responsibility and evidence matrix

| Layer        | Owner question                               | Evidence                                          |
| ------------ | -------------------------------------------- | ------------------------------------------------- |
| Organization | Who attaches policy/creates accounts?        | Effective policy path and organization events     |
| Landing zone | Which accounts/OUs are actually enrolled?    | Control status, baselines and drift               |
| Deployment   | Which role can replace/delete resources?     | Template/diff/change set and stack events         |
| Fleet        | Which nodes/identities can execute commands? | Managed-node status, invocation and session audit |
| Compliance   | Which configuration/OS state was evaluated?  | Rule/baseline version and timestamped results     |
| Recovery     | Who can restore data/configuration?          | Isolated restore test and key/role dependencies   |

Start with read-only inventory, then controlled sandbox deployment and a bounded operation. Account enrollment, successful stack creation and a compliant patch status are different observations; none implies full application security or recovery. Keep log/backup retention and cost controls alongside governance rather than removing audit data to simplify cleanup.

## References

- [Organizations policy behavior](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- [Control Tower controls](https://docs.aws.amazon.com/controltower/latest/controlreference/controls.html)
- [StackSets permission models](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-concepts.html)
- [Systems Manager requirements](https://docs.aws.amazon.com/systems-manager/latest/userguide/managed-node-prerequisites.html)

## Guardrails and sharing

Follow [[AWS/management-governance/guardrails-and-resource-sharing|the two-account guardrail/RAM workflow]] to separate policy ceilings, service delegation, resource ownership and permitted consumer use.
