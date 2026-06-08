# Gateway API — In-Depth Reference

> Source of truth: https://gateway-api.sigs.k8s.io (spec v1, channel `standard`).
> This doc covers the spec at depth, with a section at the end explicitly contrasting Ingress.

---

## 1. Why Gateway API Exists

Ingress has four structural problems that became unworkable by 2023:

1. **No role separation.** Every "Ingress" YAML is owned by whoever applied it. The infra team (LoadBalancer, DNS, cert) and the app team (paths, headers, canary) collide in the same object. Annotations became the workaround, but annotations are vendor-specific strings with no validation.
2. **HTTP-only mental model.** L4 routing (TCP, UDP, TLS passthrough) was bolted on differently by every provider.
3. **No traffic split.** Canary / blue-green required vendor-specific annotations (NGINX, Contour, etc.) with no semantics. Argo Rollouts / Flagger had to invent their own resource model.
4. **No policy attachment.** A "rate limit this route" is a hack — usually a CRD from the same vendor that owns the controller.

Gateway API fixes this by making the spec **role-aware**, **multi-protocol**, and **policy-attachable**, while staying vendor-neutral.

---

## 2. The Resource Model

Six core resources, organized by **who owns them** in a real cluster:

### 2.1 `GatewayClass` — cluster-scoped, **infrastructure provider**

The "I exist, I'm an Envoy Gateway" object. Names the controller (`spec.controllerName`). Once a cluster has a `GatewayClass`, anyone can create a `Gateway` that points at it.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
```

In EG, this object ships with the chart — you don't need to write it.

### 2.2 `Gateway` — cluster-scoped or namespace-scoped, **infra admin**

Defines the L4+L7 listener surface: which ports, which TLS certs, which hostnames. One Gateway = one data-plane deployment (in EG; in some impls, multiple Gateways can be merged — see §10).

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: eg
  namespace: infra
spec:
  gatewayClassName: eg
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
```

A Gateway's `status.listeners[].conditions` and the top-level `conditions[]` array is the source of truth for "is this thing actually serving?"

### 2.3 `HTTPRoute` (and friends) — namespace-scoped, **app developer**

Where the app team lives. Points at one or more `Gateway` (or `sectionName` of a listener) via `parentRefs`, and declares rules: matches (host, path, header, method, query param) → filters (header rewrite, redirect, mirror, CORS) → `backendRefs` (services, with weights).

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
  namespace: app
spec:
  parentRefs:
  - name: eg
    namespace: infra
  hostnames: ["my-app.example.com"]
  rules:
  - matches:
    - path: { type: PathPrefix, value: / }
    backendRefs:
    - name: my-app
      port: 8080
```

Sister resources: `TCPRoute`, `UDPRoute`, `TLSRoute` (SNI-based), `GRPCRoute` (gRPC method matching, with a `GRPCRouteMatch` first-class support).

### 2.4 Policies — `**Policy` CRDs, **app or platform team**

Attach to a `Gateway`, listener, route, or service. The standard ones in `standard` channel:

- `BackendTLSPolicy` — verify TLS to upstream (mTLS, CA certs via `ConfigMap` or `WellKnownCACertificates`)
- `RequestMirror` — fan-out a copy of a request to a debug service
- The rest (`RateLimitPolicy`, `AuthPolicy`, `SessionPersistence`, etc.) are in `experimental` channel or vendor-extensions.

Plus, **EG-specific extensions** (out of spec, but stable in the project):
- `SecurityPolicy` — JWT, OIDC, Basic auth, extAuthz, CORS, IP allow/deny, rate limit (local)
- `EnvoyProxy` — break the glass into the underlying Envoy config

---

## 3. Conformance Profiles

The spec defines **conformance levels** so you can ask "does this provider do the things I need?"

- **Core** — every conformant implementation must do this. The minimum.
- **Extended** (formerly `Compliance`) — features most providers support but the spec doesn't force. (The naming churned in v1.1; the test suite is `conformance/utils`.)

The real matrix lives at https://gateway-api.sigs.k8s.io/conformance — Envoy Gateway scores well, especially for HTTP core, TLS, and traffic split.

`gateway-api.sigs.k8s.io` publishes **release channels**:

- `standard` — GA features, default
- `experimental` — alpha features, opt in

You install CRDs once per channel choice:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
```

