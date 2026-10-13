---
title: CloudWatch Events
description: CloudWatch Events (EventBridge) — event-driven automation using rules that react to AWS API events, schedules, or custom application events. Rules, targets, and event patterns.
tags:
  - aws/monitoring
date: 2026-10-12
---

# CloudWatch Events

Prerequisites: [[AWS/security/iam/README|scoped IAM access]] and [[AWS/monitoring/README|telemetry, SLI and retention design]].

CloudWatch Events is the historical name/API lineage for event-bus rule capabilities now taught through Amazon EventBridge. It is not a second independent platform to select for a new design.

## Canonical lesson

Continue with [[AWS/application-integration/eventbridge/README|Amazon EventBridge]] for bus selection, matching rules, target authorization, retries, dead-letter queues and archive/replay. The `aws events` CLI namespace remains current; old API naming does not imply a retired command.

Existing rules can continue to operate, but new time-based scheduling should evaluate EventBridge Scheduler rather than treating legacy scheduled rules as the complete scheduling product. Scheduler and Pipes have separate APIs, permissions and pricing.

## Migration exercise

Inventory an existing rule with describe-rule/list-targets-by-rule, record its bus and target policy, and test its event pattern with test-event-pattern. Compare the actual target's delivery evidence and failures before changing configuration. Preserve idempotency when replaying or changing routes; do not delete a production rule merely to rename the service.

Use the canonical EventBridge lab for a safe sandbox exercise and cleanup. Event delivery, telemetry retention and billing scope must be assessed separately; an AWS service-originated event is not automatically billed like a custom application event.

## Historical model and modern mapping

| Original CloudWatch Events concept | Current lesson                     | Boundary to retain                                 |
| ---------------------------------- | ---------------------------------- | -------------------------------------------------- |
| Event-pattern rule                 | EventBridge bus rule               | Pattern matching and target delivery               |
| Scheduled rule                     | Legacy rule or Scheduler migration | Scheduler role/timezone/window differ              |
| AWS state event                    | Owning AWS integration             | Delivery/detail contract is service-specific       |
| Cross-account bus                  | EventBridge forwarding             | Sender role plus receiving bus policy              |
| Schema discovery                   | EventBridge schemas                | Separate API and generated-code ownership          |
| Rule DLQ                           | EventBridge target DLQ             | Exhausted delivery, not application processing DLQ |

```text
AWS/custom event → bus → each matching rule → authorized targets
                           └─ delivery retry exhaustion → target DLQ
```

## Event and schedule walkthroughs

An EC2 state-change event can be matched by source aws.ec2, detail-type EC2 Instance State-change Notification and detail.state. Test the actual envelope before deployment. An S3 object event requires the owning bucket integration/notification configuration; creating a rule alone does not turn on every S3 event.

Legacy scheduled rules use UTC rate/cron expressions. For example `rate(5 minutes)` is a repeated interval and `cron(0 9 * * ? *)` expresses 09:00 UTC daily. The six cron fields are minute, hour, day-of-month, month, day-of-week and year; `?` leaves day-of-week unspecified here. Compare `cron(0 9 ? * MON-FRI *)` for weekdays only, and verify the next expected UTC firing times before enabling a rule. EventBridge Scheduler supports its own timezone/flexible-window capabilities and target execution role; do not paste the legacy rule request into Scheduler unchanged. See the [scheduled-rule expression contract](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-scheduled-rule-pattern.html).

For database maintenance, schedule a safe service-specific runbook with bounded retries, ownership and approval; an event cannot make an arbitrary database change safe. Test restoration/failure reporting in a sandbox.

## Read-only inventory and migration plan

```bash
aws events list-rules --event-bus-name default
aws events describe-rule --name EXISTING_RULE --event-bus-name default
aws events list-targets-by-rule --rule EXISTING_RULE --event-bus-name default
```

Record patterns/schedules, input transformations, target roles/policies, retry/DLQ configuration and consumers. Recreate a parallel sandbox path through the canonical EventBridge lesson, verify allowed/denied events and duplicate-safe processing, then choose a controlled migration window.

Use these mappings for current EventBridge configuration and historical inventory; schema APIs have their own documented namespace. After migration remove only approved legacy rules/targets; preserve shared destinations and replay evidence.

## Cross-wiki comparisons

- [[Linux/boot-init/cron-anacron|Cron and Anacron]] — scheduled work (Linux)
- [[Linux/boot-init/systemd-timers|systemd Timers]] — scheduled work (Linux)

## References

- [EventBridge and CloudWatch Events](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-cwe-now-eb.html)
- [EventBridge documentation](https://docs.aws.amazon.com/eventbridge/latest/userguide/what-is-amazon-eventbridge.html)
- [EventBridge pricing](https://aws.amazon.com/eventbridge/pricing/)

## Across the wiki

- [[Kubernetes/concepts/L03-workloads/07-cronjob|CronJobs — Time-Scheduled Workloads]]
