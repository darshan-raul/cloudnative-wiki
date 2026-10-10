---
title: Prometheus on EKS
tags: [eks, observability, prometheus, metrics, amp]
date: 2026-05-17
description: Three ways to run Prometheus metrics on EKS — self-managed kube-prometheus-stack, Amazon Managed Service for Prometheus with remote write, and agentless managed scrapers — with what to scrape and how to control cost.
---

# Prometheus on EKS

Prometheus is the de facto metrics system for Kubernetes: nearly every component and add-on exposes a `/metrics` endpoint in its format. On EKS the question is not whether to use it but **who runs the storage and who does the scraping**. How Prometheus itself works is covered in [[Observability/prometheus/README|Prometheus architecture]] and [[Observability/prometheus/promql|PromQL]].

## Three operating models

| Model                                    | Scraping                           | Storage                                        | You operate                                 |
| :--------------------------------------- | :--------------------------------- | :--------------------------------------------- | :------------------------------------------ |
| **Self-managed** (kube-prometheus-stack) | Prometheus pods in the cluster     | [[Kubernetes/eks/storage/ebs-csi\|EBS]] volume | Everything: sizing, HA, retention, upgrades |
| **AMP + in-cluster agent**               | Prometheus agent or OTel collector | Amazon Managed Prometheus                      | The scraper only                            |
| **AMP + managed scraper**                | AWS-run, agentless                 | Amazon Managed Prometheus                      | Nothing in the cluster                      |

Amazon Managed Service for Prometheus (AMP) is a Prometheus-compatible, multi-AZ store. You get a workspace with a remote-write endpoint and a query endpoint; it scales automatically, keeps 150 days by default, and is paid per sample ingested, per GB stored and per query.

## Model 1: self-managed

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set prometheus.prometheusSpec.retention=15d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=gp3 \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=100Gi
```

This installs the Prometheus Operator, Prometheus, Alertmanager, Grafana, node-exporter and kube-state-metrics, plus a large set of default dashboards and alert rules. It is the fastest way to a working setup and fine for a single cluster.

Its limits appear with scale: one Prometheus is one pod with one volume in one zone, memory grows with the number of active series, and a second replica doubles cost without sharing data. Long retention and a global view across clusters need Thanos or Mimir on top — or AMP.

**EKS-specific gotcha:** the chart's default rules alert on `etcd`, `kube-scheduler` and `kube-controller-manager` targets. On EKS those run in the AWS-managed control plane and are not scrapable from inside the cluster the same way, so the alerts fire permanently. Disable them (`kubeEtcd.enabled=false` and so on) and read control-plane metrics from the API server's metrics endpoints instead.

## Model 2: AMP with remote write

Keep the scraper in the cluster, but run Prometheus in **agent mode** (no local querying, minimal storage) and forward everything:

```yaml
prometheus:
  prometheusSpec:
    serviceAccountName: amp-ingest
    remoteWrite:
      - url: https://aps-workspaces.eu-west-1.amazonaws.com/workspaces/ws-1234/api/v1/remote_write
        sigv4:
          region: eu-west-1
        queueConfig:
          maxSamplesPerSend: 1000
          maxShards: 200
          capacity: 2500
```

The service account needs `aps:RemoteWrite` through [[Kubernetes/eks/security/pod-identity|Pod Identity]] or [[Kubernetes/eks/security/iam-roles-for-sa|IRSA]]. An [[Kubernetes/eks/observability/metrics/adot|ADOT collector]] with the `prometheus` receiver and `prometheusremotewrite` exporter does the same job and is the better choice if you also collect traces.

## Model 3: managed scrapers

AMP can scrape the cluster for you. A managed collector runs in AWS's account, reaches into your VPC through ENIs in the subnets you choose, discovers targets with the same `scrape_configs` syntax, and writes to a workspace.

```bash
aws amp create-scraper \
  --source eksConfiguration="{clusterArn=arn:aws:eks:eu-west-1:111122223333:cluster/my-cluster,subnetIds=[subnet-a,subnet-b]}" \
  --destination ampConfiguration="{workspaceArn=arn:aws:aps:eu-west-1:111122223333:workspace/ws-1234}" \
  --scrape-configuration configurationBlob=fileb://scrape-config.yaml
```

The scraper authenticates to the cluster through an [[Kubernetes/eks/security/access/cluster-access-management|access entry]]. Nothing runs on your nodes, so there is no scraper to size or upgrade. It is the lowest-effort option, with less flexibility: no custom relabelling plugins, no exec-based discovery.

## What to scrape

| Source                       | Tells you                                                    | Provided by                       |
| :--------------------------- | :----------------------------------------------------------- | :-------------------------------- |
| kubelet / cAdvisor           | CPU, memory, filesystem and network per container            | Built into every node             |
| kube-state-metrics           | Object state: desired vs ready replicas, pod phase, restarts | Add-on or chart                   |
| node-exporter                | Host CPU, memory, disk, network                              | DaemonSet                         |
| API server                   | Request rates, latency, errors                               | `kubernetes` Service endpoint     |
| CoreDNS, VPC CNI, kube-proxy | DNS errors, IP address pool exhaustion, proxy sync latency   | Each exposes `/metrics`           |
| Your applications            | The golden signals for the service                           | Client libraries or OpenTelemetry |

The VPC CNI metrics (`awscni_assigned_ip_addresses`, `awscni_total_ip_addresses`) deserve an alert of their own: running out of pod IPs is a common EKS-specific outage — see [[Kubernetes/eks/networking/vpc-cni/eni-allocation|ENI allocation]]. What each source means is covered in [[Kubernetes/concepts/L08-operations/04-metrics-sources|metrics sources]].

## Alerting and dashboards

- **Rules.** AMP has a ruler: upload recording and alerting rule files to the workspace (`aws amp create-rule-groups-namespace`).
- **Alertmanager.** AMP includes a managed Alertmanager that routes to SNS; fan out from there to chat and paging.
- **Dashboards.** Amazon Managed Grafana, or your own [[Observability/grafana|Grafana]], with AMP as a Prometheus data source using SigV4.

Alert on symptoms users feel, not on every cause — see [[DevOps/sre/slos-and-error-budgets|SLOs and error budgets]] and [[Observability/alerting|alerting]].

## Controlling cost

Cost follows **active series**, and series are multiplied by label cardinality.

1. Measure first: `topk(20, count by (__name__)({__name__=~".+"}))` shows the largest metrics.
2. Drop metrics nobody queries with `metric_relabel_configs` before they are sent. cAdvisor and the API server histograms are the usual offenders.
3. Never put unbounded values (user IDs, request IDs, full URLs) in labels.
4. Lengthen the scrape interval from 15s to 30s or 60s for targets that do not need the resolution.
5. Use recording rules for expensive dashboard queries rather than widening retention of raw data.

## Related

- [[Kubernetes/eks/observability/README|EKS observability overview]]
- [[Kubernetes/eks/observability/metrics/cloudwatch-container-insights|CloudWatch Container Insights]] — the non-Prometheus alternative
- [[Observability/prometheus/instrumenting|Instrumenting applications]]
- [[Kubernetes/concepts/L06-scheduling-scaling/03-horizontalpodautoscaler|HPA]] and [[Kubernetes/concepts/L06-scheduling-scaling/10-keda|KEDA]] — scaling on Prometheus metrics
- [Amazon Managed Service for Prometheus user guide](https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-Prometheus.html)
