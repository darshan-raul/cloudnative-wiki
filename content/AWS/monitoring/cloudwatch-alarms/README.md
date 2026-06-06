---
title: CloudWatch Alarms
description: CloudWatch Alarms — metric alerting with threshold-based triggers, composite alarms, anomaly detection, and alarm actions (SNS, Auto Scaling, EC2 actions).
tags:
  - aws
  - monitoring
  - alarms
  - cloudwatch
---

# CloudWatch Alarms

CloudWatch Alarms watch a metric and trigger actions when the metric crosses a threshold for a specified number of evaluation periods.

## Core Concepts

### Alarm States

```
OK         → Metric is within threshold
INSUFFICIENT_DATA → Metric not available or not enough data
ALARM     → Metric breached threshold for N consecutive periods
```

### Alarm Evaluation

```
Evaluation period: 1 minute (shortest possible)
Data points to alarm: 3 (consecutive breaches)
Period: 1 minute

Alarm triggers when:
  Minute 1: CPU > 80%   (1 of 3)
  Minute 2: CPU > 80%   (2 of 3)
  Minute 3: CPU > 80%   (3 of 3) → ALARM
```

### Creating an Alarm

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name HighCPU \
  --alarm-description "Alert when CPU exceeds 80% for 3 consecutive minutes" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 60 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 3 \
  --alarm-actions arn:aws:sns:us-east-1:123456789012:my-alert-topic \
  --dimensions Name=InstanceId,Value=i-xxxxx
```

### Alarm Actions

| Action | Use |
|--------|-----|
| SNS Topic | Send notification (email, SMS, PagerDuty) |
| Auto Scaling | Scale ASG in/out |
| EC2 Action | Stop, terminate, or reboot EC2 |
| Systems Manager OpsItem | Create OpsItem for runbook automation |

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name HighCPU-AutoScale \
  --alarm-description "Scale out ASG when CPU is high" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 60 \
  --threshold 70 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 3 \
  --alarm-actions \
    arn:aws:autoscaling:us-east-1:123456789012:scalingPolicy:abc123:autoScalingGroupName:my-asg:policyName:scale-out
```

## Composite Alarms

Composite alarms evaluate multiple alarms together using boolean logic:

```bash
aws cloudwatch put-composite-alarm \
  --alarm-name ServiceDown \
  --alarm-rule "(ALARM HighCPU OR ALARM HighMemory) AND ALARM HighNetwork" \
  --alarm-actions arn:aws:sns:us-east-1:123456789012:my-alert-topic
```

This reduces alarm noise — a page only fires when multiple conditions are met, not when each individual alarm fires separately.

## Anomaly Detection

CloudWatch Anomaly Detection uses machine learning to establish a "normal" baseline and alert on deviations:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name HighLatency-Anomaly \
  --alarm-description "Alert when p99 latency is unusually high" \
  --metric-name TargetResponseTime \
  --namespace AWS/ApplicationELB \
  --statistic p99 \
  --period 300 \
  --threshold 2.5 \
  --comparison-operator GreaterThanUpperThreshold \
  --evaluation-periods 2 \
  --treat-missing-data notBreaching \
  --metrics '[{"Id":"m1","MetricStat":{"Metric":{"Namespace":"AWS/ApplicationELB","MetricName":"TargetResponseTime","Period":300,"Stat":"p99"},"ReturnData":false}}]' \
  --enable-metric-math
