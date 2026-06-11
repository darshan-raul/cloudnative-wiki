---
title: Ingress 404 / 502 / 503
tags:
  - Kubernetes
  - Troubleshooting
  - Networking
  - Ingress
---

External traffic hits your cluster, but the response is wrong: 404 (no route), 502 (bad gateway), 503 (service unavailable), or hangs. This is **Ingress** or **Ingress controller** trouble — the path from outside the cluster to a pod is broken.

## Symptoms

```bash
# from outside
$ curl -v https://app.example.com
< HTTP/2 404
# or
< HTTP/2 502
# or
< HTTP/2 503
# or
curl: (28) Failed to connect to app.example.com port 443: Connection timed out
```

```bash
# from inside the cluster
$ kubectl exec -it client -- curl -sS -i http://web-service
HTTP/1.1 200 OK
# the Service works, but Ingress doesn't reach it
```

## The 4-step diagnosis

```bash
# 1. is the Ingress resource valid?
kubectl get ingress
kubectl describe ingress my-app

# 2. is the Ingress controller running?
kubectl get pods -n ingress-nginx   # or whatever namespace
kubectl get svc -n ingress-nginx

# 3. is the Ingress controller's Service / NodePort / LB reachable from outside?
kubectl get svc -n ingress-nginx ingress-nginx-controller

# 4. can the Ingress controller reach the backend Service?
kubectl logs -n ingress-nginx ingress-nginx-controller-xxx --tail=100
```

## The taxonomy of Ingress failures

```
┌──────────────────────────────────────────────────────────────┐
│                Ingress Failures                              │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. 404 — Ingress not matching the request                   │
│  2. 502 — Backend Service has no endpoints                   │
│  3. 502 — Backend pod not listening on the right port        │
│  4. 503 — Backend pod overwhelmed                            │
│  5. 502 — TLS handshake fails (cert wrong / SNI mismatch)    │
│  6. Connection refused — Ingress controller not running      │
│  7. Connection timeout — DNS or routing issue                │
│  8. Cert errors — Let's Encrypt / cert-manager issue         │
│  9. Wrong host — Ingress has wrong hostname                  │
│ 10. Path prefix issue — rewrite rules not working            │
│ 11. Backend Service port mismatch                            │
│ 12. IngressClass missing                                     │
│ 13. Health checks failing (NLB/ALB)                          │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## 1. 404 — Ingress not matching

The Ingress exists, the controller is running, but your request doesn't match any rule.

**Signatures:**

```bash
$ curl -i https://app.example.com/
HTTP/2 404
server: nginx/1.25.3
# the controller received the request, but didn't find a matching rule
```

```bash
# controller logs
$ kubectl logs -n ingress-nginx ingress-nginx-controller-xxx | grep 404
10.0.0.5 - - [15/Jan/2024:10:00:00 +0000] "GET / HTTP/1.1" 404 ...
```

**Diagnosis:**

```bash
# 1. what does the Ingress expect?
kubectl get ingress my-app -o yaml
# apiVersion: networking.k8s.io/v1
# kind: Ingress
# spec:
#   rules:
#   - host: api.example.com   <-- only matches this host
#     http:
#       paths:
#       - path: /v1            <-- only matches this path
#         pathType: Prefix
#         backend:
#           service:
#             name: api-service
#             port:
#               number: 80
```

Common mismatches:
- You sent to `app.example.com` but the Ingress expects `api.example.com`
- You sent `GET /v2/users` but the Ingress only has `/v1`
- TLS-SNI mismatch: the cert is for `app.example.com` but you sent a request for `api.example.com`

**Fix:** add the rule to the Ingress, or fix the request.

## 2. 502 — Backend Service has no endpoints

The Ingress matched the rule, but the backend Service has no pods.

**Signatures:**

```bash
$ curl -i https://app.example.com/
HTTP/2 502
server: nginx/1.25.3
```

```bash
$ kubectl get endpoints api-service
NAME           ENDPOINTS
api-service                       <-- empty
```

The Ingress controller is trying to forward to the Service, but the Service has no Pod IPs to send to.

**Diagnosis:**

```bash
# 1. service endpoints
kubectl get endpoints api-service

