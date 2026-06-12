---
title: Linkerd
tags:
  - Kubernetes
  - Networking
  - Service Mesh
  - Linkerd
  - mTLS
---

Linkerd is the **lightweight service mesh** for k8s. Built on Rust (Linkerd2-proxy, linkerd2-proxy), it's faster and smaller than Envoy-based meshes. **mTLS, telemetry, and traffic management without the operational overhead of Istio.**

## Why Linkerd

| | Linkerd | Istio |
|---|---------|-------|
| **Proxy** | linkerd2-proxy (Rust) | Envoy (C++) |
| **Memory per pod** | ~20-30MB | ~50-100MB |
| **Latency overhead** | <1ms | 1-3ms |
| **mTLS** | ✅ automatic | ✅ automatic |
| **Traffic management** | ✅ (less feature-rich) | ✅ (more flexible) |
| **Authorization** | ✅ Server, AuthzPolicy | ✅ more flexible |
| **Multi-cluster** | ✅ | ✅ |
| **Gateway** | ✅ built-in | ✅ |
| **Complexity** | Lower | Higher |
| **Maturity** | Production (CNCF Graduated) | Production (CNCF Graduated) |
| **Use cases** | Most | More complex |

**Use Linkerd when:**
- You want mTLS without operational overhead
- You don't need Istio's full feature set (e.g., complex EnvoyFilter)
- You want a smaller, more focused mesh

**Use Istio when:**
- You need Envoy's full power (custom filters, WASM)
- You need advanced traffic management
- You're a very large org with mesh expertise

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│  Control plane (linkerd)                                  │
│  - Destination: service discovery                         │
│  - Identity: cert management (mTLS)                       │
│  - Proxy injector: injects linkerd2-proxy at startup      │
│  - Web, Tap, Viz extensions                              │
└──────────────────────┬─────────────────────────────────────┘
                       │
┌──────────────────────┼────────────────────────────────────┐
│  Data plane                                            │
│  ┌────────────────┐  ┌────────────────┐                 │
│  │ Pod A          │  │ Pod B          │                 │
│  │  ┌──────────┐  │  │  ┌──────────┐  │                 │
│  │  │ App      │  │  │  │ App      │  │                 │
│  │  └────┬─────┘  │  │  └────┬─────┘  │                 │
│  │       │        │  │       │        │                 │
│  │  ┌────▼─────┐  │  │  ┌────▼─────┐  │                 │
│  │  │ linkerd2 │  │  │  │ linkerd2 │  │                 │
│  │  │  -proxy  │  │  │  │  -proxy  │  │                 │
│  │  │  (Rust)  │  │  │  │  (Rust)  │  │                 │
│  │  └──────────┘  │  │  └──────────┘  │                 │
│  └────────────────┘  └────────────────┘                 │
└──────────────────────────────────────────────────────────┘
```

**Smaller, faster, simpler than Istio.** The trade-off: fewer features.

## Install

### CLI (recommended)

```bash
# install linkerd CLI
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh
export PATH=$PATH:$HOME/.linkerd2/bin

# pre-flight check
linkerd check --pre

# install CRDs
linkerd install --crds | kubectl apply -f -

# install Linkerd
linkerd install | kubectl apply -f -

# verify
linkerd check
```

### Helm

```bash
helm repo add linkerd https://helm.linkerd.io/stable
helm repo update
```

```bash
# install CRDs
helm install linkerd-crds linkerd/linkerd-crds -n linkerd --create-namespace

# install Linkerd
helm install linkerd linkerd/linkerd-control-plane \
  -n linkerd \
  --set identity.issuer.tls.crtPEM=... \
  --set identity.issuer.tls.keyPEM=...
```

### HA mode

```bash
# install with HA (3+ replicas for each component)
linkerd install --ha | kubectl apply -f -
```

This sets:
- 3 destination replicas
- 3 identity replicas
- 3 proxy-injector replicas
- PodDisruptionBudgets

## Sidecar injection

### Namespace label (opt-in)

```bash
kubectl label namespace my-app linkerd.io/injection=enabled
```

New pods get proxies. Existing pods need restart.

### Annotation (per pod)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    metadata:
      annotations:
        linkerd.io/inject: enabled
```

### Verifying

```bash
linkerd stat -n my-app
# shows pods with proxy status
```

## mTLS

**Automatic by default.** All Linkerd-to-Linkerd traffic is mTLS. No config needed.

**Verify mTLS:**

```bash
linkerd stat -n my-app
# AUTHENTICATION column shows "mtls"

# detailed view
linkerd viz stat -n my-app deploy
```

**For non-Linkerd workloads** (no sidecar):

