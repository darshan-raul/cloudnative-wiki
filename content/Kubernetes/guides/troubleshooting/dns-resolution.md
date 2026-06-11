---
title: DNS Resolution Failures
tags:
  - Kubernetes
  - Troubleshooting
  - Networking
  - DNS
  - CoreDNS
---

Pods can resolve Service names through CoreDNS. When DNS doesn't work, **every Service-to-Service call fails**, even though the Services themselves are healthy. This is the third most common k8s issue (after CrashLoopBackOff and pending pods).

## Symptoms

```bash
# from inside a pod
$ nslookup web-service
;; connection timed out; no servers could be reached

$ nslookup web-service
Server:    10.96.0.10
Address 1: 10.96.0.10
*** Can't find web-service: No answer

$ nslookup web-service
Server:    10.96.0.10
Address 1: 10.96.0.10
Name:      web-service
Address 1: 10.244.1.5    <-- pod IP, not ClusterIP
# Headless service? Or broken kube-dns?
```

```bash
$ curl http://web-service:8080
curl: (6) Could not resolve host: web-service

$ curl http://web-service.default.svc.cluster.local:8080
hello world    <-- but the FQDN works
# ndots issue, not a real DNS failure
```

```bash
$ curl http://google.com
curl: (6) Could not resolve host: google.com
# external DNS broken
```

## The 30-second diagnosis

```bash
# 1. can you resolve anything?
kubectl exec -it debug -- nslookup kubernetes.default

# 2. is CoreDNS running?
kubectl get pods -n kube-system -l k8s-app=kube-dns
# kube-dns is the name, CoreDNS is the implementation

# 3. is the Service for kube-dns OK?
kubectl get svc -n kube-system kube-dns
# NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)
# kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP

# 4. what does the pod's resolv.conf look like?
kubectl exec -it debug -- cat /etc/resolv.conf
# nameserver 10.96.0.10
# search default.svc.cluster.local svc.cluster.local cluster.local
# options ndots:5

# 5. is the kube-dns Service actually answering?
kubectl run debug --rm -it --image=busybox --restart=Never -- \
  nslookup web-service 10.96.0.10
```

## How DNS works in Kubernetes

Every pod gets `/etc/resolv.conf` injected:

```
nameserver 10.96.0.10
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

```
┌────────────────────────────────────────────────────────────┐
│ Pod's resolv.conf                                          │
│                                                            │
│  nameserver 10.96.0.10        ← kube-dns Service ClusterIP│
│  search ns.svc.cluster.local  ← search domains             │
│         svc.cluster.local                                 │
│         cluster.local                                     │
│  options ndots:5             ← FQDN check threshold        │
└────────────────────────────────────────────────────────────┘
        │
        │ (UDP/TCP 53)
        ▼
┌────────────────────────────────────────────────────────────┐
│ kube-dns Service (10.96.0.10)                              │
│   ↓ iptables/IPVS rules                                    │
│ CoreDNS pods (in kube-system)                              │
│   - watch k8s API for Service/Endpoint changes             │
│   - serve A/AAAA/SRV records for Services                  │
│   - forward external queries to upstream DNS               │
└────────────────────────────────────────────────────────────┘
```

The flow for a query:
1. Pod asks `web-service`
2. With `ndots:5`, the resolver checks: is this an FQDN? `web-service` has 0 dots, so no.
3. The resolver appends search domains: `web-service.default.svc.cluster.local.`, then `web-service.svc.cluster.local.`, etc.
4. If none match, fallback to `web-service.cluster.local.`
5. If still no match, query upstream DNS for `web-service` (treating as external)

If the first name (`web-service.default.svc.cluster.local.`) matches a Service, you get an answer. If it doesn't match (e.g., you meant an external hostname), you get **5 failed lookups** before the resolver asks upstream.

## The taxonomy of DNS issues

```
┌──────────────────────────────────────────────────────────────┐
│                  DNS Resolution Failures                     │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. CoreDNS pods not running     (CoreDNS itself crashed)    │
│  2. kube-dns Service missing     (Service was deleted)       │
│  3. resolv.conf injection wrong  (custom config or kubelet)  │
│  4. CoreDNS can't reach apiserver (RBAC, network)            │
│  5. ndots:5 makes external slow  (perceived as broken)       │
│  6. DNS forwarder broken         (upstream unreachable)      │
│  7. Too many Services, CoreDNS OOM (memory pressure)         │
│  8. NetworkPolicy blocks port 53 (DNS queries to kube-dns)   │
│  9. Pod's DNS cache stale        (records not refreshing)   │
│ 10. CoreDNS version vs k8s       (Corefile incompatible)     │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## 1. CoreDNS pods not running

