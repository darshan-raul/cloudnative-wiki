---
title: OpenTelemetry Kubernetes Deployment
description: OTel Collector deployment patterns on Kubernetes — Agent, Gateway, Operator
tags:
  - opentelemetry
  - kubernetes
  - k8s
  - deployment
date: 2025-01-01
draft: false
---

# OpenTelemetry Kubernetes Deployment

## Deployment Architectures

### Architecture 1: Agent as DaemonSet

Collector runs as a DaemonSet on every node. Applications send OTLP to the local node agent.

```
Pod → OTel Agent (localhost:4317) → OTel Gateway (ClusterIP) → Backend
```

```yaml
# Agent mode: DaemonSet
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: otel-agent
spec:
  mode: daemonset
  config: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    processors:
      batch:
        timeout: 1s
        send_batch_size: 1024
      memory_limiter:
        limit_mib: 512
        check_interval: 1s
      k8sattributes:
        extract:
          metadata:
            - k8s.namespace.name
            - k8s.pod.name
            - k8s.pod.uid
            - k8s.deployment.name
            - k8s.node.name
            - k8s.container.name
    exporters:
      otlp:
        endpoint: otel-gateway:4317
        tls:
          insecure: true
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [k8sattributes, batch, memory_limiter]
          exporters: [otlp]
        metrics:
          receivers: [otlp]
          processors: [batch, memory_limiter]
          exporters: [otlp]
        logs:
          receivers: [otlp]
          processors: [batch, memory_limiter]
          exporters: [otlp]
```

### Architecture 2: Gateway as Deployment

Collector runs as a central Gateway Deployment. Receives from agents or direct apps.

```yaml
# Gateway mode: Deployment + ClusterIP Service
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: otel-gateway
spec:
  mode: deployment
  replicas: 3
  config: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    processors:
      batch:
        timeout: 5s
        send_batch_size: 8192
      memory_limiter:
        limit_mib: 1024
        check_interval: 1s
      tail_sampling:
        decision_wait: 10s
        num_traces: 100000
        policies:
          - name: errors-policy
            type: status_code
            status_code: {status_codes: [ERROR]}
          - name: latency-slo-policy
            type: latency
            latency: {threshold_ms: 500}
          - name: probabilistic-policy
            type: probabilistic
            probabilistic: {sampling_percentage: 10}
    exporters:
      otlp/tempo:
        endpoint: http://tempo:4317
        tls:
          insecure: true
      prometheus:
        endpoint: 0.0.0.0:8889
      loki:
        endpoint: http://loki:3100/otlp
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [tail_sampling, batch, memory_limiter]
          exporters: [otlp/tempo]
        metrics:
          receivers: [otlp]
          processors: [batch, memory_limiter]
          exporters: [prometheus]
        logs:
          receivers: [otlp]
          processors: [batch, memory_limiter]
          exporters: [loki]
```

## Auto-Instrumentation Injection

The OpenTelemetry Operator can **inject auto-instrumentation** into pods automatically via admission webhooks.

### Enable Auto-Instrumentation for All Namespaces

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: my-instrumentation
spec:
  exporter:
    endpoint: http://otel-agent.default:4317
  propagators:
    - tracecontext
    - baggage
  sampler:
    type: parentbased_traceidratio
    argument: "0.1"
```

### Pod with Auto-Instrumentation

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app-pod
  annotations:
    instrumentation.opentelemetry.io/inject-sdk: "true"
    instrumentation.opentelemetry.io/inject-contrib: "true"  # for Python auto-instrumentation libs
    instrumentation.opentelemetry.io/service-name: "my-service"
    instrumentation.opentelemetry.io/otel-traces-sampler: "parentbased_traceidratio"
    instrumentation.opentelemetry.io/otel-traces-sampler-argument: "0.1"
spec:
  containers:
    - name: app
      image: my-app:latest
```

### Namespace-Level Injection

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  annotations:
    instrumentation.opentelemetry.io/inject-sdk: "true"
    instrumentation.opentelemetry.io/exporter-endpoint: "http://otel-agent.observability:4317"
