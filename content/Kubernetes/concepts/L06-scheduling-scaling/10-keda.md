# KEDA (Kubernetes Event-Driven Autoscaling)

*"https://keda.sh/"*

KEDA is an **event-driven autoscaler** for Kubernetes. It extends HPA with **scalers** that can watch external sources — Kafka lag, RabbitMQ queue depth, SQS message count, Redis lists, Prometheus metrics, cron schedules, and 60+ others. KEDA scales a Deployment / StatefulSet / Job from zero to N replicas based on the source's metric, and back to zero when there's no work.

### Table of Contents

1. [What KEDA Solves](#1-what-keda-solves)
2. [Architecture and Components](#2-architecture-and-components)
3. [The ScaledObject Resource](#3-the-scaledobject-resource)
4. [The ScaledJob Resource](#4-the-scaledjob-resource)
5. [The Scalers Catalog](#5-the-scalers-catalog)
6. [TriggerAuth and Authentication](#6-triggerauth-and-authentication)
7. [Scaling to Zero and From Zero](#7-scaling-to-zero-and-from-zero)
8. [Fallback and HPA Coexistence](#8-fallback-and-hpa-coexistence)
9. [Common Patterns](#9-common-patterns)
10. [Custom Scalers](#10-custom-scalers)
11. [Operations and Debugging](#11-operations-and-debugging)
12. [Gotchas and Common Mistakes](#12-gotchas-and-common-mistakes)

---

## 1. What KEDA Solves

HPA scales on **k8s metrics** (CPU, memory, custom metrics). But many real workloads are driven by **external signals** that HPA can't see:

* A **Kafka consumer** that should scale on consumer lag.
* A **SQS worker** that should scale on message count.
* A **RabbitMQ consumer** that should scale on queue depth.
* A **cron job** that should run at a specific time.
* A **Prometheus alert** that says "the DB connection pool is saturated, scale up".
* A **Redis list** that should be processed by a worker pool.

KEDA plugs into HPA. You write a `ScaledObject` (or `ScaledJob`), and KEDA:

1. Watches the external source via a **scaler**.
2. Computes the desired replica count.
3. Writes the desired replicas to HPA via the **custom metrics API**.
4. HPA scales the Deployment.
5. When the source is "empty" (e.g. Kafka lag = 0), KEDA scales the Deployment to **zero**.

```
   External source                KEDA                              HPA + Deployment
   (Kafka, SQS, …)
        │                          │                                    │
        │  "lag = 5000"            │                                    │
        │ ─────────────────────►   │  ScaledObject watches source      │
        │                          │  Computes desiredReplicas = 5     │
        │                          │ ──────────────────────────────►   │
        │                          │  Writes to external metrics API   │
        │                          │                                    │  HPA scales to 5
        │                          │                                    │
        │  "lag = 0"               │                                    │
        │ ─────────────────────►   │  Computes desiredReplicas = 0     │
        │                          │ ──────────────────────────────►   │
        │                          │                                    │  HPA scales to 0
        │                          │                                    │
```

## 2. Architecture and Components

KEDA has three components:

```
┌────────────────────────────────────────────────────────────┐
│  keda-operator (Deployment, leader-elected)                │
│                                                            │
│  - Watches ScaledObject, ScaledJob, TriggerAuthentication  │
│  - Manages HPA objects (creates them)                      │
│  - Validates trigger configs                               │
└────────────────────────────────────────────────────────────┘
┌────────────────────────────────────────────────────────────┐
│  keda-metrics-apiserver (Deployment)                       │
│                                                            │
│  - Custom + External metrics API server                    │
│  - HPA queries this for the "scaled metric"                │
│  - Implements the k8s custom-metrics API                   │
└────────────────────────────────────────────────────────────┘
┌────────────────────────────────────────────────────────────┐
│  keda-admission-webhooks (Deployment)                      │
│                                                            │
│  - Validates ScaledObject / ScaledJob on creation          │
│  - Defaults fields                                          │
└────────────────────────────────────────────────────────────┘
```

The operator and metrics server are the two most important. The admission webhook is optional but recommended.

### 2.1 KEDA + HPA

KEDA **creates and manages an HPA** for each `ScaledObject`. You don't write the HPA — KEDA does. The HPA:

* Targets the Deployment you specify.
* Has the min / max replicas you specify.
* Has the custom metric you specify (KEDA's metric).

You can also have an HPA already (in "fallback" mode — see section 8). KEDA can take over when an external source is active, and back off to the existing HPA when it's not.

## 3. The ScaledObject Resource

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: kafka-consumer
  namespace: default
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: kafka-consumer
  pollingInterval: 30           # how often KEDA checks the source (seconds)
  cooldownPeriod: 300           # how long to wait before scaling to zero (seconds)
  idleReplicaCount: 0           # when source is "empty", scale to this
  minReplicaCount: 0            # also the floor
  maxReplicaCount: 100
  fallback:                     # fallback if the external source is unreachable
    failureThreshold: 3
    replicas: 6
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        scaleDown:
          stabilizationWindowSeconds: 300
  triggers:
  - type: kafka
    metadata:
      bootstrapServers: kafka.svc:9092
      consumerGroup: my-consumer
      lagThreshold: "100"       # 100 lag = 1 replica (formula below)
      offsetResetPolicy: earliest
    authenticationRef:
      name: kafka-auth          # TriggerAuthentication
```

This ScaledObject:

* Watches the `kafka-consumer` Deployment.
* Checks Kafka lag every 30s.
* When lag = 0, scales to 0 replicas.
* When lag > 100, scales up (lag / 100 = replicas, capped at 100).
* After 5 min of no activity, scales to 0.
* If Kafka is unreachable for 3 checks, falls back to 6 replicas.

### 3.1 The `lagThreshold` formula

`lagThreshold` is the **lag per replica**. The formula:

```
desiredReplicas = ceil(currentLag / lagThreshold)
```

* `lag = 50, lagThreshold = 100` → 1 replica
* `lag = 500, lagThreshold = 100` → 5 replicas
* `lag = 0, lagThreshold = 100` → 0 replicas (if `minReplicaCount: 0`)

### 3.2 The `activationLagThreshold`

For scaling **from zero**, you can set a different threshold:

```yaml
triggers:
- type: kafka
  metadata:
    lagThreshold: "100"
    activationLagThreshold: "1"   # need at least 1 lag to scale from 0
```

`activationLagThreshold` is the **minimum value to scale from zero**. If lag = 0.5 (less than 1), KEDA stays at 0. If lag = 1.5, KEDA scales up to 1 replica.

This is a way to **debounce** scale-from-zero — a small spike doesn't trigger a cold start.

## 4. The ScaledJob Resource

For **Jobs** (one-shot work, not a long-running Deployment), use `ScaledJob`:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledJob
metadata:
  name: sqs-worker
  namespace: default
spec:
  jobTargetRef:
    template:
      spec:
        containers:
        - name: worker
          image: my-worker:1.0
        restartPolicy: Never
        completionMode: Indexed
        completions: 1
        parallelism: 1
  pollingInterval: 30
  successfulJobsHistoryLimit: 5
  failedJobsHistoryLimit: 5
  maxReplicaCount: 50
  triggers:
  - type: aws-sqs-queue
    metadata:
      queueURL: https://sqs.us-east-1.amazonaws.com/123456789012/my-queue
      queueLength: "5"            # 5 messages per replica
      activationQueueLength: "1"
      awsRegion: us-east-1
    authenticationRef:
      name: aws-auth
```

A ScaledJob:

* Creates Jobs based on the source metric.
* Each Job processes some work (`queueLength` items per replica).
* When the queue is empty, no new Jobs are created.

**ScaledJob is different from a Deployment HPA**: it's about **batch processing** (one Job per replica), not **long-running services**.

## 5. The Scalers Catalog

KEDA has **60+ built-in scalers**. The full list is in the [KEDA docs](https://keda.sh/docs/latest/scalers/). Common ones:

### 5.1 Messaging

| Scaler | What it scales on |
|---|---|
| `kafka` | Consumer lag (per topic / partition) |
| `rabbitmq-queue` | Queue depth |
| `aws-sqs-queue` | SQS message count |
| `aws-kinesis-stream` | Stream iterator age |
| `azure-servicebus` | Queue or topic message count |
| `gcp-pubsub` | Subscription backlog |
| `nats-jetstream` | Consumer lag |
| `pulsar` | Backlog size |

### 5.2 Databases and caches

| Scaler | What it scales on |
|---|---|
| `redis` | List length, sorted set cardinality, stream length |
| `mysql` | Query result (e.g. `SELECT COUNT(*) FROM jobs WHERE pending=1`) |
| `postgresql` | Query result |
| `mongodb` | Collection document count |
| `elasticsearch` | Search query backlog |

### 5.3 Metrics and observability

| Scaler | What it scales on |
|---|---|
| `prometheus` | Any Prometheus query result |
| `datadog` | Datadog metric value |
| `influxdb` | InfluxDB query result |
| `stackdriver` | GCP Cloud Monitoring metric |

### 5.4 Cloud-specific

| Scaler | What it scales on |
|---|---|
| `aws-cloudwatch` | CloudWatch alarm state / metric |
| `aws-dynamodb` | Table item count |
| `aws-dynamodb-streams` | Stream iterator age |
| `aws-kinesis-stream` | Iterator age |
| `azure-blob` | Container blob count |
| `azure-eventhub` | Event Hub consumer group lag |
| `gcp-storage` | GCS object count |

### 5.5 Cron and rate

| Scaler | What it scales on |
|---|---|
| `cron` | Schedule (scale up at X, scale down at Y) |
| `rate` | Static rate (e.g. 10 messages/sec) |

### 5.6 The `cron` scaler

```yaml
triggers:
- type: cron
  metadata:
    timezone: America/New_York
    start: 0 9 * * *        # 9am EST
    end: 0 17 * * *         # 5pm EST
    desiredReplicas: "10"
```

Scale to 10 replicas from 9am to 5pm, then back to 0. Useful for business-hours workloads.

## 6. TriggerAuth and Authentication

Many scalers need credentials. KEDA uses `TriggerAuthentication` (namespaced) and `ClusterTriggerAuthentication` (cluster-wide):

```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: kafka-auth
  namespace: default
spec:
  secretTargetRef:
  - parameter: sasl          # the auth parameter in the scaler
    name: kafka-credentials
    key: username
  - parameter: username
    name: kafka-credentials
    key: username
  - parameter: password
    name: kafka-credentials
    key: password
```

```yaml
# In the ScaledObject
triggers:
- type: kafka
  metadata:
    bootstrapServers: kafka.svc:9092
    consumerGroup: my-consumer
    lagThreshold: "100"
  authenticationRef:
    name: kafka-auth
```

The ScaledObject references the TriggerAuthentication. KEDA passes the credentials to the scaler when querying the source.

**ClusterTriggerAuthentication** is the same but for cluster-wide use:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ClusterTriggerAuthentication
metadata:
  name: aws-shared
spec:
  secretTargetRef:
  - parameter: awsAccessKeyID
    name: aws-credentials
    key: access-key
  - parameter: awsSecretAccessKey
    name: aws-credentials
    key: secret-key
```

```yaml
# In the ScaledObject
triggers:
- type: aws-sqs-queue
  authenticationRef:
    name: aws-shared
    kind: ClusterTriggerAuthentication
```

## 7. Scaling to Zero and From Zero

KEDA's killer feature: **scale to zero when there's no work, scale up when work appears**.

### 7.1 The `idleReplicaCount` and `minReplicaCount`

```yaml
spec:
  minReplicaCount: 0    # the floor — KEDA can scale to 0
  idleReplicaCount: 0   # when the source is "empty", scale to this
```

If both are 0, KEDA scales to 0 when the source is empty (e.g. Kafka lag = 0).

`minReplicaCount: 1` means KEDA never goes below 1 replica. The Deployment is always running.

### 7.2 The cold start

When scaling from 0, KEDA has to **start a Pod**. This takes time:

* Image pull (10-30s if cached, 1-2 min if not).
* Container start (1-5s).
* Readiness probe (5-10s).
* Service routing update (5-10s).

Total: **5-30s** typically. **The first request after a scale-to-zero incurs this latency.** Plan for it.

### 7.3 The `cooldownPeriod`

```yaml
spec:
  cooldownPeriod: 300     # wait 5 min of "empty" before scaling to 0
```

After the source goes empty, KEDA waits `cooldownPeriod` seconds before scaling to 0. This prevents **scale-to-zero thrashing** — a brief gap in messages doesn't kill the Pods.

### 7.4 The `pollingInterval`

```yaml
spec:
  pollingInterval: 30     # check the source every 30s
```

How often KEDA queries the source. Higher = less load on the source, slower reaction. Lower = more load, faster reaction.

For most workloads, 30s is a good default. For latency-sensitive workloads, 5-10s.

## 8. Fallback and HPA Coexistence

KEDA can **fall back** to a fixed replica count if the external source is unreachable:

```yaml
spec:
  fallback:
    failureThreshold: 3     # 3 failed checks = fallback
    replicas: 6
```

If KEDA can't reach Kafka (or whatever) for 3 consecutive checks, it scales the Deployment to 6 replicas. This is a safety net — you don't lose all your replicas because of a transient source outage.

### 8.1 KEDA + existing HPA

KEDA can coexist with an existing HPA on the same Deployment. The pattern:

* The existing HPA scales on CPU (or another k8s metric).
* KEDA scales on the external source.
* **KEDA's HPA takes priority** when the source is active.
* The existing HPA takes over when the source is empty (KEDA scales to 0, but the other HPA might keep 1+ replicas).

This is the **"HPA with external metrics" pattern**. KEDA implements the external metrics API.

```yaml
# Existing HPA
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: web-cpu }
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: web }
  minReplicas: 1
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
---
# KEDA ScaledObject
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata: { name: web-keda }
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: web }
  minReplicaCount: 0
  maxReplicaCount: 100
  triggers:
  - type: kafka
    metadata: { ... }
```

**Only one HPA actually drives the replicas at a time.** KEDA's HPA "wins" when the source has data; the CPU HPA wins when KEDA is at zero or the source is empty.

## 9. Common Patterns

### 9.1 Kafka consumer with lag-based scaling

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata: { name: kafka-worker }
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: kafka-worker }
  pollingInterval: 15
  cooldownPeriod: 60
  minReplicaCount: 0
  maxReplicaCount: 50
  triggers:
  - type: kafka
    metadata:
      bootstrapServers: kafka.svc.cluster.local:9092
      consumerGroup: my-group
      lagThreshold: "50"
      activationLagThreshold: "1"
      offsetResetPolicy: earliest
```

50 lag per replica. Scale from 0 when lag ≥ 1.

### 9.2 SQS batch processor

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledJob
metadata: { name: sqs-processor }
spec:
  jobTargetRef:
    template:
      spec:
        restartPolicy: Never
        containers:
        - name: worker
          image: my-worker:1.0
          env:
          - name: QUEUE_URL
            value: https://sqs.us-east-1.amazonaws.com/123/my-queue
  pollingInterval: 20
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  maxReplicaCount: 30
  triggers:
  - type: aws-sqs-queue
    metadata:
      queueURL: https://sqs.us-east-1.amazonaws.com/123/my-queue
      queueLength: "5"
      awsRegion: us-east-1
    authenticationRef: { name: aws-auth }
```

5 messages per Job. Max 30 parallel Jobs.

### 9.3 Prometheus-driven scaling

```yaml
triggers:
- type: prometheus
  metadata:
    serverAddress: http://prometheus.monitoring.svc:9090
    query: |
      sum(rate(http_requests_total{status="500"}[5m]))
    threshold: "0.1"
    activationThreshold: "0.05"
```

Scale on the rate of 500 errors. When error rate is high, scale up.

### 9.4 Cron-scheduled worker

```yaml
triggers:
- type: cron
  metadata:
    timezone: UTC
    start: 0 2 * * *       # 2am
    end: 0 4 * * *         # 4am
    desiredReplicas: "20"
```

Scale to 20 replicas at 2am, scale to 0 at 4am. Run a nightly batch.

## 10. Custom Scalers

If a built-in scaler doesn't fit, you can write your own. The `keda-metrics-apiserver` exposes the `keda.sh/v1alpha1.ExternalMetric` API. A custom scaler is a **gRPC server** that:

* Receives a `GetMetricsRequest` with the trigger metadata.
* Queries the external source.
* Returns a `GetMetricsResponse` with the metric value.

The gRPC server is a separate deployment (your code). KEDA's `external scaler` type references it:

```yaml
triggers:
- type: external
  metadata:
    scalerAddress: my-custom-scaler.default.svc:50051
    metricName: my-metric
    threshold: "100"
    query: some-query-string
```

Custom scalers are an advanced pattern. For most needs, the 60+ built-in scalers are enough.

## 11. Operations and Debugging

### 11.1 Common commands

```bash
# list ScaledObjects
kubectl get scaledobject -A

# describe
kubectl describe scaledobject <name>
# shows the HPA, the trigger, the current metric value

# check the operator
kubectl -n keda get pods -l app=keda-operator
kubectl -n keda logs -l app=keda-operator --tail=100

# check the metrics server
kubectl -n keda get pods -l app=keda-metrics-apiserver
kubectl -n keda logs -l app=keda-metrics-apiserver --tail=100

# check the HPA that KEDA created
kubectl get hpa -A
# the HPA has ownerReference to the ScaledObject
```

### 11.2 The "KEDA not scaling" checklist

```bash
# 1. Is the ScaledObject valid?
kubectl describe scaledobject <name>
# look at Status.Conditions

# 2. Is the trigger working?
kubectl -n keda logs -l app=keda-metrics-apiserver --tail=100
# look for "GetMetrics" entries

# 3. Is the HPA reading the right metric?
kubectl get hpa <name> -o yaml
# look at spec.metrics[].external.metric.name

# 4. Can the source be reached?
# test from inside the cluster
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- bash
# inside: nc -zv kafka.svc 9092

# 5. Are the credentials right?
kubectl get triggerauthentication -A
# verify the Secret exists and has the right keys
```

### 11.3 The "scale to zero stuck" case

If KEDA isn't scaling to 0 when the source is empty:

```bash
# check the cooldown period
kubectl get scaledobject <name> -o jsonpath='{.spec.cooldownPeriod}'
# 300 = 5 min default

# check the source metric
kubectl describe scaledobject <name>
# look at the "Active" status — if true, KEDA sees data

# check the HPA's desired replicas
kubectl get hpa <name>
# if desiredReplicas > 0, KEDA's HPA isn't at zero
```

## 12. Gotchas and Common Mistakes

### 12.1 The 25+ common mistakes

1. **KEDA's HPA is created automatically.** Don't write a separate HPA for the same Deployment + same metric.

2. **`minReplicaCount: 0` is the scale-to-zero opt-in.** Without it, KEDA won't scale below the existing replica count.

3. **`cooldownPeriod` is per-ScaledObject.** A common mistake: setting it to 0 and getting scale-to-zero thrashing.

4. **`pollingInterval` adds latency.** Lower = faster reaction but more load on the source. 30s is a good default.

5. **The `lagThreshold` is per replica, not the absolute value.** `lagThreshold: 100` means 1 replica per 100 lag.

6. **The `activationLagThreshold` is the "scale from zero" threshold.** Without it, any small lag value scales up from zero.

7. **KEDA needs the metrics-server to be running** (or its own metrics server). Without it, the HPA can't get metrics.

8. **KEDA's metrics server is on port 9022** (or whatever you configure). The HPA needs to be able to reach it.

9. **The `TriggerAuthentication` is namespaced.** A `TriggerAuthentication` in `ns-a` can't be used in `ns-b`. Use `ClusterTriggerAuthentication` for cluster-wide.

10. **ScaledJob is for batch processing.** Don't use it for long-running services — use ScaledObject.

11. **ScaledJob's `completions` and `parallelism` are per-Job.** The number of Jobs is `replicas` (driven by the metric). Each Job runs `completions` iterations.

12. **The cron scaler uses the controller's timezone.** Default is UTC. Set `timezone: America/New_York` for EST.

13. **The Prometheus scaler queries the Prometheus server directly.** The Prometheus server must be reachable from the keda-metrics-apiserver.

14. **KEDA's fallback only triggers on a *consecutive* failure threshold.** A single failed check doesn't trigger fallback.

15. **KEDA + HPA on the same metric is fine, KEDA + VPA on the same metric fights.** Pick one.

16. **KEDA's `ScaledObject` doesn't manage the Deployment.** It only creates an HPA. The Deployment must be created separately.

17. **KEDA's `pollingInterval` is for the source query, not the HPA poll.** The HPA's `--horizontal-pod-autoscaler-sync-period` (default 15s) is separate.

18. **A `ScaledObject` in a namespace with a `NetworkPolicy` that blocks egress to the source won't work.** The metrics-apiserver can't reach Kafka / SQS / etc.

19. **KEDA's metrics server implements the k8s custom-metrics API.** It's not a Prometheus adapter — you can't use it for general custom metrics.

20. **The `aws-sqs-queue` scaler polls SQS every `pollingInterval`.** SQS has a `GetQueueAttributes` rate limit (cheap, but not free). Lower pollingInterval = more API calls.

21. **KEDA's `cooldownPeriod` is the "after empty" delay.** If lag drops to 0 at T=0, KEDA scales to 0 at T=cooldownPeriod.

22. **KEDA doesn't restart Pods.** It changes the replica count. The Deployment / StatefulSet controller does the rest.

23. **A ScaledObject with `maxReplicaCount: 0`** means KEDA can never scale up. (Why would you do this? Don't.)

24. **KEDA's `external` scaler requires a gRPC server.** Not a REST API. The gRPC server must implement the `ExternalScaler` interface.

25. **KEDA's metrics are NOT the same as HPA's resource metrics.** They're external metrics, exposed via a different API path.

26. **KEDA's operator creates one HPA per ScaledObject.** Multiple ScaledObjects on the same Deployment create multiple HPAs. The last one wins (or the highest replica count).

27. **KEDA doesn't manage `kube-system` Pods by default.** The `ScaledObject` for a Deployment in `kube-system` works, but ensure the operator has permission (ClusterRole).

28. **KEDA's `idempotency` for HPA management** means the operator is the source of truth. Don't edit the HPA directly — KEDA will revert your changes.

29. **KEDA's logs are usually at `kubectl -n keda logs -l app=keda-operator -f`.** Tail them while scaling to see the trigger value, the computed replicas, and the HPA update.

30. **KEDA's `pollingInterval` of 0 is not allowed** — it would busy-loop. Minimum is 1 second.

## See also

* [[Kubernetes/concepts/L06-scheduling-scaling/03-horizontalpodautoscaler|HPA]] — the underlying autoscaler KEDA extends
* [[Kubernetes/concepts/L06-scheduling-scaling/05-scaling|Scaling]] — L06 overview
* [[Kubernetes/concepts/L06-scheduling-scaling/07-vertical-pod-autoscaler|VPA]] — the vertical counterpart
* [[Kubernetes/concepts/L06-scheduling-scaling/08-karpenter|Karpenter]] — node autoscaling
