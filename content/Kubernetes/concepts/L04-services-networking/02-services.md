# Services

*"https://kubernetes.io/docs/concepts/services-networking/service/"*

A Service is a **stable virtual IP + DNS name** that fronts a dynamic set of Pods. Pods come and go, their IPs change, but a Service IP stays put.

## The problem it solves

* Pod IPs are ephemeral — when a Pod is rescheduled, it gets a new IP
* You don't want clients hardcoding Pod IPs
* You want **load balancing** across replicas without managing it yourself

A Service gives you a **single stable endpoint** that routes to whichever Pods match its selector.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend
spec:
  selector:
    app: frontend        # routes to all Pods with this label
  ports:
  - port: 80             # Service port
    targetPort: 8080     # container port on the Pod
    protocol: TCP
```

The Service is automatically assigned a **ClusterIP** (virtual IP) and a DNS name: `frontend.default.svc.cluster.local`.

## The four Service types

| Type | What it does | Use case |
|---|---|---|
| `ClusterIP` | Internal cluster IP only. Default. | Pod-to-pod, app-to-DB within the cluster |
| `NodePort` | Exposes the Service on a static port on every node's IP. `<NodeIP>:<NodePort>` | Dev, on-prem, when you don't have a load balancer |
| `LoadBalancer` | Provisions a cloud load balancer (AWS NLB, GCP LB, etc.) | Production external traffic on a cloud |
| `ExternalName` | CNAME alias to an external DNS name | Migration to a service living outside the cluster |

### ClusterIP (default)

```yaml
spec:
  type: ClusterIP    # default, can be omitted
  selector:
    app: backend
  ports:
  - port: 80
    targetPort: 8080
```

Reachable from within the cluster at `backend.default.svc.cluster.local:80` (or just `backend` from inside the same namespace).

### NodePort

```yaml
spec:
  type: NodePort
  ports:
  - port: 80
    targetPort: 8080
    nodePort: 30080   # optional, 30000-32767 by default
```

Every node listens on port 30080 and forwards to the Service. From outside: `http://<any-node-ip>:30080`.

### LoadBalancer

```yaml
spec:
  type: LoadBalancer
  ports:
  - port: 443
    targetPort: 8080
    protocol: TCP
```

Provisions a cloud LB that points at the cluster nodes. AWS: an NLB by default. Behavior is cloud-specific (and influenced by cloud-provider-specific annotations, e.g. `service.beta.kubernetes.io/aws-load-balancer-type: nlb`).

### ExternalName

```yaml
spec:
  type: ExternalName
  externalName: api.example.com
```

No selector, no ports. Just a CNAME — DNS queries for the Service return the external name. Useful for moving services out of the cluster without changing client code.

## Headless services

Set `clusterIP: None` and the Service gets **no virtual IP**. Instead, DNS returns the Pod IPs directly. Used for:

* StatefulSets (you want to discover each Pod by name)
* Client-side load balancing (the client chooses which Pod to talk to)

```yaml
spec:
  clusterIP: None
  selector:
    app: db
```

## Endpoints and EndpointSlices

A Service's selector is automatically translated into a list of `<ip:port>` pairs:

* **Endpoints** (legacy) — one resource per Service, list of all backends
* **EndpointSlices** (modern, default since k8s 1.21) — the same data, sharded for scalability

See [[Kubernetes/concepts/L04-services-networking/08-endpoint-slices|endpoint-slices]] for the deep dive.

## Gotchas

* **A Service without a selector doesn't get Endpoints** — you have to create them manually. Common with ExternalName or when targeting external services via a sidecar.
* **The Service IP is virtual — it's not a routable address from outside the cluster** (unless you use NodePort / LoadBalancer / kube-proxy magic). Don't put it in external DNS.
* **The Service port and the targetPort can be different** — `port: 80, targetPort: 8080` is normal. The Service exposes 80, the Pod listens on 8080.
* **Session affinity is off by default** — every connection is a fresh load balancing decision. If you need sticky sessions, set `sessionAffinity: ClientIP` and `sessionAffinityConfig.clientIP.timeoutSeconds: 10800`.
* **`selector` is empty** for ExternalName and some custom setups. A Service with no selector won't have Endpoints.
* **Headless services are not "off"** — they're a real pattern. Don't try to manually create Endpoints to "make" a headless service.
* **Readiness probes are the difference between "registered" and "ready"** — a Pod is added to a Service's endpoints when it exists AND its readiness probe passes. If your readiness probe is missing or always passing, traffic goes to Pods that aren't ready.

## When to use what

* Internal-only traffic: **ClusterIP**
* North-south from a cloud LB: **LoadBalancer** (or **Ingress** for HTTP)
* HTTP routing by hostname/path: **Ingress** — see [[Kubernetes/concepts/L04-services-networking/04-ingress|ingress]]
* Pod-to-Pod by stable DNS name in a StatefulSet: **headless Service**
* Alias to an external service: **ExternalName**
