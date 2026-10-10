---
title: Alerting
tags: [observability, alerting, alertmanager, prometheus, on-call]
date: 2026-10-10
description: Designing alerts people trust — symptoms over causes, severity and routing, Prometheus alerting rules, Alertmanager grouping and inhibition, burn-rate alerts, and how to reduce noise.
---

# Alerting

An alert is an interruption. It takes a person away from what they were doing, sometimes out of bed, on the claim that something needs a human now. Every alert that turns out not to need one teaches the team to ignore alerts, and that is how real incidents get missed.

Good alerting is therefore mostly about restraint: few alerts, each one actionable.

## What deserves an alert

Ask of every proposed alert:

1. **Does it indicate that users are, or soon will be, affected?**
2. **Is there something a person must do about it now?**
3. **Could the response be automated instead?**

If the answers are no, no, or yes, it is not a page. It may be a ticket, a dashboard panel, or nothing.

| Alert on symptoms                            | Not on causes                 |
| :------------------------------------------- | :---------------------------- |
| Error ratio for checkout is above 2%         | A pod restarted               |
| p99 latency is above the objective           | CPU is at 85%                 |
| The queue's oldest message is 10 minutes old | One of three replicas is down |
| Disk will be full in four hours              | Disk is 80% full              |

Causes belong on dashboards, where they help diagnose a symptom alert. Kubernetes in particular restarts and reschedules things constantly; alerting on that machinery produces noise about problems the system already handled. A small number of cause-based alerts are still justified when they predict an outage with enough lead time: certificate expiry, disk or IP exhaustion, quota limits.

## Severity and routing

| Severity   | Meaning                                       | Goes to                      | Response              |
| :--------- | :-------------------------------------------- | :--------------------------- | :-------------------- |
| **Page**   | Users are affected or will be within the hour | The on-call engineer's phone | Immediately, any hour |
| **Ticket** | Needs attention, but not tonight              | The team's queue             | Next working day      |
| **Info**   | Context for an investigation                  | A dashboard or a channel     | None                  |

Two severities that page and do not page are enough for most teams. Everything that pages must have an owner and a runbook. The human side is in [[DevOps/sre/on-call|on-call]].

## Prometheus alerting rules

```yaml
groups:
  - name: checkout
    rules:
      - alert: CheckoutHighErrorRatio
        expr: |
          sum(rate(http_requests_total{service="checkout", status=~"5.."}[5m]))
            /
          sum(rate(http_requests_total{service="checkout"}[5m]))
            > 0.02
        for: 5m
        labels:
          severity: page
          team: payments
        annotations:
          summary: "Checkout is failing {{ $value | humanizePercentage }} of requests"
          description: "Error ratio has been above 2% for 5 minutes."
          runbook_url: https://runbooks.example.com/checkout/high-error-ratio
          dashboard: https://grafana.example.com/d/checkout
```

- **`expr`** is any [[Observability/prometheus/promql|PromQL]] expression; each returned series is one alert instance.
- **`for`** requires the condition to hold continuously, which filters out blips. Too short pages on noise; too long delays detection. `keep_firing_for` stops an alert from flapping when it briefly recovers.
- **Labels** drive routing. **Annotations** are for the human reading it and should say what is wrong, how bad, and where to look.

Alert on **ratios**, not counts. Ten errors per second is a disaster for a small service and invisible for a large one.

### Alerts that catch silence

A broken exporter produces no data, and `error_rate > 0.02` on no data is not true — so nothing fires. Guard against it explicitly:

```yaml
- alert: CheckoutMetricsAbsent
  expr: absent(up{job="checkout"} == 1)
  for: 10m
  labels: { severity: page }
```

Also run one alert that always fires (a "dead man's switch") into an external service that pages when it _stops_ arriving. That is the only way to learn that the alerting pipeline itself is down.

## Burn-rate alerts

A fixed threshold forces a bad choice: sensitive enough to catch slow leaks, it also pages on brief spikes. Burn-rate alerting solves this by asking how fast the [[DevOps/sre/slos-and-error-budgets|error budget]] is being spent.

