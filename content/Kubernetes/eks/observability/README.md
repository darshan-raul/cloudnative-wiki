---
title: Observability on EKS
tags: [eks, observability]
date: 2026-05-17
description: Monitoring, logging, and cost visibility for EKS clusters
---

# Observability on EKS

## Overview

EKS integrates with AWS native (CloudWatch) and open source (Prometheus, Grafana, OpenTelemetry) observability solutions.

## Topics

### Logging
- [[Kubernetes/eks/observability/logging/control-plane-logs|Control Plane Logs]] - API server, audit, authenticator logs
- [[Kubernetes/eks/observability/logging/pod-logging|Pod Logging]] - Application log aggregation

### Metrics
- [[Kubernetes/eks/observability/metrics/cloudwatch-container-insights|CloudWatch Container Insights]]
- [[Kubernetes/eks/observability/metrics/prometheus|Prometheus]] - Amazon Managed Service for Prometheus
- [[Kubernetes/eks/observability/metrics/adot|ADOT]] - AWS Distro for OpenTelemetry

### Cost
- [[Kubernetes/eks/observability/cost-monitoring/kubecost|Kubecost]] - Cost visibility and optimization

### Analytics
- [[Kubernetes/eks/observability/opensearch|OpenSearch]] - Log analysis

## Architecture Options

### AWS Native
```
EKS --> CloudWatch Logs --> CloudWatch Container Insights
                     --> CloudWatch Metrics
```

### Open Source Managed
```
EKS --> AMP (Prometheus) --> AMG (Grafana)
   --> ADOT --> AMP/CloudWatch
```

## References

- [EKS Observability](https://docs.aws.amazon.com/eks/latest/userguide/observability.html)
- [EKS Workshop - Observability](https://www.eksworkshop.com/docs/observability/)