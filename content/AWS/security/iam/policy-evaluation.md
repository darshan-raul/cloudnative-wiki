---
title: "IAM policy evaluation"
description: "Diagnose authorization by distinguishing identity, resource, trust, session and organization policies rather than applying one oversimplified rule."
tags:
  - cloud/aws/security/iam
date: 2026-10-12
---

# IAM policy evaluation

AWS authorization is not just “allow plus deny.” First identify the action, resource, principal type, account boundary and request context. Then apply the policies relevant to that request. Start with [[AWS/security/iam/README|IAM]].

## Policy roles

| Policy               | Role in the decision                                            |
| -------------------- | --------------------------------------------------------------- |
| Identity policy      | Permissions attached to a user/role                             |
| Resource policy      | Access granted by the resource; principal and account matter    |
| Role trust policy    | Who can assume the role, not what the session can do afterward  |
| Permissions boundary | Maximum identity-policy permissions, not a grant                |
| Session policy       | Narrows an assumed session; not a permanent role-policy change  |
| SCP                  | Organization permissions ceiling for affected member principals |
| RCP                  | Resource-side organization ceiling for supported resources      |

An applicable explicit deny wins. However, implicit-deny interactions depend on whether a resource policy grants to a user ARN, role ARN or role-session ARN. Do not promise that a boundary behaves identically for every resource-policy principal form. Cross-account access generally requires permission on both sides and can also involve encryption-key authorization.

SCPs do not grant permissions and do not constrain the management account like a member account. Service-linked roles have documented exemptions. RCPs apply to supported resource/service cases, not universally to every AWS action.

## AccessDenied investigation

1. Record GetCallerIdentity, action, full resource ARN, Region and error request ID.
2. Confirm the API maps to the expected permission action; service integrations may need more than one.
3. Inspect identity, resource and key policies, role trust (for assumption), boundary/session restrictions and relevant SCP/RCP hierarchy.
4. Check condition keys against actual context: tags, source identity, network source, encryption context or requested Region.
5. Distinguish no grant from explicit deny. Consult CloudTrail where the action is recorded; do not assume every data operation is logged by default.
6. Change the smallest necessary scope and repeat both positive and negative tests.

PassRole permits passing an approved role to a service; it is not permission to assume that role. Scope its resource and service condition and inspect the receiving service's trust relationship.

## Local policy exercise

Write down a user/role permission, a boundary omitting that action, and a resource-policy grant. Predict the result for a role ARN and a role-session ARN separately, then compare with AWS's evaluation documentation or a sandbox test. Use Access Analyzer policy validation to detect malformed documents; a valid policy can still grant unwanted access.

Do not deploy an all-resource wildcard grant as a diagnostic shortcut. If using the policy simulator, read its documented limitations: it is not an exact simulation of every service/resource-policy/context combination.

### Worked same-account boundary exception

Use a synthetic S3 object `arn:aws:s3:::wiki-policy-lab-123456789012/fixture.txt`, a role `arn:aws:iam::123456789012:role/WikiPolicyLab` and its assumed session `arn:aws:sts::123456789012:assumed-role/WikiPolicyLab/boundary-demo`. Replace all account/bucket identifiers together if doing the optional sandbox test. Assume ordinary S3 object access (no separate KMS requirement), no session policy, no applicable organizational restriction and no other explicit denies.

The role's identity policy grants one object read (`identity.json`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::wiki-policy-lab-123456789012/fixture.txt"
    }
  ]
}
```

Its permissions boundary only allows bucket listing (`boundary.json`), implicitly omitting object reads:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::wiki-policy-lab-123456789012"
    }
  ]
}
```

First evaluate this bucket policy (`resource-role.json`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::123456789012:role/WikiPolicyLab" },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::wiki-policy-lab-123456789012/fixture.txt"
    }
  ]
}
```

For case two, copy that document as `resource-session.json`, changing only Principal.AWS to `arn:aws:sts::123456789012:assumed-role/WikiPolicyLab/boundary-demo`. This direct session grant is intentionally exceptional; it is not a recommended way to bypass governance. For case three, add this statement to the boundary's Statement array:

```json
{
  "Effect": "Deny",
  "Action": "s3:GetObject",
  "Resource": "arn:aws:s3:::wiki-policy-lab-123456789012/fixture.txt"
}
```

| Case | Resource-policy principal | Boundary read restriction | Expected GetObject result            |
| ---- | ------------------------- | ------------------------- | ------------------------------------ |
| 1    | Role ARN                  | Implicit omission         | Denied                               |
| 2    | Exact role-session ARN    | Implicit omission         | Allowed under the stated assumptions |
| 3    | Either form               | Applicable explicit deny  | Denied                               |

The [principal-specific boundary rules](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html) explain these outcomes. This table is not a cross-account rule or a universal KMS authorization model.

To observe rather than simulate, have an approved administrator provision a dedicated bucket/object/role with the above identity policy and boundary, and trust only your sandbox caller. Assume it with session name `boundary-demo`, verify GetCallerIdentity, and run `aws s3api get-object --bucket wiki-policy-lab-123456789012 --key fixture.txt fixture-download.txt` as that session after each administrator policy change. Wait/retry only for bounded IAM propagation; do not change policies as the test role. Save request/error evidence without credentials. Restore/remove the dedicated bucket policy, object, role policy and boundary attachment before deleting the lab role/boundary; never experiment on a shared bucket. An Access Analyzer validation result proves document analysis, not the observed authorization outcome.

## References

- [Evaluation logic](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html).
- [Principal type and boundaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html).
- [SCP effects and exemptions](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html).
- [PassRole](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html).
- Next: [[AWS/security/iam/sts-and-federation|STS sessions]] and [[AWS/security/iam/external-id-and-confused-deputy-problem|third-party delegation]].
