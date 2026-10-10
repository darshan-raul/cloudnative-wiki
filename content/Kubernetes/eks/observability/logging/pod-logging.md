---
title: Pod Logging on EKS
tags: [eks, observability, logging, fluent-bit, cloudwatch]
date: 2026-05-17
description: Collecting container logs on EKS — how logs get from stdout to disk, running Fluent Bit as a DaemonSet, the Fargate log router, choosing a destination and avoiding lost or expensive logs.
---

# Pod Logging on EKS

Kubernetes does not ship logs anywhere. It keeps what containers write to stdout and stderr in files on the node, rotates them, and deletes them when the pod goes away. Anything durable is the job of a log agent you run.

## From `printf` to a file

```
container stdout/stderr
      │   (containerd CRI logging)
      ▼
/var/log/pods/<ns>_<pod>_<uid>/<container>/0.log      ← real files
/var/log/containers/<pod>_<ns>_<container>-<id>.log   ← symlinks, one flat directory
      │   (kubelet rotates: 10 MiB × 5 files per container by default)
      ▼
log agent tails the files, adds Kubernetes metadata, ships them
```

Three consequences:

- `kubectl logs` reads these files through the kubelet. Once the pod is deleted or the node is terminated, the logs are gone.
- A container that logs faster than the agent reads can rotate a file away before it is shipped. That is silent log loss.
- Applications should log to stdout as structured JSON, one event per line. Files inside the container are invisible to this pipeline.

The node's own logs (kubelet, containerd) live in the systemd journal — see [[Linux/observability/journalctl|journalctl]] and [[Linux/concepts/08-logging|Linux logging]].

## Fluent Bit as a DaemonSet

Fluent Bit is the standard agent on EKS: small, fast, and with native outputs for AWS services. One pod per node tails `/var/log/containers/*.log`.

The quickest route is the **Amazon CloudWatch Observability** add-on, which installs Fluent Bit and the CloudWatch agent and sends application logs to `/aws/containerinsights/<cluster>/application`:

```bash
aws eks create-addon \
  --cluster-name my-cluster \
  --addon-name amazon-cloudwatch-observability \
  --pod-identity-associations \
    serviceAccount=cloudwatch-agent,roleArn=arn:aws:iam::111122223333:role/cloudwatch-agent
```

For other destinations, or more control, deploy the `aws-for-fluent-bit` Helm chart. The pipeline has four stages:

```ini
[INPUT]
    Name              tail
    Path              /var/log/containers/*.log
    multiline.parser  cri
    Tag               kube.*
    Mem_Buf_Limit     50MB
    Skip_Long_Lines   On
    DB                /var/fluent-bit/state/flb_kube.db

[FILTER]
    Name                kubernetes
    Match               kube.*
    Merge_Log           On
    Keep_Log            Off
    K8S-Logging.Parser  On
    K8S-Logging.Exclude On

[FILTER]
    Name    grep
    Match   kube.*
    Exclude $kubernetes['namespace_name'] ^(kube-system|amazon-cloudwatch)$

[OUTPUT]
    Name              cloudwatch_logs
    Match             kube.*
    region            eu-west-1
    log_group_name    /eks/my-cluster/app
    log_stream_prefix ${HOSTNAME}-
    auto_create_group true
    log_retention_days 30
```

What matters in that file:

- **`DB`** stores read offsets on a host path, so a restarted agent resumes instead of re-sending or skipping.
- **`multiline.parser cri`** reassembles lines the runtime split at 16 KB; add a language multiline parser for stack traces.
- **`Merge_Log`** parses JSON log lines into fields, which is what makes them queryable.
- **The `grep` filter** drops namespaces you do not want to pay for. A pod can also opt out with the annotation `fluentbit.io/exclude: "true"`.
- **`Mem_Buf_Limit`** applies back-pressure. When the destination is slow, Fluent Bit pauses the input rather than exhausting memory — and if files rotate meanwhile, logs are lost. Use filesystem buffering (`storage.type filesystem`) for anything you cannot lose.

## Choosing a destination

| Destination                                                | Strengths                                             | Watch out for                                       |
| :--------------------------------------------------------- | :---------------------------------------------------- | :-------------------------------------------------- |
| [[AWS/monitoring/cloudwatch-logs/README\|CloudWatch Logs]] | Zero operations, IAM-native, Logs Insights            | Ingestion price at high volume                      |
| [[Kubernetes/eks/observability/opensearch\|OpenSearch]]    | Full-text search, dashboards, long-standing tooling   | A cluster to size and run                           |
| Grafana Loki ([[Observability/logging\|logging]])          | Cheap object storage, label-based, pairs with Grafana | Not a full-text index; label cardinality discipline |
| [[AWS/storage/s3/README\|S3]] via Data Firehose            | Cheapest archive, queryable with Athena               | Not interactive                                     |

It is common to send everything to S3 for retention and only a filtered subset to an interactive store.

## Fargate

[[Kubernetes/eks/compute/fargate/README|Fargate]] has no nodes to run a DaemonSet on. Instead it runs a managed Fluent Bit sidecar, configured by a ConfigMap in a specially named namespace:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: aws-observability
  labels:
    aws-observability: enabled
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-logging
  namespace: aws-observability
data:
  output.conf: |
    [OUTPUT]
        Name cloudwatch_logs
        Match *
        region eu-west-1
        log_group_name /eks/my-cluster/fargate
        log_stream_prefix fargate-
        auto_create_group true
```

The **pod execution role** needs permission to write to the destination. Only pods started after the ConfigMap exists pick it up, and only a restricted set of outputs is supported (CloudWatch, OpenSearch, Firehose, Kinesis).

## Keeping the bill sane

Logging cost scales with bytes ingested, and a single debug-level service can dominate it.

1. Log at `info` in production; make the level changeable at runtime.
2. Drop health-check and readiness-probe access logs at the agent.
3. Set retention on every log group; the default is forever.
4. Do not use logs as metrics. Counting log lines in Insights is far more expensive than emitting a counter — see [[Observability/fundamentals|observability fundamentals]].
5. Find the top talkers: `stats sum(@message_size) by kubernetes.namespace_name, kubernetes.container_name`.

## Troubleshooting

| Symptom                               | Check                                                                                        |
| :------------------------------------ | :------------------------------------------------------------------------------------------- |
| No logs at all                        | Agent pods running on every node? IAM role attached? `kubectl logs` on the Fluent Bit pod    |
| Logs from some nodes only             | DaemonSet tolerations — tainted node groups need matching tolerations                        |
| Gaps under load                       | Buffer limits and rotation; raise kubelet `containerLogMaxSize`, enable filesystem buffering |
| Stack traces split into many events   | Missing multiline parser                                                                     |
| `ThrottlingException` from CloudWatch | Too many small `PutLogEvents` calls; fewer streams, larger batches                           |

## Related

- [[Kubernetes/eks/observability/README|EKS observability overview]]
- [[Kubernetes/eks/observability/logging/control-plane-logs|Control plane logs]]
- [[Observability/opentelemetry/logs-101|OpenTelemetry logs]] — the vendor-neutral model
- [[Linux/observability/log-management|Linux log management]]
- [Send logs to CloudWatch with Fluent Bit](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-setup-logs-FluentBit.html)

## Across the wiki

- [[AWS/analytics/opensearch/README|Amazon OpenSearch]] — host and container logs (AWS)
- [[Security/siem/elastic-security/README|Elastic Security]] — host and container logs (Security)