The CoreDNS Deployment is unhealthy, so no DNS server is responding.

**Signatures:**

```bash
$ kubectl get pods -n kube-system -l k8s-app=kube-dns
NAME                       READY   STATUS             RESTARTS   AGE
coredns-5554c7b6f7-1       0/1     CrashLoopBackOff   5          5m
coredns-5554c7b6f7-2       1/1     Running            0          1h
```

```bash
$ kubectl exec -it debug -- nslookup web-service
;; connection timed out; no servers could be reached
```

**Diagnosis:** see [[Kubernetes/guides/troubleshooting/crashloop-backoff|crashloop-backoff]] for diagnosing the CoreDNS pod. The same patterns apply.

**Common sub-causes:**

1. **CoreDNS is OOMKilled.** CoreDNS has a default memory limit (~170Mi) that's tight for clusters with thousands of Services. When the limit is hit, OOMKilled.
   ```bash
   $ kubectl describe pod coredns-xxx -n kube-system | grep -A 3 "Last State"
   Last State:     Terminated
     Reason:       OOMKilled
     Exit Code:    137
   ```
   Fix: increase the memory limit in the CoreDNS Deployment.

2. **CoreDNS can't reach the apiserver.** If the apiserver is unreachable, CoreDNS can't watch Services and can't serve records.
   ```bash
   $ kubectl logs -n kube-system coredns-xxx
   .:53
   2024-01-15 10:00:00 [ERROR] plugin/kubernetes: failed to list API: ...
   ```
   Fix: see the apiserver connectivity issue.

3. **CoreDNS Deployment scaled to zero.** A bad Helm release or manual scale-down.
   ```bash
   $ kubectl get deploy -n kube-system coredns
   NAME      READY   UP-TO-DATE   AVAILABLE   AGE
   coredns   0/2     0            0           5m
   ```
   Fix: `kubectl scale deploy coredns -n kube-system --replicas=2`.

## 2. kube-dns Service missing

The Service that fronts CoreDNS is gone. Pods try to reach `10.96.0.10`, get nothing.

**Signatures:**

```bash
$ kubectl get svc -n kube-system kube-dns
Error from server (NotFound): services "kube-dns" not found

$ kubectl exec -it debug -- cat /etc/resolv.conf
nameserver 10.96.0.10   <-- points to a Service that doesn't exist
```

**Diagnosis:**

```bash
# 1. is the Service there?
kubectl get svc -n kube-system kube-dns
kubectl get svc -n kube-system -l k8s-app=kube-dns

# 2. recreate it
kubectl apply -f https://k8s.io/examples/admin/dns/dns-udp-service.yaml
```

**Common sub-causes:**

1. **Someone deleted the Service.** Manual deletion, or a tool that re-creates CoreDNS without recreating the Service.
2. **Cluster bootstrap didn't include kube-dns.** Rare; usually only on minimal clusters.
3. **The Service has the wrong ClusterIP.** Pods cache the old IP. Restart pods to refresh.

## 3. resolv.conf injection wrong

The pod's `/etc/resolv.conf` doesn't have the right nameserver, or has a stale IP.

**Signatures:**

```bash
$ kubectl exec -it debug -- cat /etc/resolv.conf
nameserver 8.8.8.8        <-- not kube-dns, just the upstream
search my-domain.local
options ndots:1
```

```bash
$ kubectl exec -it debug -- cat /etc/resolv.conf
nameserver 10.96.0.10
search wrong-namespace.svc.cluster.local   <-- wrong ns
```

**Diagnosis:**

```bash
# 1. what's the kubelet's DNS config?
ssh node-1
$ cat /var/lib/kubelet/config.yaml | grep -A 10 "dns:"

# 2. what did the user configure on the pod?
kubectl get pod debug -o json | jq '.spec.dnsConfig'
# could be a dnsPolicy or dnsConfig customization
```

**Common sub-causes:**

