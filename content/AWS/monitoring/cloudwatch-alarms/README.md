---
title: CloudWatch Alarms
description: CloudWatch Alarms — metric alerting with threshold-based triggers, composite alarms, anomaly detection, and alarm actions (SNS, Auto Scaling, EC2 actions).
tags:
  - aws/monitoring
date: 2026-10-12
---

# CloudWatch Alarms

Prerequisites: [[AWS/security/iam/README|scoped IAM access]] and [[AWS/monitoring/README|telemetry, SLI and retention design]].

An alarm evaluates a metric or expression and invokes configured actions on supported state transitions. A useful alarm has an owner, a runbook and a tested notification path.

## Evaluation semantics

Alarm states are OK, ALARM and INSUFFICIENT_DATA. An M-of-N alarm requires M breaching datapoints among N evaluation periods; choose the period and evaluation range based on the signal's publishing behavior. Missing-data treatment defaults to missing, not notBreaching. ignore preserves current state; breaching and notBreaching deliberately interpret absent data. A sparse error counter and a heartbeat need different policies.

An alarm can be created before a metric exists. It may remain INSUFFICIENT_DATA until evaluation data arrives. High-resolution periods must satisfy the API's supported values; do not assume AWS silently rounds an invalid period.

## Complete metric-evaluation lab

First complete [[AWS/monitoring/cloudwatch-metrics/README|the metric fixture]]. A sandbox role needs PutMetricAlarm/DescribeAlarms/DeleteAlarms and metric read/write. This alarm deliberately has no notification actions, preventing accidental pages.

```bash
aws cloudwatch put-metric-alarm --alarm-name wiki-lab-latency \
  --namespace WikiLab --metric-name Latency \
  --dimensions Name=Service,Value=demo --statistic Average --unit Milliseconds \
  --period 60 --evaluation-periods 1 --datapoints-to-alarm 1 \
  --threshold 100 --comparison-operator GreaterThanThreshold \
  --treat-missing-data missing
aws cloudwatch describe-alarms --alarm-names wiki-lab-latency
```

Publish 120 ms in a fresh minute, wait for evaluation and inspect StateReason. Then publish 80 ms in a later minute and verify recovery. Stop publishing to inspect missing-data behavior. Recent older datapoints in the evaluation range can delay the transition; do not infer semantics from one immediate read.

## Notifications and composite alarms

For an end-to-end notification test, create a sandbox [[AWS/application-integration/sns/README|SNS topic]], confirm its subscription and authorize CloudWatch publishing in its topic/KMS policies. Attach its ARN with alarm-actions/ok-actions. Verify an actual evaluation transition reaches the endpoint and that the runbook identifies impact and rollback. Forced SetAlarmState tests are temporary and not proof of metric evaluation.

Composite alarms reduce noise by combining alarm states, not arbitrary metrics; check current composition/dependency quotas and action restrictions. SNS delivery has protocol-specific retry behavior rather than a universal silent-loss rule.

## Cleanup and costs

Delete the lab alarm with `aws cloudwatch delete-alarms --alarm-names wiki-lab-latency`, remove any lab-only topic/subscription and stop metric publication. Alarm costs vary with type/resolution and evaluated metrics; use current regional pricing, not a universal per-alarm assumption.

## State/evaluation and service pattern tables

| Signal            | Statistic/dimension decision                                | Failure to avoid                                   |
| ----------------- | ----------------------------------------------------------- | -------------------------------------------------- |
| EC2 CPU           | Average with InstanceId; measure sustained pressure         | Calling high CPU a universal application outage    |
| EC2 status checks | Supported status-check metric/action                        | Treating guest/application health as identical     |
| ALB targets       | UnHealthyHostCount with required LB/target-group dimensions | Wrong AWS/ALB namespace or incomplete identity     |
| ALB errors        | Error percentage using a matching request denominator       | Alarm only on raw count during varying traffic     |
| Queue age         | Source-specific age/backlog plus worker errors              | Assuming queue depth alone measures customer delay |

```text
metric periods → evaluation range → M of N + missing-data policy
                                       ↓
                           OK / ALARM / INSUFFICIENT_DATA
                                       ↓
                      authorized action → responder/runbook
```

CloudWatch can fetch more datapoints than N to evaluate missing data according to its contract. Sparse counters and heartbeat metrics need different treatment. Alarm actions have type/state-specific behavior; not every action executes for every state transition.

## ALB error-ratio expression

This complete Metrics array references a real sandbox ALB (replace app/... identifier). Use it with the documented PutMetricAlarm Metrics form rather than mixing metric-name and expression forms.

```json
[
  {
    "Id": "errors",
    "MetricStat": {
      "Metric": {
        "Namespace": "AWS/ApplicationELB",
        "MetricName": "HTTPCode_Target_5XX_Count",
        "Dimensions": [
          { "Name": "LoadBalancer", "Value": "app/REPLACE/REPLACE" }
        ]
      },
      "Period": 60,
      "Stat": "Sum"
    },
    "ReturnData": false
  },
  {
    "Id": "requests",
    "MetricStat": {
      "Metric": {
        "Namespace": "AWS/ApplicationELB",
        "MetricName": "RequestCount",
        "Dimensions": [
          { "Name": "LoadBalancer", "Value": "app/REPLACE/REPLACE" }
        ]
      },
      "Period": 60,
      "Stat": "Sum"
    },
    "ReturnData": false
  },
  {
    "Id": "rate",
    "Expression": "IF(requests>0,100*errors/requests,0)",
    "Label": "Target error percent",
    "ReturnData": true
  }
]
```

Decide what no traffic means before interpreting zero. Target 5xx and load-balancer-generated 5xx are different metrics. Validate expression data in a graph, then configure comparison/threshold, N/M, missing policy and an approved SNS action.

## Composite and anomaly alarms

A composite rule such as ALARM("service-errors") AND NOT ALARM("planned-maintenance") combines alarm states. Suppressing a page does not suppress metrics or fix an outage; track maintenance ownership and expiry.

Anomaly detection fits a model to supported metric behavior. A band-based alarm needs the supported expression/ThresholdMetricId form and enough history; it is not a universal static “two standard deviations” replacement. Check metric/model exclusions and deployment changes; known-bad training data can mislead detection.

## Action testing and operations

Confirm SNS subscriptions and topic/KMS permissions, then test a genuine sandbox evaluation transition. Record state reason, datapoint timestamps and notification receipt. SetAlarmState is a temporary action-path test, not proof of metric math.

Alarm on insufficient data when absence itself is a customer risk; avoid an alert storm for expected sparse metrics. Investigate publishing interval, resolution, delayed ingestion, wrong dimensions and evaluation windows before disabling an alarm. Remove disposable composites before their child alarms; delete lab notification paths and stop custom publication.

References: [metric-math alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Create-alarm-on-metric-math-expression.html), [composite alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Create_Composite_Alarm.html), [anomaly alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Create_Anomaly_Detection_Alarm.html), [ALB metrics](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-cloudwatch-metrics.html).

## References

- [Missing-data evaluation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/alarms-and-missing-data.html)
- [PutMetricAlarm](https://docs.aws.amazon.com/AmazonCloudWatch/latest/APIReference/API_PutMetricAlarm.html)
- [SNS retries](https://docs.aws.amazon.com/sns/latest/dg/sns-message-delivery-retries.html)
- [Pricing](https://aws.amazon.com/cloudwatch/pricing/)
