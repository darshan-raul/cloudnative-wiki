# DNS in Kubernetes

*"https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/"*

Every Service gets a DNS name automatically. Every Pod gets one too. This is the **primary way services find each other** in a cluster — don't hardcode IPs, ever.

## Service DNS

For a Service `my-svc` in namespace `my-ns`:

```
my-svc.my-ns.svc.cluster.local
```

A real example: Service `frontend` in namespace `production`:

```
frontend.production.svc.cluster.local
```

From inside the same namespace (`production`):

```
frontend                # short form
frontend.production     # namespace form
frontend.production.svc # namespace + service form
```

## Pod DNS

Pods get DNS names based on their IP:

```
<ip-with-dashes>.<namespace>.pod.cluster.local
```

Example: Pod with IP `10-0-0-5` in namespace `default`:

```
10-0-0-5.default.pod.cluster.local
```

This is useful but rare. Most apps just use Service DNS.

## Cluster domain

The default cluster domain is `cluster.local`. Configurable via the `kubelet` flag `--cluster-domain`. Most clusters use the default; you'll see it in every FQDN.

## Records created for each Service

* **ClusterIP Service**: A record `my-svc.my-ns.svc.cluster.local` → ClusterIP
* **Headless Service** (`clusterIP: None`): A record for **each backing Pod**, not the Service IP
* **ExternalName Service**: CNAME to the external name

## Search paths (the magic)

Inside a Pod, `/etc/resolv.conf` looks like:

```
nameserver 10.96.0.10        # the CoreDNS service IP
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

`ndots:5` means: if the query has fewer than 5 dots, append each `search` path in turn and try again. This is why `curl frontend` works from inside the cluster — the resolver tries `frontend.default.svc.cluster.local` before failing.

**Implication:** if you make a query to `api.example.com` (2 dots), the resolver first tries `api.example.com.default.svc.cluster.local`, then `api.example.com.svc.cluster.local`, then `api.example.com.cluster.local`, **then** the real one. That's 3 failed lookups for every external call.

Fix: set `dnsConfig.options` in the Pod spec to lower `ndots`, or use FQDNs for external services:

```yaml
spec:
  dnsConfig:
    options:
    - name: ndots
      value: "2"
```

## CoreDNS

CoreDNS is the default cluster DNS since k8s 1.13. It runs as a Deployment in `kube-system` and exposes itself as a Service named `kube-dns` (kept for compatibility).

Tuning CoreDNS:

* **Forward plugins** — `/etc/resolv.conf` of the cluster nodes is used to forward external queries. Customize via the CoreDNS Corefile (ConfigMap `coredns` in `kube-system`).
* **Stub domains** — rewrite `.consul` queries to a Consul DNS server, etc.
* **Autopath** — reduces the failed-query problem above by skipping search paths when it can guess the FQDN.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          fallthrough in-addr.arpa ip6.arpa
        }
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
```

## Gotchas

* **The kubelet generates `/etc/resolv.conf` for each Pod.** Don't override it manually — use `dnsConfig` and `dnsPolicy` in the Pod spec.
* **`dnsPolicy: ClusterFirst` is the default** — use the upstream nameserver for queries not in the cluster domain. `Default` ignores cluster DNS entirely.
* **Headless services with StatefulSets** give you stable per-Pod DNS like `mongo-0.mongo.default.svc.cluster.local` — this is the right way to address individual replicas.
* **Service DNS is not updated when the Service's ClusterIP changes** — which is never, in practice. ClusterIPs are stable for the life of the Service.
* **ExternalName Services don't have an IP, just a CNAME** — so anything doing a name:port lookup needs to know it'll get a CNAME back.
* **Short names only work inside Pods.** From a node or your laptop, you have to use FQDNs (or set up search domains in your local resolver).
* **DNS is a frequent cause of "service not found"** in CI. The `kube-dns` Service IP must be reachable from the Pod, and CoreDNS Pods must be healthy.

## Headless service + StatefulSet = per-Pod DNS

A common pattern with StatefulSets:

```yaml
# Service
spec:
  clusterIP: None
  selector:
    app: db
---
# StatefulSet
spec:
  serviceName: db
  replicas: 3
```

Result:

* `db-0.db.default.svc.cluster.local` → Pod 0's IP
* `db-1.db.default.svc.cluster.local` → Pod 1's IP
* `db-2.db.default.svc.cluster.local` → Pod 2's IP

This is how you build stable per-replica addressing for databases, Kafka brokers, etcd members, etc.