1. **Pod has `dnsPolicy: Default`** (uses node's resolv.conf, not k8s DNS).
   ```yaml
   spec:
     dnsPolicy: Default   # inherits from node, not k8s
   ```
   Fix: change to `ClusterFirst` (default).

2. **Pod has `dnsConfig` overriding search/nameserver.**
   ```yaml
   spec:
     dnsConfig:
       nameservers:
       - 8.8.8.8          # bypasses kube-dns
       searches:
       - my-domain.local
   ```
   Fix: remove the override, or fix it.

3. **The kubelet was configured with `--cluster-dns=<wrong-ip>`.**
   ```bash
   # in /var/lib/kubelet/config.yaml
   clusterDNS:
   - 10.96.0.42          # wrong IP
   ```
   Fix: update to the right ClusterIP of the kube-dns Service.

4. **Custom DNS settings on the container runtime** (rare, but possible with custom containerd configs).

## 4. CoreDNS can't reach the apiserver

CoreDNS watches the apiserver for Service changes. If it can't reach the apiserver, it serves stale records (or empty).

**Signatures:**

```bash
$ kubectl logs -n kube-system coredns-xxx
[ERROR] plugin/kubernetes: failed to list API: Get "https://10.96.0.1:443/api/v1/services":
  dial tcp 10.96.0.1:443: i/o timeout
```

```bash
# from a pod, Service lookups return NXDOMAIN or wrong IPs
$ nslookup web-service
*** Can't find web-service: No answer
```

**Diagnosis:**

```bash
# 1. can CoreDNS reach the apiserver?
kubectl exec -n kube-system coredns-xxx -- wget -qO- https://10.96.0.1/api
# or
kubectl exec -n kube-system coredns-xxx -- curl -k -sS https://10.96.0.1/api

# 2. check CoreDNS RBAC
kubectl get clusterrolebinding | grep coredns

# 3. check the CoreDNS ConfigMap
kubectl get cm -n kube-system coredns -o yaml
```

**Common sub-causes:**

1. **CoreDNS ServiceAccount missing the cluster role binding.**
   ```bash
   $ kubectl get clusterrolebinding system:coredns -o yaml
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRoleBinding
   subjects:
   - kind: ServiceAccount
     name: coredns
     namespace: kube-system
   ```
   Fix: re-create the ClusterRoleBinding.

2. **NetworkPolicy blocks CoreDNS from reaching the apiserver.** If the kube-system namespace has a default-deny, CoreDNS might be blocked.
3. **DNS forward upstream is broken.** CoreDNS forwards external queries to upstream; if those forwarders are down, external lookups fail.

## 5. ndots:5 makes external slow (the famous one)

`ndots:5` means "if the name has fewer than 5 dots, append search domains." Most external hostnames have 1-2 dots, so the resolver tries 4+ search domains before falling through.

**Signatures:**

```bash
# curl to external hostname takes 5+ seconds
$ time curl https://google.com
# real    0m 5.234s
```

**Diagnosis:**

```bash
# 1. check the pod's resolv.conf
kubectl exec -it pod -- cat /etc/resolv.conf
# options ndots:5   <-- the culprit

# 2. look at the queries in tcpdump or CoreDNS logs
kubectl logs -n kube-system coredns-xxx | grep google.com
# you'd see 4-5 queries for variants of google.com + search domains
```

**Fix:** set `ndots:2` in the pod's `dnsConfig`:

```yaml
spec:
  dnsConfig:
    options:
    - name: ndots
      value: "2"
```

Or for an FQDN, add a trailing dot (e.g., `google.com.`), which is treated as fully-qualified and skips the search expansion.

## 6. DNS forwarder broken

CoreDNS forwards external queries to upstream resolvers. If those are unreachable, external DNS fails.

**Signatures:**

```bash
$ kubectl exec -it pod -- nslookup google.com
Server:    10.96.0.10
Address 1: 10.96.0.10
*** Can't find google.com: No answer
# internal works, external doesn't
```

```bash
$ kubectl logs -n kube-system coredns-xxx | grep forward
# errors about upstream resolvers
```

**Diagnosis:**

```bash
# 1. check the Corefile
kubectl get cm -n kube-system coredns -o jsonpath='{.data.Corefile}' | grep forward

# 2. test the upstream
kubectl exec -n kube-system coredns-xxx -- nslookup google.com 8.8.8.8

# 3. check the CoreDNS deployment's env for resolver overrides
kubectl get deploy -n kube-system coredns -o yaml | grep -A 5 "env"
```

**Common sub-causes:**

1. **Upstream DNS unreachable from cluster.** Firewall blocks port 53 outbound to 8.8.8.8.
2. **Wrong forward target.** The Corefile says `forward . 8.8.8.8 1.1.1.1` but the cluster should be using internal DNS (e.g., VPC DNS at 10.0.0.2).
3. **The Corefile has a typo.** `forwrad` instead of `forward`.
4. **Upstream DNS returns SERVFAIL** for some queries. Some resolvers block certain domains.

## 7. Too many Services, CoreDNS OOM

CoreDNS has a default memory limit. Clusters with thousands of Services can blow through it.

**Signatures:**

```bash
$ kubectl describe pod coredns-xxx -n kube-system | grep -A 3 "Last State"
Last State:     Terminated
  Reason:       OOMKilled
  Exit Code:    137
```

```bash
# CoreDNS restarts every few minutes
$ kubectl get pods -n kube-system -l k8s-app=kube-dns
NAME                       READY   STATUS    RESTARTS
coredns-5554c7b6f7-1       1/1     Running   12
coredns-5554c7b6f7-2       1/1     Running   10
```

**Fix:** increase the memory limit in the CoreDNS Deployment:

```yaml
resources:
  limits:
    memory: 512Mi   # up from 170Mi
  requests:
    cpu: 100m
    memory: 70Mi
```

For very large clusters (10K+ Services), consider:
- **NodeLocal DNSCache** — runs a DNS proxy on every node, reduces CoreDNS load.
- **Cilium DNS proxy** — eBPF-based, scales better.
- **External DNS provider** (e.g., SkyDNS replacement, BIND-based, etc.).

## 8. NetworkPolicy blocks port 53

A default-deny NetworkPolicy without an allow for kube-dns. Pods can't reach the DNS server.

**Signatures:**

```bash
$ kubectl exec -it pod -- nslookup web-service
;; connection timed out; no servers could be reached
```

**Diagnosis:**

```bash
# 1. what NetworkPolicies apply to the pod?
kubectl get netpol -n my-ns
# a default-deny

# 2. is there an egress allow for kube-dns?
kubectl get netpol -n my-ns -o yaml | grep -A 10 "egress"
```

**Fix:** add an egress allow for DNS to the kube-system namespace:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: my-ns
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
```

## 9. Pod's DNS cache stale

Some applications cache DNS results. If a Service's IP changes (e.g., during a rollout), the app keeps using the old IP.

**Signatures:**

```bash
# the Service is healthy, but the app keeps trying the old IP
$ kubectl logs -it pod
dial tcp 10.244.1.5:8080: connect: connection refused
# the IP used to work; now nothing listens there
```

**Fix:** disable DNS caching in the app, or set a short TTL. In Go, the default TTL is 30s; in `musl libc` containers, there's no caching by default. In JVM, the default is forever (the famous "DNS resolution stuck" Java bug).

For JVM:
```java
# set TTL in security policy
networkaddress.cache.ttl=10
```

## 10. CoreDNS version vs k8s version

Older CoreDNS versions may not work with newer k8s. The Corefile syntax can be incompatible.

**Signatures:**

```bash
$ kubectl logs -n kube-system coredns-xxx
[FATAL] plugin/kubernetes: incompatible CoreDNS version
```

**Fix:** upgrade CoreDNS to a version compatible with your k8s version. The k8s documentation lists the supported CoreDNS versions for each release.

## Useful DNS debugging tools

```bash
# 1. dnsutils — has nslookup, dig, host
kubectl run debug --rm -it --image=gcr.io/kubernetes-e2e-test-images/jessie-dnsutils:1.5 --restart=Never -- bash

# 2. nslookup the ClusterIP
kubectl exec -it pod -- nslookup web-service 10.96.0.10

# 3. dig with trace
kubectl exec -it pod -- dig +trace web-service

# 4. check response time
kubectl exec -it pod -- time nslookup web-service

# 5. specific record type
kubectl exec -it pod -- dig web-service A
kubectl exec -it pod -- dig web-service SRV
```

## The "is it CoreDNS or the pod?" test

```bash
# 1. can you resolve directly from CoreDNS?
kubectl exec -n kube-system coredns-xxx -- nslookup web-service
# if YES → CoreDNS is fine, issue is the pod's resolv.conf
# if NO  → CoreDNS is the problem

# 2. can a different pod in the same namespace resolve?
kubectl exec -it other-pod -- nslookup web-service
# if YES → issue is the original pod's resolv.conf
# if NO  → issue is CoreDNS or shared config

# 3. can CoreDNS resolve from the kube-system namespace?
kubectl exec -n kube-system coredns-xxx -- nslookup kubernetes.default
# if NO  → CoreDNS itself is broken
```

## The "is it internal or external DNS?" test

```bash
# 1. internal
kubectl exec -it pod -- nslookup web-service
# works → internal DNS is fine
# fails → CoreDNS or resolv.conf issue

# 2. external
kubectl exec -it pod -- nslookup google.com
# works → external DNS is fine
# fails → forwarder issue

# 3. FQDN
kubectl exec -it pod -- nslookup web-service.default.svc.cluster.local
# works → search domains might be the issue
# fails → something deeper
```

## Common gotchas

* **`/etc/resolv.conf` from the node, not the pod.** If your container has its own `resolv.conf` baked in (e.g., a custom base image), k8s won't override it. The pod will use whatever you put in the image.
* **`ndots:5` is the default** and is often wrong. Set `ndots:2` for typical apps.
* **Headless Services return pod IPs from DNS.** If your app expects a single ClusterIP, you'll be confused by the multiple A records.
* **SRV records for named ports.** If your Service has `port.name: http`, the DNS query for `_http._tcp.web-service` returns an SRV record, not A. Some clients don't handle SRV.
* **The DNS path has 5 levels of caching.** Pod's libc cache, NodeLocal DNSCache (if installed), CoreDNS, kube-dns Service VIP, apiserver cache. Each can be stale.
* **CoreDNS logging can spam.** If you turn on debug logging, it can fill the disk quickly. Don't leave it on.
* **Search domains add up.** If you have many search domains, the resolver tries each one. `ndots:5` + 3 search domains = a lot of queries for short names.
* **Some apps don't honor resolv.conf.** Hard-coded DNS in the app (e.g., `dns.resolver({ servers: ['8.8.8.8'] })`) bypasses k8s DNS.
* **TCP vs UDP.** CoreDNS serves both, but some networks only allow UDP. If UDP is dropped, TCP should still work, but if both are blocked, DNS fails.
* **The `kube-dns` Service is the cluster DNS Service.** It's named `kube-dns` for historical reasons (the original was `kube-dns`, an older SkyDNS-based system). CoreDNS is the modern implementation that runs behind it.

## A worked example

```bash
$ kubectl exec -it web-1 -- nslookup api-service
Server:    10.96.0.10
Address 1: 10.96.0.10
*** Can't find api-service: No answer

$ kubectl get svc -n my-ns
NAME           TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)
api-service    ClusterIP   10.96.0.100    <none>        80/TCP
# Service exists