# 2. pods that match the service selector
kubectl get pods -l app=api

# 3. pod readiness
kubectl get pods -l app=api -o wide
```

**Fix:** see [[Kubernetes/guides/troubleshooting/service-unreachable|service-unreachable]] for the full diagnosis. Common cause: pods not Ready (readiness probe failing), or selector mismatch.

## 3. 502 — Backend pod not listening on the right port

The Ingress is forwarding to a port the pod doesn't listen on.

**Signatures:**

```bash
$ curl -i https://app.example.com/
HTTP/2 502
```

```bash
$ kubectl logs -n ingress-nginx ingress-nginx-controller-xxx | tail
[error] 32#32: *567 connect() failed (111: Connection refused) while connecting to upstream
upstream: "http://10.244.1.5:9090"
```

The controller is trying to connect to `10.244.1.5:9090`, getting "Connection refused" because the pod listens on a different port.

**Diagnosis:**

```bash
# 1. what port is the Ingress forwarding to?
kubectl get ingress my-app -o jsonpath='{.spec.rules[*].http.paths[*].backend.service.port.number}'
# 9090

# 2. what port is the pod actually listening on?
kubectl exec -it api-1 -- ss -tlnp
# LISTEN  *:8080  *  ...
```

**Fix:** correct the `service.port` in the Ingress or the `targetPort` in the Service.

## 4. 503 — Backend pod overwhelmed

The Ingress reaches the pod, but the pod is overloaded (CPU throttling, GC pause, slow response).

**Signatures:**

```bash
$ curl -i https://app.example.com/
HTTP/2 503
```

```bash
# in controller logs
upstream timed out (110: Connection timed out) while reading response header from upstream
upstream: "http://10.244.1.5:8080"
```

**Diagnosis:**

```bash
# 1. CPU throttling
kubectl top pods -l app=api
# api-1   1000m   512Mi   <-- maxed out

# 2. response time
# (in your APM / Prometheus)
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))

