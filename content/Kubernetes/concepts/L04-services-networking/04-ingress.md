# Ingress

*"https://kubernetes.io/docs/concepts/services-networking/ingress/"*

Ingress is the k8s-native way to expose **HTTP/HTTPS routes** to services from outside the cluster. It gives you hostname-based and path-based routing, TLS termination, and a single entry point — instead of one LoadBalancer per Service.

## What it actually is

Two parts:

1. **Ingress resource** — the YAML you write (the rules)
2. **Ingress controller** — the thing that reads those rules and configures a real reverse proxy (NGINX, Traefik, HAProxy, Envoy, ...)

The k8s API does **not** ship a controller. You install one yourself. The most common are:

* ingress-nginx (the kubernetes project's NGINX-based one)
* Traefik
* HAProxy Ingress
* Envoy Gateway / Contour

In practice: **Ingress is a spec; IngressController is the implementation.**

## Basic example

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

* `app.example.com/` → frontend
* `app.example.com/api` → api
* TLS terminated at the Ingress, cert from the `app-tls` Secret

## pathType

Each path needs a `pathType`:

* `Exact` — match only the exact path (`/foo` matches only `/foo`)
* `Prefix` — match the prefix, segment-by-segment (`/foo` matches `/foo` and `/foo/bar`, not `/foobar`)
* `ImplementationSpecific` — implementation-defined behavior (deprecated; avoid)

## ingressClassName

Replaces the older `kubernetes.io/ingress.class` annotation. Multiple controllers in a cluster? Each Ingress specifies which one it belongs to.

```yaml
spec:
  ingressClassName: nginx
```

## TLS

```yaml
spec:
  tls:
  - hosts:
    - app.example.com
    secretName: app-tls
```

The Secret must be of type `kubernetes.io/tls` with keys `tls.crt` and `tls.key`. For automated cert provisioning, use cert-manager.

## Ingress vs LoadBalancer Service

| | Ingress | LoadBalancer Service |
|---|---|---|
| Layer | L7 (HTTP) | L4 (TCP/UDP) |
| Use case | HTTPS routes by host/path | Raw TCP/UDP, non-HTTP (DB, game server) |
| Cost on cloud | One LB for many services | One LB per Service |
| TLS | Terminated at the Ingress | At the Service / client |

If you have 30 microservices and 1 LB, use Ingress. If you're exposing a Postgres port, use LoadBalancer (or NodePort for dev).

## Gateway API (the future)

The [Gateway API](https://gateway-api.sigs.k8s.io/) is the next-gen replacement for Ingress:

* More expressive (route matching, header-based routing, traffic splitting)
* Multi-tenant by design (GatewayClass → Gateway → Routes)
* Cross-protocol (HTTP, gRPC, TCP, UDP)

The Gateway API is GA as of k8s 1.30. Most controllers support it now. If you're starting a new deployment, use Gateway API. If you have an existing Ingress setup, it still works fine.

## Gotchas

* **You need a controller installed.** A bare Ingress resource does nothing.
* **Path matching changed between `extensions/v1beta1` and `networking.k8s.io/v1`.** Old manifests that "worked" silently break — `pathType` is now required.
* **`rewrite-target` is implementation-specific.** `nginx.ingress.kubernetes.io/rewrite-target` is an annotation only the NGINX controller understands. Traefik uses different annotations.
* **Default backends are deprecated** (k8s 1.20+). If you want a "404 page" or "catch-all", make a real route.
* **Hostless routes** (`host: ""`) match any host. Use with care.
* **TLS secret must be in the same namespace as the Ingress.**
* **Ingress is per-namespace** — an Ingress in `ns-a` cannot route to a Service in `ns-b` without explicit configuration (`backend.service.name` with a namespace, or implementation-specific annotations).
