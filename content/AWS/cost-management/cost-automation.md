---
title: Cost Automation
description: AWS cost automation — Lambda functions for automated cleanup, CloudWatch Events schedules, Instance Scheduler, automated remediation
tags:
  - aws
  - cost-management
---

# Cost Automation

AWS cost management works best when it's automated. Manual processes fail, get ignored, or can't respond fast enough. Lambda-based automation closes the loop between detecting a cost problem and fixing it.

## Automated Cleanup Patterns

### Stop Idle EC2 Instances

The most common cost waste: development and test instances left running 24/7 when they only need to be available during business hours.

**Implementation:** CloudWatch Events (or EventBridge) → Lambda that:
1. Finds EC2 instances with tag `Schedule=stop-after-hours` or `Environment=dev`
2. Checks if any cloud-init user data is running critical tasks
3. Stops instances that have been idle for 4+ hours
4. Sends Slack notification with instance details

```python
import boto3
import os

def handler(event, context):
    ec2 = boto3.client('ec2')
    
    # Find instances with 'auto-stop' tag
    instances = ec2.describe_instances(
        Filters=[
            {'Name': 'tag:AutoStop', 'Values': ['true']},
            {'Name': 'instance-state-name', 'Values': ['running']}
        ]
    )
    
    for reservation in instances['Reservations']:
        for instance in reservation['Instances']:
            instance_id = instance['InstanceId']
            
            # Check if instance has been idle (no CPU > 5% for 4 hours)
            # Using CloudWatch metrics check
            
            ec2.stop_instances(InstanceIds=[instance_id])
            print(f"Stopped {instance_id}")
```

**Scheduling:** Run the Lambda every hour during off-peak hours (7PM-7AM weekdays, all day weekends).

### Delete Unattached EBS Volumes

EBS volumes remain after terminated instances and accumulate storage costs.

**Implementation:** Scheduled Lambda that:
1. Finds volumes in `available` state
2. Checks age — volumes attached long ago and unattached are likely orphaned
3. Checks for `DoNotDelete` tag (protection)
4. Deletes volumes older than 30 days unattached
5. Reports deleted volumes to Slack

### Expire Old Snapshots

Snapshots accumulate from failed migrations, failed instance lifecycle manager runs, or manual backups.

**Implementation:** Lambda that:
1. Finds snapshots older than retention period
2. Checks `DoNotDelete` tag
3. Deletes snapshots that have no associated volume (orphaned)
4. Reports deleted count and storage reclaimed

### Clean Up Old AMIs

AMIs are stored in S3 and cost money. Old AMIs from instance migrations or failed deployments pile up.

**Lambda:** Finds AMIs with `CreatedBy` tag or creation date older than retention, deregisters and deletes associated snapshots.

## AWS Instance Scheduler

Instead of building custom Lambda functions, the AWS Solutions team provides **Instance Scheduler** — a pre-built CloudFormation template that automates stopping/starting EC2 and RDS instances on schedules.

**Features:**
- Tag-based: add `Schedule=BusinessHours` tag to instances
- Supports both EC2 and RDS
- Multiple schedules (weekday, weekend, custom)
- CloudWatch Events drives the schedule
- Reports cost savings in CloudWatch metrics

**Setup:**
```bash
# Deploy via CloudFormation (one-click in AWS Console)
# Tag instances: Schedule=business-hours
# Instances stop at 7PM and restart at 7AM weekdays
```

**Savings example:**
```
Before: t3.medium running 24/7 = $0.0416/hour × 24 × 30 = $29.95/month
After: Running 10 hours/weekday × 22 weekdays = 220 hours/month
        = $0.0416 × 220 = $9.15/month
Savings: ~70% per dev instance
```

## CloudWatch Events Patterns

All Lambda-based cost automation follows the same pattern:

```
CloudWatch Rules (EventBridge) → Lambda (boto3) → AWS API call
                              ↓
                        Slack notification
```

**Common schedule patterns:**
- **Every 15 minutes:** High-frequency cleanup (build agents, short-lived resources)
- **Every hour:** General cleanup (idle instances, unattached volumes)
- **Daily (off-peak):** Deep cleanup (snapshots, old AMIs, old CloudWatch log groups)
- **Weekly:** Strategic cleanup (old EBS snapshots, unused security groups)

## Automated Remediation

