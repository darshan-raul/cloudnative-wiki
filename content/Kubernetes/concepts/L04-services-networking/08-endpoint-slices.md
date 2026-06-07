# EndpointSlices

*"https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/"*

An EndpointSlice is the **modern, scalable replacement** for the Endpoints API. It tracks the set of network endpoints (typically a Pod IP + port) that back a Service. As of k8s 1.21, EndpointSlices are the default; the legacy Endpoints API is auto-managed for backward compatibility.

## The problem with Endpoints

Before k8s 1.21, every Service had a single `Endpoints` object that listed all its backend Pods. With a Service backed by 5,000 Pods, the Endpoints object was 5,000 entries. With 1,000 Services, each backed by 100 Pods, you had 100,000 entries spread across 1,000 Endpoints objects.

The problems:

* **Large objects**. A 5,000-endpoint Endpoints object is ~500 KB. Updating it requires sending the whole thing. API server traffic scales with the number of Services × endpoints per Service.
* **Watch amplification**. Every controller watching Endpoints (and the kube-proxy on every node does) gets a notification on every change. A rolling update of a 1,000-replica Deployment generates 1,000+ Endpoints updates.
* **No sharding**. The whole Endpoints object is one etcd key. A single point of contention.

## The EndpointSlice solution

EndpointSlices **shard** the endpoint set for a Service into multiple smaller objects:

```
Service "frontend" (selector: app=frontend, 1000 Pods)
  ├── EndpointSlice 1 (200 endpoints)
  ├── EndpointSlice 2 (200 endpoints)
  ├── EndpointSlice 3 (200 endpoints)
  ├── EndpointSlice 4 (200 endpoints)
  └── EndpointSlice 5 (200 endpoints)
```

Each EndpointSlice is small (default 100 endpoints), and the total set is sharded across multiple objects. Updates to one Pod only change the slice that contains it.

## Anatomy

```yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: frontend-abcde       # auto-generated
  generateName: frontend-    # the controller sets this
  labels:
    kubernetes.io/service-name: frontend
    endpointslice.kubernetes.io/managed-by: endpointslice-controller.k8s.io
  namespace: production
addressType: IPv4
ports:
- name: http
  port: 80
  protocol: TCP
endpoints:
- addresses:
  - 10.244.1.5
  conditions:
    ready: true
    serving: true
    terminating: false
  nodeName: node-1
  zone: us-east-1a
  targetRef:
    kind: Pod
    name: frontend-aaa
    namespace: production
- addresses:
  - 10.244.2.7
  conditions:
    ready: true
    serving: true
    terminating: false
  nodeName: node-2
  zone: us-east-1b
  targetRef:
    kind: Pod
    name: frontend-bbb
    namespace: production
# ... up to 100 endpoints per slice
```

### Key fields

| Field | What it means |
|---|---|
| `addressType` | `IPv4`, `IPv6`, or `FQDN` |
| `ports` | List of Service ports the slice handles |
| `endpoints[].addresses` | The IP addresses (Pod IPs, for `IPv4`/`IPv6`) |
| `endpoints[].conditions.ready` | Is this endpoint ready? Mirrors the Pod's readiness |
| `endpoints[].conditions.serving` | Is the endpoint configured to serve traffic (different from ready during shutdown)? |
| `endpoints[].conditions.terminating` | Is the endpoint in the process of terminating? |
| `endpoints[].nodeName` | The node the Pod is on — used for topology-aware routing |
| `endpoints[].zone` | The zone the Pod is in — used for zonal awareness |
| `endpoints[].targetRef` | The Pod (or other object) this endpoint represents |

The `kubernetes.io/service-name` label **links the slice to the Service**. All slices for a Service have the same label.

## The terminating / serving / ready dance

Endpoint conditions matter most during Pod shutdown:

| Pod state | `ready` | `serving` | `terminating` |
|---|---|---|---|
| Running, ready | true | true | false |
| Running, not ready (readiness probe failing) | false | true | false |
| Pod being deleted, still has endpoints | true | true | **true** |
| Pod being deleted, no longer has endpoints | false | false | **true** |

The controller transitions an endpoint from `(ready=true, terminating=false)` to `(ready=false, terminating=true)` to `(serving=false, terminating=true)` based on the Pod's state.

This lets **kube-proxy gracefully remove the endpoint** from iptables while the Pod's `preStop` hook runs, draining in-flight connections.

## How it interacts with Services

A Service has a **selector** that defines which Pods are its endpoints. The `endpoints-controller` (in `kube-controller-manager`) translates this selector into EndpointSlices:

1. Watch all Pods in the namespace
2. For each Pod matching the Service's selector, add an entry to an EndpointSlice
3. Shard into slices of `maxEndpointsPerSlice` (default 100)
4. Update slices when Pods are added, removed, or change readiness

You can also have **manually-managed EndpointSlices** (no Service selector), which is useful for:

* Services that point to external IPs (databases outside the cluster)
* Headless services with custom endpoint logic

## How kube-proxy uses them

