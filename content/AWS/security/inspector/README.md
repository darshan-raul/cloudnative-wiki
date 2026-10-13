---
title: AWS Inspector
description: AWS Inspector — automated vulnerability scanning for EC2, ECR, and Lambda. Network reachability, CVE scanning, CIS benchmarks, security assessments, and findings integration with Security Hub.
tags:
  - aws/security
date: 2026-10-12
---

# AWS Inspector

Prerequisites: [[AWS/security/iam/README|IAM roles and least privilege]] and the [[AWS/security/README|security evidence/response model]].

Amazon Inspector assesses vulnerabilities for supported EC2, ECR image and Lambda workloads. Findings require prioritization and remediation; a scan is not proof that a workload is secure.

## Coverage and agents

Use the current Inspector2 API, not historical Inspector Classic examples. EC2 assessment has agent-based and agentless eligibility/coverage differences. Agent-based collection depends on SSM Agent/management prerequisites; installing CloudWatch Agent is not installing SSM Agent. ECR enhanced scanning is configured at the registry through the ECR registry API, not a repository's basic scan configuration.

Lambda standard scanning and code scanning have different coverage/pricing. Check supported operating systems, runtimes, Regions and inactive-resource behavior before assuming every resource is continuously assessed.

## Reversible coverage lab

Prerequisites: a sandbox role with Inspector2 read/enable/disable permissions and the documented service-linked-role setup authority. Enabling a type changes account/Region scanning and may incur charges; do this only in a disposable environment.

```bash
aws inspector2 enable --resource-types EC2 ECR LAMBDA
aws inspector2 list-coverage
aws inspector2 list-findings --filter-criteria '{"findingStatus":[{"comparison":"EQUALS","value":"ACTIVE"}]}'
```

Expected: coverage records for eligible existing sandbox resources and active findings if present. An empty finding set is not proof of no vulnerabilities; inspect coverage and scan failures first. Findings are retrieved through list-findings, not nonexistent describe-findings.

For an ECR-specific experiment, configure enhanced scanning with `aws ecr put-registry-scanning-configuration --scan-type ENHANCED` after reviewing the registry rule contract. This changes registry-wide behavior; preserve the prior configuration and scope repository filters where supported. Push a disposable test image by digest, inspect coverage/findings, patch/rebuild and compare the new digest.

## Failure, cleanup and costs

Diagnose unsupported image/runtime/OS, missing SSM management and permissions before broadening access. Do not intentionally expose a vulnerable instance to the internet.

Delete disposable images/resources and restore the previous ECR scan configuration. If the account was not previously enabled, disable only the types enabled for this lab; disabling a production scanner is not a cost exercise.

The standard published trial is fifteen days for eligible types, not a permanent free allowance of five hundred instances. EC2 resource-hours, ECR images and rescans, Lambda standard/code scanning have different billable dimensions and trial eligibility.

## Scanner comparison and resource pipeline

| Service   | Primary question                                     | Evidence                                       |
| --------- | ---------------------------------------------------- | ---------------------------------------------- |
| Inspector | Is supported software/configuration vulnerable?      | Coverage plus version/CVE/reachability context |
| GuardDuty | Is supported behavior suspicious?                    | Finding/source/activity context                |
| Macie     | Does eligible S3 data contain sensitive information? | Inspection/sampling/statistics                 |
| Config    | Does recorded configuration satisfy a rule?          | Capture/evaluation/annotation                  |

```text
eligible EC2/ECR/Lambda resource → coverage/scan → finding
                                                ↓
                          digest/version + exploit/context assessment
                                                ↓
                                patch/rebuild/redeploy → re-assess
```

Inspector Classic target/template examples are historical, not current Inspector2 deployment contracts. CloudWatch Agent is not SSM Agent, and historical v1 reachability findings are not universal Inspector2 behavior.

## Coverage and filter walkthrough