`standard-install.yaml` is the **smaller** one. The `experimental-install.yaml` adds `XxxPolicy` alpha resources.

---

## 4. Roles & Personas — The Killer Feature

| Role | Owns | Examples |
|------|------|----------|
| **Infrastructure provider** | `GatewayClass` | Vendor, platform team |
| **Cluster operator** | `Gateway`, namespace, RBAC | Cluster admin, SRE |
| **Application developer** | `HTTPRoute`, Services, `SecurityPolicy` | App team |

In practice: the infra team creates `Gateway` objects with `allowedRoutes.namespaces: from: Selector` (or `All`). The app team never touches the Gateway — they only write `HTTPRoute` and Services in their own namespace. The cluster admin gates everything with RBAC:

```yaml
# App team can only create HTTPRoute in their namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
rules:
- apiGroups: ["gateway.networking.k8s.io"]
  resources: ["httproutes"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

This is what the Ingress model never gave you cleanly.

---

## 5. Route Attachment — The Subtle Stuff

### 5.1 `parentRefs`

A route is "claimed" by a Gateway (or a specific listener via `sectionName`) via `parentRefs`:

```yaml
parentRefs:
- group: gateway.networking.k8s.io
  kind: Gateway
  name: eg
  namespace: infra
  sectionName: http        # specific listener; optional
  port: 80                 # only if listener name doesn't disambiguate
```

### 5.2 Hostname intersection

The route's `hostnames` are **intersected** with the listener's `hostname`. If a listener has `*.example.com` and a route has `foo.example.com`, the route is bound to that listener.

**Gotcha:** if you have a listener with no `hostname` (catch-all), it can absorb everything. Be careful — or use a `namespace` selector to limit.

### 5.3 Allowed routes

Each listener has `allowedRoutes` — usually `from: All` or `from: Selector` with `matchLabels`. This is the second layer of multi-tenancy (after RBAC).

### 5.4 Merging

Multiple HTTPRoutes can attach to the same listener. The implementation **merges** them in a deterministic order (creation timestamp, then namespace+name lexicographic). You can use `order` annotation (in some impls) or — more cleanly — let the merge happen and rely on `backendRefs` weights.

### 5.5 Conflict conditions

A route that can't bind to its `parentRefs` shows `Accepted=False` with reason `NoMatchingParent`, `NotAllowedByListeners`, or `Conflicted`. The `kubectl describe` output is your friend:

```bash
kubectl describe httproute my-app -n app
```

---

## 6. ReferenceGrant — Cross-Namespace Safety

By default, a route in namespace `A` cannot point at a Service in namespace `B`. You must opt in with a `ReferenceGrant` in the **target** namespace:

```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-app-a
  namespace: app-b     # target namespace
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: app-a  # consumer
  to:
  - group: ""
    kind: Service
```

Same pattern applies to Secret refs in `BackendTLSPolicy`. **The grant must be in the target namespace**, which is what makes it safe — the target owner approves.

---

## 7. BackendTLSPolicy — Upstream mTLS

You want the gateway to talk TLS to the upstream service and verify its cert:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: BackendTLSPolicy
metadata:
  name: mtls-upstream
  namespace: app
spec:
  targetRefs:
  - group: ""
    kind: Service
    name: my-app
  tls:
    caCertificateRefs:
    - group: ""
      kind: ConfigMap
      name: upstream-ca
    hostname: my-app.app.svc.cluster.local
    wellKnownCACertificates: SystemTrustStore  # or omit for just CAref
    mode: Require
```

`mode: Require` enforces, `Allow` permits cleartext too. Don't use `Allow` in production without a reason.

