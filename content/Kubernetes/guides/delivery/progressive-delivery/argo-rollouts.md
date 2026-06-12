---
title: Argo Rollouts
tags:
  - Kubernetes
  - Delivery
  - Progressive-Delivery
  - Argo Rollouts
  - Canary
  - Blue-Green
---

Argo Rollouts is a **drop-in replacement for Deployments** that supports advanced deployment strategies: canary, blue-green, traffic shifting, and analysis. The controller watches the Rollout resource, manages ReplicaSets, and shifts traffic via Ingress / Service Mesh / Gateway API.

## Why not just Deployments

Deployments do **rolling update**: kill old, start new, in batches. Works for most cases. But:

- All-or-nothing per replica set
- No traffic shifting (only readiness gates)
- No automatic rollback on bad metrics
- No pause for manual approval
- No A/B testing

**Argo Rollouts solves all of this** while still being a k8s resource (CRD, declarative, GitOps-friendly).

## The strategies

### Rolling update (default, like Deployment)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: my-app
spec:
  replicas: 5
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: myregistry/myapp:v1
```

Same as Deployment. Use this if you don't need the advanced features.

### Canary

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: my-app
spec:
  replicas: 10
  strategy:
    canary:
      steps:
      - setWeight: 5         # 5% to new version
      - pause: {duration: 5m}
      - setWeight: 20
      - pause: {duration: 5m}
      - setWeight: 50
      - pause: {duration: 5m}
      - setWeight: 100
      canaryService: my-app-canary
      stableService: my-app-stable
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: myregistry/myapp:v2
```

**Canary flow:**
1. New ReplicaSet created with v2
2. 5% traffic shifts to v2 (rest to v1)
3. Pause 5 minutes (monitor)
4. 20% traffic to v2
5. Pause 5 minutes
6. 50% → 100%
7. Old v1 ReplicaSet scaled to 0

**Two Services** are required: `my-app-stable` (v1 traffic) and `my-app-canary` (v2 traffic). The Rollout controller updates the weights.

### Blue-green

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: my-app
spec:
  replicas: 5
  strategy:
    blueGreen:
      activeService: my-app-active
      previewService: my-app-preview
      autoPromotionEnabled: false
      scaleDownDelaySeconds: 30
      previewReplicaCount: 100%   # run preview at full replicas
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: myregistry/myapp:v2
```

**Blue-green flow:**
1. New ReplicaSet created with v2 (green)
2. `my-app-preview` Service routes to green
3. `my-app-active` still routes to blue (v1)
4. You test green via preview Service
5. Promote: switch active to green, scale down blue

**Auto-promotion:** set `autoPromotionEnabled: true` to skip the manual step (less safe).

## Traffic providers

The Rollout controller needs a way to shift traffic. Pick one:

### 1. Service-based (no mesh, basic)

```yaml
strategy:
  canary:
    canaryService: my-app-canary
    stableService: my-app-stable
    trafficRouting:
      # default — service selector
```

**How it works:** both Services exist, Rollout updates the selector to point to the new ReplicaSet (or splits via pod count).

**Limitation:** not actual weight-based splitting. L4 load balancing, not L7.

### 2. NGINX Ingress

```yaml
strategy:
  canary:
    canaryService: my-app-canary
    stableService: my-app-stable
    trafficRouting:
      nginx:
        additionalIngressAnnotations:
          canary-by-header: X-Canary
          canary-by-header-value: enroll
        stableIngress: my-app-stable
        additionalMatchAnnotations:
          canary: "true"
```

Requires `nginx.ingress.kubernetes.io/canary-weight` annotations on Ingresses.

### 3. Istio

```yaml
strategy:
  canary:
    trafficRouting:
      istio:
        virtualService:
          name: my-app-vsvc
        destinationRule:
          name: my-app-destrule
```

**Most powerful.** Istio handles L7 traffic splitting, retries, header-based routing.

### 4. AWS Load Balancer Controller

```yaml
strategy:
  canary:
    trafficRouting:
      alb:
        ingress: my-app-ingress
        servicePort: 80
        rootService: my-app-stable
```

ALB target group weight-based splitting.

### 5. Gateway API

```yaml
strategy:
  canary:
    trafficRouting:
      gatewayApi:
        # assumes HTTPRoute
```

For Gateway API-based ingresses (Contour, Envoy Gateway, Istio).

### 6. SMI (Service Mesh Interface)

```yaml
strategy:
  canary:
    trafficRouting:
      smi:
        # for Linkerd, Consul Connect
```

### 7. Traefik

```yaml
strategy:
  canary:
    trafficRouting:
      traefik:
        # for Traefik ingress
