---
title: AWS CloudTrail
description: AWS CloudTrail — API audit logging. Trails, event history, S3 log delivery, CloudWatch integration, encryption, and compliance.
tags:
  - aws/security
date: 2026-10-12
---

# AWS CloudTrail

Prerequisites: [[AWS/security/iam/README|IAM roles and least privilege]] and the [[AWS/security/README|security evidence/response model]].

CloudTrail records supported AWS activity for audit. It does not promise a record of every possible application action; management, data, network-activity and Insights coverage require deliberate selection.

## Coverage and delivery

Event History is the regional ninety-day management-event view, not an all-data-event archive. Trails provide selected delivery to S3 and optionally CloudWatch Logs; CloudTrail Lake has its own event stores, retention and query pricing.

Default trail management-event coverage includes supported control-plane reads such as Describe operations. Data-event logging is selected separately for supported resources. Do not claim two events for every S3 operation or classify Lambda as a global service.

Trail delivery to S3 typically averages about five minutes, not a guaranteed real-time SLA. Logging delays matter when using audit signals for response; design detection with bounded expectations rather than instantaneous delivery promises.

## Sandbox integrity exercise

Prerequisites: an isolated logging bucket with the documented CloudTrail bucket policy, a disposable trail and scoped read/trail configuration permissions. Use the official setup workflow to create a trail, choose management read/write events, enable log-file validation and start logging.

Perform a harmless management read (for example DescribeTrails), then inspect its event in Event History and the delivered S3 log. Record actor, eventTime, eventSource, eventName and request identity.

Digest delivery is not verification. Run:

```bash
aws cloudtrail validate-logs --trail-arn TRAIL_ARN \
  --start-time 2026-10-12T00:00:00Z --end-time 2026-10-13T00:00:00Z
```

Replace the interval with one containing delivered digest files and ensure S3 read permissions. Expected: integrity-validation output for covered logs. Validation detects modifications as well as deletions. Test tampering only on copies in an isolated exercise; never alter real audit evidence.

## Cleanup and safeguards

Only stop/delete the disposable trail after collecting evidence; keep production/organization trails enabled. Preserve records according to retention/legal requirements. Remove lab-only bucket objects/resources only when authorized; deleting the trail does not automatically delete archived logs.

Separate logging administration from investigation access. Encrypt and restrict buckets, consider immutable retention and alarm on logging changes. Cost optimization must preserve required security coverage.

## Pricing

Distinguish first management-event trail copy, additional management copies, selected data/network events, Insights and Lake ingestion/query/retention. S3/KMS/CloudWatch charges are additional. An event copy model cannot be replaced by a universal log-GB tariff; use current regional tables and actual selector volume.

## Event classes and telemetry comparison

| Evidence                     | Scope                                             | Not a substitute for                |
| ---------------------------- | ------------------------------------------------- | ----------------------------------- |
| CloudTrail management event  | Supported control-plane actions, identity/context | Every data or application operation |
| Selected data/network events | Supported selectors/resource/service coverage     | Implicit universal coverage         |
| CloudTrail Insights          | Supported unusual activity analysis               | Application performance traces      |
| CloudWatch application logs  | Workload-produced events                          | Independent control-plane audit     |
| VPC Flow Logs                | Supported network metadata                        | Full packets or API caller identity |

```text
supported AWS action → event selector → trail → S3 logs + digest
                                              └─ optional Logs integration
event store → CloudTrail Lake retention/query (separate lifecycle/cost)
```

## Trail creation and bucket-policy boundaries

Before creation provision the dedicated bucket and the documented CloudTrail permissions: bucket GetBucketAcl plus object PutObject to the intended account/trail prefix, with applicable ACL/source-ARN conditions. Scope to the correct partition/account/trail and KMS key if selected. A generic S3 write policy is not an audited logging setup.

With that setup complete:

```bash
aws cloudtrail create-trail --name wiki-audit-lab --s3-bucket-name LAB_LOG_BUCKET \
  --is-multi-region-trail --enable-log-file-validation
aws cloudtrail start-logging --name wiki-audit-lab
aws cloudtrail get-trail-status --name wiki-audit-lab
aws cloudtrail get-event-selectors --trail-name wiki-audit-lab
```

Inspect IsLogging and delivery errors/timestamps; successful CreateTrail alone does not prove logging. Change selectors only with an approved coverage plan. Multiple copies across trails, organization trails and data selectors affect cost/ownership.

## Event History and log investigation

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=DescribeTrails \
  --start-time 2026-10-12T00:00:00Z --end-time 2026-10-13T00:00:00Z
```

Replace the interval; Event History supports its own lookup constraints/pagination and management-event scope. Decode CloudTrailEvent JSON before analyzing request/user identity. Correlate userIdentity/sessionIssuer, eventTime, eventSource/eventName, sourceIPAddress and requestID; redact sensitive fields.

For S3 archive queries, create an Athena table using the owning CloudTrail schema/location/partition guide rather than an invented generic log schema. Restrict scan scope and protect the result bucket. For CloudWatch Logs integration, configure the actual group ARN and CloudTrail delivery role; a created group does not attach itself to the trail.

## Integrity, encryption and incident operations

SSE-KMS requires both log-delivery encryption and investigator decrypt access with the correct context/policy. The trail/digest chain helps detect changed/deleted files, but enabling it does not run validation or prove retention is immutable. Run validation over the required interval and preserve output/evidence.

Investigate stopped logging, deleted trails, selector changes and bucket/key denial with an independent administrative/audit path. Alert on these changes; don't disable logging to suppress the alarm. Cleanup stops/deletes only the dedicated trail and follows approved log retention; do not delete required evidence or an organization trail.

References: [bucket policy](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/create-s3-bucket-policy-for-cloudtrail.html), [Logs integration](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/send-cloudtrail-events-to-cloudwatch-logs.html), [Athena](https://docs.aws.amazon.com/athena/latest/ug/cloudtrail-logs.html), [event structure](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-event-reference-record-contents.html).

## Cross-wiki comparisons

- [[Linux/security/auditd|auditd]] — audit trails (Linux)

## References

- [Management events](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/logging-management-events-with-cloudtrail.html)
- [Trail setup](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-create-and-update-a-trail.html)
- [Delivery behavior](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/get-and-view-cloudtrail-log-files.html)
- [Integrity validation](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-log-file-validation-intro.html)
- [CLI validation](https://docs.aws.amazon.com/cli/latest/reference/cloudtrail/validate-logs.html)
- [Pricing](https://aws.amazon.com/cloudtrail/pricing/)

## Across the wiki

- [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/15-audit-logging|Audit Logging]]
- [[Security/siem/wazuh/README|Wazuh]]
- [[Kubernetes/eks/observability/logging/control-plane-logs|EKS Control Plane Logs]]
