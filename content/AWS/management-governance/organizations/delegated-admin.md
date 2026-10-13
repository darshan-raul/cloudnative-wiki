---
title: "Delegated administration"
description: "Delegated administration lets a supported AWS service manage organization-wide features from a member account."
tags:
  - aws/management-governance
date: 2026-10-12
---

# Delegated administration

Delegated administration lets a supported AWS service manage organization-wide features from a member account. It does not turn that member into the management account or grant arbitrary access to every member resource.

Prerequisites: [[AWS/management-governance/organizations/README|Organizations]], [[AWS/security/iam/README|IAM]] and the owning service's permission model.

## Distinguish four identities

The Organizations root is a container; the management account is an account; its root user is a principal; a service's delegated administrator is a registered member account. Trusted service access and delegated registration are distinct setup steps. A delegated service operator still needs IAM permissions and applicable organization policy allowance.

The permitted number of delegated administrators and service principal depend on the operation. There is no exactly-one rule for all services. AWS Config supports up to three; organizational rules/conformance packs use config-multiaccountsetup.amazonaws.com, while aggregation uses config.amazonaws.com. Registering the wrong principal does not enable the desired workflow.

## Setup and revocation workflow

Check that the feature supports delegation, choose a dedicated eligible account, enable required trusted access and register it using the service's documented sequence. Configure its operator role with least privilege; record which Region/account owns configuration. Keep management-account-only actions explicit.

Before deregistration, inspect service-created roles, organization resources and dependent automation. Deregistering an account is not proof that all integrations/logging/resources were deleted, and disabling trusted access can disrupt production.

## Bounded verification exercise

In an authorized sandbox, inspect existing registrations before adding anything:

```bash
aws organizations list-delegated-administrators
aws organizations list-aws-service-access-for-organization
```

These read-only CLI v2 calls require Organizations permissions and may reveal account information. Select one supported service feature, then verify the delegated account can perform that feature while a nondelegated test account cannot. Confirm an unrelated management-account-only action remains denied.

Document actual registrations, effective IAM permission and service results—not merely a successful registration API response. Revoke only the test registration/configuration after checking dependencies and keep an audit record.

## Service-specific authority matrix

| Task                                        | Management account                       | Delegated service account                      |
| ------------------------------------------- | ---------------------------------------- | ---------------------------------------------- |
| Organization management/root policy changes | Owns supported organization operations   | Not granted by a generic service registration  |
| Enable required trusted service access      | Supported privileged setup               | Depends on actual delegated service capability |
| Operate a supported delegated feature       | May retain supported administration      | Only that feature plus required IAM authority  |
| Access arbitrary workload resources         | Still requires authorization             | Not automatically inherited                    |
| Deregister/disable integration              | Review documented authority/dependencies | Service-specific, not blanket cleanup          |

For AWS Config, aggregation and organizational rules/conformance packs use different service principals. The supported multi-administrator limit is service-specific; do not turn one service's example into a universal exactly-one constraint.

## Registration workflow and verification

A CLI registration shape is:

```bash
aws organizations register-delegated-administrator \
  --account-id 123456789012 \
  --service-principal config-multiaccountsetup.amazonaws.com
```

This is a consequential administrative example, not executed here. It requires an eligible member account, supported feature, management-account authority and trusted access/prerequisites. Choose config.amazonaws.com for the corresponding aggregation workflow only when the owning guide calls for it; using one string everywhere does not enable all Config operations.

After registration, establish the delegated account's actual role and configure a bounded organizational service feature. Verify resource coverage and unauthorized denial. Compare results from management, delegated and ordinary member identities so the authority boundary is visible.

Before deregistration, inventory service-created organization configuration, schedules, roles and reports. Disabling trusted access can stop production integrations; removal of registration does not prove every resource/role was deleted. Keep an audit trail, approved rollback and an explicit owner for retained configuration.

## References

- [Organizations delegated administrator operations](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_delegate_policies.html)
- [RegisterDelegatedAdministrator contract](https://docs.aws.amazon.com/organizations/latest/APIReference/API_RegisterDelegatedAdministrator.html)
- [Config integration/service principals](https://docs.aws.amazon.com/organizations/latest/userguide/services-that-can-integrate-config.html)
