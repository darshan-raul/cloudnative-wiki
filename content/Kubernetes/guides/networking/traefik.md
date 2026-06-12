---
title: Traefik
tags:
  - Kubernetes
  - Networking
  - Ingress
  - Traefik
  - Gateway API
---

Traefik is a **modern reverse proxy and load balancer** that integrates natively with k8s, Docker, and many other backends. It auto-discovers services, supports Ingress, IngressRoute (CRD), and Gateway API, and is the most flexible open-source ingress controller.

## Why Traefik

| Feature | Traefik | NGINX | HAProxy |
|---------|---------|-------|---------|
| **Auto-discovery** | ✅ (k8s, Docker, Consul) | ❌ manual config | ❌ manual config |
| **Ingress support** | ✅ | ✅ | ✅ |
| **Gateway API** | ✅ | ✅ (some) | ❌ |
| **CRD** | IngressRoute | ❌ | ❌ |
| **Let's Encrypt** | ✅ built-in | Manual | Manual |
| **Dashboard** | ✅ | ❌ | ❌ |
| **Metrics** | ✅ Prometheus | ✅ | ✅ |
| **Configuration** | Labels, CRDs | ConfigMap | Config file |
| **Performance** | Good | Excellent | Excellent |

**Traefik shines when:** you have lots of services, want auto-discovery, want Gateway API, want a dashboard.

**NGINX shines when:** you need maximum throughput, battle-tested config, complex rewrites.

## The install

### Helm (recommended)

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
```

```yaml
# values.yaml
ingressClass:
  enabled: true
  name: traefik
  isDefaultClass: true

ports:
  web:
    port: 80
    redirectTo: websecure
  websecure:
    port: 443
    tls:
      enabled: true
      certResolver: letsencrypt

certificatesResolvers:
  letsencrypt:
    acme:
      email: ops@example.com
      storage: /data/acme.json
      httpChallenge:
        entryPoint: web

logs:
  general:
    level: INFO
  access:
    enabled: true

api:
  dashboard: true
  insecure: false

metrics:
  prometheus:
    enabled: true

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 1
    memory: 512Mi

persistence:
  enabled: true
  size: 1Gi
  storageClass: gp3
  accessMode: ReadWriteOnce
```

```bash
helm install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  --values values.yaml
```

### Manifests (quick test)

```bash
kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.0/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml
# CRDs
kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.0/docs/content/reference/dynamic-configuration/kubernetes-auth.yml
# RBAC
kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.0/docs/content/reference/dynamic-configuration/kubernetes-service.yml
# Service + Deployment
```

## The Ingress resource

Traefik supports standard k8s Ingress:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
    traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt
spec:
  ingressClassName: traefik
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
  tls:
  - hosts:
    - app.example.com
```

## The IngressRoute (CRD)

Traefik's custom resource, more powerful than Ingress:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
spec:
  entryPoints:
  - websecure
  routes:
  - match: Host(`app.example.com`) && PathPrefix(`/`)
    kind: Rule
    services:
    - name: my-app
      port: 80
  tls:
    certResolver: letsencrypt
    domains:
    - main: example.com
      sans:
      - "*.example.com"
```

**Why IngressRoute over Ingress:**
- Multiple services per route
- Middlewares per route
- Weighted load balancing
- Mirror services
- Retry policies

### Weighted load balancing

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
spec:
  entryPoints:
  - websecure
  routes:
  - match: Host(`app.example.com`)
    kind: Rule
    services:
    - name: my-app-v1
      port: 80
      weight: 90
    - name: my-app-v2
      port: 80
      weight: 10   # canary
  tls:
    certResolver: letsencrypt
```

**This is the canary pattern.** No need for Argo Rollouts (for HTTP-only canaries).

## Middlewares

Traefik's middlewares are powerful. Common ones:

### Rate limiting

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: rate-limit
spec:
  rateLimit:
    average: 100
    burst: 200
    period: 1m