# 3. backend logs
kubectl logs -l app=api --tail=100 | grep "timeout\|slow\|hang"
```

**Common sub-causes:**

1. **CPU limit too low.** Pod is being throttled.
   ```bash
   # in metrics
   rate(container_cpu_cfs_throttled_seconds_total[5m])
   ```
   Fix: increase CPU limit, or remove it.

2. **Too few replicas.** All traffic to one pod.
   ```bash
   $ kubectl get pods -l app=api
   NAME     READY   STATUS    RESTARTS   AGE
   api-1    1/1     Running   0          5m
   # only one pod
   ```
   Fix: scale up.

3. **Slow downstream.** The pod itself is fine, but it depends on a slow database, microservice, etc.
   Fix: find the slow dependency.

4. **GC pause.** JVM GC can stall the app for seconds.
   ```bash
   $ kubectl logs -l app=api | grep "GC pause"
   [GC (Allocation Failure)  524288K->262144K(524288K), 5.123 secs]
   ```
   Fix: tune the JVM.

## 5. 502 — TLS handshake fails

The TLS connection fails at the controller or the backend.

**Signatures:**

```bash
$ curl -i https://app.example.com/
curl: (35) error:14094410:SSL routines:ssl3_read_bytes:sslv3 alert handshake failure
```

```bash
# in controller logs
SSL_do_handshake() failed (SSL: error:1417A0C1 ...)
```

**Common sub-causes:**

1. **Cert doesn't match the host.** SNI mismatch.
   ```bash
   $ openssl s_client -connect app.example.com:443 -servername app.example.com
   # returns cert for app.example.com
   $ openssl s_client -connect app.example.com:443 -servername api.example.com
   # returns NO cert or wrong cert
   ```
   Fix: ensure the cert covers the requested host (`subjectAltName`).

2. **Cert is self-signed and the client doesn't trust it.**
   ```bash
   curl: (60) SSL certificate problem: self signed certificate
   ```
   Fix: install a CA-signed cert (Let's Encrypt) or add the CA to the client's trust store.

3. **Backend TLS (upstream).** The Ingress forwards to a backend that requires TLS, but the Ingress isn't configured to use TLS.
   ```yaml
   # ingress
   spec:
     rules:
     - host: app.example.com
       http:
         paths:
         - path: /
           backend:
             service:
               name: web
               port:
                 number: 443
                 # ^-- this is the Service port; Ingress will try plain HTTP to it
                 # to use TLS to upstream, you need a different config
   ```
   Fix: configure the Ingress to use TLS to the backend (e.g., `nginx.ingress.kubernetes.io/backend-protocol: HTTPS`).

4. **TLS version mismatch.** The client only supports TLS 1.0, the controller only supports TLS 1.2+.
   ```bash
   curl: (35) error:1407742E:SSL routines:SSL23_GET_SERVER_HELLO:tlsv1 alert protocol version
   ```
   Fix: configure the controller to support older TLS (not recommended), or update the client.

5. **Cert is expired.**
   ```bash
   curl: (60) SSL certificate problem: certificate has expired
   ```
   Fix: renew the cert.

## 6. Connection refused — Ingress controller not running

The Ingress controller pod is dead.

**Signatures:**

```bash
$ curl https://app.example.com/
curl: (7) Failed to connect to app.example.com port 443: Connection refused
```

```bash
$ kubectl get pods -n ingress-nginx
NAME                                      READY   STATUS    RESTARTS   AGE
ingress-nginx-controller-7d8b8b7c9d-xxx  0/1     Running   1          5m
# but the Service might still work
```

If the controller is dead, the cloud load balancer (if any) will get connection refused on health checks and remove the controller from the load balancing pool.

**Diagnosis:** see [[Kubernetes/guides/troubleshooting/crashloop-backoff|crashloop-backoff]] for the controller pod.

## 7. Connection timeout — DNS or routing

External traffic can't reach the cluster at all.

**Signatures:**

```bash
$ curl https://app.example.com/
curl: (28) Failed to connect to app.example.com port 443: Connection timed out
```

**Diagnosis:**

```bash
# 1. does the DNS resolve?
dig app.example.com
# or
nslookup app.example.com

# 2. does the resolved IP respond?
curl -v --connect-timeout 5 https://<resolved-ip>/

# 3. is there a load balancer in front?
dig app.example.com
# if the IP is an AWS ALB / GCP LB, check the cloud console

# 4. is the controller's Service type correct?
kubectl get svc -n ingress-nginx
# NAME                       TYPE
# ingress-nginx-controller   LoadBalancer   <-- should be LB
# ingress-nginx-controller   NodePort       <-- need to use NodePort
```

**Common sub-causes:**

1. **DNS not pointing to the cluster.** The domain doesn't have an A record (or has a wrong one).
   Fix: update DNS to point to the LoadBalancer's CNAME or A record.

2. **Cloud LB not provisioned.** The Service is `type: LoadBalancer`, but the cloud hasn't provisioned an LB.
   ```bash
   $ kubectl get svc -n ingress-nginx
   NAME                       TYPE           EXTERNAL-IP
   ingress-nginx-controller   LoadBalancer   <pending>   <-- LB not ready
   ```
   Fix: wait, or check the cloud's LB provisioning logs.

3. **Security group / firewall blocking.** The cloud's security group doesn't allow traffic on 443/80.
   Fix: open the ports.

4. **Wrong NodePort range.** Some networks block the default NodePort range (30000-32767).
   Fix: use a Service of type LoadBalancer, or open the NodePort range.

5. **Cluster behind corporate firewall.** The cluster is on-prem, behind a NAT, and external traffic can't reach the cluster's external IPs.
   Fix: corporate network routing.

## 8. Cert errors — Let's Encrypt / cert-manager

cert-manager automates cert provisioning. When it breaks, certs aren't renewed, and Ingress serves expired or self-signed certs.

**Signatures:**

```bash
$ curl -i https://app.example.com/
curl: (60) SSL certificate problem: certificate has expired
```

```bash
$ kubectl get certificate -A
NAME          READY   SECRET                AGE
app-cert      False   app-tls               30d
# the cert is not ready
```

```bash
$ kubectl describe certificate app-cert
Events:
  Type     Reason          Age   From          Message
  ----     ------          ----  ----          -------
  Warning  IssuerNotReady  30m   cert-manager  Issuer letsencrypt-prod not ready
