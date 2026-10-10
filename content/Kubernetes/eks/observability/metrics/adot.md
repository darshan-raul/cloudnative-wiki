---
title: AWS Distro for OpenTelemetry on EKS
tags: [eks, observability, opentelemetry, adot, tracing, metrics]
date: 2026-05-17
description: Running the AWS Distro for OpenTelemetry on EKS — what ADOT adds to upstream, the operator add-on, collector deployment modes, pipelines to Managed Prometheus, X-Ray and CloudWatch, and auto-instrumentation.
---

# AWS Distro for OpenTelemetry on EKS

AWS Distro for OpenTelemetry (ADOT) is AWS's supported build of the OpenTelemetry Collector and SDKs. It is upstream OpenTelemetry with the AWS components included and tested: SigV4 authentication, exporters for X-Ray and CloudWatch, resource detectors for EKS and EC2.

Use it when you want one agent and one instrumentation standard for traces, metrics and logs, with the freedom to change backends later. If the OpenTelemetry model is new, read [[Observability/opentelemetry/overview|OpenTelemetry overview]] and [[Observability/opentelemetry/collector|the Collector]] first — this page covers only the EKS-specific parts.

## What you install

The EKS add-on named `adot` installs the **OpenTelemetry Operator**, not a collector. The operator gives you two custom resources:

| Resource                 | Purpose                                                                                    |
| :----------------------- | :----------------------------------------------------------------------------------------- |
| `OpenTelemetryCollector` | Declares a collector: its mode, image and pipeline configuration                           |
| `Instrumentation`        | Declares how to inject auto-instrumentation agents into pods without changing their images |

```bash
# The operator's webhooks need certificates
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

aws eks create-addon --cluster-name my-cluster --addon-name adot
```

## Collector deployment modes

| Mode          | Topology                | Use for                                                                               |
| :------------ | :---------------------- | :------------------------------------------------------------------------------------ |
| `daemonset`   | One collector per node  | Node and kubelet metrics, container logs, a local OTLP endpoint for applications      |
| `deployment`  | A scalable central pool | Gateway: batching, tail sampling, cluster-level metrics, fan-out to several backends  |
| `statefulset` | Stable identities       | Prometheus scraping with the target allocator, so each target is scraped exactly once |
| `sidecar`     | One collector per pod   | [[Kubernetes/eks/compute/fargate/README\|Fargate]], or strict per-tenant isolation    |

A production layout usually has two tiers: a DaemonSet agent that receives from local pods and forwards, and a Deployment gateway that holds the credentials and export logic. Applications then send to `http://$(HOST_IP):4317` and never know about the backend.

## A complete pipeline

```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: gateway
  namespace: observability
spec:
  mode: deployment
  replicas: 2
  serviceAccount: adot-collector
  config:
    extensions:
      sigv4auth:
        region: eu-west-1
        service: aps
    receivers:
      otlp:
        protocols:
          grpc: { endpoint: 0.0.0.0:4317 }
          http: { endpoint: 0.0.0.0:4318 }
    processors:
      memory_limiter:
        check_interval: 1s
        limit_percentage: 80
        spike_limit_percentage: 20
      k8sattributes: {}
      resourcedetection:
        detectors: [env, eks, ec2]
      batch: {}
    exporters:
      prometheusremotewrite:
        endpoint: https://aps-workspaces.eu-west-1.amazonaws.com/workspaces/ws-1234/api/v1/remote_write
        auth: { authenticator: sigv4auth }
      awsxray:
        region: eu-west-1
      awscloudwatchlogs:
        region: eu-west-1
        log_group_name: /eks/my-cluster/otel
        log_stream_name: app
    service:
      extensions: [sigv4auth]
      pipelines:
        metrics:
          receivers: [otlp]
          processors: [memory_limiter, k8sattributes, resourcedetection, batch]
          exporters: [prometheusremotewrite]
        traces:
          receivers: [otlp]
          processors: [memory_limiter, k8sattributes, resourcedetection, batch]
          exporters: [awsxray]
        logs:
          receivers: [otlp]
          processors: [memory_limiter, k8sattributes, batch]
          exporters: [awscloudwatchlogs]
```

Order matters in `processors`: `memory_limiter` first so the collector sheds load before it is OOM-killed, `batch` last.

## Permissions

Bind the collector's service account to a role with [[Kubernetes/eks/security/pod-identity|Pod Identity]] or [[Kubernetes/eks/security/iam-roles-for-sa|IRSA]]:

| Backend                                                                 | Managed policy                      |
| :---------------------------------------------------------------------- | :---------------------------------- |
| [[Kubernetes/eks/observability/metrics/prometheus\|Managed Prometheus]] | `AmazonPrometheusRemoteWriteAccess` |
| X-Ray                                                                   | `AWSXrayWriteOnlyAccess`            |
| CloudWatch metrics and logs                                             | `CloudWatchAgentServerPolicy`       |

The `k8sattributes` processor also needs Kubernetes [[Kubernetes/concepts/L07-security/01-api-access/03-rbac|RBAC]] to `get`, `list` and `watch` pods, namespaces and replica sets.

## Auto-instrumentation

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: default
  namespace: payments
spec:
  exporter:
    endpoint: http://gateway-collector.observability:4317
  propagators: [tracecontext, baggage, xray]
  sampler:
    type: parentbased_traceidratio
    argument: "0.1"
```

Annotate a workload's pod template with `instrumentation.opentelemetry.io/inject-java: "true"` (or `-python`, `-nodejs`, `-dotnet`) and the operator adds an init container that loads the agent. This gives traces and runtime metrics for common frameworks with no code change. Include the `xray` propagator if requests pass through AWS services that only understand the X-Ray header — details in [[Observability/opentelemetry/context-propagation|context propagation]].

## ADOT or the CloudWatch agent

The **CloudWatch Observability** add-on is the turnkey alternative: it installs the CloudWatch agent with [[Kubernetes/eks/observability/metrics/cloudwatch-container-insights|Container Insights]] and Application Signals preconfigured. Choose it when CloudWatch is the only backend and you want the least configuration. Choose ADOT when you want vendor-neutral pipelines, Prometheus-compatible storage, or to send the same telemetry to more than one place.

## Operating it

- The collector exposes its own metrics on port 8888. Alert on `otelcol_exporter_send_failed_*` and `otelcol_processor_refused_*`; they are the first sign of dropped telemetry.
- Enable the `debug` exporter temporarily to see exactly what a pipeline emits.
- High-cardinality attributes become high-cardinality Prometheus labels and a large bill. Drop them in the collector with the `attributes` or `transform` processor.
- Pin the add-on version and read release notes: collector configuration keys do change between versions.

## Related

- [[Kubernetes/eks/observability/README|EKS observability overview]]
- [[Observability/opentelemetry/kubernetes|OpenTelemetry on Kubernetes]]
- [[Observability/tracing|Distributed tracing]]
- [[Observability/opentelemetry/semantic-conventions|Semantic conventions]]
- [ADOT documentation](https://aws-otel.github.io/docs/introduction)
