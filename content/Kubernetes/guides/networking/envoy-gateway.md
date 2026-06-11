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
- [EKS Workshop - Gateway API](https://www.eksworkshop.com/docs/networking/gateway-api/)

---

# Envoy Gateway on EKS

Using Envoy Gateway with AWS EKS involves several EKS-specific considerations: IRSA for IAM, VPC CNI networking, and how it compares to the AWS Load Balancer Controller.

## EKS Installation

### Prerequisites

- EKS cluster (1.27+) with kubectl configured
- Helm 3.x
- AWS IAM permissions for IRSA (optional but recommended)

### Install with IRSA (Recommended)

Create an IAM role bound to the Envoy Gateway service account via IRSA:

```bash
# Create IAM policy for Envoy Gateway
aws iam create-policy \
  --policy-name EnvoyGatewayPolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["logs:PutLogEvents", "cloudwatch:PutMetricData"],
      "Resource": "*"
    }]
  }'

# Create IRSA
eksctl create iamserviceaccount \
  --name envoy-gateway \
  --namespace envoy-gateway-system \
  --cluster <cluster-name> \
  --policy-name EnvoyGatewayPolicy \
  --approve
```

Then install via Helm with IRSA enabled:

```bash
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.8.0 \
  -n envoy-gateway-system \
  --create-namespace \
  --set securityContext.enableSCC=true
```

### Install Gateway API CRDs (Provider-Managed)

If your EKS cluster already has Gateway API CRDs managed by AWS (EKS 1.29+ may include them):

```bash
# Check existing CRDs
kubectl get crd gatewayclasses.gateway.networking.k8s.io

# If CRDs exist, skip CRD installation
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.8.0 \
  -n envoy-gateway-system \
  --create-namespace \
  --set Gateway.APIVersion=gateway.networking.k8s.io/v1
```

## AWS VPC CNI Considerations

Envoy Gateway pods use VPC CNI for networking (same as other EKS workloads). Key points:

### ENI and IP Allocation

- Envoy Gateway control plane pods get secondary ENIs from the node subnet
- Each pod receives an IP from the node's subnet range
- No additional NAT required — pods have direct VPC connectivity

### Security Groups for Pods

If using Security Groups for Pods (SGP) with VPC CNI:

```yaml
apiVersion: vpcresources.k8s.aws/v1alpha1
kind: SecurityGroupPolicy
metadata:
  name: envoy-gateway-sgp
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: envoy-gateway
  securityGroups:
    - sg-xxxxxxxx  # Security group allowing control plane traffic
```

### Subnet Requirements

Ensure subnets have sufficient IP capacity:
- Envoy Gateway control plane: 2-3 pods typically
- Each Envoy proxy: 1 IP per configured listener
- Plan for HTTPRoute backend expansions

## Gateway API vs AWS Load Balancer Controller

| Aspect | Envoy Gateway | AWS LB Controller |
|--------|--------------|-------------------|
| **API Model** | Gateway API (native K8s) | AWS Load Balancer Controller (Ingress/NLB) |
| **Traffic Type** | L7 HTTP/HTTPS/gRPC | L4 NLB, L7 ALB |
| **Config Style** | Declarative Gateway/HTTPRoute | Ingress annotations |
| **Feature Scope** | API gateway (auth, rate-limit, routing) | Cloud integration (WAF, health checks) |
| **Cloud Awareness** | No | Yes (subnet selection, CC/SG) |

### When to Use Envoy Gateway on EKS

- You want standardized Gateway API across clusters (multi-cloud)
- You need advanced L7 features (JWT auth, rate limiting, circuit breaking)
- You already use Gateway API for other providers (GKE, AKS)
- You want to avoid AWS-specific ingress annotations

### When to Use AWS LB Controller

- You need NLB for non-HTTP workloads (TCP, TLS passthrough)
- You need AWS WAF integration at the ALB level
- You want AWS-native health checks and cross-zone load balancing
- You don't need Gateway API features

### Running Both Together

It's possible to run both — use AWS LB Controller for NLB/Ingress and Envoy Gateway for Gateway API routing within the cluster:

```yaml
# External NLB via AWS LB Controller
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nlb-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
```

## EKS-Specific Gateway Example

### Gateway with TLS Termination

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: eg
  annotations:
    eks.amazonaws.com/cert-cluster: "us-west-2"
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
            # cert-manager creates this
  addresses:
    - type: LoadBalancer
      value: internal  # For internal-facing gateway
```

### HTTPRoute with Service Export (Multi-Cluster)

If using EKS Connector or multi-cluster service discovery:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: multi-cluster-route
  annotations:
    networking.kgateway.dev/export-namespace: default
spec:
  parentRefs:
    - name: eg
      namespace: envoy-gateway-system
  hostnames:
    - api.example.com
  rules:
    - backendRefs:
        - name: backend-service
          port: 8080
```

### IRSA for Backend Authentication

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backend-app
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/BackendAppRole
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: backend-with-irsa
spec:
  parentRefs:
    - name: eg
  rules:
    - backendRefs:
        - name: backend-app
          port: 8080
          # Traffic uses pod IP; IRSA handles AWS API auth
```

## Observability on EKS

### CloudWatch Metrics

Envoy Gateway metrics can be scraped by ADOT (AWS Distro for OpenTelemetry):

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: adot-collector
spec:
  mode: daemonset
  config: |
    receivers:
      prometheus:
        config:
          scrape_configs:
            - job_name: envoy-gateway
              static_configs:
                - targets: ['envoy-gateway.envoy-gateway-system:19001']
    exporters:
      awscw:
        region: us-west-2
        log_group_name: /eks/envoy-gateway/metrics
    service:
      pipelines:
        prometheus/awscw:
          receivers: [prometheus]
          exporters: [awscw]
```

### Access Logs to CloudWatch

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: ClientTrafficPolicy
metadata:
  name: cloudwatch-access-log
spec:
  targetRefs:
    - kind: Gateway
      name: eg
  accessLogging:
    - type: File
      file:
        path: /dev/stdout
  # Parse with: kubectl logs -n envoy-gateway-system -l app=envoy-gateway
```

## Comparison: Envoy Gateway vs Ingress Controllers on EKS

| Feature | Envoy Gateway | NGINX Ingress | AWS ALB Ingress |
|---------|--------------|---------------|-----------------|
| **Standard API** | Gateway API (CRD) | NGINX-specific | AWS-specific |
| **JWT Auth** | Native (SecurityPolicy) | Via annotation | Via AWS Cognito |
| **Rate Limiting** | Global + Local | Global only | Via AWS WAF |
| **Circuit Breaking** | Yes | Yes | Limited |
| **mTLS** | Yes | Yes | Via AWS ACM |
| **gRPC** | Native | Via grpc_pass | Via ALB rules |
| **Multi-cluster** | Yes (GMC) | No | No |
| **EKS Integration** | Via IRSA | Via IRSA | Native |
| **Learning Curve** | Moderate | Low | Moderate |

## Egctl for EKS

Install the Envoy Gateway CLI for debugging:

```bash
# Linux
curl -L https://gateway.envoyproxy.io/tools/egctl/install.sh | bash -

# Verify installation
egctl version

# Diagnose Gateway resources
egctl gatewayapi diagnose gateway/eg -n envoy-gateway-system
```

## Clean Up

```bash
# Remove quickstart resources
kubectl delete -f https://github.com/envoyproxy/gateway/releases/download/v1.8.0/quickstart.yaml -n default

# Uninstall Helm
helm uninstall eg -n envoy-gateway-system

# Delete namespace
kubectl delete namespace envoy-gateway-system

# If using IRSA
eksctl delete iamserviceaccount \
  --name envoy-gateway \
  --namespace envoy-gateway-system \
  --cluster <cluster-name>
```