```

**Diagnosis:**

```bash
# 1. cert-manager running?
kubectl get pods -n cert-manager

# 2. ClusterIssuer / Issuer status
kubectl describe clusterissuer letsencrypt-prod

# 3. cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=100

# 4. Certificate challenges
kubectl get challenges -A
kubectl describe challenge -A
```

**Common sub-causes:**

1. **ACME challenge failing.** Let's Encrypt can't reach the HTTP-01 challenge endpoint.
   ```bash
   $ kubectl get challenges -A
   NAME                                      STATE     AGE
   app-cert-1234567890-12345678              pending   5m
   ```
   ```bash
   $ kubectl describe challenge app-cert-xxx
   Reason:  Waiting for HTTP-01 challenge propagation: failed to perform self check
   ```
   Fix: ensure the Ingress is reachable from the internet on port 80.

2. **DNS-01 challenge failing.** The DNS provider isn't configured correctly.
   Fix: check the `dns01` solver config, the API token.

3. **Rate limit hit.** Let's Encrypt has rate limits (5 certs per domain per week for the production issuer).
   ```bash
   $ kubectl logs -n cert-manager -l app=cert-manager | grep "rate limit"
   ```
   Fix: use the staging issuer for testing.

4. **Cert expired and cert-manager didn't renew.** Could be a renewal schedule, or a renewal that failed silently.
   ```bash
   $ kubectl get certificate -o jsonpath='{.items[*].status.renewalTime}'
   # past now
   ```
   Fix: investigate why renewal failed.

## 9. Wrong host

The Ingress has the wrong hostname.

**Signatures:**

```bash
$ curl -i https://app.example.com/
HTTP/2 404
# but the Ingress has:
# spec:
#   rules:
#   - host: api.example.com  <-- wrong host
```

**Fix:** correct the host in the Ingress spec.

## 10. Path prefix issue

The Ingress matches on path, but the request has a different path or rewrite rules don't work.

**Signatures:**

```bash
$ curl https://app.example.com/api/v1/users
# 404 from the backend
# the backend doesn't have /api/v1/users
```

```bash
# ingress with rewrite
nginx.ingress.kubernetes.io/rewrite-target: /$2
# and path: /api(/|$)(.*)
# the rewrite might be wrong
```

**Common sub-causes:**

1. **`pathType: Prefix` vs `pathType: ImplementationSpecific`.** `Prefix` matches prefix; `ImplementationSpecific` is implementation-defined (nginx: regex).
2. **Rewrite target not configured.** The Ingress doesn't rewrite, so the backend gets the original path.
3. **Backend doesn't have the path.** Your app serves `/`, not `/api/v1/users`.

**Fix:** either configure rewrite in the Ingress, or set up the backend to handle the original path.

## 11. Backend Service port mismatch

The Ingress references a Service port that doesn't exist.

**Signatures:**

```bash
$ kubectl describe ingress my-app
Backend:
  Service:
    Name:  api-service
    Port:
      Number: 9090   <-- Service has no port 9090
```

```bash
$ kubectl get svc api-service -o jsonpath='{.spec.ports}' | jq .
[{"port": 80, "targetPort": 8080, "protocol": "TCP"}]
# no 9090
```

**Fix:** match the Ingress `port` to an actual Service `port`.

## 12. IngressClass missing

The Ingress doesn't have `ingressClassName`, and the cluster has multiple controllers.

**Signatures:**

```bash
$ kubectl get ingressclass
NAME              CONTROLLER
nginx             k8s.io/ingress-nginx
traefik           traefik.io/ingress-controller
```

```bash
$ kubectl get ingress my-app -o yaml
# no ingressClassName field
```

The Ingress has no class, so no controller picks it up.

**Fix:** set `ingressClassName` in the Ingress, or set a default IngressClass.

```yaml
spec:
  ingressClassName: nginx
