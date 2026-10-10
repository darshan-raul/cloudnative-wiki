---
title: Grafana
tags: [observability, grafana, dashboards, visualization]
date: 2026-10-10
description: Using Grafana well — data sources, dashboard design that answers questions, variables, dashboards as code, correlating metrics with logs and traces, alerting and access control.
---

# Grafana

Grafana is a visualisation and query front end. It stores no telemetry of its own; it queries **data sources** — Prometheus, Loki, Tempo, CloudWatch, SQL databases and many more — and renders the results as dashboards. Its value is putting data from different systems side by side on one time axis.

## Core concepts

| Concept     | Meaning                                                                         |
| :---------- | :------------------------------------------------------------------------------ |
| Data source | A connection to a backend plus the query editor for its language                |
| Panel       | One visualisation driven by one or more queries                                 |
| Dashboard   | A set of panels with a shared time range and variables                          |
| Variable    | A dropdown whose value is substituted into queries: cluster, namespace, service |
| Folder      | Groups dashboards and carries permissions                                       |
| Explore     | An ad hoc query view for investigation, without building a dashboard            |
| Alert rule  | A query evaluated on a schedule that fires when a condition holds               |

## Dashboards that answer questions

Most dashboards fail because they are a wall of graphs with no argument. A useful one is built top-down:

1. **Row one: is it healthy?** A few stat panels for the service's key indicators — request rate, error ratio, latency percentile, saturation. Someone should be able to tell good from bad in five seconds.
2. **Row two: where is the problem?** The same signals broken down by the most useful dimension: endpoint, dependency, zone, version.
3. **Row three and below: why?** Resources, runtime internals, dependencies. Collapsed by default.

Practical rules:

- **One dashboard per service or per question**, not one per metric source.
- **Use the RED and USE layouts** consistently so every service's dashboard reads the same way. The signals come from [[Observability/prometheus/instrumenting|instrumentation]].
- **Show percentiles, not averages**, for latency.
- **Fix the y-axis** where it matters: an error-ratio panel that auto-scales makes 0.01% look as alarming as 10%.
- **Units and thresholds on every panel.** Draw the objective as a line.
- **Annotate deployments.** Vertical markers at release times explain half of all step changes.
- **Link, do not cram.** Add drill-down links from an overview to detail dashboards instead of fitting everything on one screen.

## Variables

```
Name:   namespace
Type:   Query
Query:  label_values(kube_pod_info{cluster="$cluster"}, namespace)
```

```promql
sum by (pod) (
  rate(container_cpu_usage_seconds_total{cluster="$cluster", namespace="$namespace"}[$__rate_interval])
)
```

- Chain variables (`cluster` → `namespace` → `workload`) so each narrows the next.
- Use `$__rate_interval` rather than a hard-coded `[5m]`. It adapts to the zoom level and the scrape interval, which avoids empty or misleading `rate()` results. The query language itself is covered in [[Observability/prometheus/promql|PromQL]].
- A multi-value variable needs a regex matcher: `namespace=~"$namespace"`.

## Dashboards as code

Dashboards edited by hand in the UI drift, get broken by a well-meant change, and vanish with the instance. Keep them in Git.

| Approach           | How                                                                                     |
| :----------------- | :-------------------------------------------------------------------------------------- |
| File provisioning  | JSON files mounted into Grafana; on Kubernetes, a sidecar loads ConfigMaps with a label |
| Grafana Operator   | `GrafanaDashboard` and `GrafanaDatasource` custom resources                             |
| Terraform provider | Dashboards, folders, data sources and alert rules as Terraform resources                |
| Generated JSON     | Grafonnet (Jsonnet) or the Foundation SDK to build many consistent dashboards from code |
| Git sync           | Grafana's built-in two-way synchronisation with a repository                            |

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: checkout-dashboard
  labels:
    grafana_dashboard: "1" # picked up by the dashboard sidecar
