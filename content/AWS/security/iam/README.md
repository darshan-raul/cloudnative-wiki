---
title: AWS IAM
description: AWS IAM — identity and access management. Users, groups, roles, policies (JSON), identity federation, SCPs, permission boundaries, service control policies, and AWS SSO.
tags:
  - aws/security
date: 2026-10-12
---

# AWS IAM (Identity and Access Management)

IAM authenticates and authorizes AWS principals. Prefer federated workforce sessions and workload roles over long-lived IAM user access keys; trust policies and permissions policies answer different questions.

## Principals and policies

Users are long-lived identities; groups collect user permissions; roles issue temporary sessions to trusted callers. A role's trust policy controls who can assume it; its identity policies control what the resulting session may do. A permissions boundary, session policy or Organizations guardrail limits permissions rather than granting them.

Study [[AWS/security/iam/policy-evaluation|policy evaluation]] for resource-policy/session-principal exceptions and SCP/RCP scope. Use [[AWS/security/iam/sts-and-federation|STS and federation]] for chaining and session attribution; use [[AWS/security/iam/identity-center|Identity Center]] for workforce permission sets/assignments. [[AWS/security/iam/various-types-of-roles|Role types]] explains service/task/instance distinctions.

## Valid policy fixture

This complete policy document permits only listing one illustrative bucket; substitute a real sandbox ARN before attaching it:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListSandboxOnly",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::wiki-lab-example"
    }
  ]
}
```

No JSON comments are allowed in a document sent to IAM. Bucket listing and object GetObject use different resource ARNs/actions; neither automatically authorizes KMS decryption.

## Read-only authorization lab

Prerequisites: a federation session and a sandbox bucket you may inspect. Record `aws sts get-caller-identity`, verify your account/Region, and validate the policy document using Access Analyzer ValidatePolicy before an administrator attaches it to a disposable role.

In that role, list the named bucket (expected success); read an object and list a different bucket (expected denial unless another applicable policy grants access). Inspect identity, resource, session, boundary and organization policies when results differ. The simulator and validation are diagnostic tools, not proof of a complete real-request decision.

The lab administrator must scope iam:PassRole/role-management permission to the disposable role and its intended service. Remove the attachment/role after the session ends; never modify a production trust policy as a learning experiment.

### Build and verify the role

For an administrator working in the approved sandbox, first save a trust document for the **exact** source role that will run the test. The source and target are examples; replace both account IDs and names. A role ARN trusted as a principal must exist when the policy is applied.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::111122223333:role/LabCaller" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Save as `trust-policy.json`; save the bucket-list policy above as `permissions.json`. Validate both documents, using `RESOURCE_POLICY` for trust and `IDENTITY_POLICY` for the permissions. Review findings before attaching anything:

```bash
aws accessanalyzer validate-policy \
  --policy-document file://trust-policy.json --policy-type RESOURCE_POLICY \
  --validate-policy-resource-type AWS::IAM::AssumeRolePolicyDocument
aws accessanalyzer validate-policy \
  --policy-document file://permissions.json --policy-type IDENTITY_POLICY
```

With the verified sandbox account, create the role and apply the narrow inline policy through the [documented CLI contracts](https://docs.aws.amazon.com/cli/latest/reference/iam/create-role.html). Inline policy attachment is a separate operation from role creation:

```bash
aws iam create-role --role-name WikiLabReadBucket \
  --assume-role-policy-document file://trust-policy.json
aws iam put-role-policy --role-name WikiLabReadBucket \
  --policy-name WikiLabBucketList --policy-document file://permissions.json