```

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
spec:
  routes:
  - match: Host(`app.example.com`)
    kind: Rule
    services:
    - name: my-app
      port: 80
    middlewares:
    - name: rate-limit
```

### Authentication (Basic)

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: basic-auth
spec:
  basicAuth:
    users:
    - admin:$apr1$xyz$...    # htpasswd hash
    - alice:$apr1$abc$...
  removeHeader: true
```

### Authentication (Forward / OIDC)

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: oidc-auth
spec:
  forwardAuth:
    address: http://oauth2-proxy.auth:4181/oauth2/auth
    trustForwardHeader: true
    authResponseHeaders:
    - X-Forwarded-User
    - X-Forwarded-Groups
    - X-Forwarded-Email
```

Use with oauth2-proxy or Pomerium for OIDC.

### IP allowlist/blocklist

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: allow-internal
spec:
  ipAllowList:
    sourceRange:
    - 10.0.0.0/8
    - 192.168.0.0/16
    - 172.16.0.0/12
    - 127.0.0.1/32
```

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: block-bad-actors
spec:
  ipDenyList:
    sourceRange:
    - 1.2.3.0/24
    - 5.6.7.0/24
```

### Header manipulation

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: add-headers
spec:
  headers:
    customRequestHeaders:
      X-Request-ID: "{{.RequestId}}"
      X-Forwarded-Proto: "https"
    customResponseHeaders:
      X-Frame-Options: "DENY"
      X-Content-Type-Options: "nosniff"
      Strict-Transport-Security: "max-age=31536000"
    sslProxyHeaders:
      X-Forwarded-Proto: "https"
```

### Redirects

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: redirect-https
spec:
  redirectScheme:
    scheme: https
    permanent: true
```

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: redirect-www
spec:
  redirectRegex:
    regex: "^https?://www\\.(.+)"
    replacement: "https://${1}"
    permanent: true
```

### Circuit breaker / retry

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: circuit-breaker
spec:
  retry:
    attempts: 3
    initialInterval: 100ms
```

## Gateway API

Traefik supports Gateway API as of v3.0:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
spec:
  parentRefs:
  - name: my-gateway
  hostnames:
  - app.example.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: my-app
      port: 80
```

**Gateway API is the future of k8s ingress.** Traefik is one of the more mature implementations.

## TLS / cert-manager

Two ways to handle TLS in Traefik:

### Option 1: Traefik's built-in ACME

```yaml
certificatesResolvers:
  letsencrypt:
    acme:
      email: ops@example.com
      storage: /data/acme.json
      httpChallenge:
        entryPoint: web
```

Traefik handles cert issuance and renewal. Simple.

### Option 2: cert-manager + TLS Store

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ops@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: traefik
```

cert-manager issues certs, Traefik serves them. More flexible.

## The dashboard

```bash
# port-forward
kubectl port-forward -n traefik deploy/traefik 9000:9000

# open http://localhost:9000/dashboard/
```

Or expose via Ingress:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-dashboard
spec:
  entryPoints:
  - websecure
  routes:
  - match: Host(`traefik.example.com`)
    kind: Rule
    services:
    - name: api@internal
      kind: TraefikService
  tls:
    certResolver: letsencrypt
```

The dashboard shows:
- Active routers
- Services
- Middlewares
- Health
- Metrics

## Observability

### Metrics

Traefik exposes Prometheus metrics on `/metrics`:

```yaml
metrics:
  prometheus:
    enabled: true
    addEntryPointsLabels: true
    addServicesLabels: true
```

```yaml
# Prometheus ServiceMonitor
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: traefik
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: traefik
  endpoints:
  - port: metrics
```

### Tracing

```yaml
tracing:
  openTelemetry:
    enabled: true
    address: otel-collector.observability:4317
    insecure: true
    samplingRate: 0.1
