---
title: Cost Automation
description: Billing models, trade-offs, safe workflows and scoped examples for cost automation.
tags:
  - aws/cost-management
date: 2026-10-12
---

# Cost Automation

Price exercises use hypothetical us-east-1 (US East, N. Virginia) rates for study on 2026-10-12, not current tariffs, unless explicitly identified as a dated published fee.

Cost automation should discover and explain waste before changing resources. Age, low CPU or an anomaly alert alone does not prove a resource is disposable.

## Approval-based workflow

1. Inventory approved accounts and Regions using paginated APIs.
2. Identify candidates and owners, including missing tags.
3. Check dependencies, retention, AMI/snapshot associations and recovery requirements.
4. Produce a read-only recommendation with estimated **avoidable** costs.
5. Require explicit approval and protection-tag checks.
6. Apply bounded, reversible changes with least privilege, audit logs and rollback.
7. Reconcile estimated savings against subsequent billing.

Do not automatically disable production scaling after an anomaly: it can turn a billing issue into an outage. CAD notification formats must be validated against actual documented subscriptions/SNS delivery; do not assume an invented `TotalImpact` event field.

## Safe inventory example

Requires AWS CLI credentials with `ec2:DescribeVolumes`. Select an authorized Region. The CLI paginates by default; this command only lists unattached volumes and does not delete them.

```bash
aws ec2 describe-volumes \
  --region us-east-1 \
  --filters Name=status,Values=available \
  --query 'Volumes[].{Id:VolumeId,GiB:Size,Created:CreateTime,Tags:Tags}' \
  --output json
```

Available volumes can be deliberately retained data. Protect backups independently of their source volume's existence; a snapshot can remain useful after that volume is gone.

## Scheduling

Instance Scheduler on AWS supports scheduled EC2/RDS operations under its documented constraints. It does not stop load balancers. EventBridge Scheduler supports time zones; a `rate(1 day)` means a recurring interval, not necessarily midnight UTC. Specify cron, timezone and daylight-saving behavior when business hours matter.

For 50 instances, always-on usage is 1,200 instance-hours/day. Over a 30-day month that is 36,000 hours. At 10 hours/day across 22 workdays, scheduled usage is 11,000 hours; gross avoided usage is 25,000 hours. At an assumed \$0.192/hour, that is \$4,800 before continuing storage, commitments and automation charges.

## Measurement and safety

Custom CloudWatch metrics are operational telemetry, not automatically Cost Explorer billing records. Report realized versus estimated savings separately. Amazon Q Developer in chat applications is the successor name to AWS Chatbot; validate supported notification/actions rather than assuming every SNS message can run arbitrary remediation.

Start alert-only, use explicit owner opt-in, bound resources per run, handle retries/idempotency and partial failures, and keep a tested rollback. Never use a blanket deletion snippet as a beginner cost lab.

## Candidate patterns and recovery gates

| Candidate       | Read-only evidence                               | Gate before any change                           |
| --------------- | ------------------------------------------------ | ------------------------------------------------ |
| Development EC2 | Owner, schedule, utilization, ASG membership     | Approved stop/restart plan; dependencies checked |
| Available EBS   | Volume state, tags, size and creation time       | Owner confirmation and recoverable data          |
| Old snapshots   | Owner, retention and AMI/backup references       | Protected recovery points and legal holds        |
| Old AMIs        | Image usage, launch templates and snapshot links | Replacement artifact and rollback retained       |
| Log groups      | Owner, ingestion, retention requirements         | Approved retention; preserve audit obligations   |

A snapshot without a source volume is not “orphaned” evidence of uselessness. AMIs typically reference billed snapshots; blindly deleting them after deregistration can destroy rollback and other dependencies.

## Complete read-only inventory program

Requires Python 3, installed Boto3, configured AWS credentials and approved `ec2:DescribeVolumes` access in the listed Regions. This is an executable **report**, not remediation. It paginates and never calls delete/stop APIs:

```python
import json
import boto3

REGIONS = ("us-east-1",)

def inventory(region):
    client = boto3.client("ec2", region_name=region)
    pages = client.get_paginator("describe_volumes").paginate(
        Filters=[{"Name": "status", "Values": ["available"]}]
    )
    for page in pages:
        for volume in page["Volumes"]:
            tags = {t["Key"]: t["Value"] for t in volume.get("Tags", [])}
            yield {
                "region": region,
                "id": volume["VolumeId"],
                "size_gib": volume["Size"],
                "created": volume["CreateTime"].isoformat(),
                "owner": tags.get("Owner", "UNASSIGNED"),
                "protected": tags.get("DoNotDelete", "").lower() == "true",
                "decision": "OWNER_REVIEW_REQUIRED",
            }

if __name__ == "__main__":
    for region in REGIONS:
        for record in inventory(region):
            print(json.dumps(record))
```

A denied API/failed Region ends the program rather than treating failure as an empty inventory. A production implementation should report partial failures, bound runtime, assume only approved roles and protect exported metadata. The report cannot certify snapshot coverage, application dependencies or data disposability.

## From report to approved action

Use a separate action role and explicit owner opt-in. Implement idempotency, a maximum affected-resource count, approval expiry, protected-resource rechecks and rollback. For EC2 APIs supporting it, `DryRun` checks permission; it does not demonstrate that a stop is operationally safe or calculate real savings. Do not remove the guard merely because a dry-run returns `DryRunOperation`.

Store action evidence and compare the next billing periods with an equivalent baseline. A \$600 gross storage reduction minus \$20 of continuing backup/automation expense is \$580 net only if the charges are actually avoidable. “Infinite ROI” and savings inferred from resource count alone are not valid.

- [Boto3 volume paginator](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2/paginator/DescribeVolumes.html)
- [EC2 stop DryRun contract](https://docs.aws.amazon.com/cli/latest/reference/ec2/stop-instances.html)

## References

- [Instance Scheduler on AWS](https://docs.aws.amazon.com/solutions/latest/instance-scheduler-on-aws/solution-overview.html)
- [Scheduler time zones and schedules](https://docs.aws.amazon.com/scheduler/latest/UserGuide/schedule-types.html)
- [Describe-volumes CLI](https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-volumes.html)
- [Budget action approvals](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-action-configure.html)