Beyond cleanup, Lambda can respond to Cost Anomaly Detection alerts:

**Anomaly alert → SNS → Lambda:**
```python
def handler(event, context):
    anomaly = json.loads(event['Records'][0]['Sns']['Message'])
    
    if anomaly['TotalImpact'] > 500:
        # Stop non-production EC2 instances to cap spending
        stop_non_production_instances()
        
        # Disable auto-scaling on production ASGs
        disable_production_asg_scaling()
        
        # Send PagerDuty alert
        send_alert(anomaly)
    else:
        # Just notify
        send_notification(anomaly)
```

**CAUTION:** Automated remediation can break production systems if not carefully designed. Always:
- Use tag-based filters (never blanket-stop all instances)
- Add circuit breakers (stop after 10 instances, not unlimited)
- Include rollback (Slack notification with "this happened, approve rollback")
- Test in dev first

## AWS Cost Optimization Integrations

### CloudWatch Metrics

Cost automation can emit custom CloudWatch metrics:
- `InstancesStopped` — count of instances stopped this run
- `VolumesDeleted` — count of volumes deleted
- `EstimatedMonthlySavings` — dollar value of actions taken

These metrics feed into Cost Explorer for reporting.

### AWS Chatbot

Integrate with Slack via AWS Chatbot instead of custom Lambda + SNS:
```bash
# AWS Chatbot can trigger Lambda from SNS alerts
# Less code than custom Lambda + Slack webhook
```

## Anti-Patterns

**Cleaning up production resources automatically.** Always use tag filters (`Environment=dev`, `Schedule=auto-stop`). Never clean up resources without explicit tags that indicate they're safe to touch.

**No circuit breaker.** A Lambda that runs every 5 minutes and deletes 100 volumes per run could delete 12,000 volumes in an hour if there's a bug. Always add limits.

**No logging.** Every automation run should log what it did and emit CloudWatch metrics. You need to be able to reconstruct what happened during a cost event.

**No Slack notification.** If no one knows the automation ran, problems go unnoticed. Always notify when resources are modified.

## References

- **Homepage:** https://aws.amazon.com/cost-management/
- **Documentation:** https://docs.aws.amazon.com/cost-management/latest/userguide/
- **Pricing:** https://aws.amazon.com/cost-management/

## Pricing Examples

**Scenario 1:** A Lambda function scheduled to run daily at 9am, scanning for unattached EBS volumes older than 7 days and deleting them. In a month with 4 cleanup runs finding and deleting 50 volumes (avg 200GB each): saved $50/month × 12 = $600/year in avoided EBS charges. Lambda cost: $0.20/month. ROI: infinite.

**Scenario 2:** Instance Scheduler solution deployed across 50 EC2 instances tagged with `Schedule=BusinessHours`. 8am-6pm weekdays only. Before:50 × 24/7 =730 instance-hours/day. After: 50 × 10 hours × 5 days = 2,500 instance-hours/week. Monthly savings: (730 × 30 - 2,500 × 4) hours = 21,900 - 10,000 = 11,900 hours/month saved. At $0.192/hr (m5.large): $2,285/month saved.

## Nuggets& Gotchas

- **Tag-based automation can fail silently if tags are missing:** An automation that deletes resources tagged `Environment=dev` will silently skip resources without that tag. If a production resource is untagged, it won't be touched (safe) but it also won't be cleaned up (cost). Always log untagged resources.
- **Lambda automation functions need their own IAM role with least privilege:** The automation Lambda should have permissions only for the specific resources it manages. A Lambda with `ec2:DescribeInstances` and `ec2:TerminateInstances` should only target instances with specific tags, not all instances.
- **CloudWatch Events rate expressions use UTC:** A rate expression of `rate(1 day)` fires at midnight UTC. If your business day is in a different timezone, adjust the schedule accordingly. Use cron expressions for timezone-aware scheduling.
- **Instance Scheduler creates CloudWatch Events in each region it's deployed:** If you deploy Instance Scheduler in 5 regions, you have 5 EventBridge rules. Each has a $0.10/million invocations cost. At large scale, this adds up but is usually negligible compared to the compute savings.
- **Automated cleanup Lambda functions can be triggered by unexpected events:** A Lambda that responds to a CloudWatch Event (like an EC2 state change) will fire on every matching event. If the event pattern is too broad, you might process thousands of events per minute. Always add throttling.