---
title: "AWS Control Tower"
description: "Control Tower establishes and governs a landing zone using Organizations and supporting services."
tags:
  - aws/management-governance
date: 2026-10-12
---

# AWS Control Tower

Control Tower establishes and governs a landing zone using [[AWS/management-governance/organizations/README|Organizations]] and supporting services. It is not a replacement for IAM, workload security or recovery design.

## Landing zone and control types

A landing zone provides account/OU structure, shared audit/logging foundations and account provisioning/enrollment. Preventive controls restrict actions, detective controls identify noncompliance and proactive controls check supported provisioning before deployment. Each control's scope, Region/resource support and underlying enforcement matter.

Account enrollment and registered OUs have specific prerequisites; existing accounts are not automatically governed merely because they are in an organization. Current landing-zone capacity is up to 10,000 accounts, subject to related quotas—not twenty. A supported third-party identity provider can remain integrated; setup does not universally replace corporate identity.

## Account Factory and infrastructure boundaries

Account Factory provisioning uses the documented Service Catalog/account workflow, not a fictional accept-responsibility-for-portfolio-access operation. AcceptPortfolioShare concerns an actual portfolio share and does not itself provision an account.

Do not manually edit Control Tower-managed resources without understanding drift/repair behavior. Separate landing-zone baselines from workload [[AWS/management-governance/cloudformation/README|CloudFormation]]/CDK stacks. Governance does not automatically enable every service's data logging, protect every data plane or eliminate regional failure risk.

## Governance exercise

Use authorized sandbox OUs/accounts and budget for logging/Config/supporting resources. Identify one supported control of each type and explain whether it blocks an action, reports state or checks provisioning. Enable only an approved sandbox control, then test an allowed action and a deliberate bounded noncompliant action.

Expected observations differ: a preventive denial, a detective finding after evaluation, or a proactive provisioning failure. An enrolled-account status alone is not evidence all workloads are compliant. Inspect drift/status and document a safe repair/rollback sequence.

Remove only test controls/resources after dependency review; account closure, landing-zone deletion or disabling audit trails are not routine learning cleanup. Retained logs continue to incur charges.

## Costs and prerequisites

Control Tower's supporting services can cost money: logging, Config recording/rules, S3/KMS and provisioned infrastructure should be budgeted. Verify home/governed Regions, identity integration, existing organization prerequisites and quotas in the current setup guide.

## Landing-zone architecture and control comparison

```text
Organizations
  → Control Tower landing zone
       ├─ audit/security access
       ├─ log archive
       ├─ registered OUs + enrolled accounts
       └─ Account Factory provisioning
            → supported preventive/detective/proactive controls
```

| Control type | When evidence appears                          | Test                                                           |
| ------------ | ---------------------------------------------- | -------------------------------------------------------------- |
| Preventive   | At the action's authorization/enforcement path | Deliberately attempt bounded denied action                     |
| Detective    | After supported resource evaluation            | Create/revert a sandbox noncompliant state and inspect finding |
| Proactive    | During supported provisioning validation       | Submit a supported noncompliant resource proposal              |

Mechanisms/support differ by control. A control enabled in an OU is not proof that every resource type/Region/deployment path is covered. Choose the relevant supported Regions and identity integration deliberately.

## Account Factory and enrollment walkthrough

1. Verify organization/landing-zone prerequisites and home Region.
2. Decide target OU, account identity/contact and federation setup.
3. Provision through the supported Account Factory/Service Catalog workflow or enroll an eligible existing account.
4. Wait for terminal provisioning/enrollment state and inspect failures.
5. Verify baseline/control coverage from the actual account.
6. Deploy workload infrastructure using separate approved roles/templates.
7. Capture audit/budget/logging evidence and test access/failure recovery.

Accepting a portfolio share is not account provisioning; use the supported Account Factory workflow for account creation/enrollment. Manually creating similar-looking resources does not establish managed baseline enrollment.

## Drift, identity and operating responsibilities

A supported external IdP can remain part of the identity architecture; Control Tower does not universally replace it. Separate federation/session/permission sets from organization control ceilings.

Avoid manual edits to managed resources without a documented repair plan. Inspect drift, baseline/control status and service failures; an account's available status can coexist with an operationally unhealthy workload. Supporting Config, logging, S3 and KMS can charge even when Control Tower itself has no separate blanket account fee.

Test changes first on approved sandbox OUs, and retain emergency access/rollback. Landing-zone removal, disabling security logging and closing accounts require controlled administrative decisions rather than tutorial cleanup.

## References

- [Control Tower getting started](https://docs.aws.amazon.com/controltower/latest/userguide/getting-started-with-control-tower.html)
- [Controls reference](https://docs.aws.amazon.com/controltower/latest/controlreference/controls.html)
- [Control Tower quotas](https://docs.aws.amazon.com/controltower/latest/userguide/limits.html)
- [Account Factory provisioning](https://docs.aws.amazon.com/controltower/latest/userguide/provision-as-end-user.html)

## Across the wiki

- [[Azure/governance/policy|Azure Governance — Management Groups, Policy & Locks]] — policy and governance (Azure)
- [[GCP/compute/gke/binary-authorization|GKE Binary Authorization, Container Attestations, and Supply Chain Security]] — policy and governance (GCP)
- [[Kubernetes/eks/security/policy-management|Policy Management on EKS]] — policy and governance (Kubernetes)
- [[Azure/compute/aks/governance-azure-policy|AKS Governance — Azure Policy for Kubernetes and OPA Gatekeeper Guardrails]] — policy and governance (Azure)
