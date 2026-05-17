---
title: Amazon Managed Prometheus
tags: [eks, observability, metrics, prometheus]
date: 2026-05-17
description: Monitor EKS with Amazon Managed Service for Prometheus (AMP)
---

# Amazon Managed Prometheus (AMP)

## Overview

AMP provides a fully managed Prometheus-compatible monitoring service.

## Install AMP Agent

```bash
# Create AMP workspace
aws amp create-workspace \
  --alias my-cluster-prometheus \
  --region us-west-2

# Get workspace endpoint
aws amp describe-workspace \
  --workspace-id ws-xxxxx \
  --query 'workspace.prometheusEndpoint'
```

## Install Prometheus with AMP

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.serviceAccount.name=amp-iam-proxy-service-account \
  --set prometheus.remoteWrite[0].url=https://aps-workspaces.us-west-2.amazonaws.com/workspaces/ws-xxxxx/api/v1/remote_write \
  --set prometheus.remoteWrite[0].sigv4.region=us-west-2
```

## Service Account with IRSA

```bash
# Create IRSA
eksctl create iamserviceaccount \
  --name amp-iam-proxy-service-account \
  --namespace monitoring \
  --cluster my-cluster \
  --attach-role-arn arn:aws:iam::123456789:role/AMPExecutionRole \
  --approve
```

## Query with Grafana

```bash
# Install Grafana
helm install grafana grafana/grafana \
  --namespace monitoring \
  --set adminPassword='Admin123' \
  --set service.type=LoadBalancer

# Configure AMP data source
# URL: https://aps-workspaces.us-west-2.amazonaws.com/workspaces/ws-xxxxx
# Auth: SigV4 with region us-west-2
```

## Useful Prometheus Queries

### Pod CPU usage
```
sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (pod)
```

### Memory utilization
```
sum(container_memory_working_set_bytes) by (pod) / sum(container_spec_memory_limit_bytes) by (pod) * 100
```

### Request rate
```
sum(rate(http_requests_total[5m])) by (service)
```

## References

- [AMP Documentation](https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-for-Prometheus.html)
- [EKS Workshop - Prometheus](https://www.eksworkshop.com/docs/observability/open-source-metrics/)