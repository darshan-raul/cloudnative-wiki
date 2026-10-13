---
title: "AWS Organizations"
description: "Organizations groups AWS accounts under a management account and Organizations root container, with OUs for policy targeting."
tags:
  - aws/management-governance
date: 2026-10-12
---

# AWS Organizations

Organizations groups AWS accounts under a management account and Organizations root container, with OUs for policy targeting. Accounts are isolation/billing boundaries; OU placement alone does not grant cross-account access. Prerequisites: [[AWS/security/iam/README|IAM]] and [[AWS/management-governance/README|governance]].

## Policy boundaries

SCPs support Allow and Deny statements. An allowlist defines the maximum permitted actions; an action must remain permitted through relevant root/OU/account policy paths, while any applicable explicit deny wins. SCPs do not grant permissions: IAM/resource policies still authorize actions.

SCPs apply to member accounts, including their root users, but not the management account or service-linked roles. Resource control policies and other organization policies have separate purpose/scope; do not treat every organization policy as an SCP. Test effective behavior from an actual member-account role.

Trusted service access permits an AWS service to integrate with the organization. [[AWS/management-governance/organizations/delegated-admin|Delegated administration]] is a separate supported service-specific registration, not blanket Organizations administrator access.

## Accounts, billing and quotas

Consolidated billing and eligible discount sharing do not merge account identities/resources. Keep the management account for narrowly scoped organization tasks; delegate supported daily operations and establish audit/logging accounts.

Current documented constraints include 2,000 OUs per organization and SCP size 10,240 characters. Default account quota is ten but can be lower for new accounts; qualified increases can reach 50,000. These are dated discovery inputs, not a guarantee for your organization; use the current quota page and service-specific limits.

Account creation is asynchronous and has prerequisites/ownership consequences. Don't use actual account closure as a disposable lab cleanup operation.

## Policy exercise

Use an existing authorized sandbox member account/OU, not the production root. Record current policy attachments and an emergency rollback path. Attach a narrowly scoped test restriction with explicit intent, then use a least-privilege role to demonstrate an allowed action and the denied action. An IAM Allow must not override an SCP deny.

Review CloudTrail evidence and effective policy path. Remove only the sandbox test attachment/policy after dependency review. Inspect before changes using these CLI v2 calls:

```bash
aws organizations describe-organization
aws organizations list-roots
aws organizations list-accounts
```

Handle pagination; a first page is not a complete account inventory. Avoid exposing sensitive account details in shared logs.

## Hierarchy, accounts and policy inheritance

```text
Management account (not constrained by SCPs)
Organizations root container
  ├─ Security OU
  │    ├─ Log archive account
  │    └─ Security tooling account
  ├─ Production OU
  │    ├─ Application account A
  │    └─ Application account B
  └─ Sandbox OU
       └─ Test member account
```

An account can be moved between OUs without moving its resources into another account. The effective policy path changes, so test deployment/runtime needs before movement. The account root principal is not the Organizations root container.

| Policy family             | Purpose                                           | Not a substitute for                       |
| ------------------------- | ------------------------------------------------- | ------------------------------------------ |
| SCP                       | Member-account permissions ceiling                | Identity/resource grants                   |
| Resource control policy   | Supported resource-side permission boundary       | Every service's policy or network controls |
| Tag policy                | Supported tagging consistency rules               | Automatic assignment of all missing tags   |
| Backup policy             | Organization backup configuration where supported | Proof that every restore succeeds          |
| AI-service opt-out policy | Supported service data-use policy                 | All privacy/retention controls             |

## A narrowly scoped SCP example

This example denies EC2 termination under its attachment scope; it does not grant other actions. Review dependencies before attaching to a sandbox OU/account, preserve emergency recovery and do not apply blindly to production.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyEc2TerminationInTestScope",
      "Effect": "Deny",
      "Action": "ec2:TerminateInstances",
      "Resource": "*"
    }
  ]
}
```

For allowlist strategies, permitted actions must survive applicable policy levels and still be granted by IAM/resource authorization. For Region restrictions, global services and control-plane endpoints need deliberate exceptions; a naive deny-by-Region template can break identity/logging operations.

## Delegation and account lifecycle walkthrough

1. Decide ownership/contact/security/logging expectations for a new account.
2. Create/invite through the supported workflow and inspect asynchronous status.
3. Place into the intended OU only after understanding inherited controls.
4. Establish federated roles, budgets, audit and supported baseline enrollment.
5. Enable trusted access/delegation only for required services.
6. Test allowed/denied actions using real member-account principals.
7. Review moves, deregistration and account closure as controlled changes.

Billing consolidation does not automatically centralize credentials or grant the payer access to workloads. Service quotas and delegated-admin counts are discovered per service. Record account IDs and policy attachments before changes; an account is not a disposable resource to delete as ordinary lab cleanup.

## References

- [SCP behavior and exceptions](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- [SCP evaluation](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_evaluation.html)
- [Organizations quotas](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_reference_limits.html)
- [Trusted access](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_integrate_services.html)

## Across the wiki

- [[Azure/governance/policy|Azure Governance — Management Groups, Policy & Locks]] — policy and governance (Azure)
- [[GCP/compute/gke/binary-authorization|GKE Binary Authorization, Container Attestations, and Supply Chain Security]] — policy and governance (GCP)
- [[Kubernetes/eks/security/policy-management|Policy Management on EKS]] — policy and governance (Kubernetes)
- [[Azure/compute/aks/governance-azure-policy|AKS Governance — Azure Policy for Kubernetes and OPA Gatekeeper Guardrails]] — policy and governance (Azure)