```

### Per-Language Annotation

| Annotation | Language | Effect |
|-----------|----------|--------|
| `instrumentation.opentelemetry.io/inject-sdk` | All | Inject OTel SDK |
| `instrumentation.opentelemetry.io/inject-javaagent` | Java | Inject Java agent JAR |
| `instrumentation.opentelemetry.io/inject-python` | Python | Inject Python auto-instrumentation |
| `instrumentation.opentelemetry.io/inject-nodejs` | Node.js | Inject Node.js auto-instrumentation |
| `instrumentation.opentelemetry.io/inject-dotnet` | .NET | Inject .NET auto-instrumentation |

## ServiceAccount for Collector

Collectors running in agent mode need a ServiceAccount for Kubernetes metadata extraction:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: otel-collector
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: otel-collector
rules:
  - apiGroups: [""]
    resources: ["pods", "namespaces", "nodes", "nodes/metrics", "nodes/proxy"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["replicasets", "deployments", "daemonsets", "statefulsets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: otel-collector
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: otel-collector
subjects:
  - kind: ServiceAccount
    name: otel-collector
    namespace: observability
```

Apply to the DaemonSet:

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: otel-agent
spec:
  mode: daemonset
  serviceAccount: otel-collector
  # ...
```

## Helm Installation

### Agent Mode (DaemonSet)

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts

helm install otel-agent open-telemetry/opentelemetry-collector \
  --namespace observability \
  --create-namespace \
  --set mode=daemonset \
  --set config.receivers.otlp.protocols.grpc.endpoint=0.0.0.0:4317 \
  --set config.receivers.otlp.protocols.http.endpoint=0.0.0.0:4318 \
  --set config.exporters.otlp.endpoint="otel-gateway.observability:4317" \
  --set config.processors.k8sattributes.enabled=true \
  --set serviceAccount.create=true
```

### Gateway Mode

```bash
helm install otel-gateway open-telemetry/opentelemetry-collector \
  --namespace observability \
  --set mode=deployment \
  --set replicaCount=3 \
  --set config.receivers.otlp.protocols.grpc.endpoint=0.0.0.0:4317 \
  --set config.exporters.prometheus.endpoint=0.0.0.0:8889 \
  --set config.exporters.otlp.endpoint="http://tempo.observability:4317"
```

### Values File for Production

```yaml
# values.yaml
mode: daemonset

replicaCount: 1

resources:
  limits:
    cpu: 500m
    memory: 1Gi
  requests:
    cpu: 100m
    memory: 256Mi

config:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318
  processors:
    batch:
      timeout: 1s
      send_batch_size: 1024
    memory_limiter:
      limit_mib: 512
      spike_limit_mib: 128
      check_interval: 1s
    k8sattributes:
      extract:
        metadata:
          - k8s.namespace.name
          - k8s.pod.name
          - k8s.deployment.name
          - k8s.node.name
          - k8s.container.name
  exporters:
    otlp:
      endpoint: otel-gateway.observability:4317
      tls:
        insecure: true
  service:
    pipelines:
      traces:
        receivers: [otlp]
        processors: [k8sattributes, batch, memory_limiter]
        exporters: [otlp]
      metrics:
        receivers: [otlp]
        processors: [batch, memory_limiter]
        exporters: [otlp]
      logs:
        receivers: [otlp]
        processors: [batch, memory_limiter]
        exporters: [otlp]

serviceAccount:
  create: true
  name: otel-collector

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - prometheus-gateway.observability.example.com
  tls:
    - secretName: otel-gateway-tls
      hosts:
        - prometheus-gateway.observability.example.com
```

## Application Configuration