```

## Analysis templates (automated rollback)

The killer feature. Argo Rollouts can query metrics and **automatically roll back** on bad signals.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate
spec:
  args:
  - name: service-name
  metrics:
  - name: success-rate
    interval: 30s
    count: 5
    successCondition: result[0] >= 0.95
    failureCondition: result[0] < 0.95
    provider:
      prometheus:
        address: http://prometheus.monitoring:9090
        query: |
          sum(rate(
            http_requests_total{service="{{args.service-name}}",status!~"5.."}[2m]
          )) /
          sum(rate(
            http_requests_total{service="{{args.service-name}}"}[2m]
          ))
  - name: latency
    interval: 30s
    count: 5
    successCondition: result[0] <= 0.5
    failureCondition: result[0] > 0.5
    provider:
      prometheus:
        address: http://prometheus.monitoring:9090
        query: |
          histogram_quantile(0.99,
            sum(rate(
              http_request_duration_seconds_bucket{service="{{args.service-name}}"}[2m]
            )) by (le)
          )
```

**Use in a Rollout:**

```yaml
strategy:
  canary:
    steps:
    - setWeight: 10
    - pause: {duration: 5m}
    - analysis:
        templates:
        - templateName: success-rate
        args:
        - name: service-name
          value: my-app
    - setWeight: 50
    - pause: {duration: 5m}
    - analysis:
        templates:
        - templateName: success-rate
        - templateName: latency
        args:
        - name: service-name
          value: my-app
    - setWeight: 100
```

**Flow:**
1. 10% to v2
2. Pause 5 min
3. Run analysis (success-rate)
4. If success: continue. If fail: abort, rollback.
5. 50% to v2
6. Pause 5 min
7. Run analysis (success-rate + latency)
8. 100% to v2

## Analysis providers

### Prometheus

```yaml
provider:
  prometheus:
    address: http://prometheus.monitoring:9090
    query: |
      sum(rate(http_requests_total{status="500"}[5m]))
```

Most common. Query Prometheus, get a value, compare against conditions.

### Datadog

```yaml
provider:
  datadog:
    address: https://api.datadoghq.com
    apiKeySecret:
      name: datadog-secret
      key: api-key
    appKeySecret:
      name: datadog-secret
      key: app-key
    query: |
      sum:myapp.request.success_rate
    interval: 5m
```

### CloudWatch

```yaml
provider:
  cloudwatch:
    region: us-east-1
    interval: 60s
    metrics:
    - name: 5xxRate
      metricDataQueries:
      - id: e1
        metricStat:
          metric:
            namespace: "MyApp"
            metricName: "5xxCount"
            dimensions:
            - name: Service
              value: "my-app"
          period: 60
          stat: Sum
```

### New Relic

```yaml
provider:
  newrelic:
    region: US   # US or EU
    apiKeySecret:
      name: newrelic-secret
      key: api-key
    query: |
      SELECT percentage(count(*), WHERE httpResponseCode LIKE '5%') FROM Transaction
      WHERE appName='my-app'
```

### Wavefront

### Kayenta (judge-based)

For multi-metric scoring:

```yaml
provider:
  kayenta:
    address: http://kayenta.default:8080
    configRef:
      name: my-kayenta-config
```

Uses Kayenta to compare canary vs. baseline. ML-based.

## Manual gates

For "human in the loop":

```yaml
steps:
- setWeight: 50
- pause: {}
```

`pause: {}` waits indefinitely. Resume with:

```bash
kubectl argo rollouts promote my-app
```

Or abort:

```bash
kubectl argo rollouts abort my-app
```

## Auto-rollback

```yaml
spec:
  strategy:
    canary:
      # ... steps
  rollback:
    revisionHistoryLimit: 5
```

If the rollout fails, controller rolls back to the previous ReplicaSet.

You can also manually rollback:

```bash
kubectl argo rollouts undo my-app
```

## Header-based routing (canary by header)

Useful for A/B testing or testing canary with specific users.

```yaml
strategy:
  canary:
    canaryService: my-app-canary
    stableService: my-app-stable
    trafficRouting:
      nginx:
        additionalIngressAnnotations:
          canary-by-header: X-Canary
          canary-by-header-value: enroll
```

Now users with `X-Canary: enroll` header get the canary. Others get stable.

## The kubectl plugin

```bash
# install
curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-darwin-amd64
chmod +x kubectl-argo-rollouts-darwin-amd64
sudo mv kubectl-argo-rollouts-darwin-amd64 /usr/local/bin/kubectl-argo-rollouts

# usage
kubectl argo rollouts get rollout my-app
kubectl argo rollouts status my-app
kubectl argo rollouts promote my-app
kubectl argo rollouts abort my-app
kubectl argo rollouts retry my-app
kubectl argo rollouts undo my-app

# real-time dashboard
kubectl argo rollouts dashboard
```

## The dashboard

```bash
kubectl argo rollouts dashboard
```

Browser UI showing:
- Active rollouts
- ReplicaSet status
- Step progress
- Analysis results
- Promote / abort buttons