The CA certs in the ConfigMap (or Secret) must be PEM. Use `wellKnownCACertificates: SystemTrustStore` for public CAs (Let's Encrypt, etc.).

---

## 8. Cert Management

Gateway API does **not** define how certs are minted — only how they're referenced. A listener uses a `tls.certificateRefs[]` of kind `Secret`:

```yaml
listeners:
- name: https
  port: 443
  protocol: HTTPS
  tls:
    mode: Terminate
    certificateRefs:
    - kind: Secret
      name: my-app-tls
```

The Secret **must** be of type `kubernetes.io/tls` with keys `tls.crt` and `tls.key`. That's the only shape that works.

### 8.1 cert-manager integration

The cleanest way. `cert-manager` v1.15+ has a built-in `gatewayCertRef` mode for `Certificate` resources:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-app
  namespace: infra
spec:
  secretName: my-app-tls
  dnsNames:
  - my-app.example.com
  - "*.example.com"
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
```

cert-manager watches the Gateway's `tls.certificateRefs` and auto-issues when the listener wants a cert. (Make sure `cert-manager` is on v1.15+ and the `cert-manager.io/issuer-name` annotation is on the Gateway, or use the newer `gatewayCertRef` flow.)

### 8.2 cert rotation

Gateway API itself does not rotate. cert-manager (or your operator) does. Envoy Gateway hot-reloads Secrets on change — verify your version (post-v1.0, all versions do this).

---

## 9. Standard Channels — What's In, What's Out

`standard` channel in v1.2.1 contains:

- `GatewayClass`, `Gateway`, `HTTPRoute`, `GRPCRoute`
- `TCPRoute`, `UDPRoute`, `TLSRoute` (still `v1alpha2` in some impls)
- `ReferenceGrant` (`v1beta1`)
- `BackendTLSPolicy` (`v1alpha3` — yes, alpha, but stable in practice)
- `RequestMirror` (alpha)
- `URLRewrite`, `RequestHeaderModifier`, `RequestRedirect` (filters; part of `HTTPRouteRule`)
- `SessionPersistence` (alpha)

`experimental` adds:
- `RateLimitPolicy`, `AuthPolicy` (note: distinct from EG's `SecurityPolicy`)
- `BackendLBPolicy`
- `ClientTrafficPolicy`, `EnvoyExperimentalFilter`

**EG-specific** (not in spec):
- `SecurityPolicy` (CORS, JWT, OIDC, Basic, extAuthz, IP allow/deny, rate limit)
- `EnvoyProxy` (the "break glass")

---

## 10. Gateway Merging

A single `Gateway` resource deploys one or more data-plane pods (in EG, a `Deployment` by default). Two `Gateway` resources pointing at the same `GatewayClass` and the same listener `port+protocol+hostname` **are not merged by default** — they conflict (status `Conflicted`).

EG supports an opt-in merge via a label on the `GatewayClass`:

```yaml
metadata:
  labels:
    gateway.envoyproxy.io/merge: "true"
```

Or in the Helm values, by configuring the controller to allow merging. Use this when multi-tenant Gateway objects need to share the same data plane (save on resources). Do **not** use it for organizational ownership — use RBAC + namespaced routes instead.

---

## 11. Status, Conditions, and Troubleshooting

Every Gateway API object has a `status.conditions[]` array. Conditions have a `type`, `status` (True/False/Unknown), `reason`, and `message`. The most important types:

- **Gateway**: `Accepted` (the spec is valid), `Programmed` (the data plane is configured), `Ready` (alias for `Programmed` in most impls)
- **HTTPRoute**: `Accepted` (bound to a parent), `ResolvedRefs` (backends exist)
- **Listener**: `Accepted`, `Conflicted`, `OverlappingTLSConfig`, `Programmed`, `Ready`

**The diagnostic loop:**

```bash
kubectl describe gateway <name> -n <ns>
kubectl describe httproute <name> -n <ns>
kubectl get events -n <ns> --sort-by=.lastTimestamp
```

If you see `OverlappingTLSConfig` on a listener, two listeners in the same Gateway are stepping on each other. Split the hostnames or ports.

---

## 12. Gateway API vs Ingress — Diff Table

| Capability | Ingress (NGINX) | Gateway API |
|---|---|---|
| HTTP routing | ✅ core | ✅ core (HTTPRoute) |
| L4 (TCP/UDP) | ❌ (Custom NGINX) | ✅ `TCPRoute`/`UDPRoute`/`TLSRoute` |
| TLS passthrough | ⚠️ annotation hack | ✅ `tls.mode: Passthrough` + `TLSRoute` |
| Role separation | ❌ | ✅ `GatewayClass` / `Gateway` / route |
| Traffic split / canary | ⚠️ vendor annotations | ✅ `backendRefs[].weight` (first-class) |
| Header rewrite | ⚠️ annotation | ✅ `RequestHeaderModifier` filter |
| URL rewrite | ⚠️ annotation | ✅ `URLRewrite` filter (path / host) |
| Redirect | ⚠️ annotation | ✅ `RequestRedirect` filter |
| CORS | ⚠️ annotation | ✅ EG `SecurityPolicy.cors` (spec alpha) |
| Auth (JWT/OIDC) | ⚠️ annotation + Lua | ✅ EG `SecurityPolicy.oidc` / `jwt` |
| Rate limit | ⚠️ annotation | ✅ EG `SecurityPolicy.rateLimit` (local) |
| Cross-namespace | ❌ (only by Service name) | ✅ via `ReferenceGrant` |
| Mirror | ⚠️ annotation | ✅ `RequestMirror` (alpha) |
| Upstream mTLS | ❌ | ✅ `BackendTLSPolicy` |
| Listener merging | ❌ (only one resource) | ✅ (`parentRefs` + sectionName) |
| Vendor neutrality | ❌ (annotations differ) | ✅ (spec) |
| Conformance | ❌ (kustomize + chaos) | ✅ (`conformance` profile) |
| Maturity | GA 2016, slowly evolving | GA 2023 (v1.0), still adding features |
| Tooling (kustomize, helm) | ✅ broad | ✅ broad, less mature |
| nginx-1.0 EOL | n/a (project retiring) | n/a |

**Bottom line:** if you're on `ingress-nginx` and don't need L4 routing, canary traffic split, or true role separation, the migration is straightforward. If you do, Gateway API is a no-brainer. The migration is also one of the few good reasons to switch — `ingress-nginx` is being retired and the recommended successor is Envoy Gateway.

---

## 13. Common Pitfalls

1. **Forgetting to install Gateway API CRDs first.** EG will install its own CRDs, but it doesn't install the spec CRDs. Always: `kubectl apply -f standard-install.yaml` **before** installing EG.
2. **Wrong `gatewayClassName`.** `eg` is the default in EG, but if you changed it in Helm values, your Gateways need to match exactly.
3. **Route bound to a hostname the listener doesn't have.** Route shows `Accepted=False`, reason `NoMatchingParent`. The hostname intersection silently does nothing.
4. **Cross-namespace Service ref without `ReferenceGrant`.** `ResolvedRefs=False`, reason `RefNotPermitted`.
5. **Cert Secret type wrong.** `tls.certificateRefs` expects `kubernetes.io/tls`. A `Opaque` Secret with the right keys is rejected.
6. **TLS SANs don't match the hostname.** Browser shows `NET::ERR_CERT_COMMON_NAME_INVALID`. cert-manager's `dnsNames` is the source.
7. **Two listeners with same port+protocol on one Gateway.** Status `Conflicted`. Split port or hostname.
8. **BackendTLSPolicy targets a Service in another namespace without ReferenceGrant.** Same pattern as route refs.
9. **`backendRefs` with weight 0.** Treated as 0-weight, never gets traffic — useful for shadow but you probably want `RequestMirror` instead.
10. **Admission webhook not reachable.** EG installs a webhook; if the API server can't reach it (firewall, port), every `kubectl apply` hangs. Check `kubectl get validatingwebhookconfigurations`.

---

## 14. Future / Experimental (FYI)

- **GAMMA** — mesh use case, `Mesh` / `MeshGateway` resources. Not yet stable.
- **Multi-cluster Gateway** — single Gateway resources spanning clusters. Still alpha.
- **Egress Gateway** — outbound policy. Concept-level.
- **AuthPolicy / RateLimitPolicy in `experimental`** — spec-level, not EG. Conformance still pending.

Treat all of these as "interesting, do not bet a production deployment on them yet."
