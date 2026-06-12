---
title: Istio
tags:
  - Kubernetes
  - Networking
  - Service Mesh
  - Istio
  - mTLS
---

Istio is a **full-featured service mesh**. Sidecar proxies (Envoy) intercept all pod traffic. You get mTLS, traffic management, observability, and policy, all without changing app code. **Powerful but complex.** Best for large, security-sensitive deployments.

## The architecture

```
┌────────────────────────────────────────────────────────────┐
│  Control plane (istiod)                                    │
│  - Pilot: service discovery, xDS to sidecars              │
│  - Citadel/CA: cert management for mTLS                    │
│  - Galley: config validation                               │
└──────────────────────┬─────────────────────────────────────┘
                       │ xDS (gRPC)
                       │
┌──────────────────────┼─────────────────────────────────────┐
│  Data plane                                             │
│  ┌────────────────┐  ┌────────────────┐                 │
│  │ Pod A          │  │ Pod B          │                 │
│  │  ┌──────────┐  │  │  ┌──────────┐  │                 │
│  │  │ App      │  │  │  │ App      │  │                 │
│  │  └────┬─────┘  │  │  └────┬─────┘  │                 │
│  │       │        │  │       │        │                 │
│  │  ┌────▼─────┐  │  │  ┌────▼─────┐  │                 │
│  │  │ Envoy    │  │  │  │ Envoy    │  │                 │
│  │  │ sidecar  │  │  │  │ sidecar  │  │                 │
│  │  └────┬─────┘  │  │  └────┬─────┘  │                 │
│  │       │        │  │       │        │                 │
│  │  iptables      │  │  iptables      │                 │
│  │  redirect      │  │  redirect      │                 │
│  └────────────────┘  └────────────────┘                 │
│       │      │              │      │                     │
│       │      └──── mTLS ────┘      │                     │
│       │                            │                     │
│       └──── plaintext to external ──┘                     │
└────────────────────────────────────────────────────────────┘
```

**Every pod gets an Envoy sidecar.** The sidecar handles all traffic (in and out), policy, telemetry. The app doesn't know.

## Why Istio

**Use Istio for:**
- Large clusters (50+ services) where service-to-service comms is complex
- mTLS required for compliance (PCI-DSS, HIPAA, FedRAMP)
- Fine-grained access control (AuthorizationPolicy)
- Advanced traffic management (canary, traffic mirroring, fault injection)
- Multi-cluster / multi-region
- Service-to-service observability

**Don't use Istio for:**
- Small clusters (1-10 services) — overhead isn't worth it
- Where simpler alternatives (Linkerd, Cilium) suffice
- Teams that don't have mesh expertise

## Install Istio

### istioctl (recommended)

```bash
# install the CLI
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH

# install with default profile
istioctl install --set profile=demo -y

# production profile (HA, smaller surface)
istioctl install --set profile=default -y

# ambient mesh (no sidecars)
istioctl install --set profile=ambient -y
```

### Helm

```bash
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
```

```bash
# install base
helm install istio-base istio/base -n istio-system --create-namespace

# install istiod
helm install istiod istio/istiod -n istio-system --wait

# install ingress gateway
helm install istio-ingress istio/gateway -n istio-ingress --create-namespace
```

### Production profile

```bash
istioctl install --set profile=default -y
```

The default profile:
- istiod (1 replica by default, scale for HA)
- Ingress gateway
- CNI plugin (optional, but recommended)
- No sidecar injection by default (per-namespace)

## Sidecar injection

**Two modes:**

### Namespace label (opt-in)

```bash
kubectl label namespace my-app istio-injection=enabled
```

New pods in this namespace get sidecars.

### Annotation (opt-out, per pod)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    metadata:
      annotations:
        sidecar.istio.io/inject: "false"   # explicitly no sidecar
    spec:
      containers:
      - name: my-app
        image: myapp:v1