```

For a default:

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
spec:
  controller: k8s.io/ingress-nginx
```

## 13. Health checks failing (NLB/ALB)

When using a cloud load balancer (NLB/ALB) in front of the Ingress controller, the LB does its own health checks.

**Signatures:**

```bash
# AWS console
# Target group: all targets "unhealthy"

# the LB doesn't route traffic because all targets fail the health check
$ curl https://app.example.com/
curl: (28) Connection timed out
```

**Common sub-causes:**

1. **Health check path wrong.** The LB is checking `/healthz` but the controller serves it at `/healthz` of the controller port.
   ```bash
   # AWS NLB
   Health check path: /healthz
   # but the controller's health endpoint might be at a different path
   ```
   Fix: check the controller's docs for the health check path.

2. **Health check port wrong.** The LB is checking port 80 but the controller listens on 443 (or vice versa).
3. **Network security group blocks the LB's health check IPs.** AWS health checks come from specific CIDRs (the VPC's CIDR + a few).
4. **Controller is unhealthy.** The controller pod is failing its own readiness probe, so it can't accept traffic.
   ```bash
   $ kubectl logs -n ingress-nginx ingress-nginx-controller-xxx
   ```

## Useful debugging commands

```bash
# 1. check the Ingress resource
kubectl get ingress -A
kubectl describe ingress <name>

# 2. controller status
kubectl get pods -n ingress-nginx -o wide
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=200

# 3. service endpoints
kubectl get endpoints <service-name>

# 4. test the backend directly (bypass Ingress)
kubectl port-forward svc/<service-name> 8080:80
curl http://localhost:8080
# if THIS works, the issue is the Ingress

# 5. controller configuration
kubectl get configmap -n ingress-nginx
kubectl exec -it -n ingress-nginx ingress-nginx-controller-xxx -- cat /etc/nginx/nginx.conf | less

# 6. cloud LB status
# AWS
aws elbv2 describe-target-health --target-group-arn <arn>
# GCP
gcloud compute target-pools get-health <name>
```

## The "is it the Ingress or the backend?" test

```bash
# 1. test the backend directly
kubectl run debug --rm -it --image=curlimages/curl --restart=Never -- \
  curl -sS -i http://<pod-ip>:<port>
# if THIS works, the backend is fine

# 2. test through the Service
kubectl run debug --rm -it --image=curlimages/curl --restart=Never -- \
  curl -sS -i http://<service-name>.<namespace>.svc.cluster.local
# if THIS works, the Service is fine

# 3. test through the Ingress (from inside the cluster)
kubectl run debug --rm -it --image=curlimages/curl --restart=Never -- \
  curl -sS -i -H "Host: app.example.com" http://<ingress-controller-service>
# if THIS works, the Ingress is fine — the issue is external access
```

## The "is it the cert or the controller?" test

```bash
# 1. test with -k (ignore cert errors)
curl -k -i https://app.example.com/
# if THIS works but normal curl doesn't, it's a cert issue

# 2. test with explicit cert
curl --cacert /path/to/ca.pem -i https://app.example.com/
# if THIS works but normal curl doesn't, the cert isn't trusted by your system

# 3. test on http (if supported)
curl -i http://app.example.com/
# if THIS works but https doesn't, it's a TLS issue

# 4. check the cert the server is presenting
openssl s_client -connect app.example.com:443 -servername app.example.com < /dev/null 2>&1 | openssl x509 -text -noout
```

## Common gotchas