Applications send telemetry to the OTel Agent on the same node (via Kubernetes service discovery via the agent's host IP):

```python
# Python: Send to local OTel Agent
import os

os.environ["OTEL_EXPORTER_OTLP_ENDPOINT"] = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317")
os.environ["OTEL_EXPORTER_OTLP_PROTOCOL"] = "grpc"
os.environ["OTEL_SERVICE_NAME"] = "my-service"
```

In Kubernetes, the agent is reached via the node's IP — not via a ClusterIP service (which would send to a random node). Use the Kubernetes downward API to get the node IP:

```yaml
env:
  - name: NODE_IP
    valueFrom:
      fieldRef:
        fieldPath: status.hostIP
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://$(NODE_IP):4317"
```

Or use the OTel Operator's auto-instrumentation which handles this automatically.

## Resource Limits and Tuning

### Agent Memory

The `memory_limiter` processor protects against OOM. Set limits ~20% above the Kubernetes memory request:

```yaml
config:
  processors:
    memory_limiter:
      limit_mib: 768       # ~20% above container limit
      spike_limit_mib: 256  # spike allowance
```

### Gateway Scaling

Gateway Collectors can be scaled horizontally:

```yaml
spec:
  mode: deployment
  replicas: 3
  autoscaler:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 60
    targetMemoryUtilizationPercentage: 60
```

### HPA for Metrics

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: otel-gateway-hpa
spec:
  scaleTargetRef:
    apiVersion: opentelemetry.io/v1alpha1
    kind: OpenTelemetryCollector
    name: otel-gateway
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
```

## Security

### TLS Between Components

```yaml
# Internal TLS between Agent and Gateway
exporters:
  otlp:
    endpoint: otel-gateway.observability:4317
    tls:
      insecure: false
      cert_file: /etc/otel/certs/agent.crt
      key_file: /etc/otel/certs/agent.key
      ca_file: /etc/otel/certs/ca.crt
```

### mTLS via OTel Operator

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector
spec:
  mode: daemonset
  securityContext:
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
  volumes:
    - name: otel-certs
      secret:
        secretName: otel-certs
  volumeMounts:
    - name: otel-certs
      mountPath: /etc/otel/certs
  config:
    exporters:
      otlp:
        tls:
          cert_file: /etc/otel/certs/agent.crt
          key_file: /etc/otel/certs/agent.key
          ca_file: /etc/otel/certs/ca.crt
```

## Monitoring the Collector

The Collector exposes its own metrics for observability:

```yaml
config:
  exporters:
    prometheus:
      endpoint: 0.0.0.0:8889
  service:
    pipelines:
      metrics:
        receivers: [prometheus]
        exporters: [prometheus]
```

Key Collector metrics to watch:

| Metric | Alert if |
|--------|----------|
| `otelcol_exporter_sent_spans` | Not increasing (export stalled) |
| `otelcol_processor_dropped_spans` | High (memory limiter kicking in) |
| `otelcol_receiver_refused_spans` | High ( Collector overwhelmed) |
| `otelcol_memory_allocate_bytes` | Approaching limit |
| `otelcol_exporter_queue_capacity` | Near 100% (backpressure) |
| `otelcol_process_cpu_seconds` | Spiking |

## OpenTelemetry Operator

The [OTel Operator](https://opentelemetry.io/docs/k8s-operator/) manages OTel Collector CRs and auto-instrumentation admission:

```bash
# Install OTel Operator
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml

# Verify
kubectl get pods -n opentelemetry-operator-system
```

### Operator CRDs

| CRD | Purpose |
|-----|---------|
| `OpenTelemetryCollector` | Managed Collector instances |
| `Instrumentation` | Auto-instrumentation configs |
| `Telemetry` | Collector telemetry settings |

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────────────┐
│  Production OTel Architecture                                       │
│                                                                      │
│  App (auto-injected) ──▶ OTel Agent ──┐                            │
│  App (auto-injected) ──▶ OTel Agent ──┼──▶ OTel Gateway ──▶ Backend │
│  App (auto-injected) ──▶ OTel Agent ──┤     │                       │
│  App (auto-injected) ──▶ OTel Agent ──┘     │                       │
│                                             ▼                       │
│                                      Prometheus (metrics)            │
│                                      Loki (logs)                      │
│                                      Tempo (traces)                  │
│                                                                      │
│  OTel Operator ──▶ Admission Webhook ──▶ Inject auto-instrumentation│
└─────────────────────────────────────────────────────────────────────┘
```
