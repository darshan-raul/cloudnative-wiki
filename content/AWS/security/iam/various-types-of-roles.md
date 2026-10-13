---
title: "Roles"
tags: [cloud/aws/security/iam]
date: 2026-10-12
description: "In AWS, IAM (Identity and Access Management) roles allow you to delegate access to different AWS services and resources without using long-term credentials like passwords or access keys."
---

# Roles

A role is a stable IAM identity without its own long-term access keys; assuming it produces temporary session credentials. These role labels describe how a role is used; they do not create different authorization engines.

## Role distinctions

- A service role is assumed by an AWS service to perform configured work. Trust the correct service principal and constrain its permissions.
- A service-linked role has a service-defined trust/permission lifecycle. Remove dependent resources before requesting deletion and inspect the deletion-task result.
- A cross-account role trusts authorized external principals. Trust alone does not necessarily authorize an originating IAM caller; evaluate both sides and any session/organization restrictions.
- An EC2 instance profile delivers role credentials to a workload. A profile is a container for the role, not an independent permission grant.
- A Lambda execution role authorizes function activity, not invocation by a client. Invocation permission is a different policy.
- An ECS task role authorizes application calls; its execution role authorizes supported startup operations such as image pull/log delivery. Do not put application permissions only in the execution role.

## Role handoff map

```text
caller principal → role trust policy → STS temporary session
                                      └→ role permissions + guardrails

EC2 instance → instance profile → attached role
Lambda service → function execution role
ECS agent/startup → task execution role
ECS application → task role
```

For each integration, identify **who assumes the role** and **which operation the resulting session performs**. An EC2 instance role is supplied through an instance profile; a Lambda execution role enables function code and service setup to call permitted AWS APIs; an ECS task execution role helps startup, while the task role reaches AWS services from the application. A cross-account role needs both a trust entry and source/destination authorization checks. A service-linked role has a service-defined lifecycle and can usually be removed only after its dependent resources are gone.

## Trust versus permission test

Begin with [[AWS/security/iam/README|IAM]] and [[AWS/security/iam/policy-evaluation|evaluation rules]]. For a disposable role, have an administrator inspect its trust policy and attached policies. Try an authorized AssumeRole request, then one from a principal excluded by trust; expect the latter to fail before target actions can execute.

Use [[AWS/security/iam/external-id-and-confused-deputy-problem|external IDs]] for applicable third-party delegation; an external ID is not a secret credential. Record the session identity through [[AWS/security/iam/sts-and-federation|STS]] and audit session attribution in CloudTrail. Remove the lab role only after dependent resources and sessions have been considered.

## Operational safeguards

Scope PassRole to the exact intended role/service; it is not permission to call AssumeRole. Avoid wildcards in trust principals without deliberate conditions. Never paste temporary credentials into notes or logs. Permission boundaries/guardrails are upper bounds, not permission grants.

## References

- [IAM roles](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html)
- [Service-linked roles](https://docs.aws.amazon.com/IAM/latest/UserGuide/using-service-linked-roles.html)
- [PassRole](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html)

## Across the wiki

- [[GCP/identity/README|GCP Identity & Access Management (IAM)]]
- [[Architecture/solution-architecture-concepts/authentication/README|Identity & Authentication — OIDC, JWT, OAuth, SAML]]
- [[Kubernetes/concepts/L07-security/01-api-access/03-rbac|RBAC (Role-Based Access Control)]]