* **`404` is the controller's default** — it received the request but didn't match a rule. `503` is the controller's "no upstream" — it matched a rule but couldn't reach a backend.
* **`ingressClassName` is the v1 API requirement.** Old `kubernetes.io/ingress.class` annotation is deprecated. Use the spec field.
* **The Ingress controller is a separate deployment** — many think it's part of the apiserver. It's not. If it's broken, Ingress doesn't work.
* **`kubectl describe ingress` is the only place you'll see backend service mismatches.** `kubectl get` shows only the resource.
* **Cloud load balancers have their own health checks** — these can fail even if the controller is healthy. Check the cloud console.
* **The Ingress controller needs the right ServiceAccount + RBAC.** Especially for AWS LB controller, GKE ingress, etc.
* **NodePort vs LoadBalancer** — if using NodePort, the cloud doesn't know about your ports. You need to either expose via LB Service or use the NodePort + node IP directly.
* **IngressClass is the modern way** to disambiguate. With multiple controllers, set the class explicitly.
* **TLS termination is at the controller** unless you configure it. If your backend requires TLS too, you need a separate config.
* **Path matching behavior** — `pathType: Prefix` matches prefix (so `/api` matches `/api/v1/users`); `pathType: Exact` matches exact; `pathType: ImplementationSpecific` is implementation-defined.
* **Ingress doesn't watch Services directly** — it relies on the controller to do the actual routing. The Ingress resource is declarative config; the controller is the implementation.
* **The `Host` header is what the Ingress uses for virtual hosting.** A request with no `Host` header (or wrong one) doesn't match.
* **The Ingress controller is its own kind of "Service" to the cluster** — it has its own Service, its own pods, its own resources. If you're running nginx-ingress, the controller is `ingress-nginx-controller`. If you're running Traefik, it's `traefik`.

## A worked example

```bash
$ curl -i https://app.example.com/
HTTP/2 502
server: nginx/1.25.3
```

502 from the controller. Let me check the controller logs:

```bash
$ kubectl logs -n ingress-nginx ingress-nginx-controller-xxx --tail=20
... upstream: "http://10.244.1.5:8080"
... [error] 32#32: *567 connect() failed (111: Connection refused) ...
```

The controller is trying to reach `10.244.1.5:8080` (a pod IP) and getting connection refused.

```bash
$ kubectl get pods -o wide | grep 10.244.1.5
# nothing — that IP doesn't exist anymore
```

The endpoints are stale. Check the Service:

```bash
$ kubectl get endpoints web-service
NAME           ENDPOINTS
web-service    10.244.1.5:8080   <-- stale
```

But the actual pods are:

```bash
$ kubectl get pods -l app=web -o wide
NAME    READY   STATUS    RESTARTS   AGE     IP
web-1   1/1     Running   0          30s     10.244.2.10   <-- new IP
web-2   1/1     Running   0          30s     10.244.2.11
```

A new pod got scheduled with a new IP, but the endpoints weren't updated. That's weird — usually the endpoints controller keeps them in sync.

```bash
$ kubectl get pods -n kube-system -l k8s-app=kube-proxy
NAME             READY   STATUS    RESTARTS   AGE
kube-proxy-1     1/1     Running   0          1h
kube-proxy-2     0/1     CrashLoopBackOff   5   1h
kube-proxy-3     1/1     Running   0          1h
```

kube-proxy is failing on one node, so the iptables rules there are stale. The Ingress controller is on the affected node, and it's using stale rules.

**Fix:**

1. Fix kube-proxy (see [[Kubernetes/guides/troubleshooting/crashloop-backoff|crashloop-backoff]])
2. Or restart the Ingress controller so it re-reads the endpoints:
   ```bash
   kubectl rollout restart deploy/ingress-nginx-controller -n ingress-nginx
   ```

## See also

* [[Kubernetes/guides/troubleshooting/service-unreachable|service-unreachable]] — when the Service is the issue
* [[Kubernetes/guides/troubleshooting/dns-resolution|dns-resolution]] — when DNS is the issue
* [[Kubernetes/guides/tools/kubectl|kubectl]] — the commands you need
* [[Kubernetes/concepts/L04-services-networking/04-ingress|ingress]] — how Ingress works
* [[Kubernetes/guides/networking/envoy-gateway|envoy-gateway]] — Gateway API alternative
