---
title: "IAM Identity Center"
description: "Assign workforce access through a managed identity source, permission sets and account assignments, then test the federated CLI session."
tags:
  - cloud/aws/security/iam
date: 2026-10-12
---

# IAM Identity Center

Identity Center manages workforce access to AWS accounts and supported applications. It is not a replacement for every application-customer identity system. Start with [[AWS/security/iam/README|IAM]] and [[AWS/security/iam/policy-evaluation|policy evaluation]].

## Identity versus authorization

Choose the identity source: Identity Center directory, supported Active Directory or an external IdP. Federation handles authentication; SCIM can provision users/groups but does not by itself grant AWS account access.

Permission sets define access configuration provisioned into target accounts. Assignments connect a user/group, permission set and account. Provisioning/assignment is asynchronous; wait for success before concluding the user has access. Account instances and organization instances have different capabilities; check the deployment type before planning multi-account administration.

## Sandbox access exercise

Prerequisites: an approved Identity Center administrator, a sandbox account and a test group. Do not modify production access to learn this workflow.

1. Create a tightly scoped permission set through the console or documented SSO Admin API. Set the session duration consciously.
2. Assign the test group to the sandbox account and wait for provisioning/assignment completion.
3. Configure a CLI SSO profile and log in as the test user.
4. Check `aws sts get-caller-identity`, then test one permitted read and one deliberately denied operation.
5. Inspect the provisioned role and audit events with an administrator; verify access comes from the intended assignment rather than an unrelated role.
6. Remove the test assignment and dedicated permission set only after reviewing impact. Existing sessions require separate lifetime/revocation consideration.

The creation API uses top-level Name and InstanceArn; permission-policy attachment is a separate operation. Do not use an invented `--permission-set` JSON argument.

## Operational decisions

Define MFA, IdP outage behavior, emergency access, joiner/mover/leaver ownership and periodic access review. A short session lifetime alone does not replace incident revocation. Protect break-glass access independently and test it without weakening normal federation.

Identity Center is offered at no additional charge, but connected services and advanced analysis features may be billed separately.

## References

- [Identity Center overview](https://docs.aws.amazon.com/singlesignon/latest/userguide/what-is.html).
- [Permission sets](https://docs.aws.amazon.com/singlesignon/latest/userguide/permissionsetsconcept.html).
- [CreatePermissionSet contract](https://docs.aws.amazon.com/cli/latest/reference/sso-admin/create-permission-set.html).
- [CLI SSO setup](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html).