Use list-coverage before treating an empty finding list as safe. Confirm resource type, eligibility/state, scan timestamps and failure reason using current response fields.

```bash
aws inspector2 list-findings \
  --filter-criteria '{"resourceType":[{"comparison":"EQUALS","value":"AWS_EC2_INSTANCE"}],"findingStatus":[{"comparison":"EQUALS","value":"ACTIVE"}]}'
aws inspector2 list-findings \
  --filter-criteria '{"resourceType":[{"comparison":"EQUALS","value":"AWS_LAMBDA_FUNCTION"}],"findingStatus":[{"comparison":"EQUALS","value":"ACTIVE"}]}'
```

Filter values/actions come from the Inspector2 contract; FINDINGS/compare and describe-findings are not correct substitutes. Handle pagination and correlate actual resource ARNs with owners.

## ECR enhanced scanning and image lifecycle

For an approved isolated registry, preserve the prior registry scan configuration. This valid enhanced configuration scopes a repository pattern:

```bash
aws ecr put-registry-scanning-configuration --scan-type ENHANCED \
  --rules '[{"scanFrequency":"CONTINUOUS_SCAN","repositoryFilters":[{"filter":"wiki-lab*","filterType":"WILDCARD"}]}]'
aws ecr get-registry-scanning-configuration
```

This changes registry configuration, not a repository's basic scan-on-push option. Use a supported image, record its digest, inspect scan coverage/findings and patch/rebuild into a new digest. Re-tagging without rebuilding does not repair vulnerable bytes. Basic/ECR versus Inspector2 retrieval contracts and rescan eligibility differ.

## EC2/Lambda prerequisites and operational triage

Agent-based EC2 coverage requires actual SSM Agent/managed-instance prerequisites and permissions; use the owning OS install workflow and management evidence. Agentless support has separate eligibility/exclusions. An instance profile must not receive administrator access merely to fix scanning.

Lambda scanning applies to supported functions/runtime/packages and scan types; code scanning has different access/product scope. Inspect deployed version/revision and package dependencies, not only the runtime's name.

Prioritize by affected deployed digest/version, exposure, exploitability and business context. A suppressed finding is not remediation. Validate deployment and rescan/finding closure; retain exceptions with expiry/owner.

Restore registry/scan settings after the sandbox, remove disposable images/functions/instances/logs and revoke lab-only access. Do not disable an organization's production scanner during cleanup.

References: [Inspector2 filters](https://docs.aws.amazon.com/cli/latest/reference/inspector2/list-findings.html), [EC2 scanning](https://docs.aws.amazon.com/inspector/latest/user/scanning-ec2.html), [ECR scanning](https://docs.aws.amazon.com/inspector/latest/user/scanning-ecr.html), [registry rules](https://docs.aws.amazon.com/cli/latest/reference/ecr/put-registry-scanning-configuration.html).

## Cross-wiki comparisons

- [[DevOps/devsecops/stage2-build/09-container-image-scanning|M09: Container Image Scanning & Hardening]] — software supply chain (DevOps)
- [[Containers/registries|Container Registries]] — software supply chain (Containers)

## References

- [Inspector coverage](https://docs.aws.amazon.com/inspector/latest/user/what-is-inspector.html)
- [Enable CLI](https://docs.aws.amazon.com/cli/latest/reference/inspector2/enable.html)
- [ListFindings contract](https://docs.aws.amazon.com/cli/latest/reference/inspector2/list-findings.html)
- [ECR registry scanning](https://docs.aws.amazon.com/cli/latest/reference/ecr/put-registry-scanning-configuration.html)
- [Pricing/trial](https://aws.amazon.com/inspector/pricing/)

## Across the wiki

- [[Security/kubernetes-security/vulnerability-scanning/README|Kubernetes Vulnerability Scanning]]
- [[Kubernetes/concepts/L07-security/02-workload-sandboxing/19-image-hardening|Image Hardening]]
