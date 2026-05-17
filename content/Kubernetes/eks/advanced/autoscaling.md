---
title: Advanced Autoscaling
tags: [eks, advanced, autoscaling, hpa, vpa, keda]
date: 2026-05-17
description: Advanced autoscaling options for EKS workloads
---

# Advanced Autoscaling on EKS

## Autoscaling Options

| Type | What It Scales | Metric Source |
|------|---------------|---------------|
| HPA | Pods | Custom metrics |
| VPA | Pod resources | Resource usage |
| KEDA | Pods + Workers | 50+ external sources |
| Cluster Proportional VPA | Nodes | Pod count |
| Karpenter | Nodes | Pending pods |

## Horizontal Pod Autoscaler (HPA)

### Custom Metrics HPA

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Pods
    pods:
      metric:
        name: http_requests_per_second
      target:
        type: AverageValue
        averageValue: "100"
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60
```

### HPA with Prometheus Metrics

```bash
# Install Prometheus adapter
helm install prometheus-adapter prometheus-community/prometheus-adapter \
  --namespace monitoring \
  --set prometheus.url=http://prometheus-server \
  --set prometheus.port=9090
```

## Vertical Pod Autoscaler (VPA)

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: my-app-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  updatePolicy:
    updateMode: "Auto"
  resourcePolicy:
    containerPolicies:
    - containerName: app
      minAllowed:
        cpu: 100m
        memory: 128Mi
      maxAllowed:
        cpu: 2
        memory: 4Gi
      controlledResources: ["cpu", "memory"]
```

## KEDA

### Install KEDA

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

helm install keda kedacore/keda \
  --namespace keda \
  --create-namespace
```

### ScaledObject with Prometheus

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: my-app-scaler
spec:
  scaleTargetRef:
    name: my-app
  minReplicaCount: 2
  maxReplicaCount: 20
  cooldownPeriod: 300
  triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus:9090
      metricName: http_requests_total
      threshold: "100"
      query: sum(rate(http_requests_total[2m]))
```

### KEDA Scalers

| Scaler | Use Case |
|--------|----------|
| prometheus | Metrics-based scaling |
| mysql | Database connection pool |
| redis | Queue length |
| aws-sqs-queue | SQS message count |
| kafka | Topic lag |
| cron | Time-based scaling |
| rabbitmq | Queue depth |

## Cluster Proportional Autoscaler

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-proportional-vertical-autoscaler
  namespace: kube-system
data:
  config: |
    {
      "clusterName": "my-cluster",
      "minReplicaCount": 1,
      "maxReplicaCount": 10,
      "metricsServer": {
        "port": 8080
      },
      "resources": [
        {
          ".namespace": "ingress-nginx",
          "controller": "deployment/ingress-nginx-controller",
          "containerName": "controller",
          "resources": {
            "requests": {
              "cpu": "100m",
              "memory": "128Mi"
            }
          }
        }
      ]
    }
```

## References

- [EKS Workshop - Autoscaling](https://www.eksworkshop.com/docs/fundamentals/workloads/)
- [KEDA Documentation](https://keda.sh/)
- [VPA Documentation](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)