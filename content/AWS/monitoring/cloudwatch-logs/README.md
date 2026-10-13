---
title: CloudWatch Logs
description: CloudWatch Logs — centralized log management for applications and AWS services. Log groups, streams, the CloudWatch Agent, retention policies, and subscription filters.
tags:
  - aws/monitoring
date: 2026-10-12
---

# CloudWatch Logs

Prerequisites: [[AWS/security/iam/README|scoped IAM access]] and [[AWS/monitoring/README|telemetry, SLI and retention design]].

CloudWatch Logs groups streams of timestamped events with retention, access controls and optional encryption. It is not a substitute for deliberate audit coverage or a free unlimited archive.

## Ingestion and lifecycle

Choose a log class for the required capabilities: Standard, Infrequent Access and Delivery have different feature availability and retention constraints. Class selection is not a universal drop-in cost optimization. Use structured JSON with severity, service and request/trace IDs; redact secrets and personal data before ingestion.

Event time is distinct from ingestion time. Set explicit retention instead of leaving indefinite storage by accident. KMS encryption requires both the appropriate key policy and caller/service authorization.

## Sandbox lab

A role needs logs CreateLogGroup/CreateLogStream/PutLogEvents/PutRetentionPolicy and scoped read/delete permissions. Substitute a unique name if this group already exists; never delete someone else's group.

```bash
aws logs create-log-group --log-group-name /wiki-lab/demo
aws logs put-retention-policy --log-group-name /wiki-lab/demo --retention-in-days 1
aws logs create-log-stream --log-group-name /wiki-lab/demo --log-stream-name fixture
```

Publish through the console or a file `events.json` containing a current epoch-millisecond timestamp:

```json
[
  {
    "timestamp": 1791763200000,
    "message": "{\"service\":\"demo\",\"status\":500,\"durationMs\":120}"
  }
]
```

The timestamp is illustrative: replace it with current time or ingestion will reject stale events. Then run `aws logs put-log-events --log-group-name /wiki-lab/demo --log-stream-name fixture --log-events file://events.json`. Verify the record with the console or `filter-log-events`. Test a malformed timestamp in the isolated fixture and inspect the returned error/rejected-event metadata rather than silently discarding failures.

Cleanup: after inspection, `aws logs delete-log-group --log-group-name /wiki-lab/demo` deletes its records permanently. Only run it against your disposable lab group.

## Subscriptions and live investigation

Subscription filters deliver compressed/base64-encoded batches to supported destinations such as Lambda, Kinesis Data Streams or Firehose—not an arbitrary log group. Cross-account destinations need destination/resource and IAM policies. Consumers must handle duplicates, retries and failed delivery. Exclude subscription processor logs from their own source scope to prevent recursion.

Documentation currently differs on the subscription-filter count. Check the applicable account/Region service quota and current API contract before designing fan-out; do not treat an old count or adjustability claim as universal. Live Tail is available through the console, API and AWS CLI, with its own access/cost model.

## Costs

Separate ingestion, retained compressed volume, queries scanned, subscription delivery and Live Tail. Terminal monthly storage and cumulative multi-year storage cost are different quantities: growing volume must be integrated over time, not labeled as one monthly bill.

## Groups, streams, agents and application integrations

```text
host/application → file/stdout → supported agent/driver → log group
                                                          ├─ stream per source
                                                          ├─ retention/key policy
                                                          ├─ Insights query
                                                          └─ subscription destination
```

A group owns retention/encryption/class controls; streams identify event sources. An ECS awslogs driver, Lambda logging and an EC2 CloudWatch Agent have different execution-role/host prerequisites. Do not install a CloudWatch Agent as a substitute for SSM Agent.

Select the official package/install procedure for the actual OS. With the agent installed and an instance role granted scoped logging access, a small configuration can be saved as agent.json:

```json
{
  "agent": { "region": "us-east-1" },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/wiki-demo.log",
            "log_group_name": "/wiki-lab/agent",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 1
          }
        ]
      }
    }
  }
}
```

Replace Region/path and ensure the agent can read the file. Using the supported installed ctl path:

```bash
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -c file:/path/to/agent.json -s
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status
```

Write a nonsensitive fixture through your application/editor and verify its stream. Inspect the agent's own status/logs for permission, file-ownership, schema or endpoint failures. Paths/package management differ by platform; these commands are for that installed Linux layout.

## Subscription pipeline walkthrough

```text
source group → subscription filter → encoded/compressed batch
                                    ├─ Lambda processor
                                    ├─ Kinesis stream
                                    └─ Firehose → authorized destination
```

With an existing authorized Lambda destination and function resource policy permitting the Logs service/source ARN:

```bash
aws logs put-subscription-filter --log-group-name /wiki-lab/demo \
  --filter-name wiki-errors --filter-pattern '{ $.status = 500 }' \
  --destination-arn LAMBDA_DESTINATION_ARN
```

The consumer decodes base64 then decompresses gzip before parsing the data envelope; it must handle control messages, duplicate delivery and failures. The function's own logs must not loop back into its source subscription. This command does not create the function or permission automatically.

For cross-account streaming, use the supported destination/stream/role and destination policy workflow. A log-group ARN alone is not a cross-account subscription delivery endpoint. Central storage, OAM query visibility and organization centralization are separate capabilities.

## Live Tail, diagnosis and storage calculation

Use current console/StartLiveTail/CLI capability with authorized group identifiers; handle its streaming session and stop it when done. Live Tail is for observation, not durable evidence retention.

For storage, 10 GB/day retained for thirty days gives roughly 300 GB before compression/expiry details. Multiply retained billed GB-month by the storage rate; cumulative multi-year cost integrates the growing/expiring volume. Add ingestion/scanned queries/subscriptions separately.

Check event timestamps/rejected indexes, retention expiry, delivery delay, agent credential resolution and key permissions. After the lab remove subscription filters before deleting destinations/groups, stop the agent's lab collection and restore prior config; deleting a group while an agent republishes can recreate logs and charges.

References: [agent installation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Install-CloudWatch-Agent.html), [subscription processing](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/SubscriptionFilters.html), [CLI filter](https://docs.aws.amazon.com/cli/latest/reference/logs/put-subscription-filter.html), [Live Tail](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CloudWatchLogs_LiveTail.html).

## Cross-wiki comparisons

- [[Azure/monitoring/log-analytics/README|Azure Monitor & Log Analytics Architecture, KQL, and Observability]] — cloud logging and monitoring (Azure)
- [[Observability/logging|Logging]] — cloud logging and monitoring (Observability)
- [[Linux/observability/README|Linux Observability]] — cloud logging and monitoring (Linux)

## References

- [Log classes](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CloudWatch_Logs_Log_Classes.html)
- [Subscription delivery](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/Subscriptions.html)
- [Subscription API](https://docs.aws.amazon.com/cli/latest/reference/logs/put-subscription-filter.html)
- [Live Tail API](https://docs.aws.amazon.com/AmazonCloudWatchLogs/latest/APIReference/API_StartLiveTail.html)
- [Pricing](https://aws.amazon.com/cloudwatch/pricing/)

## Across the wiki

- [[GCP/monitoring/cloud-logging/README|Cloud Logging Architecture, Log Router, and Log Analytics]]
