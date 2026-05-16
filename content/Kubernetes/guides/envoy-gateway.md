---
title: Envoy Gateway
tags: [Kubernetes, Networking, Ingress, API Gateway]
date: 2026-05-16
description: Manage Envoy Proxy as a Kubernetes-based application gateway using the Gateway API
---

# Envoy Gateway

[Envoy Gateway](https://gateway.envoyproxy.io/) is an open source project that manages Envoy Proxy as a standalone or Kubernetes-based application gateway. It uses [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/) resources to dynamically provision and configure the managed Envoy Proxies.

Envoy Gateway simplifies configuring Envoy Proxy by implementing and extending the Kubernetes Gateway API. You define high-level traffic rules using resources like `Gateway`, `HTTPRoute`, or `TLSRoute`, and Envoy Gateway automatically translates them into detailed Envoy Proxy configurations.

## Overview

An API gateway is a centralized entry point for managing, securing, and routing requests to backend services. It handles cross-cutting concerns like authentication, rate limiting, and protocol translation, so individual services don't have to.

**Key capabilities:**
- Traffic management (routing, load balancing, retries, circuit breaking)
- Security (mTLS, JWT authentication, OIDC, API keys)
- Rate limiting (global and local)
- Observability (metrics, logging, distributed tracing)
- Extensibility (Wasm, Lua, external processing)

## Installation

### Prerequisites

- Kubernetes cluster (1.27+)
- Helm 3.x

### Install with Helm

```shell
helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.8.0 -n envoy-gateway-system --create-namespace
```

Wait for Envoy Gateway to become available:

```shell
kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available
```

Install the GatewayClass, Gateway, HTTPRoute, and example app:

```shell
kubectl apply -f https://github.com/envoyproxy/gateway/releases/download/v1.8.0/quickstart.yaml -n default
```

### Verify Installation

```shell
export GATEWAY_HOST=$(kubectl get gateway/eg -o jsonpath='{.status.addresses[0].value}')
curl --verbose --header "Host: www.example.com" http://$GATEWAY_HOST/get
```

## Core Concepts

### Gateway API

The [Gateway API](https://gateway.envoyproxy.io/docs/concepts/gateway-api/) is a Kubernetes API designed to provide a consistent, expressive, and extensible method for managing network traffic into and within a Kubernetes cluster. It introduces:

- **GatewayClass** - Defines a class of gateways (similar to IngressClass)
- **Gateway** - Listener configuration and IP allocation
- **HTTPRoute/GRPCRoute/TCPRoute** - Traffic routing rules
- **ReferenceGrant** - Cross-namespace reference permissions

### Envoy Gateway Extensions

Envoy Gateway extends the Gateway API with custom resources:

- **BackendTrafficPolicy** - Rate limiting, load balancing, circuit breaking
- **ClientTrafficPolicy** - TLS configuration, connection limits
- **SecurityPolicy** - Authentication, authorization, CORS

## Quick Example

Create a Gateway with HTTP and HTTPS listeners:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: eg
spec:
  gatewayClassName: eg
  listeners:
    - name: http
      protocol: HTTP
      port: 80
    - name: https
      protocol: HTTPS
      port: 443
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: example-cert
```

Create an HTTPRoute to route traffic:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: backend
spec:
  parentRefs:
    - name: eg
  hostnames:
    - www.example.com
  rules:
    - backendRefs:
        - name: backend-service
          port: 8080
```

## Security

### TLS Termination

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: eg
spec:
  gatewayClassName: eg
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: example-cert
```

### JWT Authentication

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: jwt-auth
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: backend
  jwt:
    providers:
      - name: example
        issuer: https://example.com
        audiences:
          - api.example.com
        remoteJWKS:
          url: https://example.com/.well-known/jwks.json
```

## Rate Limiting

### Global Rate Limiting

Shared limits across all Envoy instances via external Rate Limit Service:

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: BackendTrafficPolicy
metadata:
  name: global-ratelimit
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: my-api
  rateLimit:
    global:
      rules:
        - limit:
            requests: 100
            unit: Minute
```

### Local Rate Limiting

Independent limits per Envoy instance:

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: BackendTrafficPolicy
metadata:
  name: local-ratelimit
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: my-api
  rateLimit:
    local:
      rules:
        - limit:
            requests: 50
            unit: Minute
```

## Traffic Management

### HTTP Routing

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: http-routing
spec:
  parentRefs:
    - name: eg
  hostnames:
    - api.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /users
      backendRefs:
        - name: users-service
          port: 8080
    - matches:
        - path:
            type: PathPrefix
            value: /products
      backendRefs:
        - name: products-service
          port: 8080
```

### Traffic Splitting

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: canary
spec:
  parentRefs:
    - name: eg
  rules:
    - backendRefs:
        - name: backend-v1
          weight: 90
        - name: backend-v2
          weight: 10
```

## Observability

### Metrics

Envoy Gateway exposes metrics at `0.0.0.0:19001`. Configure Prometheus scraping:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: envoy-gateway
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: envoy-gateway
  endpoints:
    - port: metrics
```

### Access Logging

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: ClientTrafficPolicy
metadata:
  name: access-log
spec:
  targetRefs:
    - kind: Gateway
      name: eg
  accessLogging:
    - type: File
      file:
        path: /dev/stdout
```

## Deployment Modes

### Kubernetes Mode (Default)

Envoy Gateway runs as a Kubernetes deployment with a managed Envoy data plane.

### Standalone Mode

For non-Kubernetes environments:

```shell
envoy-gateway serve --config envoy-gateway.yaml
```

## Ports Reference

### Envoy Gateway Control Plane

| Service | Address | Port |
|---------|---------|------|
| Xds EnvoyProxy Server | 0.0.0.0 | 18000 |
| Xds RateLimit Server | 0.0.0.0 | 18001 |
| Admin Server | 127.0.0.1 | 19000 |
| Metrics Server | 0.0.0.0 | 19001 |

### Envoy Proxy Data Plane

| Service | Address | Port |
|---------|---------|------|
| Admin Server | 127.0.0.1 | 19000 |
| Stats | 0.0.0.0 | 19001 |
| Shutdown Manager | 0.0.0.0 | 19002 |
| Readiness | 0.0.0.0 | 19003 |

## Integrations

Envoy Gateway integrates with:
- **Argo CD** - GitOps deployment
- **Flux CD** - GitOps deployment
- **cert-manager** - Automated TLS certificate management
- **Istio** - Complementary service mesh capabilities
- **Knative** - Serverless workloads
- **KServe** - ML inference serving

## References

- [Official Documentation](https://gateway.envoyproxy.io/docs/)
- [GitHub Repository](https://github.com/envoyproxy/gateway)
- [Quickstart Guide](https://gateway.envoyproxy.io/docs/tasks/quickstart/)
- [Gateway API Spec](https://gateway-api.sigs.k8s.io/)
- [Compatibility Matrix](https://gateway.envoyproxy.io/news/releases/matrix/)