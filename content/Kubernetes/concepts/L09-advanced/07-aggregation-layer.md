# Aggregation Layer

*"https://kubernetes.io/docs/tasks/access-kubernetes-api/configure-aggregation-layer/"*

The aggregation layer lets you **run additional API servers alongside the main kube-apiserver**, with the requests proxied through the main apiserver. It's how the `metrics-server`, custom apiservices, and certain cloud-provider integrations expose their APIs as if they were part of k8s.

## The basic idea

```
Client (kubectl)
   │
   │  GET /apis/metrics.k8s.io/v1beta1/nodes
   │
   ▼
┌──────────────────────┐
│   kube-apiserver     │
│                      │
│   routes /apis/...   │
│   ┌──────────────┐   │
│   │ APIService   │   │
│   │ (registry)   │   │
│   └──────┬───────┘   │
│          │           │
│   ┌──────▼───────┐   │
│   │ proxy to     │   │
│   │ backend      │   │
│   └──────┬───────┘   │
└──────────┼──────────┘
           │
           ▼
┌──────────────────────┐
│  metrics-server      │  ← a separate apiserver
│  (backend API)       │     speaks the Kubernetes API protocol
└──────────────────────┘
```

From the client's perspective, the request is `GET /apis/metrics.k8s.io/v1beta1/nodes` against the kube-apiserver. The kube-apiserver routes it to the registered backend (`metrics-server`). The client doesn't know or care that there's a separate apiserver behind the scenes.

## What's in it

Three pieces:

1. **APIService** — a resource that registers a path prefix with the aggregation layer
2. **A backend apiserver** — a separate server (often called "aggregated apiserver" or "extension apiserver") that handles the requests
3. **A client config** in the kube-apiserver that knows how to reach the backend (CA cert, service ref)

```yaml
apiVersion: apiregistration.k8s.io/v1
kind: APIService
metadata:
  name: v1beta1.metrics.k8s.io
spec:
  group: metrics.k8s.io
  version: v1beta1
  groupPriorityMinimum: 100
  versionPriority: 100
  service:
    name: metrics-server
    namespace: kube-system
    port: 443
  caBundle: <base64-encoded CA cert>
```

Once this is created, `kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes` is routed to `metrics-server.kube-system.svc:443`.

## What uses it

Several core k8s features are themselves aggregated apiservers:

* **metrics-server** — for `kubectl top` and HPA
* **kube-state-metrics** is NOT an aggregated apiserver (it just exposes Prometheus metrics), but it watches the API like one
* **IDP/SSO integrations** — some OIDC brokers expose user/groups via an aggregated apiserver
* **Cloud provider APIs** — GKE, EKS, AKS sometimes expose cluster-specific APIs through the aggregation layer
* **Custom controllers' CRDs** — wait, CRDs are not the aggregation layer. CRDs are stored in the main apiserver.

**The aggregation layer is rare in custom controllers.** Most teams use **CRDs** for their own API extensions, not aggregated apiservers. Aggregated apiservers are for cases where you need:

* A separate API server (different deployment, scaling, etc.)
* A different storage backend (not etcd)
* Custom authentication / authorization (different from the main apiserver)
* A non-k8s API (e.g. a gRPC service that translates to/from the k8s API protocol)

## Aggregated apiserver vs CRD

| | Aggregated apiserver | CRD |
|---|---|---|
| Where it runs | Separate pod | In the main apiserver |
| Storage | Whatever you want | etcd |
| Authentication | Custom | Same as apiserver |
| Authorization | Custom | RBAC |
| Complexity | High | Low |
| Use case | High-scale, custom backend, sub-resources | Most cases |

**Use CRDs unless you have a specific reason to use the aggregation layer.** The threshold is roughly: "I need features that the main apiserver doesn't have, and CRDs can't provide them."

## How a request flows

```bash
kubectl get --raw /apis/mycompany.com/v1/widgets
```

