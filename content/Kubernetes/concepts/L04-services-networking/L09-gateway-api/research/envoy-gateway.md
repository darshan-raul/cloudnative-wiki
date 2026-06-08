# Envoy Gateway — In-Depth Reference

> Source of truth: https://gateway.envoyproxy.io (this doc tracks v1.4.x as of writing).

---

## 1. What Envoy Gateway Is

Envoy Gateway (EG) is the **official** Gateway API implementation from the Envoy project. It consists of:

- A **controller** (`envoy-gateway`) that watches Gateway API resources and translates them into Envoy xDS config
- A **data plane** (`envoy`) — one or more pods per `Gateway` resource, configured via xDS
- An **optional ratelimit service** (`envoy-ratelimit`) when using global rate limiting with Redis

It replaced the older `envoyproxy/envoy` "gateway" project (which was experimental) and is the recommended path if you want a real L7 proxy with Gateway API semantics.

---

## 2. Architecture

```
┌────────────────────┐  watches   ┌──────────────────────┐
│ GatewayClass       │ ─────────► │                      │
│ Gateway            │ ─────────► │  envoy-gateway       │
│ HTTPRoute          │ ─────────► │  (controller)        │   xDS  ┌──────────────┐
│ GRPCRoute          │ ─────────► │                      │ ─────► │  envoy       │
│ BackendTLSPolicy   │ ─────────► │  Renders Listener /  │        │  (data plane)│
│ SecurityPolicy     │ ─────────► │  Route / Cluster xDS │        │              │
│ EnvoyProxy         │ ─────────► │                      │        │  :10000 LB   │
└────────────────────┘            └──────────────────────┘        │  :19000 admin│
                                                                  │  :19001 read │
                                                                  └──────────────┘
                                                                           ▲
                                            L7 traffic                    │
   Client ───────────────────────────────────────────────────────────────┘
```

- **Controller** is one Deployment (or 2+ for HA; the Helm chart does 2 by default in v1.3+). Stateless. Light CPU/memory. Webhook on `:443` of its Service.
- **Data plane** is one Deployment per `Gateway` by default. Can be `DaemonSet` via the `EnvoyProxy` CRD or a `deployment` strategy override. Heavy on memory if you have many routes / large clusters / large xDS payloads.
- **xDS** is over gRPC. The data plane's bootstrap is rendered by the controller to point at the controller's xDS service.

---

## 3. Why Envoy Gateway (and not the alternatives)

| Impl | Status | Why pick it | Why not |
|------|--------|-------------|---------|
| **Envoy Gateway** | Active, official | Cleanly tracks Gateway API, strong conformance, security-hardened defaults, no vendored extensions needed for most cases | Lighter on bells-and-whistles vs NGINX (no Lua, no fancy authn modules) |
| `ingress-nginx` | **Retired** (EOL ~March 2026) | Familiar, broad ecosystem | Project is being sunset; community migration plan points to EG |
| `nginx-gateway-fabric` | Active | NGINX semantics, Gateway API, fast | Smaller community; some features still maturing |
| `Traefik Proxy / Gateway` | Active | L7 features, simple, single binary | Different model, not always Gateway API conformant |
| `HAProxy` | Active | Performance, mature | Less Gateway API feature coverage; mostly L4 |
| `Cilium` Gateway | Active | Network-policy integration, eBPF | Optimized for L4; L7 still emerging |
| `Istio` (Ingress Gateway) | Active | Mesh integration, mTLS native | Heavy; mesh runtime when you only want ingress |
| `Kong` | Active | Plugin ecosystem | Opinionated; many enterprise features paid |

**My pick: Envoy Gateway** for greenfield. It's the cleanest Gateway API conformance story, the project's momentum is strongest, and `ingress-nginx`'s retirement makes the migration argument compelling.

---

## 4. Release Model & Versioning

- **Minor**: quarterly. Schema-breaking changes go here. Pin a minor.
- **Patch**: monthly, security/CVE-driven. Always upgrade.
- **Channels**: there's a `stable` and a `latest`; the Helm chart `appVersion` is the data plane version, `version` is the chart. Always match them.

**Pin in CI** with the exact version. Don't ride `latest`.

---

## 5. Supported Features

The official matrix is at https://gateway.envoyproxy.io/docs/about/features. Quick summary:

