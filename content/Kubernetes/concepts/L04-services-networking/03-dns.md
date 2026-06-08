# DNS in Kubernetes

*"https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/"*

Every Service gets a DNS name automatically. Every Pod gets one too. This is the **primary way services find each other** in a cluster — don't hardcode IPs, ever. DNS in k8s is implemented by **CoreDNS** (since k8s 1.13), running as a Deployment in `kube-system` and exposed as a Service named `kube-dns` (kept for compatibility).

### Table of Contents

1. [Service DNS Records](#1-service-dns-records)
2. [Pod DNS Records](#2-pod-dns-records)
3. [The resolv.conf and ndots Magic](#3-the-resolvconf-and-ndots-magic)
4. [CoreDNS Architecture](#4-coredns-architecture)
5. [dnsPolicy and Pod-Level DNS Behavior](#5-dnspolicy-and-pod-level-dns-behavior)
6. [Custom dnsConfig and Search Paths](#6-custom-dnsconfig-and-search-paths)
7. [Headless Services + StatefulSets = Per-Pod DNS](#7-headless-services--statefulsets--per-pod-dns)
8. [Tuning CoreDNS for Performance](#8-tuning-coredns-for-performance)
9. [Stub Domains, Forward Plugins, and Custom Upstreams](#9-stub-domains-forward-plugins-and-custom-upstreams)
10. [Operations: Health, Scaling, Debugging](#10-operations-health-scaling-debugging)
11. [Gotchas and Common Mistakes](#11-gotchas-and-common-mistakes)

---

## 1. Service DNS Records

For a Service `my-svc` in namespace `my-ns` in a cluster with domain `cluster.local`:

```
my-svc.my-ns.svc.cluster.local
```

A real example, Service `frontend` in namespace `production`:

```
frontend.production.svc.cluster.local
```

### 1.1 Short forms

Inside a Pod, the resolver tries several forms before giving up (the **search path**). From inside the same namespace:

```
frontend                          # bare name (resolves in same namespace)
frontend.production               # namespace form
frontend.production.svc           # namespace + service
frontend.production.svc.cluster.local  # full FQDN
```

From a different namespace (`default`):

```
frontend                          # DOES NOT resolve (search path doesn't include other namespaces)
frontend.production               # DOES resolve
frontend.production.svc.cluster.local  # DOES resolve
```

This is why **cross-namespace access always needs at least the `<service>.<namespace>` form**.

### 1.2 Records created per Service type

| Service type | DNS record | Returns |
|---|---|---|
| `ClusterIP` | A record `<svc>.<ns>.svc.cluster.local` | The ClusterIP |
| `Headless` (`clusterIP: None`) | A records, **one per Pod** | Each Pod's IP |
| `ExternalName` | CNAME `<svc>.<ns>.svc.cluster.local` | The external name's resolved name |
| `NodePort` / `LoadBalancer` | A record (same as ClusterIP) | The ClusterIP — NodePort/LB is on the node IP, not in DNS |

**Headless** is special — instead of one A record pointing at the ClusterIP, you get N A records (one per Pod). This is the basis for per-Pod discovery in StatefulSets.

**ExternalName** returns a CNAME chain, not an A record. The actual resolution happens when the client queries the final name.

## 2. Pod DNS Records

Pods get DNS names based on their IP:

```
<ip-with-dashes>.<namespace>.pod.cluster.local
```

Example: Pod with IP `10.0.0.5` in namespace `default`:

```
10-0-0-5.default.pod.cluster.local
```

The IP is reversed and dots are replaced with dashes. This is sometimes useful, but most apps use Service DNS instead.

**Note:** the Pod's hostname (`spec.hostname`) and subdomain (`spec.subdomain`) also create records:

```yaml
spec:
  hostname: my-pod
  subdomain: my-headless-svc
```

With a headless Service `my-headless-svc`, this gives:

```
my-pod.my-headless-svc.<namespace>.svc.cluster.local
```

This is the older pattern for per-Pod discovery; StatefulSets do it more cleanly with stable names.

## 3. The resolv.conf and ndots Magic

When a Pod starts, the kubelet writes a `/etc/resolv.conf` for it:

```
nameserver 10.96.0.10        # the CoreDNS Service IP (kube-dns)
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

Three things to understand:

### 3.1 `nameserver`

The CoreDNS Service IP (called `kube-dns` for compatibility, but it's CoreDNS). **This is the only nameserver the Pod uses.** All DNS queries go through it.

### 3.2 `search`

When you do `nslookup frontend`, the resolver tries:

1. `frontend.default.svc.cluster.local` (prepend `<namespace>.svc.cluster.local`)
2. `frontend.svc.cluster.local` (prepend `svc.cluster.local`)
3. `frontend.cluster.local` (prepend `cluster.local`)
4. `frontend` (the bare name, as a last resort)

The first one that resolves wins. The Pod's namespace is the first search domain, so **inside the same namespace, bare names work**.

### 3.3 `ndots:5`

`ndots` is a **threshold**. If the query has **fewer than 5 dots**, the resolver tries the search path first. The query `frontend` has 0 dots — definitely under 5 — so all 4 search paths are tried.

A query like `api.example.com` has 2 dots — under 5 — so it's tried as:

1. `api.example.com.default.svc.cluster.local`  (NXDOMAIN)
2. `api.example.com.svc.cluster.local`           (NXDOMAIN)
3. `api.example.com.cluster.local`                (NXDOMAIN)
4. `api.example.com`                              (resolves!)

That's **3 failed lookups for every external call**. On busy clusters, this is a real perf problem.

The fix:

```yaml
spec:
  dnsConfig:
    options:
    - name: ndots
      value: "2"
```

With `ndots: 2`, queries with 2+ dots skip the search path. `api.example.com` (2 dots) goes straight to the upstream DNS. Saves 3 round-trips per external call.

**Tuning ndots is one of the highest-impact cluster optimizations** for apps that call external services. The default `ndots:5` is a k8s default, not a DNS default — most apps don't need it that high.

## 4. CoreDNS Architecture

CoreDNS is a single Deployment (usually 2 replicas for HA) plus a Service in `kube-system`. The Deployment runs `coredns` Pods that serve DNS on port 53.

```
┌──────────────────────────────────────────────────────────┐
│  Pod A's resolv.conf                                     │
│  nameserver 10.96.0.10 (kube-dns Service)                │
└─────────────────────┬────────────────────────────────────┘
                      │  DNS query (UDP or TCP :53)
                      ▼
┌──────────────────────────────────────────────────────────┐
│  kube-dns Service (ClusterIP 10.96.0.10)                 │
│  Routes to CoreDNS Pods in kube-system                   │
└─────────────────────┬────────────────────────────────────┘
                      │
                      ▼
┌──────────────────────────────────────────────────────────┐
│  CoreDNS Pod                                             │
│  ┌────────────────────────────────────────────────────┐  │
│  │ kubernetes plugin                                  │  │
│  │  - watches Services, Pods, Endpoints               │  │
│  │  - serves cluster.local records                    │  │
│  │  - serves in-addr.arpa / ip6.arpa (reverse)        │  │
│  ├────────────────────────────────────────────────────┤  │
│  │ forward plugin                                     │  │
│  │  - forwards external queries to upstream DNS       │  │
│  │  - uses /etc/resolv.conf of the CoreDNS pod        │  │
│  ├────────────────────────────────────────────────────┤  │
│  │ cache plugin                                       │  │
│  │  - caches responses (default 30s TTL)              │  │
│  │  - reduces upstream load                          │  │
│  ├────────────────────────────────────────────────────┤  │
│  │ health, ready, log, errors                         │  │
│  │  - health: HTTP /health on port :8080              │  │
│  │  - ready: HTTP /ready on :8181                     │  │
│  └────────────────────────────────────────────────────┘  │
└─────────────────────┬────────────────────────────────────┘
                      │
                      ▼
       Upstream DNS (node's /etc/resolv.conf)
       or custom forward (e.g. corporate DNS, 8.8.8.8)
```

### 4.1 The Corefile

CoreDNS is configured by a **Corefile**, stored in a ConfigMap named `coredns` in `kube-system`:

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

Plugins execute in order, top to bottom. The first plugin to answer wins; the rest are skipped for that query.

| Plugin | What it does |
|---|---|
| `errors` | Logs errors |
| `health` | Serves HTTP on :8080 for liveness checks |
| `ready` | Serves HTTP on :8181 to indicate the Pod is ready (only after plugins have loaded) |
| `kubernetes` | The core plugin. Watches the apiserver for Services and Pods, serves `cluster.local` records. The `pods insecure` option enables per-Pod DNS. |
| `forward` | Forwards queries to upstream DNS (uses the CoreDNS Pod's `/etc/resolv.conf` by default) |
| `cache` | Caches responses, 30s TTL by default |
| `loop` | Detects forwarding loops |
| `reload` | Hot-reloads the Corefile on change |
| `loadbalance` | Round-robins A record responses |

## 5. dnsPolicy and Pod-Level DNS Behavior

The Pod's `dnsPolicy` controls how `/etc/resolv.conf` is generated:

| Policy | Behavior | Use case |
|---|---|---|
| `ClusterFirst` | Use CoreDNS for cluster queries, upstream for everything else (default) | Most apps |
| `Default` | Inherit the node's `/etc/resolv.conf` entirely | Apps that need node-level DNS, e.g. some monitoring |
| `ClusterFirstWithHostNet` | `ClusterFirst` for queries, but use the host's network for the Pod itself | Host-network Pods that still want cluster DNS |
| `None` | No DNS config generated. You must specify `dnsConfig` explicitly | Fully custom DNS, advanced use cases |

```yaml
spec:
  dnsPolicy: ClusterFirst   # default, can be omitted
  dnsConfig:
    options:
    - name: ndots
      value: "2"
    nameservers:
    - 1.1.1.1               # custom upstream (used with dnsPolicy: None)
```

### 5.1 The `hostNetwork` gotcha

If a Pod has `hostNetwork: true` and `dnsPolicy: ClusterFirst`, the kubelet can't write the right resolv.conf — the Pod is on the host's network and uses the host's resolver. **Use `ClusterFirstWithHostNet` to keep cluster DNS working.**

## 6. Custom dnsConfig and Search Paths

```yaml
spec:
  dnsConfig:
    nameservers:
    - 10.96.0.10            # CoreDNS (default; usually not overridden)
    - 1.1.1.1               # fallback upstream
    searches:
    - my-org.svc.cluster.local
    - other-org.svc.cluster.local
    options:
    - name: ndots
      value: "2"
    - name: timeout
      value: "3"
    - name: attempts
      value: "2"
```

The `searches` field **replaces** the default search path. If you specify it, you lose the default `default.svc.cluster.local svc.cluster.local cluster.local` — you need to add them back if you still want them.

### 6.1 Custom resolvers per Pod

You can set `dnsConfig.nameservers` to point to specific DNS servers:

```yaml
dnsConfig:
  nameservers:
  - 10.0.0.53              # corporate DNS
  - 8.8.8.8                # backup
  options:
  - name: ndots
    value: "1"
```

This is useful when:

* You have a private DNS zone for `internal.company.com` that the cluster DNS can't see.
* You're connecting to a legacy network that has its own DNS.
* You're testing DNS behavior.

## 7. Headless Services + StatefulSets = Per-Pod DNS

A common pattern for stateful workloads:

```yaml
# Service: headless
apiVersion: v1
kind: Service
metadata:
  name: db
spec:
  clusterIP: None           # headless
  selector:
    app: db
  ports:
  - port: 5432
---
# StatefulSet
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: db
spec:
  serviceName: db           # ties to the headless Service
  replicas: 3
  selector:
    matchLabels:
      app: db
  template:
    metadata:
      labels:
        app: db
    spec:
      containers:
      - name: postgres
        image: postgres:15
  ...
```

Result:

```
db-0.db.default.svc.cluster.local  →  10.244.1.5
db-1.db.default.svc.cluster.local  →  10.244.2.7
db-2.db.default.svc.cluster.local  →  10.244.3.9
```

The Pods are reachable by their **stable ordinal name**. Even when Pod-0 is rescheduled to a new node and gets a new IP, the DNS record follows it (CoreDNS watches EndpointSlices).

This is the **canonical way** to address replicas in:

* PostgreSQL (primary + replicas)
* MongoDB (replica sets)
* Kafka (brokers)
* etcd (members)
* ZooKeeper (ensemble)
* Elasticsearch (data/master nodes)

## 8. Tuning CoreDNS for Performance

### 8.1 The default scale

Most k8s distributions install CoreDNS with 2 replicas. This handles up to ~1000 QPS before latency starts to creep.

### 8.2 When to scale

Watch these metrics (CoreDNS exposes Prometheus metrics on :9153):

* `coredns_dns_requests_total` — request rate
* `coredns_dns_responses_total` — response rate
* `coredns_dns_request_duration_seconds` — p50/p99 latency
* `coredns_cache_hits_total` vs `coredns_cache_misses_total` — cache hit ratio

If p99 latency is > 5ms or cache hit ratio is < 80%, scale up.

### 8.3 Common tunings

```yaml
# increase replicas
spec:
  replicas: 4   # was 2
```

```yaml
# increase cache TTL in the Corefile
cache 300   # 5 minutes, was 30s
```

**Note:** higher cache TTL means longer delay when records change. 30s is a reasonable default. 300s is fine for services that don't churn.

```yaml
# add the autopath plugin
autopath @kubernetes
```

The `autopath` plugin **reduces the ndots:5 problem** by skipping search paths when it can guess the FQDN. Less effective than setting `ndots: 2` in the Pod, but helps for Pods that don't set dnsConfig.

```yaml
# use NodeLocal DNSCache
# a DaemonSet that runs a DNS cache on every node
# caches per-node, reducing CoreDNS load by 10-100x
# https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/
```

NodeLocal DNSCache is one of the **biggest perf wins** for DNS-heavy clusters. It runs a per-node caching proxy that serves most queries from memory, only hitting CoreDNS for cache misses.

## 9. Stub Domains, Forward Plugins, and Custom Upstreams

### 9.1 Stub domains

A **stub domain** is a custom DNS zone that's served by a specific DNS server. Example: queries for `consul.local` should go to the Consul DNS server.

```Corefile
.:53 {
    kubernetes cluster.local in-addr.arpa ip6.arpa {
      pods insecure
      fallthrough in-addr.arpa ip6.arpa
    }
    forward . /etc/resolv.conf
    cache 30
}

consul.local:53 {
    forward . 10.0.0.53:8600   # Consul DNS
    cache 30
}
```

Now queries for `service.consul.local` go to the Consul DNS server. Used for:

* Consul service discovery
* Active Directory (the Windows kind)
* Custom internal DNS zones

### 9.2 Custom forward targets

By default, `forward . /etc/resolv.conf` sends external queries to whatever's in the CoreDNS Pod's resolv.conf (which is the node's resolv.conf). You can change this:

```Corefile
.:53 {
    kubernetes cluster.local in-addr.arpa ip6.arpa {
      pods insecure
      fallthrough in-addr.arpa ip6.arpa
    }
    forward . 8.8.8.8 1.1.1.1   # custom upstreams
    cache 30
}
```

Useful for:

* Restricting which upstreams the cluster can talk to (security)
* Routing through a corporate DNS for compliance
* Using a faster public DNS

### 9.3 Modifying the Corefile

```bash
kubectl -n kube-system edit configmap coredns
# edit the Corefile

# CoreDNS picks up the change automatically (reload plugin)
# or if reload is disabled:
kubectl -n kube-system rollout restart deployment coredns
```

`kubectl rollout restart` is the safe way — CoreDNS Pods roll one at a time, so DNS never goes down. The `reload` plugin watches the file and re-reads it on change.

## 10. Operations: Health, Scaling, Debugging

### 10.1 Health and ready

CoreDNS exposes:

* `http://<pod>:8080/health` — liveness probe (lives on :8080)
* `http://<pod>:8181/ready` — readiness probe (lives on :8181)

The default liveness/readiness probes (in the Deployment) hit these. **Both are essential** — if `ready` fails, the Pod is removed from the Service, and DNS queries to its IP fail.

### 10.2 Common commands

```bash
# check CoreDNS health
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=100

# test DNS from inside a Pod
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- bash
# inside:
nslookup kubernetes.default
nslookup backend.prod
nslookup google.com

# check the CoreDNS service
kubectl -n kube-system get svc kube-dns
# ClusterIP 10.96.0.10 is what every Pod's resolv.conf points at

# view the Corefile
kubectl -n kube-system get configmap coredns -o yaml

# check CoreDNS metrics
kubectl -n kube-system port-forward <coredns-pod> 9153:9153
# then: curl localhost:9153/metrics
```

### 10.3 Debugging DNS failures

```
DNS not resolving
       │
       ├── "connection refused" on UDP :53 ── CoreDNS Pods not running, 
       │                                         or kube-dns Service IP not routable
       │
       ├── "timeout" ── upstream DNS is unreachable, or NetworkPolicy blocking egress
       │
       ├── "NXDOMAIN" on a known Service ── CoreDNS not watching the namespace, 
       │                                      or Service doesn't exist
       │
       ├── "no such host" ── resolv.conf is wrong, nameservers empty
       │
       └── "SERVFAIL" ── CoreDNS plugin chain is broken, check logs
```

**Step 1: verify CoreDNS is up.**

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=50
```

**Step 2: verify the kube-dns Service is up and reachable from the Pod.**

```bash
kubectl exec -it <pod> -- nslookup kubernetes.default
# should return the kubernetes Service IP (10.96.0.1 by default)
```

**Step 3: verify upstream DNS works.**

```bash
kubectl exec -it <pod> -- nslookup google.com
# should return 142.250.x.x or similar
```

**Step 4: check the Pod's resolv.conf.**

```bash
kubectl exec -it <pod> -- cat /etc/resolv.conf
# should show nameserver 10.96.0.10 (or whatever kube-dns is)
```

**Step 5: check NetworkPolicy.**

```bash
kubectl get networkpolicy -A
# is there an Egress policy that blocks UDP :53 from the Pod?
```

### 10.4 The `ndots:5` perf problem

If your app is making slow external calls, check:

```bash
# from inside the Pod
strace -e trace=connect -f nslookup api.example.com 2>&1 | grep AF_INET
# count the connect() calls — should be 1-2, not 4+
```

If you see 4+ connections per lookup, the app's resolv.conf has high `ndots`. Fix it via `dnsConfig`.

## 11. Gotchas and Common Mistakes

### 11.1 The 25+ common mistakes

1. **Not tuning `ndots:5` for external services.** Every external DNS query has 3 failed lookups before the real one. **Biggest perf issue in default k8s DNS.**

2. **Putting the Service's ClusterIP in external DNS.** ClusterIPs aren't routable from outside the cluster. They'll be unreachable.

3. **Resolving Service DNS from outside the cluster.** `dig backend.prod.svc.cluster.local` from your laptop will fail unless you've set up DNS forwarding.

4. **CoreDNS OOMKilled on busy clusters.** Default memory limit is too low. Increase to 256Mi or 512Mi depending on QPS.

5. **`dnsPolicy: Default` accidentally set.** Inherits the node's resolv.conf, breaking cluster DNS resolution. Some Helm charts set this for monitoring sidecars.

6. **`dnsPolicy: ClusterFirstWithHostNet` forgotten on hostNetwork Pods.** Pods with `hostNetwork: true` and `ClusterFirst` end up using the host's resolver (not CoreDNS). Symptom: cluster Service names don't resolve.

7. **`dnsPolicy: None` without `dnsConfig`.** The Pod gets no resolv.conf. DNS resolution is broken.

8. **Forgetting `protocol: UDP` for DNS Services.** A Service exposing DNS on port 53 with `protocol: TCP` (default) only serves TCP DNS, breaking UDP-based resolution.

9. **Stub domain config breaks cluster DNS.** A typo in the Corefile can break the whole config. The `loop` plugin catches some of these, but not all.

10. **CoreDNS Pods are not all Ready.** The `ready` plugin reports Ready only after all plugins are loaded. On startup, this takes a few seconds. During this window, queries fail.

11. **ExternalName with a deep CNAME chain.** Some clients don't follow long chains. Use an A record for the final name if the client is finicky.

12. **Headless Service without `serviceName` on the StatefulSet.** The Pods don't get per-Pod DNS records. Symptom: queries for `pod-0.svc.namespace` return NXDOMAIN.

13. **CoreDNS `forward` plugin points to a server that doesn't respond.** Queries hang. The `loop` plugin detects forwarding loops, but a slow / unresponsive upstream just slows everything down.

14. **Cache TTL too high for high-churn Services.** If a Service gets new Pod IPs every few seconds, the cache will return stale IPs for the duration of the TTL. Don't go above 60s in production.

15. **Modifying the Corefile with `kubectl edit` doesn't propagate.** The `reload` plugin only watches the local file, which is mounted from the ConfigMap. After editing the ConfigMap, the Pods may need a restart. **Always check the Pod's logs to confirm.**

16. **Forgetting `fallthrough` in the kubernetes plugin.** Without it, the plugin only answers records for the cluster.local zone. PTR queries (reverse DNS) for other zones fail.

17. **`pods insecure` vs `pods verified`.** `pods insecure` allows per-Pod DNS records (e.g. `10-0-0-5.default.pod.cluster.local`) without checking the Pod's owner. `pods verified` requires the Pod to be in a known namespace. `pods disabled` turns off per-Pod records entirely.

18. **The `cache` plugin caches negative responses too.** A NXDOMAIN for a Service that's about to be created can be cached for 30s, delaying the rollout.

19. **CoreDNS metrics on :9153, health on :8080, ready on :8181.** These are three different ports. Scrape metrics on :9153, not :8080.

20. **Cross-namespace Pod DNS works for any Pod, but cross-namespace Service DNS needs the namespace form.** `backend` works only in the same namespace. `backend.prod` works from anywhere.

21. **The `kubernetes` plugin watches the apiserver. If the apiserver is unreachable, DNS for cluster.local stops working.** CoreDNS doesn't have a cache of all Services — it queries the apiserver on demand.

22. **`/etc/resolv.conf` of the CoreDNS Pod is inherited from the node.** If the node's DNS is misconfigured, external queries fail. The `forward` plugin uses this.

23. **The `search` path doesn't include the cluster domain by default on some kubeadm versions.** Always check `cat /etc/resolv.conf` from a Pod.

24. **`/etc/nsswitch.conf` is generated by the kubelet.** Apps that do NSS lookups (glibc, `getent hosts`) use it. Most languages (Go, Python, Java) bypass NSS and call the resolver directly. Different layers, different behavior.

25. **Reverse DNS (`in-addr.arpa`) for Pod IPs is enabled with `pods insecure`.** If you turn it off, reverse lookups stop working — some apps use them for logging or auth.

26. **Multi-cluster DNS is not automatic.** Pods in cluster A can't resolve `backend` in cluster B without explicit setup (submariner, skupper, Cilium ClusterMesh, etc.).

27. **IPv6 DNS requires dual-stack config.** The reverse zone `ip6.arpa` is configured separately from `in-addr.arpa`. Both must be set in the kubernetes plugin.

28. **The DNS Service IP must be in the Service CIDR.** If the apiserver's `--service-cluster-ip-range` doesn't include the kube-dns IP, the Service won't be created. Symptom: CoreDNS is up but Pods can't reach it.

29. **Some apps don't use system DNS at all.** They have their own DNS client (Java's InetAddress, Go's net.Resolver, etc.). These usually respect `/etc/resolv.conf` but may not respect `dnsConfig` in the Pod spec the same way.

30. **The `dnsConfig.options` field accepts only specific names.** `ndots`, `timeout`, `attempts`, `rotate`, `use-vc` (force TCP). Other names are silently ignored.

### 11.2 The "DNS not resolving" checklist

```bash
# 1. CoreDNS is up?
kubectl -n kube-system get pods -l k8s-app=kube-dns

# 2. kube-dns Service is up?
kubectl -n kube-system get svc kube-dns

# 3. From inside a Pod:
kubectl exec -it <pod> -- nslookup kubernetes.default
# should return 10.96.0.1 (or similar)

# 4. resolv.conf is correct?
kubectl exec -it <pod> -- cat /etc/resolv.conf
# nameserver should be the kube-dns Service IP

# 5. NetworkPolicy allows UDP :53 egress?
kubectl get networkpolicy -A

# 6. External DNS works?
kubectl exec -it <pod> -- nslookup google.com

# 7. Check CoreDNS logs for errors
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=100 | grep -i error
```

## See also

* [[Kubernetes/concepts/L04-services-networking/01-networking|Networking]] — the L04 mental model
* [[Kubernetes/concepts/L04-services-networking/02-services|Services]] — the primary user of DNS
* [[Kubernetes/concepts/L04-services-networking/04-ingress|Ingress]] — L7 routing
* [[Kubernetes/concepts/L04-services-networking/06-cni|CNI]] — the layer below
* [[Kubernetes/concepts/L03-workloads/04-statefulsets|StatefulSets]] — primary consumer of per-Pod DNS
