---
title: External ID and the confused deputy
description: Bind a third-party AssumeRole request to the correct customer without treating the external ID as a password.
tags:
  - cloud/aws/security/iam
date: 2026-10-12
---

# External ID and the confused deputy

An external ID binds a third-party role-assumption request to a customer. **It is not a password or secret.** Knowing a role ARN does not by itself authorize access.

## Threat model

A monitoring vendor serves customers A and B and legitimately has access to roles in both accounts. If B submits A's role ARN and the vendor blindly assumes it, the vendor could use its legitimate permissions for the wrong customer.

The vendor assigns a unique external ID per customer and chooses it from its authenticated customer context—not from arbitrary request input. A's trust policy requires A's assigned ID. A request made for B therefore fails when the vendor uses B's ID, even if B knows A's ARN and ID.

## Trust and permissions are separate

This illustrative customer trust policy permits a specific vendor role, conditioned on its customer binding. Replace the example account and role with the vendor's actual identity.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111122223333:role/CustomerMonitoring"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "vendor-assigned-customer-42"
        }
      }
    }
  ]
}
```

The vendor also needs permission to call AssumeRole on the customer role. The customer role's permission policy limits what the resulting session can do. Do not grant broad ReadOnlyAccess automatically; scope actions and resources to the agreed monitoring needs. Other policy controls can still deny access.

## End-to-end handoff

| Step                 | Vendor                                                                                                   | Customer                                                                                     |
| -------------------- | -------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Register integration | Assign a unique ID in the vendor's authenticated customer record and identify the exact vendor principal | Confirm vendor identity and requested actions                                                |
| Create trust         | Provide the ID and principal ARN through an approved channel                                             | Create a role trust policy with the vendor principal and matching `sts:ExternalId` condition |
| Grant work           | Request only the needed resources/actions                                                                | Attach a scoped permission policy to the customer role                                       |
| Assume role          | Select the ID from the authenticated customer record when calling STS                                    | Monitor role assumptions and resulting actions                                               |
| Revoke               | Stop the integration and invalidate customer mapping                                                     | Remove or tighten trust and permissions, considering existing sessions                       |

The role ARN and external ID may be known to others. Security depends on the vendor's authenticated customer mapping, the trusted principal and the role's policies. Never accept an arbitrary external ID supplied by an untrusted request as the tenant binding.

## Verification exercise

Use two sandbox accounts and an already-created least-privilege role; obtain approval for the cross-account trust. Authenticate as the authorized vendor role with temporary credentials. First verify the identity with `aws sts get-caller-identity`.

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::444455556666:role/VendorMonitoringRole \
  --role-session-name external-id-test \
  --external-id vendor-assigned-customer-42 \
  --query 'AssumedRoleUser.Arn' \
  --output text
```

Expected: an assumed-role ARN. Repeat with a wrong ID and with no ID; both should return AccessDenied. Test from an unauthorized principal as well: the correct ID alone must not grant access. Check CloudTrail for the test events; never print or publish returned session credentials.

If a role succeeds without the required ID, inspect all trust-policy statements for another allowed path. After testing, remove the sandbox trust/role or restore the approved policy; expire/revoke test sessions as required. STS itself has no request charge, but activities performed using the session may be billed.

## AWS service deputies

Cross-service confused deputies are a related but different case. Use supported `aws:SourceArn`/`aws:SourceAccount` conditions for the AWS service and integration involved; do not mechanically substitute an external ID into every service-role policy.

## References

- [Third-party roles and external IDs](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_common-scenarios_third-party.html).
- [Confused deputy prevention](https://docs.aws.amazon.com/IAM/latest/UserGuide/confused-deputy.html).
- Prerequisite: [[AWS/security/iam/README|IAM]]. Related: [[AWS/security/iam/various-types-of-roles|role types]].