## A/B testing with multiple branches

```yaml
strategy:
  canary:
    steps:
    - setWeight: 50
    - pause: {duration: 30m}
    abortScaleDownDelaySeconds: 30
    canaryService: my-app-canary
    stableService: my-app-stable
    trafficRouting:
      nginx:
        additionalIngressAnnotations:
          canary-by-header: X-Experiment
          canary-by-header-value: variant-a
```

Users with `X-Experiment: variant-a` get canary. Compare metrics.

## Integration with GitOps

Argo Rollouts is just k8s resources. Argo CD reconciles them.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: my-app
  annotations:
    argocd.argoproj.io/sync-wave: "2"   # apply after Service
```

The image tag in the Rollout is updated by CI (or Image Updater), GitOps syncs, Rollout rolls out.

## Common gotchas

* **Two Services are required** for canary (`canaryService` and `stableService`). One Service can only point to one ReplicaSet.
* **Ingress controllers differ in canary support.** NGINX has `canary-weight`, Traefik has weighted middlewares, Istio has VS.
* **Analysis requires metrics** — Prometheus (or other provider) must be installed and the metrics must exist.
* **`pause: {}` (indefinite) is a footgun.** Use `pause: {duration: "30m"}` with a real timeout, or you'll never auto-resume.
* **The `replicas` field in the Rollout is the total desired.** Not per-ReplicaSet.
* **When changing strategy mid-rollout,** the rollout may abort. Plan the migration.
* **MaxSurge/MaxUnavailable don't apply** to canary/blue-green the same way. The Rollout controller manages replica counts.
* **Aborted rollouts don't undo automatically** — you may need to `undo` to revert to a known good state.
* **Analysis templates are global.** One template, many Rollouts.
* **Each `setWeight` step** creates new pods. The weight is L7 (Istio, etc.) or approximate (Service-based).
* **Service-based traffic routing is "best effort."** Not real L7 weighting.
* **The Rollout controller itself is a SPOF.** Run it HA (2+ replicas).
* **Active rollouts consume resources** (pods of both versions). For big rollouts, plan capacity.

## A worked example

**Goal:** canary deploy a web service with auto-rollback if error rate exceeds 5%.

**Setup:**

1. Install Argo Rollouts controller
2. Install Prometheus
3. Configure Service-based routing (or Istio)
4. Define AnalysisTemplate
5. Define Rollout

**The Rollout:**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: web
  namespace: prod
spec:
  replicas: 10
  revisionHistoryLimit: 3
  selector:
    matchLabels:
      app: web
  strategy:
    canary:
      canaryService: web-canary
      stableService: web-stable
      maxSurge: 25%
      maxUnavailable: 0
      steps:
      - setWeight: 5
      - pause: {duration: 2m}
      - setWeight: 25
      - pause: {duration: 2m}
      - analysis:
          templates:
          - templateName: error-rate-check
          args:
          - name: service-name
            value: web
      - setWeight: 50
      - pause: {duration: 5m}
      - setWeight: 100
      - pause: {duration: 1m}
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: web
        image: myregistry/web:v1
        ports:
        - containerPort: 8080
        readinessProbe:
          httpGet:
            path: /healthz
            port: 8080
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
```

**The Services:**

```yaml
# stable
apiVersion: v1
kind: Service
metadata:
  name: web-stable
  namespace: prod
spec:
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 8080

---
# canary
apiVersion: v1
kind: Service
metadata:
  name: web-canary
  namespace: prod
spec:
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 8080
```

**The AnalysisTemplate:**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: error-rate-check
  namespace: prod
spec:
  args:
  - name: service-name
  metrics:
  - name: error-rate
    interval: 30s
    count: 5
    successCondition: result[0] < 0.05
    failureCondition: result[0] >= 0.05
    provider:
      prometheus:
        address: http://prometheus.monitoring:9090
        query: |
          sum(rate(
            http_requests_total{service="{{args.service-name}}",status=~"5.."}[2m]
          )) /
          sum(rate(
            http_requests_total{service="{{args.service-name}}"}[2m]
          ))
```

**Trigger a rollout:**

```bash
# change image in the Rollout
kubectl argo rollouts set image web web=myregistry/web:v2
```

**Or via GitOps:** update the image tag in git, commit, sync.

**Monitor:**

```bash
kubectl argo rollouts get rollout web --watch
```

## See also

* [[Kubernetes/guides/delivery/gitops/basics|gitops-basics]] — Rollouts live in GitOps
* [[Kubernetes/guides/delivery/pipeline-workflows/argo-workflows|argo-workflows]] — CI for image builds
* [[Kubernetes/guides/non-functional/chaos-engineering|chaos-engineering]] — break things safely
* [Argo Rollouts docs](https://argoproj.github.io/argo-rollouts/)
