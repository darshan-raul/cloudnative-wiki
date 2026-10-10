---
title: CloudWatch Container Insights on EKS
tags: [eks, observability, cloudwatch, metrics, container-insights]
date: 2026-05-17
description: Monitoring EKS with CloudWatch Container Insights — what the Observability add-on installs, the metrics and dashboards you get, enhanced observability pricing, useful queries and alarms, and how it compares with Prometheus.
---

# CloudWatch Container Insights on EKS

Container Insights is the AWS-native way to get cluster, node, pod and container metrics from EKS into [[AWS/monitoring/cloudwatch-metrics/README|CloudWatch]], with ready-made dashboards. It is the fastest route from a new cluster to usable monitoring, and it needs no metrics backend of your own.

## What gets installed

The **Amazon CloudWatch Observability** add-on deploys:

| Component        | Runs as    | Collects                                                                                            |
| :--------------- | :--------- | :-------------------------------------------------------------------------------------------------- |
| CloudWatch agent | DaemonSet  | Node, pod and container metrics from the kubelet and cAdvisor; control-plane and kube-state metrics |
| Fluent Bit       | DaemonSet  | Container, host and data-plane logs                                                                 |
| Agent operator   | Deployment | Manages the agents; injects Application Signals auto-instrumentation                                |

```bash
aws eks create-addon \
  --cluster-name my-cluster \
  --addon-name amazon-cloudwatch-observability \
  --pod-identity-associations \
    serviceAccount=cloudwatch-agent,roleArn=arn:aws:iam::111122223333:role/cloudwatch-agent
```

The role needs `CloudWatchAgentServerPolicy` (and `AWSXrayWriteOnlyAccess` if you use Application Signals), bound through [[Kubernetes/eks/security/pod-identity|Pod Identity]].

## How the data flows

The agent does not send individual metrics. It writes **performance log events** in embedded metric format to the log group `/aws/containerinsights/<cluster>/performance`, and CloudWatch extracts metrics from them into the `ContainerInsights` namespace. So the detailed per-container data is always queryable in [[AWS/monitoring/cloudwatch-insights/README|Logs Insights]], even for dimensions that were not turned into metrics.

Log groups created:

| Log group                                      | Contents                     |
| :--------------------------------------------- | :--------------------------- |
| `/aws/containerinsights/<cluster>/performance` | Metric events                |
| `/aws/containerinsights/<cluster>/application` | Container stdout and stderr  |
| `/aws/containerinsights/<cluster>/host`        | Node system logs             |
| `/aws/containerinsights/<cluster>/dataplane`   | kubelet, kube-proxy, runtime |

Set retention on all four — the default is to keep them forever.

## Enhanced observability

The current default, "Container Insights with enhanced observability", adds container-level granularity, control-plane metrics (API server request rates and latency, etcd size), kube-state metrics (desired versus ready replicas, pod status), and curated dashboards that drill from cluster to node to pod to container.

It is **priced per observation** rather than per custom metric, which is usually much cheaper for the same detail and far more predictable. Optional extras include GPU and other accelerator metrics, EBS volume performance metrics and Windows node support.

**Application Signals** builds on the same agent: it auto-instruments Java, Python, .NET and Node.js services with OpenTelemetry and produces service maps, RED metrics and SLO tracking without code changes.

## Metrics worth knowing

| Metric                                            | Use                                              |
| :------------------------------------------------ | :----------------------------------------------- |
| `node_cpu_utilization`, `node_memory_utilization` | Node saturation                                  |
| `node_filesystem_utilization`                     | Disk pressure before the kubelet starts evicting |
| `pod_cpu_utilization_over_pod_limit`              | Pods close to throttling                         |
| `pod_memory_utilization_over_pod_limit`           | Pods close to being OOM-killed                   |
| `pod_number_of_container_restarts`                | Crash loops                                      |
| `cluster_failed_node_count`                       | Nodes `NotReady`                                 |
| `node_number_of_running_pods`                     | Approaching `maxPods`                            |
| `apiserver_request_total` and latency             | Control-plane health and noisy clients           |

What each underlying source means is covered in [[Kubernetes/concepts/L08-operations/04-metrics-sources|metrics sources]].

## Useful Logs Insights queries

**Top memory consumers by pod:**

```
fields @timestamp, PodName, Namespace, pod_memory_working_set
| filter Type = "Pod"
| stats max(pod_memory_working_set) as mem by PodName, Namespace
| sort mem desc
| limit 20
```

**Containers that restarted:**

```
filter Type = "Pod" and pod_number_of_container_restarts > 0
| stats max(pod_number_of_container_restarts) as restarts by PodName, Namespace
| sort restarts desc
```

**CPU requested versus used, per namespace** (for right-sizing):

```
filter Type = "Pod"
| stats avg(pod_cpu_request) as requested, avg(pod_cpu_usage_total) as used by Namespace
```

## Alarms to create first

| Condition                                                    | Why                                                |
| :----------------------------------------------------------- | :------------------------------------------------- |
| `cluster_failed_node_count` > 0 for 5 minutes                | Capacity is lost                                   |
| `node_filesystem_utilization` > 80%                          | Evictions are coming                               |
| `pod_memory_utilization_over_pod_limit` > 90% for a workload | OOM kills are likely                               |
| Container restarts rising for a Deployment                   | Crash loop                                         |
| API server 5xx rate or latency anomaly                       | Control plane trouble, or a misbehaving controller |

Use anomaly-detection or composite [[AWS/monitoring/cloudwatch-alarms/README|alarms]] to avoid paging on every pod. These are infrastructure signals; alert on user-facing symptoms as well — [[Observability/alerting|alerting]].

## Container Insights or Prometheus

|                                      | Container Insights                             | [[Kubernetes/eks/observability/metrics/prometheus\|Prometheus]] (self-run or managed) |
| :----------------------------------- | :--------------------------------------------- | :------------------------------------------------------------------------------------ |
| Set-up effort                        | One add-on                                     | More: scraping, storage, dashboards                                                   |
| Query language                       | CloudWatch metrics math, Logs Insights         | PromQL                                                                                |
| Application metrics                  | Through EMF or the agent's Prometheus scraping | Native                                                                                |
| Ecosystem dashboards and alert rules | AWS-curated                                    | Very large community catalogue                                                        |
| Portability                          | AWS only                                       | Any cluster, any cloud                                                                |
| Cost model                           | Per observation and log volume                 | Per sample ingested, or your own infrastructure                                       |

Many teams run both: Container Insights for infrastructure views and AWS-native alarms, Prometheus for application metrics and SLOs. For a vendor-neutral pipeline that can feed either, see [[Kubernetes/eks/observability/metrics/adot|ADOT]].

## Controlling cost

- Cost follows the number of pods and containers observed and the log volume. Review the bill after a week.
- Set log retention; send only the namespaces you need from Fluent Bit — [[Kubernetes/eks/observability/logging/pod-logging|pod logging]].
- Disable optional accelerator or EBS metrics where unused.
- Non-production clusters may not need container-level granularity.

## Related

- [[Kubernetes/eks/observability/README|EKS observability overview]]
- [[AWS/monitoring/cloudwatch-dashboards/README|CloudWatch dashboards]]
- [[Observability/fundamentals|Observability fundamentals]]
- [Container Insights with enhanced observability for EKS](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/container-insights-detailed-metrics.html)