With a 99.9% objective over 30 days, the budget is 0.1% of requests. A burn rate of 1 uses exactly the budget in 30 days; a burn rate of 14.4 uses 2% of it in one hour.

| Budget consumed | In      | Burn rate | Long window | Short window | Action |
| :-------------- | :------ | :-------- | :---------- | :----------- | :----- |
| 2%              | 1 hour  | 14.4      | 1h          | 5m           | Page   |
| 5%              | 6 hours | 6         | 6h          | 30m          | Page   |
| 10%             | 3 days  | 1         | 3d          | 6h           | Ticket |

```yaml
- alert: CheckoutErrorBudgetFastBurn
  expr: |
    (
      sum(rate(http_requests_total{service="checkout",status=~"5.."}[1h]))
        / sum(rate(http_requests_total{service="checkout"}[1h])) > (14.4 * 0.001)
    )
    and
    (
      sum(rate(http_requests_total{service="checkout",status=~"5.."}[5m]))
        / sum(rate(http_requests_total{service="checkout"}[5m])) > (14.4 * 0.001)
    )
  labels: { severity: page }
```

The long window proves the problem is significant; the short window proves it is still happening, so the alert resolves quickly after recovery. Tools such as Sloth and Pyrra generate these rules from an SLO definition.

## Alertmanager

Prometheus decides _that_ an alert fires. Alertmanager decides _who hears about it and how often_.

```yaml
route:
  receiver: team-default
  group_by: [alertname, cluster, service]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    - matchers: [severity="page"]
      receiver: pagerduty
    - matchers: [team="payments"]
      receiver: payments-slack

inhibit_rules:
  - source_matchers: [alertname="ClusterDown"]
    target_matchers: [severity=~"page|ticket"]
    equal: [cluster]

receivers:
  - name: pagerduty
    pagerduty_configs:
      - routing_key_file: /etc/alertmanager/pagerduty-key
  - name: payments-slack
    slack_configs:
      - channel: "#payments-alerts"
        send_resolved: true
```

| Mechanism      | What it does                                                                             |
| :------------- | :--------------------------------------------------------------------------------------- |
| **Grouping**   | Bundles related alerts into one notification, so a failed node sends one page, not fifty |
| **Inhibition** | Suppresses downstream alerts while a broader one is firing                               |
| **Silences**   | Mutes matching alerts for a period — for maintenance or a known issue                    |
| **Routing**    | Sends alerts to receivers by label, in a tree evaluated top-down                         |

Run Alertmanager as a cluster of three; instances gossip so that each notification is sent once. Always attach a comment and an expiry to a silence — a forgotten silence is an outage waiting to go unnoticed.

## Reducing noise

Review alerts regularly with data, not memory:

- Count pages per week and per alert. The top three usually account for most of the pain.
- For each page ask: was action needed? If not, fix the alert — raise the threshold, lengthen `for`, demote it to a ticket, or delete it.
- An alert that fires and resolves by itself repeatedly should be redesigned or removed.
- An alert nobody has acted on in three months is a candidate for deletion.
- Every incident that was detected by a customer rather than an alert means an alert is missing.

A healthy target is a couple of pages per on-call shift, nearly all of them actionable.

## Writing the notification

At three in the morning the reader has no context. Give it to them:

- **What** is broken, in plain words, with the current value.
- **Impact**: who is affected.
- **Where**: cluster, namespace, service.
- **Links**: the runbook, the dashboard, recent deployments.

A runbook does not need to be long. It needs the first three things to check and the known mitigations — see [[Security/incident-response/playbooks/README|playbooks]] for structure.

## Related

- [[Observability/prometheus/README|Prometheus architecture]]
- [[Observability/grafana|Grafana]] — its alerting can evaluate rules across several data sources
- [[DevOps/sre/incident-management|Incident management]]
- [[AWS/monitoring/cloudwatch-alarms/README|CloudWatch alarms]]
- [[Security/siem/alerting/README|Security alerting]]