```

## Alarm Configuration Options

### Missing Data Treatment

| Option | Behavior |
|--------|----------|
| `notBreaching` (default) | Missing data treated as "good" — no alarm |
| `breaching` | Missing data treated as "breached" — alarm |
| `ignore` | Missing data doesn't affect alarm state |
| `missing` | Alarm stays in current state |

### Evaluation Periods and Period Length

| Scenario | Period | Evaluation Periods |
|----------|--------|-------------------|
| Real-time (1-min detection) | 60 | 3 |
| Standard (5-min detection) | 300 | 2 |
| Cost-optimized (15-min detection) | 900 | 2 |

## Alarm Best Practices

```
□ Use composite alarms to reduce noise — combine related conditions
□ Set alarm actions to send to SNS (email/SMS) and OpsItem (runbook)
□ Use GetMetricData for alarms on multiple metrics (cheaper than multiple alarms)
□ Anomaly detection for metrics with seasonal variation (e.g., traffic peaks)
□ Set treat-missing-data appropriately — don't page for missing data from a dev instance
□ Use 1-minute alarms for critical services, 5-minute for non-critical
□ Always test alarms by manually triggering them (aws cloudwatch set-alarm-state)
```

## AWS Service Alarm Patterns

### EC2 Instance Alarms

```bash
# CPU
aws cloudwatch put-metric-alarm --alarm-name HighCPU --metric-name CPUUtilization \
  --namespace AWS/EC2 --statistic Average --period 60 --threshold 80 \
  --evaluation-periods 3 --comparison-operator GreaterThanThreshold

# Status check
aws cloudwatch put-metric-alarm --alarm-name InstanceStatus \
  --namespace AWS/EC2 --metric-name StatusCheckFailed \
  --statistic Maximum --period 60 --threshold 1 \
  --evaluation-periods 1 --comparison-operator GreaterThanThreshold
```

### ALB Alarm

```bash
# Unhealthy hosts
aws cloudwatch put-metric-alarm --alarm-name UnhealthyHosts \
  --namespace AWS/ApplicationELB --metric-name UnHealthyHostCount \
  --statistic Maximum --period 60 --threshold 1 \
  --evaluation-periods 2 --comparison-operator GreaterThanThreshold
```

## Limits

| Resource | Limit |
|----------|-------|
| Alarms per region | 10,000 (can request increase) |
| Alarm actions per alarm | 5 |
| Composite alarm depth | 5 nested alarms |
| Metrics per alarm | 1 (use metric math for multiple) |

## References

- **Homepage:** https://aws.amazon.com/cloudwatch/
- **Documentation:** https://docs.aws.amazon.com/cloudwatch/
- **Pricing:** https://aws.amazon.com/cloudwatch/pricing/

## Pricing Examples

**Scenario 1:** A production system with 10 alarms (CPU, memory, disk, network per instance, 50 instances). 500 alarms total. At $0.10/alarm/month = $50/month. Plus SNS notifications (negligible cost). Total: ~$50/month. Without alarms, a CPU spike goes unnoticed for hours, causing customer impact.

**Scenario 2:** Using anomaly detection on ALB request count. The service has daily and weekly seasonality — peak at 9am, low at 2am. A fixed threshold alarm would false-positive constantly. Anomaly detection learns the pattern and only fires when traffic is outside the learned range. Anomaly detection: $0.30/alarm/month × 5 alarms = $1.50/month for more accurate alerting.

## Nuggets & Gotchas

- **The minimum alarm evaluation period is 10 seconds — not 1 second:** Even if you set `--period 1`, CloudWatch rounds it to 10 seconds. For sub-10-second alerting, you need a different approach (CloudWatch Contributor Insights for near-real-time, or a third-party monitoring tool).
- **Alarms go to INSUFFICIENT_DATA when the instance is stopped/terminated:** A CPU alarm on an instance that gets stopped goes to INSUFFICIENT_DATA. If you have `treat-missing-data: breaching`, the alarm fires when instances are stopped (unwanted). Use `treat-missing-data: notBreaching` for instance-level alarms.
- **Composite alarms with OR conditions can still page too much:** If you have `ALARM HighCPU OR ALARM HighMemory`, and HighCPU fires every hour during peak traffic, you'll get a page every hour. Consider using a composite with AND conditions or a time-based suppression (CloudWatch Events rule that mutes the alarm for a period after it fires).
- **Alarm actions are not retried if SNS fails:** If the SNS topic is misconfigured or rate-limited, the alarm action silently fails. There's no built-in retry. Use dead-letter queues or Lambda-based fan-out for critical notifications.
- **You cannot create an alarm on a metric that doesn't exist yet:** CloudWatch only creates metrics when data is first put. If you create an alarm on a metric that your application hasn't emitted yet, the alarm goes to INSUFFICIENT_DATA and stays there until the metric starts emitting.