- ✅ Core: HTTP routing, header match, path match, query match, method match, weights, redirects, URL rewrites, header modifiers, listener merging (opt-in), multiple listeners
- ✅ TLS: edge, passthrough, re-encrypt; BackendTLSPolicy (upstream mTLS); cert-manager integration; `WellKnownCACertificates: SystemTrustStore`
- ✅ Traffic split: weighted backendRefs; also `EnvoyProxy` for advanced routing
- ✅ Mirroring: `RequestMirror` (spec alpha) + EG's `SecurityPolicy` extension
- ✅ Auth (EG extensions): JWT, OIDC, Basic, extAuthz, IP allow/deny, CORS
- ✅ Rate limit (EG extension): local, and global with Redis
- ✅ Observability: OTel, Prometheus metrics, access logs, tracing
- ⚠️ GAMMA (mesh): partial; not recommended
- ❌ Multi-cluster Gateway: not yet

---

## 6. Installation — Helm

### 6.1 Repo

```bash
helm repo add gateway-helm https://gateway-helm.charts.gitops.io
helm repo update
```

(There's also the OCI mirror `oci://docker.io/envoyproxy/gateway-helm` — same chart, pick the one your environment prefers.)

### 6.2 Values to know

| Key | Default | Why you care |
|-----|---------|--------------|
| `deployment.affinity` | `{}` | Pin to specific node pools |
| `envoyGateway.resources` | light | Controller; usually fine as-is |
| `config.envoyGateway.gatewayControllerName` | `gateway.envoyproxy.io/gatewayclass-controller` | Must match `GatewayClass.spec.controllerName` |
| `config.envoyGateway.extensionApis.enableEnvoyPatchPolicy` | `false` | Off by default; only enable if you need `EnvoyPatchPolicy` |
| `resources.requests/limits` | nil | Set for prod; controller is fine on 100m/128Mi, data plane is 500m/512Mi min |
| `podSecurityContext` | strict (non-root, no priv) | Don't loosen |
| `securityContext` | strict | Same |
| `gateway` block | nil | The `envoyproxy`/`gateway` subchart that renders the default Gateway |
| `telemetry.metrics` | nil | Set to `{ prometheus: { enabled: true } }` for Prometheus scrape |
| `telemetry.accessLog` | disabled | Set to `{ enabled: true, format: ... }` for request logs |
| `telemetry.tracing` | disabled | Set for OTel tracing |
| `ratelimit` subchart | disabled | Enable for global rate limiting with Redis |

### 6.3 Install

```bash
helm install eg gateway-helm/gateway-helm \
  --namespace envoy-gateway-system \
  --create-namespace \
  --version v1.4.0 \
  --values values.yaml
```

(`gateway-helm/gateway-helm` is the actual chart name; the project is also a `gateway-helm` org. Confusing — check the docs page.)

---

## 7. Security Defaults

EG is built to be secure out of the box:

- **Distroless base image** for the controller
- **`runAsNonRoot: true`**, `runAsUser: 65532` (distroless non-root)
- **No host network, no privileged**
- **PodSecurity `restricted` compliant**
- **No secret in env vars** — all config via `ConfigMap`s
- **Webhook with TLS** (cert from the controller; rotates automatically)
- **Envoy admin interface** is internal-only; not exposed via the Gateway
- **No default `LoadBalancer`** for the data plane — you choose. Often a `NodePort`/`ClusterIP` + your own LB/ingress.

**Things to verify** when you customize:
- `securityContext.privileged` should never be `true`
- `hostNetwork` should never be `true`
- Service account token mount should be explicit (`automountServiceAccountToken: false` if not needed)

---

## 8. Customization: `EnvoyProxy` CRD

When you need to break the seal — say, set a specific buffer limit, override `concurrency`, or attach a custom Envoy filter — use `EnvoyProxy`:

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: tuning
  namespace: infra
spec:
  bootstrap:
    type: Merge
    value: |
      ...
  concurrency: 4
  envoyDaemonSet: {}   # or omit for Deployment
```

Apply via `infrastructure.parametersRef` on the `Gateway`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: eg
  namespace: infra
spec:
  infrastructure:
    parametersRef:
      group: gateway.envoyproxy.io
      kind: EnvoyProxy
      name: tuning
  ...
```

This is the **last resort**. Most tuning is already exposed via Helm values.

---

## 9. Operational Notes

### 9.1 Conditions to watch

```bash
kubectl get gateway -A
# NAME  CLASS  ADDRESS  PROGRAMMED  AGE
# eg    eg             True        5m

kubectl get gateway eg -n infra -o jsonpath='{.status.conditions[?(@.type=="Programmed")}]'
```

If `Programmed=False`, look at the message — usually `RefNotPermitted`, `Invalid`, or `Conflicted`.

### 9.2 Envoy admin

Port-forward the data plane to debug:

```bash
kubectl port-forward -n infra deploy/eg 19000:19000
curl -s http://localhost:19000/ready
curl -s http://localhost:19000/config_dump | less
curl -s http://localhost:19000/clusters    # upstream health
curl -s http://localhost:19000/stats | head
```

### 9.3 Metrics

Prometheus endpoint: `:19001` (readiness/metrics). By default, no metrics are exposed externally; you `ServiceMonitor`-scrape or port-forward.

```yaml
telemetry:
  metrics:
    prometheus:
      enable: true
```

### 9.4 Logs

Access logs are off by default. Enable in Helm:

```yaml
telemetry:
  accessLog:
    enable: true
    format: |
      [%START_TIME%] "%REQ(:METHOD)% %REQ(X-ENVOY-ORIGINAL-PATH?:PATH)% %PROTOCOL%" %RESPONSE_CODE% %RESPONSE_FLAGS% %BYTES_RECEIVED% %BYTES_SENT% %DURATION% %RESP(X-ENVOY-UPSTREAM-SERVICE-TIME)% "%REQ(X-FORWARDED-FOR)%" "%REQ(USER-AGENT)%" "%REQ(X-REQUEST-ID)%" "%REQ(:AUTHORITY)%" "%UPSTREAM_CLUSTER%"
```

### 9.5 xDS

xDS is a gRPC stream. Watch for### 9.6 Upgrades

- **Patch** upgrades: zero-downtime, just bump version.
- **Minor** upgrades: read release notes — GatewayClass config or CRD versions may change.
- **Multi-controller** (HA): EG supports leader election; secondaries are passive. Run odd numbers (1, 3) for clean quorum.

### 9.7 Disruption

The data plane is graceful on shutdown — Envoy drains connections. `terminationGracePeriodSeconds` defaults are sane (30s). For long-lived WebSockets, bump to 60s.

---

## 10. When to use EG extensions vs spec

| Need | Use |
|------|-----|
| Plain HTTP/HTTPS routing | Spec (HTTPRoute) |
| Header rewrite, redirect, URL rewrite | Spec (filters) |
| Weighted traffic split | Spec (backendRefs weight) |
| Cross-namespace | Spec (ReferenceGrant) |
| Upstream mTLS | Spec (BackendTLSPolicy) |
| TLS termination | Spec (Gateway listener) |
| JWT validation | EG extension (`SecurityPolicy`) |
| OIDC | EG extension |
| Basic auth | EG extension |
| External authz (OPA, custom) | EG extension (`extAuthz`) |
| IP allow/deny | EG extension |
| CORS | EG extension |
| Local rate limit | EG extension |
| Global rate limit (Redis) | EG extension + subchart |
| Service mesh | Use Istio/Linkerd/Cilium, not EG |

EG extensions are stable but **vendor-specific**. If portability is critical, keep auth/CORS/rate-limit in the app, not the gateway. If you want centralized control, EG extensions are the pragmatic choice.

---

## 11. Quick Troubleshooting Map

| Symptom | First check | Likely fix |
|---------|-------------|-----------|
| `kubectl apply` hangs | Webhook unreachable | Check NetworkPolicy, controller Service `:443` |
| Gateway `Programmed=False` | `kubectl describe` | Fix listener conflict or invalid cert |
| HTTPRoute `Accepted=False, NoMatchingParent` | Hostname intersection | Fix `hostnames` on route or listener |
| HTTPRoute `ResolvedRefs=False, RefNotPermitted` | Cross-ns | Add `ReferenceGrant` |
| Cert errors in browser | SAN list | `dnsNames` in cert-manager Certificate |
| 503 from gateway | `kubectl get endpoints` | Pods aren't ready; check `kubectl describe` |
| `connection refused` on admin | No port-forward | `kubectl port-forward` first |
| OOM in data plane | Routes / clusters | Bump `limits.memory` or split Gateway |
| xDS NACKs | `kubectl logs` | Schema change; check EG version compat |
| Slow first request | Cluster warm-up | Expected; subsequent requests are fast |