```

### Verifying injection

```bash
kubectl get pod -n my-app -l app=my-app -o jsonpath='{.items[0].spec.containers[*].name}'
# should show: my-app istio-proxy
```

## mTLS (the killer feature)

**STRICT mTLS** (default in newer Istio):

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
```

All pods in the cluster (with sidecars) communicate over mTLS. **Plaintext is rejected.**

**For non-Istio workloads** (legacy, no sidecar):

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: legacy
  namespace: legacy
spec:
  mtls:
    mode: PERMISSIVE   # accept both mTLS and plaintext
```

**For migration:**

```yaml
# step 1: PERMISSIVE (accept both)
# step 2: verify with metrics that all clients are using mTLS
# step 3: STRICT (only mTLS)
```

**Inspecting certs:**

```bash
istioctl authn tls-check <pod>.<namespace>
```

## Authorization policies

Fine-grained access control:

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: my-app-policy
  namespace: my-app
spec:
  selector:
    matchLabels:
      app: my-app
  rules:
  # allow only from my-app's own namespace
  - from:
    - source:
        principals:
        - cluster.local/ns/my-app/sa/my-app-sa
  # allow only GET, POST methods
  - to:
    - operation:
        methods: ["GET", "POST"]
```

**Patterns:**

```yaml
# allow all from same namespace
- from:
  - source:
      principals:
      - cluster.local/ns/<ns>/*

# allow specific service
- from:
  - source:
      principals:
      - cluster.local/ns/<ns>/sa/<sa>

# allow with specific header
- when:
  - key: request.headers[x-api-key]
    values: ["secret"]

# allow from external (with JWT)
- from:
  - source:
      requestPrincipals: ["*"]
```

**Default deny:**

```yaml
# empty rules + selector = deny all
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: deny-all
  namespace: my-app
spec:
  {}   # empty
```

Combine with allow rules for "default deny + explicit allow."

## Traffic management

### VirtualService (request routing)

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-app
spec:
  hosts:
  - my-app
  http:
  - match:
    - headers:
        x-canary:
          exact: "true"
    route:
    - destination:
        host: my-app
        subset: v2
  - route:
    - destination:
        host: my-app
        subset: v1
      weight: 90
    - destination:
        host: my-app
        subset: v2
      weight: 10   # 10% canary
```

### DestinationRule (subset definition)

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: my-app
spec:
  host: my-app
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        h2UpgradePolicy: DEFAULT
        maxRequestsPerConnection: 10
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
```

### Canary deploy via Istio

```yaml
# 1. Deploy v1 (existing) and v2 (new)
# v1 has label version: v1
# v2 has label version: v2

# 2. Create DestinationRule
# (above)

# 3. Create VirtualService with 0% to v2 initially
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-app
spec:
  hosts:
  - my-app
  http:
  - route:
    - destination:
        host: my-app
        subset: v1
      weight: 100
    - destination:
        host: my-app
        subset: v2
      weight: 0

# 4. Update weights to 1%, 5%, 10%, 50%, 100%
# (over time, as you monitor)

# 5. Roll back by setting v2 weight to 0
```

### Fault injection

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-app
spec:
  hosts:
  - my-app
  http:
  - fault:
      delay:
        percentage:
          value: 10
        fixedDelay: 2s
      abort:
        percentage:
          value: 5
        httpStatus: 503
    route:
    - destination:
        host: my-app
        subset: v1
```

**Inject 10% of requests to have 2s delay, 5% to abort with 503.** Test how your system handles failure.

### Traffic mirroring (shadow)

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-app
spec:
  hosts:
  - my-app
  http:
  - route:
    - destination:
        host: my-app
        subset: v1
    mirror:
      host: my-app
      subset: v2
    mirrorPercentage:
      value: 100
```

All v1 traffic is mirrored to v2. v2's response is discarded.

## The Gateway

Ingress from outside the cluster:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: my-gateway
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: my-app-cert
    hosts:
    - app.example.com
```

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-app
spec:
  hosts:
  - app.example.com
  gateways:
  - my-gateway
  http:
  - route:
    - destination:
        host: my-app
        port:
          number: 80
```

