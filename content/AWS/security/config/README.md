---
title: AWS Config
description: AWS Config — resource inventory, change tracking, and compliance. Config rules, conformance packs, timeline of resource changes, and multi-account aggregation.
tags:
  - aws/security
date: 2026-10-12
---

# AWS Config

Prerequisites: [[AWS/security/iam/README|IAM roles and least privilege]] and the [[AWS/security/README|security evidence/response model]].

AWS Config records supported resource configuration and evaluates configured rules. Recording, evaluation, aggregation and remediation are separate capabilities with separate authorization and cost.

## Scope and dependencies

Choose supported resource types and continuous/daily recording deliberately; Config does not universally observe every resource and every change. Global IAM types have Region-generation restrictions; record/evaluate global resources once where feasible to avoid duplicated charges.

A customer-managed recorder needs its service role and a delivery channel with the documented S3/SNS permissions. One delivery channel is supported per account/Region. Do not infer a universal same-Region S3 restriction from a KMS Region condition.

Rules can be configuration-change, periodic or combined, according to the rule contract. An aggregator is read-only: it collects source evidence but cannot deploy rules or repair source resources. Remediation needs an independently authorized Automation workflow and role.

## Controlled compliance lab

Prerequisites: sandbox configuration recorder/channel permissions, a documented Config service role, and a logging bucket with Config delivery access. Configuration-item and evaluation charges apply.

1. In the console create the recorder/delivery channel using only supported resource types needed for the experiment; do not accidentally enable an all-resource recorder in a production account.
2. Start recording and create the managed rule S3_BUCKET_PUBLIC_READ_PROHIBITED.
3. Select a private disposable S3 bucket and wait for its configuration/evaluation. Expected: COMPLIANT. Keep S3 Block Public Access enabled.
4. To learn failure handling without exposing data, use a documented test fixture/isolated policy simulation or review a pre-existing noncompliant sandbox record. Do not make a real bucket public just to generate a finding.
5. Inspect evaluation annotation, resource ID, capture time and rule trigger. A missing record can mean unsupported selection, stopped recorder or delivery/IAM failure rather than compliance.
6. For authorized remediation, use the owning SSM Automation document, narrow assume-role permissions and test parameters on an isolated resource. Re-evaluate after repair; a successful automation invocation alone does not prove compliance.

## Cleanup and cost

Delete the lab rule/remediation and stop/delete only the recorder/channel created for this lab; restore prior configuration if one existed. Remove lab records/bucket objects only under the retention policy.

Budget recorded configuration items, Config rule evaluations and conformance-pack evaluations separately. Fewer than fifty rules does not make them free; Security Hub integration does not include these costs automatically.

## Recorder, delivery, rule and aggregator architecture

```text
supported resources → scoped recorder → configuration history → delivery channel
                                           ↓
                                  managed/custom rules → compliance
                                           ↓
                                   authorized remediation
source accounts/Regions → read-only aggregator → investigation
```

| Component        | Owns                                   | Does not do                                   |
| ---------------- | -------------------------------------- | --------------------------------------------- |
| Recorder         | Supported resource selection/frequency | Every possible application change             |
| Delivery channel | Documented S3/SNS delivery             | Grant all investigator/remediator permissions |
| Rule             | Trigger/evaluation logic               | Automatically repair all failures             |
| Conformance pack | Rule/remediation package               | Bypass source roles/recording coverage        |
| Aggregator       | Read-only combined evidence            | Deploy rules or modify source resources       |

## Inventory and timeline walkthrough

With an already enabled sandbox recorder and read permissions:

```bash
aws configservice list-discovered-resources --resource-type AWS::EC2::Instance
aws configservice get-resource-config-history \
  --resource-type AWS::EC2::Instance --resource-id INSTANCE_ID \
  --chronological-order Forward
aws configservice select-resource-config \
  --expression "SELECT resourceId, resourceType WHERE resourceType = 'AWS::EC2::Instance'"
```

Distinguish current recorded configuration from the live resource and historical capture time. Advanced-query syntax supports a bounded subset, not arbitrary SQL joins and every missing/deleted record. Query explicit configuration fields only after inspecting their actual shape.

## Managed/custom rules and conformance packs

A managed rule requires its SourceIdentifier and supported input/trigger settings. Change-trigger and periodic rules differ; increasing recorder coverage does not force every periodic evaluation immediately.

A custom Lambda rule needs the AWS Config invocation permission, execution role, event parsing, evaluation results and failure handling. Use the owning maintained example rather than an undefined evaluation helper. A conformance-pack template must contain supported Config rule/remediation resources, not a free-form YAML policy list.

```bash
aws configservice describe-config-rules
aws configservice describe-compliance-by-config-rule --config-rule-names LAB_RULE_NAME
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name LAB_RULE_NAME --compliance-types NON_COMPLIANT
```

Inspect annotation/resource/capture/evaluation times. A noncompliant event can become stale before automation runs; verify current state and input before remediation. Grant Automation only the intended resource changes, test rollback and re-evaluate.

## Multi-account and troubleshooting runbook

Use Organizations/service-trust/delegated-administration or account-specific aggregation authorization according to the owning model. The aggregator is read-only; it does not imply source recording, rule deployment or remediation permission.

Check supported resource selection/global-IAM Region rules, recorder state/role, delivery bucket/key/SNS policy, rule trigger and aggregator freshness separately. Missing inventory is not compliance. Restore prior recorder/channel/rule settings; remove only dedicated lab aggregators/rules/packs and preserve source records under retention.

References: [advanced query](https://docs.aws.amazon.com/config/latest/developerguide/querying-AWS-resources.html), [history API](https://docs.aws.amazon.com/cli/latest/reference/configservice/get-resource-config-history.html), [custom rules](https://docs.aws.amazon.com/config/latest/developerguide/evaluate-config_develop-rules.html), [conformance packs](https://docs.aws.amazon.com/config/latest/developerguide/conformance-packs.html).

## References

- [Recording selection and global scope](https://docs.aws.amazon.com/config/latest/developerguide/select-resources.html)
- [Delivery channel](https://docs.aws.amazon.com/config/latest/developerguide/manage-delivery-channel.html)
- [Read-only aggregation](https://docs.aws.amazon.com/config/latest/developerguide/aggregate-data.html)
- [Remediation](https://docs.aws.amazon.com/config/latest/developerguide/remediation.html)
- [Pricing](https://aws.amazon.com/config/pricing/)

## Across the wiki

- [[Security/cloud-security/README|Cloud Security Hub]]
- [[GCP/compute/gke/security|GKE Security & Hardening — Workload Identity & Binary Authorization]]
- [[Security/cloud-security/aws/README|AWS Security]]
- [[Security/cloud-security/azure/README|Azure Security]]