```yaml
apiVersion: policy.linkerd.io/v1beta1
kind: Server
metadata:
  name: legacy
  namespace: my-app
spec:
  podSelector:
    matchLabels:
      app: legacy-app
  port: 80
  proxyProtocol: "unknown"   # accept plain or mTLS
```

The legacy app accepts both. Mesh traffic to it is plain.

## Authorization policies

Less expressive than Istio, but simpler.

```yaml
apiVersion: policy.linkerd.io/v1beta1
kind: Server
metadata:
  name: my-app
  namespace: my-app
spec:
  podSelector:
    matchLabels:
      app: my-app
  port: 80
  proxyProtocol: HTTP/2
```

```yaml
# AuthorizationPolicy (allow from same mesh)
apiVersion: policy.linkerd.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-mesh
  namespace: my-app
spec:
  targetRef:
    group: policy.linkerd.io
    kind: Server
    name: my-app
  requiredAuthenticationRefs:
  - group: policy.linkerd.io
    kind: MeshTLSAuthentication
    name: allow-mesh
---
apiVersion: policy.linkerd.io/v1beta1
kind: MeshTLSAuthentication
metadata:
  name: allow-mesh
  namespace: my-app
spec:
  identityRefs:
  - group: core
    kind: ServiceAccount
    name: "*"   # any service account in the mesh
```

**Patterns:**

```yaml
# allow all authenticated clients
requiredAuthenticationRefs:
- group: policy.linkerd.io
  kind: MeshTLSAuthentication
  name: allow-mesh

# allow specific namespace
- group: policy.linkerd.io
  kind: MeshTLSAuthentication
  name: allow-from-ns-x
---
apiVersion: policy.linkerd.io/v1beta1
kind: MeshTLSAuthentication
metadata:
  name: allow-from-ns-x
  namespace: my-app
spec:
  identityRefs:
  - group: core
    kind: ServiceAccount
    name: app-x-sa
    namespace: app-x

# deny all (default deny)
requiredAuthenticationRefs: []   # empty = no auth = denied
```

## Traffic management

### Service profiles (per-route metrics)

```yaml
apiVersion: linkerd.io/v1alpha2
kind: ServiceProfile
metadata:
  name: my-app.my-app.svc.cluster.local
  namespace: my-app
spec:
  routes:
  - name: GET /api/users/{id}
    condition:
      method: GET
      pathRegex: /api/users/[^/]+
    isRetryable: false
    timeout: 5s
    responseClasses:
    - condition:
        status:
          min: 500
          max: 599
      isFailure: true
```

**Why?** Per-route metrics (success rate, latency), timeouts, retry budgets.

### Traffic split (canary)

```yaml
apiVersion: split.smi-spec.io/v1alpha2
kind: TrafficSplit
metadata:
  name: my-app-canary
  namespace: my-app
spec:
  service: my-app
  backends:
  - service: my-app-v1
    weight: 90
  - service: my-app-v2
    weight: 10
```

**SMI (Service Mesh Interface)** standard. Linkerd implements it. **Tool-agnostic.**

### Ingress (the built-in ingress)

Linkerd's own ingress:

```bash
linkerd install --set ingress.enabled=true | kubectl apply -f -
```

```yaml
# HTTPRoute (or Ingress)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    ingress.kubernetes.io/customHeaders: X-Forwarded-Proto: https
spec:
  ingressClassName: linkerd-http
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
    secretName: my-app-cert
```

The linkerd-proxy handles TLS termination, then forwards to the app.

### Fault injection (via ServiceProfile)

```yaml
apiVersion: linkerd.io/v1alpha2
kind: ServiceProfile
metadata:
  name: my-app.my-app.svc.cluster.local
spec:
  routes:
  - name: GET /api
    isRetryable: true
    timeout: 5s
    retryBudget:
      minRetriesPerSecond: 10
      maxRetriesPerSecond: 100
      retryRatio: 0.2
```

**Retry budget:** max retries as a fraction of requests. Prevents retry storms.

## Observability

### Built-in dashboard

```bash
linkerd viz install | kubectl apply -f -
linkerd viz dashboard
```

Browser UI showing:
- Service mesh
- Per-route metrics
- Live traffic
- Top requests
- Errors

### Prometheus metrics

```bash
# scrape linkerd metrics
linkerd viz install --set prometheus.enabled=true | kubectl apply -f -
```

Metrics are exposed on `:4191` for proxies, `:8086` for the control plane.

**Key metrics:**
- `request_total` — request count
- `response_latency_ms` — request latency
- `tcp_open_total` — TCP connections
- `connection_errors_total` — connection errors

### Distributed tracing