**Two resources, two roles:**
- **Gateway:** L4 (port, TLS, hosts)
- **VirtualService:** L7 (routing rules)

## Observability

### Kiali (mesh visualization)

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml
```

UI shows:
- Service graph
- Traffic flow
- mTLS status
- Errors
- Latency

### Jaeger (distributed tracing)

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/jaeger.yaml
```

Sidecars auto-instrument. Each request gets a trace. Open in Jaeger UI.

### Prometheus metrics

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/prometheus.yaml
```

Sidecars export metrics on `:15090`. Scrape with Prometheus.

**Key metrics:**
- `istio_requests_total` — request count, labels: source, destination, status
- `istio_request_duration_milliseconds` — latency
- `istio_tcp_sent_bytes_total` — TCP traffic
- `envoy_cluster_*` — cluster-level metrics

## Ambient mesh (the future)

Istio 1.20+ supports **ambient mesh** — no sidecars, just a per-node ztunnel.

```bash
istioctl install --set profile=ambient -y
```

**Pros:**
- No sidecar resource overhead
- Faster pod startup
- Less CPU/memory per pod

**Cons:**
- Newer, less battle-tested
- Some features not yet available (e.g., per-pod config)

## Common gotchas

* **Sidecars add latency** (~1-3ms per request) and resource overhead (~50-100MB per pod).
* **STRICT mTLS breaks non-Istio clients.** Start with PERMISSIVE, migrate carefully.
* **AuthorizationPolicy is namespace-scoped.** Cluster-wide policies need ClusterAuthorizationPolicy (or use mesh-level).
* **Service entries** for external services (databases, etc.) need to be defined. Otherwise, sidecars can't reach them.
* **Outbound traffic** is blocked by default. Add ServiceEntry for external dependencies.
* **The ingress gateway is a SPOF** if not scaled. Run 2+ replicas.
* **Patching sidecars in running pods** requires pod restart. Update the deployment.
* **Resource limits on sidecars** can cause issues. Sidecar needs enough to handle traffic.
* **The control plane (istiod) is a SPOF** if not HA. Run 3+ replicas for production.
* **Mutual mTLS doesn't replace app-level auth.** It's network-layer only. Apps still need to authenticate users.
* **Sidecar ordering matters in init containers.** Istio uses iptables to redirect traffic; broken iptables rules break apps.

## Migration from non-mesh

1. **Install Istio with default profile.**
2. **Label namespaces for injection** one at a time.
3. **Restart pods** to get sidecars.
4. **Verify with istioctl authn tls-check** that mTLS is working.
5. **Set PeerAuthentication to STRICT** per namespace, one at a time.
6. **Add AuthorizationPolicies** as needed.
7. **Update apps** if they have hardcoded HTTP/HTTPS ports (Istio uses standard).

## A complete production setup

```yaml
# 1. install with default profile
istioctl install --set profile=default -y

# 2. enable injection for app namespaces
kubectl label namespace my-app istio-injection=enabled

# 3. strict mTLS at mesh level
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT

# 4. ingress gateway
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: prod-gateway
  namespace: istio-ingress
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: prod-cert
    hosts:
    - app.example.com

# 5. VirtualService routing
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-app
spec:
  hosts:
  - app.example.com
  gateways:
  - istio-ingress/prod-gateway
  http:
  - route:
    - destination:
        host: my-app.my-app.svc.cluster.local
        port:
          number: 80

# 6. AuthorizationPolicy
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: my-app
  namespace: my-app
spec:
  rules:
  - from:
    - source:
        principals:
        - cluster.local/ns/istio-ingress/sa/ingressgateway-sa
```

## See also

* [[Kubernetes/guides/networking/linkerd|linkerd]] — lighter alternative
* [[Kubernetes/guides/networking/comparison|comparison]] — Istio vs Linkerd vs Cilium
* [[Kubernetes/guides/delivery/progressive-delivery/strategies|progressive-delivery]] — canary patterns
* [Istio docs](https://istio.io/latest/docs/)