```

### Access logs

```yaml
accessLog:
  enabled: true
  filePath: /var/log/traefik/access.log
  format: json
  fields:
    defaultMode: keep
    headers:
      defaultMode: drop
      names:
        User-Agent: keep
        X-Forwarded-For: keep
```

## HA setup

```yaml
# values.yaml
deployment:
  kind: Deployment
  replicas: 3

# or DaemonSet for max performance
deployment:
  kind: DaemonSet

updateStrategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 1
```

```yaml
# anti-affinity
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 100
    podAffinityTerm:
      topologyKey: kubernetes.io/hostname
      labelSelector:
        matchLabels:
          app.kubernetes.io/name: traefik
```

```yaml
# topology spread
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: ScheduleAnyway
  labelSelector:
    matchLabels:
      app.kubernetes.io/name: traefik
```

## Common patterns

### Blue-green deploy

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
spec:
  entryPoints:
  - websecure
  routes:
  - match: Host(`app.example.com`)
    kind: Rule
    services:
    - name: my-app-blue
      port: 80
  tls:
    certResolver: letsencrypt
```

To switch: change `my-app-blue` to `my-app-green`. Atomic. Instant rollback.

### Sticky sessions

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
spec:
  routes:
  - match: Host(`app.example.com`)
    kind: Rule
    services:
    - name: my-app
      port: 80
    strategy: RoundRobin
    sticky:
      cookie:
        name: my-app-stickiness
        secure: true
        httpOnly: true
        sameSite: lax
```

### Mirror (shadow traffic)

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
spec:
  routes:
  - match: Host(`app.example.com`)
    kind: Rule
    services:
    - name: my-app-v1
      port: 80
    - name: my-app-v2
      port: 80
      mirror: true   # mirror to v2, response discarded
```

### Path-based routing

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: monorouter
spec:
  routes:
  - match: Host(`app.example.com`) && PathPrefix(`/api`)
    kind: Rule
    services:
    - name: api
      port: 80
  - match: Host(`app.example.com`) && PathPrefix(`/web`)
    kind: Rule
    services:
    - name: web
      port: 80
```

## Migration from NGINX

```yaml
# old
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/cors-allow-origin: "https://example.com"
spec:
  ingressClassName: nginx
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
```

```yaml
# new
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
spec:
  entryPoints:
  - websecure
  routes:
  - match: Host(`app.example.com`) && PathPrefix(`/`)
    kind: Rule
    services:
    - name: my-app
      port: 80
    middlewares:
    - name: cors
    - name: strip-prefix
  tls:
    certResolver: letsencrypt
```

**Differences:**
- Traefik uses CRDs (IngressRoute), not just Ingress
- Middlewares are first-class (not annotations)
- TLS is per-route, not per-Ingress
- Some NGINX-specific annotations don't translate

## Common gotchas

* **IngressRoute vs Ingress:** Traefik supports both, but IngressRoute is more powerful.
* **Path matching syntax differs** between Ingress and IngressRoute. IngressRoute uses Traefik's match syntax.
* **The dashboard is a security risk** if exposed. Use auth.
* **Custom headers can break things** if you override X-Forwarded-* badly.
* **Sticky sessions are simple but** don't survive pod restarts. For real session management, use Redis.
* **ACME storage is a single file.** If the Traefik pod restarts and storage isn't persistent, you reissue certs.
* **Rate limiting is per Traefik instance** unless you use Redis backend. For multi-replica, use Redis.
* **The `websecure` entrypoint requires TLS** to be configured, or the route won't work.
* **Traefik can be a SPOF** if not HA. Run 3+ replicas across zones.
* **BackendRefs must exist** when the route is created. Race conditions during deploy.

## See also

* [[Kubernetes/guides/networking/envoy-gateway|envoy-gateway]] — alternative
* [[Kubernetes/guides/networking/istio|istio]] — service mesh
* [[Kubernetes/guides/troubleshooting/ingress-404|ingress-404]] — troubleshooting
* [Traefik docs](https://doc.traefik.io/traefik/)