1. The client sends a GET to the kube-apiserver at the apis path
2. The kube-apiserver checks the APIService registry
3. The matching APIService (`mycompany.com`) says "this is handled by `my-api.my-ns.svc:443`"
4. The kube-apiserver opens a connection to the backend (with TLS using the APIService's `caBundle`)
5. The backend processes the request
6. The response flows back to the client

The client never sees the backend's address. The kube-apiserver is a transparent proxy.

## Building an aggregated apiserver

The standard approach:

1. **Define your API** with Protocol Buffers (or OpenAPI)
2. **Generate boilerplate** with `k8s.io/code-generator` (or `kubebuilder apiserver`)
3. **Implement the storage** — could be etcd, could be something else
4. **Implement the authentication / authorization** — typically delegates to the kube-apiserver via delegation tokens
5. **Deploy the apiserver** as a Pod
6. **Create an APIService** that points to it

The boilerplate is heavy. **Don't write one from scratch unless you really need it.** Most teams start with CRDs and only consider the aggregation layer if they hit a wall.

### Authentication delegation

The aggregated apiserver needs to know who's making the request. It can either:

* Use **delegation tokens** — the kube-apiserver generates a special token in the request, valid only for the aggregated apiserver to call back to validate. The aggregated apiserver exchanges this for a TokenReview.
* Use its own authentication (rare).

Delegation is the standard. The aggregated apiserver uses `--authentication-kubeconfig` to call the kube-apiserver for validation.

```go
// in the aggregated apiserver
config, _ := clientcmd.BuildConfigFromFlags("", *authKubeconfigPath)
// use config to call TokenReview
```

## The aggregation layer's limits

* The **kube-apiserver must be configured** to enable the aggregation layer. Most distros enable it by default; some stripped-down ones don't.
* The **CA bundle** in the APIService must match the backend apiserver's serving cert. Mismatches cause 503s.
* The **backend must respond fast** — it's on the request hot path. A slow backend blocks all requests to its API group.
* The **API path** must be a valid `apiGroup/version` (e.g. `mycompany.com/v1`). You can't aggregate at a custom path.
* **Discovery works through the kube-apiserver** — `kubectl api-resources` includes the aggregated APIs.
* **RBAC is per-apiservice** — the aggregated apiserver decides what permissions a request has, not the main apiserver (after delegation).

## When to use the aggregation layer

* **You need a separate database** — e.g. your "Widgets" are stored in a SQL DB, not etcd
* **You need custom auth** — e.g. SAML, mTLS at a different layer
* **You have a non-k8s API** that you want exposed as if it were k8s — e.g. a custom gRPC service
* **You need to serve a large number of subresources** efficiently
* **You're building a control plane** for an entire domain (e.g. a multi-cloud control plane)

## When NOT to use the aggregation layer

* **You can use a CRD** — do that instead. 99% of the time, CRD is the right answer.
* **You just want a new object type** — CRD
* **You want to validate or mutate objects** — admission webhook (see L09)
* **You have a small team** — the operational burden of running an aggregated apiserver is too high

## Real-world aggregated apiservers

* **metrics-server** — for HPA / `kubectl top`
* **cloud-guard** (in some GKE / EKS setups) — exposes cluster security info
* **AWS ACK** (AWS Controllers for Kubernetes) — exposes AWS resources as CRDs (not via aggregation, but related)
* **Various third-party** — for example, some database operators expose a query API

## How the kube-apiserver is configured

The kube-apiserver needs:

```bash
--enable-aggregator-routing=true     # route requests to the aggregated apiserver
--proxy-client-cert-file=...        # cert for the proxy client
--proxy-client-key-file=...         # key for the proxy client
--requestheader-client-ca-file=...  # CA for client certs in request headers
--requestheader-username-headers=X-Remote-User
--requestheader-group-headers=X-Remote-Group
```

The `--requestheader-*` flags tell the kube-apiserver to extract user identity from request headers (set by the aggregated apiserver via delegation).

If you're using a managed cluster, these are configured for you.

## Gotchas

* **The aggregation layer is one of the first things to disable** in custom apiserver builds. If you're building a small apiserver (e.g. for a controller), you don't need the aggregation layer.
* **APIService `caBundle` must be valid base64.** A malformed CA bundle causes every request to fail.
* **The aggregation layer adds latency.** Every request goes through the kube-apiserver, then to the backend. For high-QPS backends, this is significant.
* **Discovery is automatic** — once an APIService is registered, `kubectl api-resources` shows the resources. There's no way to "hide" an aggregated API.
* **The aggregated apiserver must handle RBAC itself** — the main apiserver delegates authn but the aggregated apiserver decides authz. This is more work than CRD + RBAC.
* **`kubectl get --raw` works against aggregated apiservers** but the kube-apiserver still validates the request shape. Some bad requests get rejected at the proxy level.
* **Aggregated apiservers can have CRDs too.** Some operators register a CRD AND a separate apiserver for subresources (e.g. status, scale).
* **The `serviceAccount` field in APIService** lets you specify which SA the kube-apiserver uses to authenticate to the backend. Default is `default` in the apiservice's namespace.
* **An aggregated apiserver can return its own discovery** — listing resources, OpenAPI schema, etc. The kube-apiserver passes this through.
* **`status` subresources** for an aggregated apiserver are separate from the main resource. The aggregated apiserver decides.

## See also

* [[Kubernetes/concepts/L09-advanced/03-customresourcedefinitions|CRDs]] — the more common alternative
* [[Kubernetes/concepts/L09-advanced/02-custom-controllers|Custom Controllers]] — what most people actually need
* [[Kubernetes/concepts/L09-advanced/04-admission-controllers|Admission Controllers & Webhooks]] — for validation, not full API servers
