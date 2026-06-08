# Ingress

*"https://kubernetes.io/docs/concepts/services-networking/ingress/"*

Ingress is the k8s-native way to expose **HTTP/HTTPS routes** to services from outside the cluster. It gives you hostname-based and path-based routing, TLS termination, and a single entry point — instead of one LoadBalancer per Service. It's the right tool for **L7 traffic into a cluster**; for raw TCP/UDP, use a LoadBalancer Service.

### Table of Contents

1. [What Ingress Actually Is](#1-what-ingress-actually-is)
2. [Basic Example](#2-basic-example)
3. [Path Matching and pathType](#3-path-matching-and-pathtype)
4. [Ingress Controllers — A Comparison](#4-ingress-controllers--a-comparison)
5. [TLS Termination and Cert Management](#5-tls-termination-and-cert-management)
6. [Annotations and Controller-Specific Behavior](#6-annotations-and-controller-specific-behavior)
7. [ingressClassName and Multiple Controllers](#7-ingressclassname-and-multiple-controllers)
8. [Default Backends and Hostless Routes](#8-default-backends-and-hostless-routes)
9. [Ingress vs LoadBalancer Service](#9-ingress-vs-loadbalancer-service)
10. [Gateway API — The Successor](#10-gateway-api--the-successor)
11. [Migration Path: Ingress → Gateway API](#11-migration-path-ingress--gateway-api)
12. [Operations and Debugging](#12-operations-and-debugging)
13. [Gotchas and Common Mistakes](#13-gotchas-and-common-mistakes)

---

## 1. What Ingress Actually Is

Two parts — and confusing this is a common mistake:

1. **Ingress resource** — the YAML you write. The k8s API object that declares "route `app.example.com` to the `frontend` Service, `api.example.com` to the `api` Service."
2. **Ingress controller** — the thing that reads those rules and configures a real reverse proxy (NGINX, Traefik, HAProxy, Envoy, ...).

The k8s API does **not** ship a controller. You install one yourself. An Ingress resource without a controller is just data in etcd — nothing routes anywhere.

```
                 Internet
                    │
                    ▼
            ┌──────────────┐
            │  Cloud LB    │  ← 1 LB, public IP, port 80/443
            └──────┬───────┘
                    │
                    ▼
        ┌───────────────────────┐
        │   Ingress Controller  │  ← runs in cluster (DaemonSet or Deployment)
        │   (nginx, Traefik, …) │
        │                       │
        │   reads Ingress       │
        │   resources and       │
        │   configures itself   │
        └───────────┬───────────┘
                    │
       ┌────────────┼────────────┐
       ▼            ▼            ▼
   Service      Service      Service
   frontend     api          admin
       │            │            │
       ▼            ▼            ▼
    Pod Pod      Pod Pod      Pod Pod
```

### 1.1 The four popular controllers

| Controller | Base | Strengths | Weaknesses |
|---|---|---|---|
| **ingress-nginx** | NGINX | Most common, mature, huge community, the k8s project's "blessed" one | Configuration via annotations (a sprawling API), no native service mesh features |
| **Traefik** | Traefik | Simpler config (CRDs), built-in dashboard, automatic Let's Encrypt | Smaller community, some advanced features behind Traefik Proxy Enterprise |
| **HAProxy Ingress** | HAProxy | High performance, mature HAProxy | Smaller community, less feature-rich than ingress-nginx |
| **Envoy Gateway / Contour** | Envoy | Gateway API native, modern, integrates well with service mesh | Newer, less documentation, more complex |

Pick based on your team's familiarity and operational model. **ingress-nginx is the safe default** — it has the largest community and the most documentation. Traefik is good if you want a simpler, dashboard-driven experience.

## 2. Basic Example

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
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
            name: frontend
            port:
              number: 80
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api
            port:
              number: 8080
  tls:
  - hosts:
    - app.example.com
    secretName: app-tls
```

Three rules in this Ingress:

* `app.example.com/` → frontend Service
* `app.example.com/api` → api Service
* TLS terminated at the Ingress, cert from the `app-tls` Secret

The `nginx.ingress.kubernetes.io/rewrite-target: /` annotation tells the NGINX controller to **strip the matched path prefix** before forwarding. So `/api/users/123` becomes `/users/123` when sent to the api Service. This is critical when the backend doesn't expect the `/api` prefix.

## 3. Path Matching and pathType

Each path needs a `pathType`. Three values:

| pathType | Matches | Use case |
|---|---|---|
| `Exact` | Only the exact path | `/healthz` for a health endpoint, `/metrics` for Prometheus |
| `Prefix` | The prefix, segment-by-segment | `/api` matches `/api`, `/api/users`, but not `/apiv2` |
| `ImplementationSpecific` | Whatever the controller wants | Avoid — deprecated, behavior varies |

### 3.1 The `Prefix` semantics — segment-by-segment

`Prefix` matching is **not substring matching**. `/api` matches `/api`, `/api/users`, `/api/v2/foo` — but **not** `/apiv2` or `/apifoo`.

```
/api         → matches /api, /api/, /api/users
/apifoo      → DOES NOT match (no segment boundary)
/api/v2      → matches
/apifoo/bar  → DOES NOT match
```

The match is on **path segments** (separated by `/`). For substring matching, you'd need `ImplementationSpecific` (and the controller's behavior is non-portable).

### 3.2 Trailing slash gotcha

`/api` and `/api/` are **the same Prefix** but the redirect behavior is different. The controller decides:

* `nginx.ingress.kubernetes.io/rewrite-target: /` and `path: /api` — requests to `/api/users` are rewritten to `/users` (prefix stripped).
* No rewrite, `path: /api` — requests to `/api/users` go to the backend as `/api/users` (the backend sees the prefix).

If your backend is mounted at `/` and you want the prefix stripped, use rewrite-target. If your backend is mounted at `/api`, don't.

## 4. Ingress Controllers — A Comparison

### 4.1 ingress-nginx

The kubernetes/community project. Most widely deployed. Uses NGINX under the hood.

* **Install:** `kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/cloud/deploy.yaml`
* **Config:** annotations on the Ingress resource. ~50+ annotations for rewrites, CORS, rate limiting, sticky sessions, etc.
* **Strong points:** mature, documented, the de-facto standard, lots of examples.
* **Weak points:** annotations are sprawling and controller-specific. Porting Ingress between controllers means rewriting annotations.

**Configmap-based tunings:** a few things are set in the controller's ConfigMap, not the Ingress annotations:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
data:
  proxy-body-size: "100m"          # max request body size
  proxy-read-timeout: "60"
  proxy-send-timeout: "60"
  use-forwarded-headers: "true"    # respect X-Forwarded-* from upstream LBs
  enable-rewrite-log: "true"
```

These affect the whole controller instance. Ingress-level config overrides them.

### 4.2 Traefik

A different model. Uses **IngressRoute** (a Traefik CRD) for routing, not the standard Ingress resource. You can use the standard Ingress too, but you lose Traefik's features.

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: app
spec:
  entryPoints:
    - websecure
  routes:
  - match: Host(`app.example.com`) && PathPrefix(`/api`)
    kind: Rule
    services:
    - name: api
      port: 8080
  tls:
    certResolver: letsencrypt
```

* **Install:** Helm chart.
* **Config:** CRDs (more expressive than annotations) + a dashboard.
* **Strong points:** simpler config, built-in dashboard, automatic Let's Encrypt with certResolver.
* **Weak points:** uses CRDs (not standard Ingress); switching controllers means rewriting routes.

### 4.3 HAProxy Ingress

The HAProxy-based controller. Less common, but used in some on-prem setups.

* **Install:** Helm chart or YAML manifests.
* **Config:** annotations.
* **Strong points:** HAProxy's performance, mature load-balancing logic.
* **Weak points:** smaller community, less documentation.

### 4.4 Envoy-based (Contour, Envoy Gateway)

Envoy as the data plane. These are the most Gateway-API-native options.

**Contour:** the Heptio / VMware project. Uses HTTPProxy CRD.
**Envoy Gateway:** newer, the CNCF-blessed Gateway API implementation.

* **Install:** Helm chart or Gateway API CRDs.
* **Config:** Gateway API (forward-looking) or HTTPProxy (Contour's CRD).
* **Strong points:** modern, Gateway API native, integrates with service mesh.
* **Weak points:** newer, less documentation, Gateway API still stabilizing.

## 5. TLS Termination and Cert Management

### 5.1 The TLS section

```yaml
spec:
  tls:
  - hosts:
    - app.example.com
    - api.example.com
    secretName: app-tls
```

The `secretName` is a Kubernetes Secret of type `kubernetes.io/tls`:

```bash
kubectl create secret tls app-tls \
  --cert=path/to/cert.pem \
  --key=path/to/key.pem
```

The Secret must be in the **same namespace as the Ingress**. The controller reads it, configures its reverse proxy, and serves the cert on the matching hosts.

### 5.2 Multiple TLS entries

```yaml
spec:
  tls:
  - hosts:
    - app.example.com
    secretName: app-tls
  - hosts:
    - api.example.com
    secretName: api-tls
```

Different hosts can have different certs. The controller does SNI routing — when a client connects, it presents the cert matching the requested hostname.

### 5.3 Wildcard certs

```yaml
spec:
  tls:
  - hosts:
    - "*.example.com"
    secretName: wildcard-tls
```

Wildcard certs work, but be aware: a wildcard cert for `*.example.com` doesn't cover `example.com` itself. You need a cert with both `example.com` and `*.example.com` in the SAN list.

### 5.4 Cert-manager — automatic provisioning

Hand-creating TLS Secrets is a chore. **cert-manager** is the de-facto standard for automated cert management in k8s.

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: app
  namespace: default
spec:
  secretName: app-tls
  dnsNames:
  - app.example.com
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
```

cert-manager:

1. Creates a `Certificate` resource
2. Sees the `Issuer` / `ClusterIssuer` (configured to use Let's Encrypt)
3. Performs the ACME challenge (HTTP-01 or DNS-01)
4. Gets the cert from Let's Encrypt
5. Stores it in the `app-tls` Secret
6. Renews before expiry

The Ingress references the same Secret. cert-manager and the controller don't need to know about each other — they both just read the Secret.

**DNS-01 challenge** is needed for wildcard certs and when HTTP-01 isn't possible (private services, etc.). Requires a DNS provider integration (Route53, Cloudflare, etc.).

### 5.5 TLS passthrough vs termination

Most Ingress controllers support two modes:

* **TLS termination** — the controller terminates TLS, decrypts the request, and forwards plain HTTP to the backend.
* **TLS passthrough** — the controller forwards the encrypted TCP stream to the backend, which terminates TLS itself. Used when the backend needs the original cert (mTLS, mutual auth).

```yaml
# ingress-nginx TLS passthrough
metadata:
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: HTTPS
spec:
  tls:
  - hosts:
    - app.example.com
    secretName: app-tls      # used for SNI matching, not for termination
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app
            port:
              number: 443   # backend listens on 443
```

The controller uses the cert for SNI (to know where to route), but the actual TLS session is between the client and the backend. **End-to-end encryption without a sidecar.**

## 6. Annotations and Controller-Specific Behavior

Annotations are **per-controller**. The same Ingress resource with the same annotation may mean different things on different controllers.

### 6.1 ingress-nginx's most-used annotations

```yaml
metadata:
  annotations:
    # rewrites
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    # SSL redirect
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    # CORS
    nginx.ingress.kubernetes.io/cors-allow-origin: "https://app.example.com"
    nginx.ingress.kubernetes.io/cors-allow-methods: "GET, POST, OPTIONS"
    # rate limiting
    nginx.ingress.kubernetes.io/limit-rps: "100"
    # body size
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    # sticky sessions
    nginx.ingress.kubernetes.io/affinity: "cookie"
    nginx.ingress.kubernetes.io/session-cookie-name: "route"
    nginx.ingress.kubernetes.io/session-cookie-expires: "172800"
    # WebSocket
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    # backend protocol
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    # custom headers
    nginx.ingress.kubernetes.io/custom-headers: "kube-system/custom-headers"
```

**The `rewrite-target` syntax is controller-specific.** ingress-nginx uses `$1`, `$2` for capture groups. Traefik uses a different syntax. HAProxy uses yet another.

### 6.2 The annotation migration problem

If you switch from ingress-nginx to Traefik, you have to rewrite your annotations. The Ingress resource spec (paths, hosts, backends) is portable, but the metadata is not. **This is one of the strongest arguments for Gateway API** — it standardizes the routing API itself, not just the resource spec.

## 7. ingressClassName and Multiple Controllers

A cluster can have **multiple Ingress controllers** running. The `ingressClassName` field on the Ingress routes the resource to the right controller.

```yaml
spec:
  ingressClassName: nginx
```

The cluster admin defines IngressClasses:

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
spec:
  controller: k8s.io/ingress-nginx   # the controller that handles this class
```

An Ingress without `ingressClassName` is treated according to the cluster's default IngressClass (if one is set):

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
spec:
  controller: k8s.io/ingress-nginx
```

**At most one IngressClass can be the default.** Setting two with the annotation makes the admission reject both.

### 7.1 The legacy `kubernetes.io/ingress.class` annotation

Before `ingressClassName` existed (k8s 1.18+), you used the annotation `kubernetes.io/ingress.class: nginx`. This still works for backward compatibility but is deprecated. **New Ingress resources should use `ingressClassName`.**

## 8. Default Backends and Hostless Routes

### 8.1 The default backend

In `extensions/v1beta1`, you could define a "default backend" — the Service that handles any request that didn't match a rule. This was removed in `networking.k8s.io/v1`.

If you want a "404 page" or "catch-all", make a real route. The new model doesn't have a default backend for the resource itself, but you can simulate one with a wide host (`host: ""`) and a Prefix `/`:

```yaml
spec:
  rules:
  - host: ""   # matches any host
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: catchall
            port:
              number: 80
```

But be careful — this catches **everything** that doesn't match a more specific rule. Most teams don't actually need this.

### 8.2 Hostless routes

`host: ""` (or omitting the host entirely) matches any hostname. Use cases:

* Internal cluster services that don't have a public DNS name
* A "default vhost" that serves anything
* Wildcard certs

```yaml
spec:
  ingressClassName: nginx
  rules:
  - http:                          # no host → matches any host
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: internal-app
            port:
              number: 80
```

## 9. Ingress vs LoadBalancer Service

| | Ingress | LoadBalancer Service |
|---|---|---|
| **Layer** | L7 (HTTP) | L4 (TCP/UDP) |
| **Use case** | HTTPS routes by host/path | Raw TCP/UDP, non-HTTP (DB, game server) |
| **Cost on cloud** | One LB for many Services | One LB per Service |
| **TLS** | Terminated at the Ingress | At the Service / client |
| **Path routing** | Yes | No |
| **Hostname routing** | Yes | No (the LB is per Service) |
| **WebSocket** | Supported | Trivial (raw TCP) |
| **gRPC** | Supported (with controller support) | Trivial (raw TCP) |

If you have 30 microservices and 1 LB, use Ingress. If you're exposing a Postgres port, use LoadBalancer (or NodePort for dev).

**The cost calculus:** a typical NLB on AWS is $20-30/month. 30 LoadBalancer Services = $600-900/month just for LBs. One Ingress behind one NLB = $20-30/month. **Ingress is a major cost optimization for HTTP-heavy clusters.**

## 10. Gateway API — The Successor

The [Gateway API](https://gateway-api.sigs.k8s.io/) is the next-gen replacement for Ingress. It's **GA in k8s 1.30+** (2024), and most major controllers support it.

### 10.1 Why Gateway API

* **More expressive** — header-based routing, traffic splitting, request mirroring, A/B testing, weighted routing.
* **Multi-tenant by design** — GatewayClass → Gateway → Routes, with RBAC at each level.
* **Cross-protocol** — HTTP, gRPC, TCP, UDP, TLS.
* **Portable** — the resource model is standardized, not the controller-specific annotations. Switching controllers is much easier.
* **Better for service mesh** — Gateway API is the basis for Istio's ingress and Cilium's service mesh.

### 10.2 The Gateway API model

```
GatewayClass  (cluster-scoped, defined by infra team)
   │
   │  (defines which controller handles this class)
   ▼
Gateway        (cluster or namespace-scoped, infra team deploys)
   │
   │  (defines listeners — ports, protocols, TLS)
   ▼
HTTPRoute      (namespace-scoped, app team deploys)
   │
   │  (defines routing rules — paths, headers, methods)
   ▼
Services
```

Separation of concerns:
- **Infra team** owns the GatewayClass and the Gateway (the load balancer, the public IP, the TLS).
- **App team** owns the HTTPRoute (the routing rules for their app).

This matches how organizations actually work. Ingress doesn't have this separation — the Ingress resource is one big YAML that the app team writes, and they need to know about TLS, the controller, etc.

### 10.3 Gateway API example

```yaml
# GatewayClass (cluster-scoped, infra team)
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy-gateway
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
---
# Gateway (infra team)
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: public-gateway
  namespace: infra
spec:
  gatewayClassName: envoy-gateway
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
  - name: https
    port: 443
    protocol: HTTPS
    tls:
      mode: Terminate
      certificateRefs:
      - name: public-cert
        kind: Secret
    allowedRoutes:
      namespaces:
        from: All
---
# HTTPRoute (app team)
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app
  namespace: default
spec:
  parentRefs:
  - name: public-gateway
    namespace: infra
  hostnames:
  - app.example.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api
    backendRefs:
    - name: api
      port: 8080
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: frontend
      port: 80
```

### 10.4 Gateway API resources

| Resource | Purpose |
|---|---|
| `GatewayClass` | Defines a controller (cluster-scoped) |
| `Gateway` | A load balancer instance with listeners (port, protocol, TLS) |
| `HTTPRoute` | L7 routing rules (paths, headers, methods) |
| `TCPRoute` | L4 routing |
| `UDPRoute` | L4 routing |
| `TLSRoute` | TLS passthrough routing |
| `GRPCRoute` | gRPC routing with method matching |
| `ReferenceGrant` | RBAC for cross-namespace references |

### 10.5 What Gateway API gives you that Ingress doesn't

* **Header-based routing** — `match.headers: { x-version: v2 }` → backend v2.
* **Method-based routing** — `GET /users` → read service, `POST /users` → write service.
* **Query parameter matching** — `?debug=true` → debug backend.
* **Traffic splitting** — 90% to v1, 10% to v2.
* **Request mirroring** — duplicate traffic to a test backend.
* **Request redirect / rewrite** — `redirect: { statusCode: 301, hostname: new.example.com }`.
* **Cross-namespace references** — Route in `default` can reference Service in `prod`, with explicit RBAC.
* **Multiple listeners** — one Gateway with HTTP and HTTPS listeners, on the same or different ports.
* **Better RBAC** — separate permissions for GatewayClass, Gateway, Routes.

## 11. Migration Path: Ingress → Gateway API

You don't have to migrate everything at once. The standard migration path:

1. **Install a Gateway API controller** (Envoy Gateway, Contour, NGINX Gateway Fabric). It can run alongside your existing Ingress controller.
2. **Create a GatewayClass and Gateway** that mirrors your existing Ingress setup.
3. **Migrate one app at a time** — create an HTTPRoute for it, point DNS, verify, then delete the old Ingress.
4. **Once all Ingresses are migrated**, remove the old controller.

Most Gateway API controllers support **both** Ingress and Gateway resources during the migration.

**The migration is most painful in the YAML — the routing rules are different.** The good news is the k8s ecosystem is moving toward Gateway API, so new projects should start there.

## 12. Operations and Debugging

### 12.1 Common commands

```bash
# list ingresses and their addresses
kubectl get ingress -A
# ADDRESS column shows the LB hostname/IP

# describe
kubectl describe ingress <name>
# shows events, controller, backend, errors

# check the controller
kubectl -n ingress-nginx get pods    # or whatever namespace your controller is in
kubectl -n ingress-nginx logs <pod> --tail=100

# test from outside the cluster
curl -H "Host: app.example.com" http://<ingress-ip>/
# should return the app's response

# test from inside a Pod
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- bash
curl -v http://app.example.com/   # if DNS resolves to the Ingress IP

# check the IngressClass
kubectl get ingressclass
```

### 12.2 The "Ingress not working" checklist

```bash
# 1. Is the controller running?
kubectl -n ingress-nginx get pods
kubectl -n ingress-nginx get svc      # should have a LoadBalancer IP

# 2. Is the Ingress admitted by the controller?
kubectl describe ingress <name>
# look for events — "ingress added", "ingress updated", or errors

# 3. Does the Ingress have an ADDRESS?
kubectl get ingress <name>
# ADDRESS column should not be empty

# 4. Is the backend Service running?
kubectl get svc <backend>
kubectl get endpoints <backend>

# 5. Can the controller reach the backend?
kubectl -n ingress-nginx exec -it <pod> -- curl http://<backend-svc>.<ns>.svc.cluster.local
# (the controller runs in the cluster's network)

# 6. Test with a real client
curl -H "Host: app.example.com" http://<ingress-ip>/
# 404? 503? 200?

# 7. Check the controller logs for the request
kubectl -n ingress-nginx logs <pod> --tail=20 -f
# make a request, see if it shows up
```

### 12.3 The "503 Service Unavailable" debugging

A 503 from the Ingress means the controller can reach the Service but the Service has no backends. Common causes:

* The Pods aren't Ready (readiness probe failing)
* The Service has the wrong selector
* The Service has the wrong port

```bash
# check the Service's endpoints
kubectl get endpoints <svc>   # should list the Pod IPs
# if empty, the selector is wrong or no Pods are Ready

# check the Pod's readiness
kubectl get pods -l <selector>
# all should be 1/1 Ready
```

### 12.4 The "404 Not Found" debugging

A 404 from the Ingress means the controller received the request but no Ingress rule matches. Common causes:

* The host doesn't match any rule's `host`
* The path doesn't match any rule's `path`
* The Ingress has no rules at all

```bash
# check the Ingress
kubectl get ingress <name> -o yaml
# look at spec.rules — is there a matching rule?

# check the request
curl -v -H "Host: app.example.com" http://<ingress-ip>/
# the controller logs should show which rule was matched (or not)
```

## 13. Gotchas and Common Mistakes

### 13.1 The 25+ common mistakes

1. **Forgetting to install a controller.** The Ingress resource is just data without a controller. Always `kubectl get pods -n <controller-namespace>` to verify.

2. **Using the wrong `pathType` for the use case.** `Exact` for "/healthz", `Prefix` for "/api". `ImplementationSpecific` is deprecated — avoid.

3. **Forgetting `ingressClassName`** when you have multiple controllers. The Ingress may be picked up by the wrong one (or none).

4. **TLS Secret in a different namespace than the Ingress.** Ingresses can't reference Secrets in other namespaces. Move them or use ReferenceGrant (Gateway API).

5. **TLS Secret not of type `kubernetes.io/tls`.** It must have keys `tls.crt` and `tls.key`. A `Opaque` Secret with the right keys won't work.

6. **Rewriting the path when you shouldn't (or vice versa).** `rewrite-target: /` with `path: /api` strips the prefix. If the backend is mounted at `/api`, drop the rewrite.

7. **Same TLS cert for multiple hosts without a wildcard.** A cert for `app.example.com` doesn't cover `api.example.com`. Get a cert with both, or use SNI with multiple TLS entries.

8. **Wildcard cert doesn't cover the bare domain.** A cert for `*.example.com` doesn't cover `example.com`. Add both to the SAN list.

9. **Annotations are controller-specific.** `nginx.ingress.kubernetes.io/rewrite-target` means nothing to Traefik. Switching controllers means rewriting annotations.

10. **The Ingress LB's health check.** Cloud LBs do health checks on the controller. If the controller's health endpoint (default `/healthz` on :10254 for ingress-nginx) fails, the LB sends no traffic. Make sure the controller is healthy.

11. **The controller's pod is in `ingress-nginx` (or `kube-system`, or wherever).** Remember the namespace when debugging.

12. **`backend.service.name` and `backend.service.port.name` vs `number`.** You can reference a port by number or by name. If the Service has multiple ports, use names.

13. **No TLS, no HTTPS redirect.** A common request: "redirect HTTP to HTTPS". `nginx.ingress.kubernetes.io/ssl-redirect: "true"` does this for ingress-nginx. Other controllers have their own annotations.

14. **Default backend confusion.** The old `extensions/v1beta1` default backend is gone. Make a real route.

15. **Ingress behind another LB (CDN, WAF).** The controller sees the LB's IP as the client. To preserve the original client IP, enable `use-forwarded-headers: "true"` (ingress-nginx) or its equivalent.

16. **Body size too small.** Default is 1m. For file uploads, increase: `nginx.ingress.kubernetes.io/proxy-body-size: "100m"`.

17. **WebSocket timeouts.** Default read/send timeouts are 60s. WebSocket connections need much longer: `3600`.

18. **WebSocket routes through the controller.** NGINX buffers WebSocket frames by default. For long-lived connections, disable buffering.

19. **gRPC requires HTTP/2.** Most controllers do HTTP/2 by default, but check. `nginx.ingress.kubernetes.io/backend-protocol: "GRPC"`.

20. **Long-running requests time out.** Default `proxy-read-timeout` is 60s. For long reports, large exports, etc., increase it.

21. **Backend protocol mismatch.** If the backend listens on HTTPS but the Ingress is configured for HTTP, the connection fails. Set `backend-protocol` correctly.

22. **IngressClass as a default — only one can be default.** Setting two with the annotation makes admission reject both. The error is sometimes confusing.

23. **TLS passthrough requires backend on 443.** The controller uses the cert for SNI matching, then forwards TCP. The backend terminates TLS itself.

24. **HSTS and other security headers require annotations.** Add them: `nginx.ingress.kubernetes.io/configuration-snippet` (deprecated) or use `custom-headers` ConfigMap.

25. **The Ingress's `spec.ingressClassName` is a pointer to an IngressClass, not a controller name.** Don't confuse the two.

26. **The IngressClass's `spec.controller` is a vendor-specific string.** `k8s.io/ingress-nginx`, `traefik.io/ingress-controller`, etc. They must match the controller's actual identifier.

27. **A new Ingress resource is admitted but has no ADDRESS for a while.** The controller takes a few seconds to pick it up and configure itself. The ADDRESS field is populated once the controller has configured the LB.

28. **The Ingress controller's logs are in the controller's namespace, not the Ingress's namespace.** Remember which namespace the controller is in.

29. **Ingress is being deprecated in favor of Gateway API, but it's not gone.** k8s 1.30+ has both GA. Ingress is fully supported, and the deprecation is "in the long term" — likely years.

30. **Ingresses for the same host with overlapping paths.** Multiple Ingresses for the same host are merged by the controller. The "most specific" path wins for each request. If two Ingresses both define `path: /`, the behavior is controller-specific.

31. **The Ingress controller's Helm chart manages its own RBAC, ServiceAccount, etc.** Installing via Helm is preferred to YAML manifests because the chart handles upgrades.

32. **`kubectl describe ingress` is the fastest way to debug.** It shows events (admission, configuration, errors), the address, the rules, the backends. Use it first.

## See also

* [[Kubernetes/concepts/L04-services-networking/01-networking|Networking]] — the L04 mental model
* [[Kubernetes/concepts/L04-services-networking/02-services|Services]] — the backends Ingress routes to
* [[Kubernetes/concepts/L04-services-networking/03-dns|DNS]] — how external clients find the Ingress
* [[Kubernetes/concepts/L04-services-networking/06-cni|CNI]] — the layer below
* [[Kubernetes/concepts/L04-services-networking/07-k8s-networking-deep-dive|Networking Deep Dive]] — packet walkthroughs