aws iam get-role --role-name WikiLabReadBucket
aws iam get-role-policy --role-name WikiLabReadBucket --policy-name WikiLabBucketList
```

The source `LabCaller` also needs a policy allowing `sts:AssumeRole` on this target role, plus any applicable boundary and organization permissions. After an authorized source assumes it, test the permitted bucket and a denied bucket. Then remove `WikiLabBucketList` and the role using `delete-role-policy` and `delete-role` after dependencies are cleared. Inspect CloudTrail for the assumption and test calls. Do not interpret an Access Analyzer finding-free policy as proof that a real request will be allowed.

## Analysis, service-linked roles and cost

Access Analyzer includes external-access analysis and policy validation; validation accepts policy documents including inline policies. Do not confuse it with a managed-policy-only tool.

Service-linked roles can be deleted after dependent service resources are removed and the deletion checks succeed. Use delete-service-linked-role and check its deletion task status; they are neither universally undeletable nor automatically removed by every service.

IAM, Identity Center and STS are offered without additional service charges. Some Access Analyzer features have their own pricing; there is no fabricated per-call STS tariff after a free quota. Avoid creating user access keys for this lab.

## Policy types, roles and authorization trace

| Policy/control        | Where it applies                                      | Does it grant access by itself?                   |
| --------------------- | ----------------------------------------------------- | ------------------------------------------------- |
| Identity policy       | User, group or role session                           | Can allow actions, subject to other controls      |
| Resource policy       | Supported resource                                    | Can allow principals under service-specific rules |
| Role trust policy     | AssumeRole entry to a role                            | Allows assumption, not arbitrary resource actions |
| Permission boundary   | IAM identity upper bound                              | No                                                |
| Session policy        | Temporary session upper bound                         | No                                                |
| Organizations SCP/RCP | Supported member-account principal/resource guardrail | No                                                |

For a cross-account request, inspect the source caller's policy, target role trust, requested session conditions, destination role permissions and applicable organization/resource controls. A successful `AssumeRole` response gives temporary credentials; it does not prove `s3:GetObject` will succeed. Conversely, an S3 resource policy may have service-specific cross-account behavior that a role-only mental model misses. Use [[AWS/security/iam/policy-evaluation|the policy evaluation lesson]] for exact rules.

An IAM group is a way to attach identity permissions to IAM users; it cannot be assumed like a role. An inline policy belongs to one identity, while a managed policy can be attached where supported and versioned as its own policy resource. A permissions boundary limits a user's or role's effective identity permissions, but does not replace careful review of resource policies, SCPs, session conditions and service behavior. Avoid wildcard actions/resources unless the use case and compensating boundaries are explicit.

```text
workforce federation / workload identity → STS session
                                      │
                     trust + identity policy + guardrails
                                      │
                         resource policy and service check
                                      │
                               allow or deny + audit event
```

Keep IAM users only for cases that truly require them; for staff, configure Identity Center assignments/permission sets and an external identity source as appropriate. For EC2, an instance profile carries the role. For Lambda, a function execution role is separate from the permission to invoke it. For ECS, task and execution roles serve different operations. Do not use root credentials or shared user keys as an easier lab route.

## Last-accessed permission review

Use Access Advisor/last-accessed reports to investigate a role's permissions. With read authorization, set `IAM_REVIEW_ROLE_ARN` to the role under review and generate a report, then inspect its job status:

```bash
IAM_ACCESS_JOB_ID=$(aws iam generate-service-last-accessed-details \
  --arn "$IAM_REVIEW_ROLE_ARN" --query JobId --output text)
aws iam get-service-last-accessed-details --job-id "$IAM_ACCESS_JOB_ID"
```

If the report is still `IN_PROGRESS`, poll with bounded backoff in the same credential session until completed or failed. Review paginated service/action results with the application owner before removing permission. [The tracking contract](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_last-accessed.html) has Region/service history limits and reports attempted access, including denials. Action detail covers supported management actions, excludes data-plane events and `iam:PassRole`, and omits some policy-derived access. Missing history therefore cannot prove a permission is unnecessary. Correlate CloudTrail, release schedules and recovery tasks, then test a scoped change with rollback.

## References

- [IAM introduction and cost](https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction.html)
- [Policy validation](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-policy-validation.html)
- [ValidatePolicy CLI](https://docs.aws.amazon.com/cli/latest/reference/accessanalyzer/validate-policy.html)
- [Service-linked-role deletion](https://docs.aws.amazon.com/cli/latest/reference/iam/delete-service-linked-role.html)

## Across the wiki

- [[Kubernetes/eks/security/pod-identity|EKS Pod Identity]]
- [[GCP/identity/workload-identity|GCP Workload Identity & Federation]]
- [[Kubernetes/eks/security/iam-roles-for-sa|IAM Roles for Service Accounts (IRSA)]]
- [[GCP/identity/README|GCP Identity & Access Management (IAM)]]
- [[Architecture/solution-architecture-concepts/authentication/README|Identity & Authentication — OIDC, JWT, OAuth, SAML]]
- [[Kubernetes/concepts/L07-security/01-api-access/03-rbac|RBAC (Role-Based Access Control)]]