$ kubectl get pods -n my-ns -l app=api
NAME       READY   STATUS    RESTARTS   AGE
api-1      0/1     Running   0          5m
api-2      1/1     Running   0          5m
# one pod is not ready

$ kubectl describe pod api-1 -n my-ns | tail -5
Events:
  Warning  Unhealthy  3m  kubelet  Readiness probe failed: HTTP 503
# the unhealthy pod isn't in endpoints

# So why does nslookup return NXDOMAIN, not just one IP?
# Because the service has only 1 healthy endpoint, and CoreDNS returned that
# but the client app is querying for a stale or different name.

$ kubectl exec -it web-1 -- nslookup api-service.my-ns.svc.cluster.local
# works

# Aha! ndots issue — the app was querying "api-service" and CoreDNS didn't
# match it without the search domain expansion
```

Wait — actually the original query was `api-service` and returned NXDOMAIN. The FQDN works. So the issue is ndots or search domains, not CoreDNS.

The fix: either use the FQDN in the app config, or set `ndots:2` to make the search domains try earlier.

## See also

* [[Kubernetes/guides/troubleshooting/service-unreachable|service-unreachable]] — when the Service itself is the issue
* [[Kubernetes/guides/troubleshooting/crashloop-backoff|crashloop-backoff]] — when CoreDNS is the crashing thing
* [[Kubernetes/concepts/L04-services-networking/03-dns|dns]] — how k8s DNS works
* [CoreDNS docs](https://coredns.io/manual/toc/)