data:
  checkout.json: |
    { "title": "Checkout", "uid": "checkout", "panels": [ ... ] }
```

Set a stable `uid` so links survive re-imports, and mark provisioned dashboards read-only so UI edits cannot silently diverge. Provision data sources the same way, with credentials from a secret store rather than typed into the UI — see [[DevOps/infrastructure-as-code/README|infrastructure as code]].

## Correlating signals

The reason to run metrics, logs and traces behind one front end is moving between them without retyping context:

```
latency panel ──(exemplar)──► trace in Tempo ──(trace to logs)──► log lines in Loki
      ▲                                                                │
      └──────────────(derived field: trace_id in a log line)◄──────────┘
```

- **Exemplars** on a histogram panel are dots that link to a concrete trace.
- **Trace to logs / trace to metrics** are configured on the tracing data source and need consistent labels (`service`, `namespace`, `pod`) across all three backends.
- **Derived fields** on the logs data source turn a `trace_id` in a log line into a link.

This only works if the telemetry shares identifiers, which is what [[Observability/opentelemetry/semantic-conventions|semantic conventions]] and [[Observability/opentelemetry/context-propagation|context propagation]] provide. The backends are described in [[Observability/lgtm-stack|the LGTM stack]].

## Alerting

Grafana has its own alerting engine: rules query any data source, including several in one rule, and notifications go through contact points and notification policies that mirror Alertmanager's routing tree.

|                             | Prometheus rules + Alertmanager             | Grafana alerting                       |
| :-------------------------- | :------------------------------------------ | :------------------------------------- |
| Data sources                | Prometheus-compatible only                  | Any, and combinations                  |
| Where rules live            | Next to the metrics, evaluated by the store | In Grafana                             |
| Survives Grafana being down | Yes                                         | No                                     |
| Managed as code             | Rule files                                  | Provisioning files, Terraform, the API |

For Prometheus metrics, keep paging rules in Prometheus or Mimir so alerting does not depend on the dashboard server. Use Grafana alerting for conditions that span sources, such as logs or SQL. Alert design is in [[Observability/alerting|alerting]].

## Access and operations

- **Authentication** through OIDC or SAML against the organisation's identity provider; map groups to roles. Background: [[Architecture/solution-architecture-concepts/authentication/README|authentication]].
- **Permissions** by folder: teams edit their own folder, view the rest.
- **Data source permissions** matter more than dashboard permissions — anyone who can use Explore can query everything the data source can read.
- **State** lives in a database. Use PostgreSQL or MySQL rather than the default SQLite for anything shared, and run more than one replica.
- **Managed options** — Grafana Cloud, Amazon Managed Grafana, Azure Managed Grafana — remove the operational work at the cost of some plugin freedom.

## Common mistakes

| Mistake                                          | Effect                                               |
| :----------------------------------------------- | :--------------------------------------------------- |
| A panel per metric, no hierarchy                 | Nobody can tell what matters                         |
| Hundreds of dashboards, nobody owns them         | People stop trusting any of them                     |
| Queries over long ranges without recording rules | Slow dashboards and a loaded metrics backend         |
| Auto-refresh at 5 seconds on a wall display      | Constant query load for no benefit                   |
| Different label names per team                   | Variables and correlations break                     |
| Copying a community dashboard unmodified         | Half the panels show "No data" because labels differ |

Delete dashboards. Grafana's usage insights show which ones nobody opens.

## Related

- [[Observability/fundamentals|Observability fundamentals]]
- [[Observability/prometheus/README|Prometheus architecture]]
- [[Observability/logging|Logging]] and [[Observability/tracing|tracing]]
- [[Kubernetes/eks/observability/README|Observability on EKS]]
- [[AWS/monitoring/cloudwatch-dashboards/README|CloudWatch dashboards]]

## Further reading

- [Grafana (video playlist)](https://www.youtube.com/playlist?list=PLrMP04WSdCjqinVQqbW4j3phsN8oiqjJw)