```bash
linkerd jaeger install | kubectl apply -f -
```

Auto-instrumented by proxies. Each request gets a trace.

## The CLI

```bash
# stat (top)
linkerd stat -n my-app deploy
# shows requests, success rate, latency, mTLS

# stat by route
linkerd stat -n my-app deploy --to deploy/my-app

# top (real-time)
linkerd top -n my-app

# tap (live requests)
linkerd tap -n my-app deploy/my-app

# check (verification)
linkerd check

# viz
linkerd viz stat -n my-app
linkerd viz routes -n my-app deploy/my-app
```

## Common patterns

### Canary deploy

```yaml
# 1. Deploy v1 (existing) and v2 (new)
# 2. TrafficSplit with 0% to v2
apiVersion: split.smi-spec.io/v1alpha2
kind: TrafficSplit
metadata:
  name: my-app
spec:
  service: my-app
  backends:
  - service: my-app-v1
    weight: 100
  - service: my-app-v2
    weight: 0

# 3. Update weights to 1%, 5%, 10%, 50%, 100%

# 4. Roll back by setting v2 to 0%
```

### Sticky session

```yaml
# ServiceProfile can set a session affinity
apiVersion: linkerd.io/v1alpha2
kind: ServiceProfile
metadata:
  name: my-app.my-app.svc.cluster.local
spec:
  routes:
  - name: GET /
    isRetryable: true
```

Linkerd doesn't have built-in sticky session; use a load balancer that does (e.g., AWS ALB).

### Outbound traffic (ServiceProfile for external)

```yaml
apiVersion: linkerd.io/v1alpha2
kind: ServiceProfile
metadata:
  name: external-api.example.com
  namespace: my-app
spec:
  routes:
  - name: GET /api/data
    condition:
      method: GET
      pathRegex: /api/data/.*
    timeout: 10s
```

Or use `ExternalService` (Linkerd 2.13+):

```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: external-api
spec:
  parentRefs:
  - name: my-app
  rules:
  - matches:
    - path: { type: PathPrefix, value: /api }
    backendRefs:
    - name: external-api
      kind: Service
      port: 443
```

## Common gotchas

* **mTLS requires both ends to be in the mesh.** If one side doesn't have a proxy, traffic is plain (unless you set `proxyProtocol: unknown`).
* **ServiceAccount-based identity** is fundamental. Make sure pods have a SA.
* **AuthorizationPolicy needs Server CRD.** First define the Server, then the policy.
* **SMI TrafficSplit is a standard,** not Linkerd-specific. Other meshes can use it.
* **The linkerd2-proxy** uses iptables to capture traffic. If iptables is broken, mesh breaks.
* **Memory limits on the proxy** can cause issues. Default limits are 50MB (small) to 200MB (large).
* **Linkerd 2.x is the production version.** Older 1.x is deprecated.
* **HA mode is recommended for production.** Default install is 1 replica of each.
* **Linkerd's ingress is simpler than Istio's** but less feature-rich. Use Envoy Gateway or Traefik for complex ingress.
* **The viz extension** is useful but resource-heavy. For production, use Prometheus + Grafana.

## HA setup

```bash
linkerd install --ha | kubectl apply -f -
```

- 3 destination replicas
- 3 identity replicas
- 3 proxy-injector replicas
- PodDisruptionBudgets

**For production:**

```bash
linkerd install --ha \
  --set identity.issuer.tls.crtPEM=... \
  --set identity.issuer.tls.keyPEM=... \
  | kubectl apply -f -
```

## Migration from non-mesh

1. **Install Linkerd.**
2. **Verify with `linkerd check`.**
3. **Label one namespace for injection.** Restart pods.
4. **Verify mTLS with `linkerd stat`.**
5. **Add ServiceProfiles for important routes.**
6. **Add AuthorizationPolicies as needed.**
7. **Add Linkerd's ingress (or use existing).**

## A complete production setup

```bash
# install with HA
linkerd install --ha | kubectl apply -f -

# install viz (metrics)
linkerd viz install | kubectl apply -f -

# install jaeger (tracing)
linkerd jaeger install | kubectl apply -f -

# label namespace
kubectl label namespace my-app linkerd.io/injection=enabled

# restart pods
kubectl rollout restart deploy -n my-app

# verify
linkerd stat -n my-app
```

## See also

* [[Kubernetes/guides/networking/istio|istio]] — full-featured alternative
* [[Kubernetes/guides/networking/comparison|comparison]] — Linkerd vs Istio vs Cilium
* [[Kubernetes/guides/networking/envoy-gateway|envoy-gateway]] — alternative ingress
* [Linkerd docs](https://linkerd.io/docs/)
