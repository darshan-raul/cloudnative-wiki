# Aggregation Layer

>*"https://kubernetes.io/docs/tasks/access-kubernetes-api/configure-aggregation-layer/"*

The aggregation layer lets you **run additional API servers alongside the main kube-apiserver**, with requests proxied through the main apiserver. It's how metrics-server, custom apiservices, and certain cloud-provider integrations expose APIs that look native to Kubernetes.

## Table of Contents

1. [The big picture](#1-the-big-picture)
2. [What's actually running](#2-whats-actually-running)
3. [APIService resource](#3-apiservice-resource)
4. [How a request flows](#4-how-a-request-flows)
5. [Priority and version precedence](#5-priority-and-version-precedence)
6. [CA bundle and TLS](#6-ca-bundle-and-tls)
7. [Authentication delegation](#7-authentication-delegation)
8. [Authorization delegation](#8-authorization-delegation)
9. [What uses the aggregation layer today](#9-what-uses-the-aggregation-layer-today)
10. [Building an aggregated apiserver](#10-building-an-aggregated-apiserver)
11. [CRDs vs aggregation layer](#11-crds-vs-aggregation-layer)
12. [Discovery and kubectl](#12-discovery-and-kubectl)
13. [The kube-apiserver configuration flags](#13-the-kube-apiserver-configuration-flags)
14. [Performance characteristics](#14-performance-characteristics)
15. [Troubleshooting](#15-troubleshooting)
16. [When to use the aggregation layer](#16-when-to-use-the-aggregation-layer)
17. [When NOT to use the aggregation layer](#17-when-not-to-use-the-aggregation-layer)
18. [Gotchas](#18-gotchas)

---

### 1. The big picture

```
Client (kubectl, controller, SDK)
   │
   │  GET /apis/metrics.k8s.io/v1beta1/nodes
   ▼
┌──────────────────────────────────────────┐
│            kube-apiserver                │
│                                          │
│   ┌─────────────────────────────────┐    │
│   │   Aggregation layer             │    │
│   │   (APIService registry + proxy) │    │
│   └──────────────┬──────────────────┘    │
│                  │                      │
│   ┌──────────────▼──────────────────┐    │
│   │   Route: /apis/metrics.k8s.io/*  │───────► metrics-server (pod)
│   │   Route: /apis/custom.example.com/* ─────► my-apiserver (pod)
│   │   Route: /api/*  ──► etcd         │──► (native resources)
│   └─────────────────────────────────┘    │
└──────────────────────────────────────────┘
```

The kube-apiserver is a **transparent proxy** for aggregated paths. The client doesn't know there's a separate server behind it.

---

### 2. What's actually running

Three things make up a full aggregated API:

1. **Your API server** — a separate Pod (or set of Pods) running your code, implementing the Kubernetes API protocol
2. **An APIService registration** — a Kubernetes resource telling the kube-apiserver how to reach your server
3. **TLS certificates** — the kube-apiserver and your server need mutual TLS to talk securely

```
┌─────────────────────────────────────────────────────┐
│  kube-system                                        │
│                                                     │
│  ┌──────────────────┐  ┌────────────────────────┐  │
│  │ kube-apiserver   │──│ metrics-server         │  │
│  │ (API server)     │◄─┤ (aggregated apiserver) │  │
│  │                  │  │  :443                   │  │
│  │ :6443            │  └────────────────────────┘  │
│  └──────────────────┘                              │
│         ▲                                           │
│         │ TLS (mutual)                             │
│         │ APIService tells kube-apiserver          │
│         │ how to reach metrics-server               │
└─────────┼───────────────────────────────────────────┘
```

---

### 3. APIService resource

```yaml
apiVersion: apiregistration.k8s.io/v1
kind: APIService
metadata:
  name: v1beta1.metrics.k8s.io
spec:
  group: metrics.k8s.io          # /apis/<group>/<version>
  version: v1beta1               # /apis/metrics.k8s.io/v1beta1
  groupPriorityMinimum: 100      # higher = preferred in discovery
  versionPriority: 100           # higher = preferred within group
  service:
    name: metrics-server
    namespace: kube-system
    port: 443
  caBundle: <base64-encoded CA cert that signed the metrics-server TLS cert>
  # or use serviceAccountIssuer to delegate cert validation
```

```bash
# After applying:
kubectl get apiservice v1beta1.metrics.k8s.io
# NAME                    SERVICE                    AVAILABLE   AGE
# v1beta1.metrics.k8s.io  kube-system/metrics-server   True    30d

# This makes kubectl top work:
kubectl top nodes
# Error from server (NotFound): metrics not available
# → metrics-server isn't running or isn't working

kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes
# {"kind": "NodeMetricsList", "apiVersion": "metrics.k8s.io/v1beta1", ...}
```

---

### 4. How a request flows

```bash
kubectl get --raw /apis/mycompany.com/v1/widgets
```

Step-by-step:

```
1. kubectl sends GET /apis/mycompany.com/v1/widgets to kube-apiserver:6443
2. kube-apiserver's aggregation layer checks APIService registry
3. Finds: APIService "v1.mycompany.com" → Service "my-api.default.svc:443"
4. kube-apiserver opens TLS connection to my-api.default.svc:443
5. kube-apiserver passes the request to the backend (with auth headers)
6. Backend (my aggregated apiserver) processes the request
7. Backend returns response
8. kube-apiserver returns response to kubectl
```

The proxy is **single-flight** — the aggregated apiserver's response is forwarded verbatim. The kube-apiserver does minimal processing.

---

### 5. Priority and version precedence

When multiple API groups or versions exist, `kubectl` needs to know which to use. Priority is set per APIService:

```yaml
# metrics-server — high priority, it powers kubectl top
groupPriorityMinimum: 100
versionPriority: 100

# a less critical aggregator
groupPriorityMinimum: 50
versionPriority: 50
```

Within a group, higher `versionPriority` = preferred version in discovery. The preferred version is what `kubectl api-resources` shows.

---

### 6. CA bundle and TLS

The `caBundle` in the APIService must be the CA that signed the aggregated apiserver's **serving certificate**. The aggregated apiserver uses that CA when registering with the kube-apiserver.

```
kube-apiserver trusts requests from the aggregated apiserver
only if the TLS cert is signed by the caBundle CA.
```

Common mistake: using the **cluster CA** (`/etc/kubernetes/pki/ca.crt`) when the aggregated apiserver's cert was signed by a different internal CA.

```bash
# Get the CA that signed a service's cert
kubectl get secret -n my-ns my-api-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | \
  openssl x509 -noout -issuer

# The issuer must match the caBundle in the APIService
```

For **automated cert management**, use a `ServiceAccount` issuer (k8s 1.20+):

```yaml
spec:
  service:
    name: my-api
    namespace: default
  # Instead of caBundle, tell kube-apiserver to validate via SA issuer
  # (requires aggregated apiserver to use a ServiceAccount-bound token)
```

---

### 7. Authentication delegation

The aggregated apiserver needs to know **who is making the request** (the user or SA). It can delegate to the kube-apiserver:

```
Aggregated apiserver
   │
   │  kube-apiserver sets headers on the proxied request:
   │  X-Remote-User: alice
   │  X-Remote-Group: developers
   │  X-Remote-Impersonate-Uid: ...
   │  X-Remote-Impersonate-Groups: ...
   │
   ▼
Own authentication logic (or skip = trust proxy headers)
```

**Standard pattern**: use `--authentication-kubeconfig` in the aggregated apiserver:

```bash
# In the aggregated apiserver's container
kube-apiserver \
  --authentication-kubeconfig=/var/run/secrets/sa.kubeconfig \
  --authorization-kubeconfig=/var/run/secrets/sa.kubeconfig
```

The SA kubeconfig contains a token for the aggregated apiserver's ServiceAccount. The aggregated apiserver uses it to call `TokenReview` back to the kube-apiserver to validate tokens.

```go
// In Go, using the k8s.io/kube-aggregator library:
config, err := controlplane.GetServingCA()
if err != nil {
    return err
}
// Use config to talk to TokenReview API
```

---

### 8. Authorization delegation

After authenticating, the aggregated apiserver decides **what the user is allowed to do**:

```go
// Option 1: Trust the impersonation headers from kube-apiserver
// (kube-apiserver already did authn/authz, we trust it)
username := request.Header.Get("X-Remote-User")

// Option 2: Do your own RBAC via kube-apiserver
config, _ := clientcmd.BuildConfigFromFlags("", "/var/run/secrets/auth/kubeconfig")
rbacClient := rbacv1.New(config)
can, _ := rbacClient.ClusterRoleBindings("my-binding").Exists(username)

// Option 3: Delegate to kube-apiserver via SubjectAccessReview
sarClient.Create(ctx, &authv1.SubjectAccessReview{
    Spec: authv1.SubjectAccessReviewSpec{
        User:   username,
        ResourceAttributes: &authv1.ResourceAttributes{
            Group:    "mycompany.com",
            Version:  "v1",
            Resource: "widgets",
            Verb:     "get",
        },
    },
})
```

The most common pattern: the aggregated apiserver trusts the impersonation headers (`X-Remote-User`, etc.) set by the kube-apiserver, which already authenticated and authorized the request.

---

### 9. What uses the aggregation layer today

| Component | What it does via aggregation |
|-----------|------------------------------|
| **metrics-server** | Exposes `NodeMetrics` and `PodMetrics` → powers `kubectl top` and HPA |
| **k8s.io/apiserver-network-proxy/konnectivity** | Tunneling API server traffic to node pools (not a CRD) |
| **GKE/EKS cloud connectors** | Cluster-scoped APIs for cloud resource management |
| **kube-oidc-proxy** | OIDC token validation via aggregated API |
| **various storage operators** | CSI driver APIs sometimes use aggregation |

The vast majority of CRDs use the **main kube-apiserver** (not the aggregation layer) — they register with `apiextensions.k8s.io/v1`.

---

### 10. Building an aggregated apiserver

The full approach with Kubebuilder (recommended):

```bash
# Create a new apiserver project
kubebuilder init --domain mycompany.com
kubebuilder edit --multigroup=true

# Create a new API (this generates the CRD + apiserver scaffold)
kubebuilder create api --group widgets --version v1 --kind Widget

# Build and run
make build
make docker-build IMG=mycompany.com/my-apiserver:v1

# Deploy the CRD and the apiserver
make deploy IMG=mycompany.com/my-apiserver:v1
```

Kubebuilder generates:
- The CRD YAML (`config/crd/bases/...`)
- The apiserver code (`api/`, `cmd/`)
- A Dockerfile for the apiserver
- A Service + APIService registration

What you implement:

```go
// api/v1/widget_types.go
type WidgetSpec struct {
    Replicas int32  `json:"replicas,omitempty"`
    Image    string `json:"image,omitempty"`
}

// api/v1/zz_generated.deepcopy.go — kubebuilder generates this

// cmd/main.go — apiserver entrypoint
func main() {
    command := server.NewCommand(...)
    command.Execute()
}
```

Kubebuilder's `APIServer` type handles: watch loop, REST storage, error handling, TLS. You implement the API types and reconcile.

---

### 11. CRDs vs aggregation layer

| | CRD | Aggregated API Server |
|---|---|---|
| **Runs in** | kube-apiserver process | Separate Pod(s) |
| **Storage** | etcd (via kube-apiserver) | Your choice (etcd, SQL, Redis, custom) |
| **Authentication** | RBAC (same as all k8s) | Custom or delegated |
| **Authorization** | RBAC | Custom or delegated |
| **Schema** | OpenAPI v3 in CRD | Protobuf or OpenAPI |
| **Performance** | Good for low/moderate volume | Better for high QPS |
| **Operational burden** | Low | High |
| **Complexity** | Low | High |
| **Schema evolution** | Webhook conversion or version migration | Your API handles it |

**When CRD is the right answer:**
- You want to extend k8s with a new resource type
- Your data lives in etcd (or you don't care where it lives)
- You want full kubectl support, RBAC, watch, etc.

**When aggregation layer is the right answer:**
- You need a different storage backend (not etcd)
- You need custom authentication (mTLS, SAML, custom OIDC)
- You have a gRPC API you want to expose as k8s-style
- You're building a control plane that manages external resources at scale
- CRDs genuinely can't do what you need

---

### 12. Discovery and kubectl

Once an APIService is registered, `kubectl` picks it up automatically:

```bash
# Discovery
kubectl api-resources
# Shows all resources including aggregated ones

kubectl api-versions
# Includes: mycompany.com/v1, metrics.k8s.io/v1beta1, ...

# Direct access
kubectl get --raw /apis/mycompany.com/v1/widgets
kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes
```

No additional kubectl plugins needed — aggregation layer APIs are first-class.

---

### 13. The kube-apiserver configuration flags

For the aggregation layer to work, the kube-apiserver needs:

```bash
kube-apiserver \
  --enable-aggregator-routing=true \
  # Enables request routing to aggregated apiservers

  # For request header-based auth delegation:
  --requestheader-client-ca-file=/etc/kubernetes/ssl/ca.crt
  --requestheader-allowed-names=aggregator
  --requestheader-username-headers=X-Remote-User
  --requestheader-group-headers=X-Remote-Group
  --requestheader-extra-headers-prefix=X-Remote-Extra-

  # For the proxy client cert (kube-apiserver → aggregated apiserver):
  --proxy-client-cert-file=/etc/kubernetes/ssl/apiserver.crt
  --proxy-client-key-file=/etc/kubernetes/ssl/apiserver.key
```

In kubeadm, these are configured via the `ClusterConfiguration` kubeadm config:

```yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
apiServer:
  extraArgs:
    enable-aggregator-routing: "true"
  extraVolumes:
    - name: usr-local-share-ca-cert
      hostPath: /usr/local/share/ca-certificates
      mountPath: /usr/local/share/ca-certificates
      readOnly: true
```

Most managed clusters (EKS, GKE) have these already configured.

---

### 14. Performance characteristics

Aggregation adds **one TCP round-trip** from kube-apiserver to the aggregated apiserver:

```
Request latency: kube-apiserver + 1ms (proxy) + aggregated-apiserver + response
```

For low-latency APIs (every pod reconcile, every `kubectl get`), this adds up. For infrequent APIs (metrics every 15s, custom APIs with low QPS), it's fine.

**Mitigations:**
- Deploy aggregated apiserver in same AZ as kube-apiserver
- Use HTTP/2 for connection reuse
- Keep aggregated apiserver stateless if possible
- Use `serviceAccountIssuer` instead of CA bundle for cert validation (faster startup)

---

### 15. Troubleshooting

```bash
# Is the APIService registered?
kubectl get apiservice -A

# Is it Available?
kubectl get apiservice <name> -o jsonpath='{.status}'
# Should show: {"conditions": [{"type": "Available", "status": "True"}]}

# Check if kube-apiserver can reach the backend
kubectl get endpoints <service-name> -n <namespace>
# Should have IP addresses under "Addresses"

# Test the backend directly
kubectl run curl --rm -it --image=curlimages/curl -- \
  https://<service-name>.<namespace>.svc:<port>/<path> \
  --cacert /tmp/ca.crt

# Common: CA bundle mismatch
# kube-apiserver logs:
# "Error getting service \"default/my-api\" in API group '': ...
#  X509: certificate signed by unknown authority"
# Fix: verify the caBundle matches the CA that signed the apiserver's cert

# The aggregated apiserver's pod logs
kubectl logs -n <namespace> -l app=<my-api>

# Get the full APIService spec
kubectl get apiservice <name> -o yaml
```

---

### 16. When to use the aggregation layer

- You need **etcd as NOT your storage backend** — e.g. SQL database, Redis, object store
- You need **custom authentication** that the main apiserver can't do — e.g. mTLS from a hardware HSM, SAML integration
- You have a **non-k8s API** (gRPC, REST) that you want to expose as if it were k8s-native
- You're building a **control plane for a distributed system** that manages external infrastructure at scale
- You need **API-level isolation** between your resources and the main kube-apiserver (different rate limits, different resource quotas)

---

### 17. When NOT to use the aggregation layer

- **You just want a new resource type** — CRD, every time
- **You want to validate/mutate objects at admission** — admission webhooks, not aggregation
- **You want to run an operator/controller** — CRD + controller (Kubebuilder/Operator SDK)
- **You want to offload reads from kube-apiserver** — consider read replicas (k8s 1.19+) or caching instead
- **You're a small team** — the operational overhead (cert management, TLS, separate deployment, monitoring) is real

---

### 18. Gotchas

* **`caBundle` must be valid base64.** A malformed CA bundle causes every request to the aggregated API to fail with a 503.
* **The kube-apiserver must have `enable-aggregator-routing: true`.** Without it, requests to aggregated paths may not be routed.
* **The aggregated apiserver must serve TLS.** Non-TLS endpoints are rejected by kube-apiserver.
* **`--authentication-kubeconfig` is the standard pattern** for delegating auth back to the kube-apiserver. Without it, you need to implement your own token validation.
* **Aggregated apiservers can have CRDs too.** Some operators bundle a CRD (for user-facing types) with an aggregated apiserver (for internal subresources).
* **Discovery is automatic** — once the APIService is registered, `kubectl api-resources` includes it. There's no way to hide it.
* **RBAC for aggregated APIs is scoped to the APIService name**, not the resources themselves. The aggregated apiserver enforces what users can do with its resources.
* **The `serviceAccountIssuer` field** (k8s 1.20+) lets you avoid CA bundle rotation issues by using a ServiceAccount token for validation instead.
* **`kubectl get --raw` works** for aggregated APIs, but the kube-apiserver still validates the request shape — some malformed requests fail at the proxy layer before reaching your apiserver.
* **The aggregated apiserver sees impersonation headers** (`X-Remote-User`, etc.) but not the original client cert. If you need the original client identity (for mTLS to external services), you need to pass that explicitly.
* **Cross-namespace requests are proxied as-is** — the aggregated apiserver receives the namespace from the request URL path, not from any isolation.

---

## See also

* [[Kubernetes/concepts/L09-advanced/03-customresourcedefinitions|CRDs]] — the simpler alternative
* [[Kubernetes/concepts/L09-advanced/02-custom-controllers|Custom Controllers]] — what most people actually build on top of CRDs
* [[Kubernetes/concepts/L09-advanced/04-admission-controllers|Admission Controllers & Webhooks]] — validation and mutation at admission
* [[Kubernetes/concepts/L04-services-networking/06-cni|CNI]] — the network layer below kube-proxy
