---
title: "STS and temporary credentials"
description: "Separate role trust, session permissions, federation and chaining, and test temporary access without distributing long-lived keys."
tags:
  - cloud/aws/security/iam
date: 2026-10-12
---

# STS and temporary credentials

STS issues temporary security credentials. A role is a stable IAM identity; a session is a time-bounded credential set derived from it. Use [[AWS/security/iam/identity-center|Identity Center]] for workforce access and service roles for supported workloads.

## Choose the federation path

AssumeRole delegates from an authorized AWS principal. AssumeRoleWithSAML and AssumeRoleWithWebIdentity accept supported identity assertions. Match issuer, audience, subject and other trust conditions to the real IdP/integration; accepting every subject from a trusted issuer is rarely the desired scope.

Session policies restrict the issued session; they do not expand the role's permissions. Session tags and source identity can support ABAC/audit when the caller is authorized to set them and trust conditions bind them correctly.

Role chaining has a one-hour session restriction for the chained role, even when its maximum session duration is longer. Workload credentials rotate; code should use the SDK credential provider rather than copy them into configuration files.

## Sandbox exercise

Use a dedicated target role with one read-only action and a specific trusted sandbox principal. Set TARGET_ROLE_ARN after verifying both accounts.

```bash
aws sts get-caller-identity
aws sts assume-role \
  --role-arn "$TARGET_ROLE_ARN" \
  --role-session-name wiki-sts-test \
  --duration-seconds 900 \
  --query '{Arn:AssumedRoleUser.Arn,Expires:Credentials.Expiration}' \
  --output json
```

Expected: target assumed-role ARN and an expiry timestamp, without displaying secret keys. This proves assumption, not access to an arbitrary target resource. Use a supported credential-process/profile workflow for the resource test, confirm the new identity, then try an allowed read and a denied write.

Failure exercise: remove the trust grant in the sandbox or supply a mismatched required external ID. Expect AccessDenied. Diagnose both caller permissions and target trust; do not fix only one side.

Cleanup: restore/remove only dedicated sandbox policies and the test role. Review existing session revocation separately; deleting a local credential file is not server-side session revocation.

## References

- [AssumeRole contract and chaining](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html).
- [Federation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers.html).
- [Revoke role sessions](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_revoke-sessions.html).
- Prerequisite: [[AWS/security/iam/policy-evaluation|policy evaluation]].
