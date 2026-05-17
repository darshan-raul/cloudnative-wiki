---
title: ADOT - AWS Distro for OpenTelemetry
tags: [eks, observability, metrics, adot, opentelemetry]
date: 2026-05-17
description: Collect telemetry data with ADOT on EKS
---

# AWS Distro for OpenTelemetry (ADOT)

## Overview

ADOT provides open source observability components for collecting metrics, traces, and logs.

## Install ADOT Operator

```bash
helm repo add adot https://aws.github.io/aws-otel-collector
helm repo update

helm install adot-operator adot/aws-otel-collector \
  --namespace monitoring \
  --create-namespace
```

## Certificate for IRSA

```bash
# Create IRSA for ADOT
eksctl create iamserviceaccount \
  --name adot-collector \
  --namespace monitoring \
  --cluster my-cluster \
  --attach-role-arn arn:aws:iam::123456789:role/ADOTExecutionRole \
  --approve
```

## Metrics Collector Configuration

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: my-app-collector
spec:
  mode: daemonset
  serviceAccount: adot-collector
  env:
    - name: AWS_REGION
      value: us-west-2
    - name: AWS_ROLE_ARN
      value: arn:aws:iam::123456789:role/ADOTExecutionRole
    - name: AWS_WEB_IDENTITY_TOKEN_FILE
      value: /var/run/secrets/eks.amazonaws.com/serviceaccount/token
  prometheusMargin: 20s
  prometheus:
    config:
      receivers:
        prometheus:
          config:
            scrape_configs:
              - job_name: kubernetes-pods
                kubernetes_sd_configs:
                  - role: pod
      exporters:
        prometheusremotewrite:
          endpoint: https://aps-workspaces.us-west-2.amazonaws.com/workspaces/ws-xxxxx/api/v1/remote_write
          auth:
            authenticator: sigv4
      service:
        pipelines:
          metrics:
            receivers: [prometheus]
            exporters: [prometheusremotewrite]
```

## Instrumentation for Applications

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: my-app-instrumentation
spec:
  propagators:
    - tracecontext
    - baggage
  sampler:
    type: parentbased_always_on
```

## Traces with X-Ray

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: xray-collector
spec:
  mode: deployment
  exporters:
    awsxray:
      region: us-west-2
    logging:
  service:
    pipelines:
      traces:
        receivers: [otlp]
        exporters: [awsxray, logging]
```

## References

- [ADOT Documentation](https://aws-otel.github.io/)
- [EKS Workshop - ADOT](https://www.eksworkshop.com/docs/observability/open-source-metrics/)
- [[Architecture/solution-architecture-concepts/observability/telemetry|Telemetry Concepts]]