`kube-proxy` on every node watches EndpointSlices (not Endpoints anymore, as of k8s 1.22+). When a slice changes, kube-proxy updates its iptables / IPVS rules:

* New endpoint → add DNAT rule from Service ClusterIP to the new Pod IP
* Endpoint removed (readiness=false) → remove the DNAT rule
* Endpoint unchanged → no update (this is the win — most changes are small)

**Watch efficiency**: kube-proxy only needs to process the slice that changed, not the whole Service's endpoint set. This is the main scalability win.

## How to view

```bash
# all EndpointSlices
kubectl get endpointslices -A

# for a specific Service
kubectl get endpointslices -l kubernetes.io/service-name=frontend

# detailed view
kubectl describe endpointslice <name> -n <ns>

# the legacy view (still works)
kubectl get endpoints frontend
```

The legacy `Endpoints` API still exists for backward compatibility. It's auto-generated from the EndpointSlices. Use EndpointSlices in tooling.

## Manually creating EndpointSlices

For Services that point to external resources (a database outside the cluster), you create EndpointSlices by hand. The Service has no selector; you create the slices yourself.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: external-db
spec:
  ports:
  - port: 5432
    targetPort: 5432
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: external-db-1
  labels:
    kubernetes.io/service-name: external-db
addressType: IPv4
ports:
- name: http
  port: 5432
  protocol: TCP
endpoints:
- addresses:
  - 10.0.5.10      # the actual database IP, outside the cluster
  conditions:
    ready: true
```

This is the right way to expose an external service (RDS, ElastiCache, a VM-hosted DB) to in-cluster clients.

For the **headless Service** with manual endpoints pattern (StatefulSets use this), you can also let the EndpointSlice controller generate slices from Pod selectors — same as a regular Service, just with `clusterIP: None`.

## The k8s 1.21+ migration

When you upgrade to k8s 1.21+, EndpointSlices are **automatically created** for every Service. You don't need to do anything. The legacy `Endpoints` objects are still maintained for backward compatibility.

For new code, use EndpointSlices. The Endpoints API is not deprecated yet, but all new development targets EndpointSlices.

## Slice size and topology

The `endpoints-controller` can be configured (via `kube-controller-manager` flags) to:

* `--max-endpoints-per-slice` (default 100) — how many endpoints per slice
* The controller automatically balances across slices, splitting when a slice grows past the limit

You can also create slices by topology:

```yaml
# Zone A
endpoints:
- addresses: [10.244.1.5]
  zone: us-east-1a
# Zone B
- addresses: [10.244.2.7]
  zone: us-east-1b
```

This is used by **topology-aware routing** (k8s 1.27+, beta in 1.21 as `service.kubernetes.io/topology-mode: Auto` on the Service). The Service's traffic prefers endpoints in the same zone as the client, reducing cross-zone data transfer costs.

## Gotchas

* **EndpointSlices are auto-managed for Services with selectors.** You almost never create them by hand unless you're pointing to external resources.
* **The `kubernetes.io/service-name` label is set by the controller.** If you create a slice by hand, you must set this label or no one will find it.
* **Watch permissions matter.** `kube-proxy` needs `watch` permission on `endpointslices` in the cluster. In restricted RBAC setups, this can break if you don't grant it explicitly.
* **A Service can have EndpointSlices from multiple sources** — the controller-generated ones and manual ones. They all merge into the Service's effective endpoint set.
* **Endpoint conditions don't match Pod conditions 1:1.** `serving=true, terminating=true` is a valid state — the Pod is shutting down, but still has endpoints in the API. The transition logic is documented in the [EndpointSlice conditions KEP](https://github.com/kubernetes/enhancements/tree/master/keps/sig-network/0752-endpointslice-terminating-conditions).
* **Removing a label from a Pod that the Service selects** removes the endpoint, even if the Pod is still running. The selector match is re-evaluated on every Pod change.
* **Removing the Service's selector** doesn't delete existing EndpointSlices. They become orphaned (the `kubernetes.io/service-name` label still points to a Service that doesn't select them, but no one cleans up). You can delete the slices manually.
* **IPv4 and IPv6 endpoints in the same Service** must be in **different slices** with different `addressType` values. A single slice can only have one address family.
* **The `targetRef` is informational.** It doesn't enforce anything. If a Pod is deleted but the EndpointSlice still references it, the endpoint is just unreachable.

## When to care

* **If you're writing a controller** that watches Services, watch EndpointSlices (not Endpoints).
* **If you're writing a service mesh / proxy** that needs the endpoint set, watch EndpointSlices.
* **If you're pointing a Service at external resources**, create EndpointSlices by hand.
* **If you're debugging "Service has no endpoints"** — look at the EndpointSlices, not the Endpoints.
* **If you're scaling to 1000s of endpoints per Service**, EndpointSlices are what makes it possible.

## See also

* [[Kubernetes/concepts/L04-services-networking/02-services|Services]] — the parent object
* [[Kubernetes/concepts/L04-services-networking/06-cni|CNI]] — handles the actual packet delivery
* [[Kubernetes/concepts/L08-ipvs|IPVS]] — alternative kube-proxy mode for scalability
