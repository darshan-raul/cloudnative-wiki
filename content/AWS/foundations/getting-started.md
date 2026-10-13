---
title: "First safe AWS session"
description: "Verify a federated CLI identity, inspect boundaries and complete the Lambda lab with explicit budget and cleanup checks."
tags:
  - cloud/aws/foundations
date: 2026-10-12
---

# First safe AWS session

Prerequisite: [[AWS/foundations/README|AWS foundations]], an approved sandbox account, AWS CLI v2 and access assigned through [[AWS/security/iam/identity-center|IAM Identity Center]]. Do not create permanent access keys as the default learning path.

## Authenticate and verify

Configure the profile using the interactive wizard; obtain the start URL and SSO Region from your administrator. They may differ from the workload Region.

```bash
aws configure sso --profile wiki-sandbox
aws sso login --profile wiki-sandbox
aws sts get-caller-identity --profile wiki-sandbox
aws configure list --profile wiki-sandbox
```

Checkpoint: the returned account is the sandbox and the ARN is the intended assumed role. Stop on an unexpected account or identity. Environment credentials can change resolution; use the explicit profile consistently and inspect credential precedence without printing keys.

List regional availability using read-only EC2 discovery:

```bash
aws ec2 describe-availability-zones \
  --profile wiki-sandbox --region us-east-1 \
  --query 'AvailabilityZones[].{Name:ZoneName,ID:ZoneId,State:State}' \
  --output table
```

Use a Region approved for your data and account; us-east-1 is an example, not a residency recommendation. Permission to describe zones does not grant permission to deploy workloads.

## First deployment

Keep the verified identity/Region when moving to the linked lab. In this dedicated sandbox shell, set the profile and approved workload Region explicitly, then recheck the account before any mutation:

```bash
export AWS_PROFILE=wiki-sandbox
export AWS_REGION=us-east-1
aws sts get-caller-identity
```

Replace us-east-1 with the approved workload Region. Stop unless the returned Account/Arn match the sandbox. Do not fall back to a production/default profile when an SSO session expires; log in again. Unset these sandbox variables when leaving this shell.

Follow [[AWS/compute/lambda/README|the complete Lambda lab]] with the sandbox profile and chosen Region. Create only the named function, dedicated execution role and log group, record their identifiers and run the valid and invalid input tests. Do not start with a public server, wildcard admin policy or production VPC.

Expected evidence: identity/account record, successful greeting, intentional validation error, invocation log and a resource inventory. Check the estimated billing dimensions before creation; duration/request examples exclude dependencies and do not prove zero cost.

## Cleanup and failure handling

Delete the function and dedicated lab resources after testing, then re-query their absence. Keep shared policies/roles. A failed create can still leave earlier resources: reconcile your inventory rather than assuming rollback happened automatically.

Log out after the session with `aws sso logout`. This removes locally cached SSO tokens; it is not a universal revocation mechanism for every already-issued session. Follow your organization's session revocation procedure when necessary.

## References

- [CLI SSO configuration](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html).
- [Credential and configuration precedence](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html).
- [GetCallerIdentity](https://docs.aws.amazon.com/STS/latest/APIReference/API_GetCallerIdentity.html).
