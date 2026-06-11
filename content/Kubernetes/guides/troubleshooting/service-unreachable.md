---
title: Service Unreachable
tags:
  - Kubernetes
  - Troubleshooting
  - Networking
  - Services
---

The most common k8s networking problem: a Service exists, pods are running, but traffic to the Service doesn't reach a pod. This is a **routing** problem, not a code problem.

## Symptoms

```bash
# from inside a pod
$ curl http://web-service:8080
curl: (6) Could not resolve host: web-service
# DNS problem

$ curl http://web-service:8080
curl: (7) Failed to connect to web-service port 8080: Connection refused
# Service exists, but no backend listening

$ curl http://web-service:8080
curl: (52) Empty reply from server
# reached a pod, but the pod isn't handling it

$ curl --connect-timeout 5 http://web-service:8080
curl: (28) Connection timed out
# Service ClusterIP, but no route / no pod
```

```bash
# from outside
$ curl https://api.example.com
504 Gateway Timeout
# Ingress controller can't reach the backend
```

## The 7-step diagnosis

This is the most efficient way to isolate a "Service not working" problem:

```bash
# 1. does the Service exist?
kubectl get svc web-service

# 2. does it have endpoints?
kubectl get endpoints web-service
# if "ENDPOINTS" is empty, that's your problem

# 3. are the pods Ready?
kubectl get pods -l app=web

# 4. can a pod reach the Service ClusterIP?
kubectl exec -it debug -- curl -sS -m 5 http://<ClusterIP>:8080

# 5. can a pod reach a specific pod IP?
kubectl exec -it debug -- curl -sS -m 5 http://<PodIP>:8080

# 6. can a pod reach the Service from another node?
kubectl exec -it debug --node-override=node-1 -- curl -sS -m 5 http://web-service:8080

# 7. is kube-proxy running on every node?
kubectl get pods -n kube-system -l k8s-app=kube-proxy
```

## The taxonomy of "Service unreachable"

```
┌──────────────────────────────────────────────────────────────┐
│                  Service Unreachable                         │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. No endpoints              (selector doesn't match pods)  │
│  2. Pod not Ready             (readiness probe failing)      │
│  3. Wrong Service port        (port mismatch)                │
│  4. Wrong target port         (targetPort doesn't exist)     │
│  5. NetworkPolicy blocks      (default-deny + no allow)      │
│  6. kube-proxy not running    (no rules programmed)          │
│  7. CNI broken                (pods can't reach each other)  │
│  8. iptables/IPVS saturation  (millions of rules, slow)      │
│  9. Service type confusion    (ClusterIP vs NodePort etc)    │
│ 10. Cross-node routing broken (CNI tunnel/route missing)     │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## 1. No endpoints

**The #1 cause of "Service not working."** The Service has no pod IPs to forward to.

**Signatures:**

```bash
$ kubectl get svc web-service
NAME           TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)
web-service    ClusterIP   10.96.0.42     <none>        8080/TCP

$ kubectl get endpoints web-service
NAME           ENDPOINTS
web-service    <none>     <-- the smoking gun
```

or with `EndpointSlices` (the modern equivalent):

```bash
$ kubectl get endpointslices -l kubernetes.io/service-name=web-service
# empty
```

**Diagnosis:**

```bash
# 1. what does the Service select for?
kubectl get svc web-service -o jsonpath='{.spec.selector}' | jq .
# {"app": "web"}

# 2. what do the pods have?
kubectl get pods -l app=web -o jsonpath='{.items[*].metadata.labels}'
# {"app": "my-web"}    <-- typo! Service wants "web", pod has "my-web"
```

**Common sub-causes:**

1. **Label selector typo.** `app: web` vs `app: my-web`. Most common.
2. **Service in different namespace from pods.** The Service's selector is namespace-scoped — it only looks at pods in its own namespace.
3. **Pods not ready.** If `readinessProbe` is configured and failing, pods aren't added to endpoints even if they match the selector.
   ```bash
   $ kubectl get pods -l app=web
   NAME    READY   STATUS    RESTARTS   AGE
   web-1   0/1     Running   0          5m   <-- not Ready
   web-2   0/1     Running   0          5m
   web-3   0/1     Running   0          5m
   ```
4. **No pods match the selector.** Deployment is at 0 replicas, DaemonSet doesn't run on this node type, etc.
5. **EndpointSlice controller issues.** Less common, but possible if the controller is unhealthy.

**Fix:**

```bash
# 1. fix the label mismatch
kubectl label pod web-1 app=web --overwrite

# or fix the Service to match
kubectl patch svc web-service -p '{"spec":{"selector":{"app":"my-web"}}}'

# 2. wait for the controller to reconcile (~10s)
kubectl get endpoints web-service -w
```

## 2. Pod not Ready

The pod is Running, the labels match, but `Ready` is `False` (or `1/2` for a multi-container pod).

**Signatures:**

```bash
$ kubectl get pods -l app=web
NAME    READY   STATUS    RESTARTS   AGE
web-1   0/1     Running   0          5m
web-2   1/1     Running   0          5m
web-3   0/1     Running   0          5m
```

```bash
$ kubectl describe pod web-1 | grep -A 5 "Readiness"
Readiness:  http-get http://:8080/healthz failed
```

**Diagnosis:**

```bash
# 1. why isn't the pod Ready?
kubectl describe pod web-1 | tail -20
# look for "Readiness probe failed:" events

# 2. test the readiness probe manually
kubectl exec -it web-1 -- curl -sS -m 5 http://localhost:8080/healthz
```

**Common sub-causes:**

1. **Readiness probe is failing.** App returns 500 on /healthz during startup, or the endpoint doesn't exist.
2. **Readiness probe timeout too short.** App takes 10s to respond, probe times out at 1s.
3. **PostStart hook failing.** App's PostStart hook hangs, and readiness waits.
4. **Init container hasn't finished.** Readiness on a sidecar/init pattern.

**Fix:** see [[Kubernetes/guides/troubleshooting/crashloop-backoff|crashloop-backoff]] for the general approach; the readiness probe is similar to liveness but with different consequences (failing readiness removes from endpoints; failing liveness kills the pod).

## 3. Wrong Service port

The Service's `port` doesn't match the application's listening port.

**Signatures:**

```bash
$ kubectl get svc web-service -o jsonpath='{.spec.ports}' | jq .
[{"port": 8080, "targetPort": 80, "protocol": "TCP"}]
# Service exposes 8080
```

```bash
$ kubectl exec -it web-1 -- netstat -tlnp
# application listens on 9090, not 80
```

**Diagnosis:**

```bash
# 1. what port does the app actually listen on?
kubectl exec -it web-1 -- ss -tlnp
# or
kubectl exec -it web-1 -- netstat -tlnp
# or just read the docs

# 2. what does the Service expose?
kubectl get svc web-service -o yaml
```

**Fix:**

```bash
# patch the Service
kubectl patch svc web-service -p '{"spec":{"ports":[{"port":9090,"targetPort":9090,"protocol":"TCP"}]}}'
```

**Common gotcha:** the Service has a `port` (ClusterIP port) and a `targetPort` (pod port). They don't have to match. If you say `port: 80, targetPort: 8080`, the ClusterIP listens on 80 and forwards to pod port 8080.

```yaml
apiVersion: v1
kind: Service
spec:
  ports:
  - port: 80          # ClusterIP listens on this
    targetPort: 8080  # pod listens on this
    protocol: TCP
```

## 4. Wrong target port

`targetPort` references a port that doesn't exist on the pod.

**Signatures:**

```bash
$ kubectl describe svc web-service
Name:              web-service
...
Port:              http  8080/TCP
TargetPort:        http  9090/TCP  <-- pod doesn't listen on 9090
Endpoints:         10.244.1.5:9090
```

```bash
$ curl -v http://web-service:8080
*   Trying 10.96.0.42:8080...
* Connected to web-service (10.96.0.42) port 8080
* ALPN: offers h2,http/1.1
* (read error: Connection reset by peer)
```

The ClusterIP works, the targetPort is wrong, the iptables rule is sending traffic to a closed port, and the connection resets.

**Diagnosis:**

```bash
# 1. what does the pod actually listen on?
kubectl exec -it web-1 -- ss -tlnp
# LISTEN  0  4096  *:8080  *  users:(("nginx",pid=1,fd=6))
# nginx is on 8080, not 9090

# 2. what does the Service send to?
kubectl get svc web-service -o jsonpath='{.spec.ports[*].targetPort}'
# 9090
```

**Fix:** set `targetPort` to a value (or named port) the pod actually listens on.

`targetPort` can be a **name** that matches a named port in the pod's container spec:

```yaml
# pod
ports:
- name: http
  containerPort: 8080

# service
ports:
- name: http
  port: 80
  targetPort: http   # matches the named port "http"
```

This is the safer pattern — no risk of typo.

## 5. NetworkPolicy blocks

A default-deny NetworkPolicy is in effect, and there's no allow rule for the source/destination combination.

**Signatures:**

```bash
# 1. check NetworkPolicy
kubectl get netpol -A
# a "deny-all" policy in the namespace

# 2. attempt to reach — hangs or times out
$ kubectl exec -it client -- curl --connect-timeout 5 http://web-service:8080
curl: (28) Connection timed out
```

**Diagnosis:**

```bash
# 1. what NetworkPolicies apply?
kubectl get netpol -n my-ns -o yaml

# 2. test without NetworkPolicy (use a debug pod in a different namespace)
kubectl run debug -n debug --rm -it --image=busybox --restart=Never -- \
  wget -qO- --timeout=5 http://web-service.my-ns:8080
# if this works, the issue is NetworkPolicy in the source namespace
```

**Common sub-causes:**

1. **Default-deny + missing allow.** A baseline `policyTypes: [Ingress,Egress]` with no rules.
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: default-deny
   spec:
     podSelector: {}     # applies to all pods in namespace
     policyTypes: [Ingress, Egress]
     # no ingress or egress = no traffic allowed
   ```
   Fix: add ingress allow rules.

2. **Wrong podSelector.** Allow rule selects `app: api`, but your source is `app: client`.
3. **Wrong namespaceSelector.** Allow rule has `namespaceSelector: {}` (all namespaces), but the source is in `kube-system` or a different cluster.
4. **Egress blocked.** Source pod can reach the Service's ClusterIP, but egress to it is denied.
5. **CNI doesn't enforce NetworkPolicy.** Flannel, basic Calico, etc. don't enforce. **Always use Calico, Cilium, or another CNI that enforces it.**

**Fix:**

```yaml
# allow ingress from anywhere in the same namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-internal
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector: {}     # any pod in this namespace
```

## 6. kube-proxy not running

kube-proxy on the node isn't running, so no iptables/IPVS rules are programmed for any Service.

**Signatures:**

```bash
$ kubectl get pods -n kube-system -l k8s-app=kube-proxy
NAME             READY   STATUS    RESTARTS   AGE
kube-proxy-1     0/1     Error     5          10m
kube-proxy-2     1/1     Running   0          5m
kube-proxy-3     1/1     Running   0          5m
```

```bash
# from a pod on node-1:
$ curl --connect-timeout 5 http://web-service:8080
curl: (28) Connection timed out
# from a pod on node-2:
$ curl http://web-service:8080
hello world
```

Same cluster, same Service, only some nodes broken — the kube-proxy node is the problem.

**Diagnosis:**

```bash
# 1. is kube-proxy running on the suspect node?
kubectl get pods -n kube-system -l k8s-app=kube-proxy --field-selector spec.nodeName=node-1

# 2. check the iptables rules on the node
ssh node-1
$ sudo iptables -t nat -L KUBE-SERVICES | grep web-service
# empty
```

**Fix:** see [[Kubernetes/guides/troubleshooting/crashloop-backoff|crashloop-backoff]] for the kube-proxy pod itself; or `systemctl restart kubelet` on the node if running as a host process.

## 7. CNI broken

The CNI plugin isn't working — pods can't reach each other at all, even on the same node.

**Signatures:**

```bash
$ kubectl exec -it pod-A -- curl --connect-timeout 5 http://pod-B-IP:8080
curl: (28) Connection timed out
```

```bash
$ kubectl exec -it pod-A -- ping -c 1 pod-B-IP
PING pod-B-IP: 56 data bytes
--- pod-B-IP ping statistics ---
1 packets transmitted, 0 received, 100% packet loss
```

```bash
$ kubectl get pods -n kube-system -l k8s-app=cilium
NAME           READY   STATUS    RESTARTS   AGE
cilium-1       0/1     CrashLoopBackOff   10  1h
cilium-2       1/1     Running   0          1h
```

**Diagnosis:**

```bash
# 1. is the CNI running on the node?
kubectl get pods -n kube-system -l k8s-app=<cni-name> -o wide
ssh node-1
$ ls /etc/cni/net.d/
$ cat /var/log/pods/.../<cni-pod>/.../log   # CNI logs
```

**Fix:** restart the CNI, or see [[Kubernetes/guides/troubleshooting/crashloop-backoff|crashloop-backoff]] for the CNI pod.

## 8. iptables / IPVS saturation

Cluster has thousands of Services. iptables rules are millions. Connection setup is slow (5-10s) or fails randomly.

**Signatures:**

```bash
# 1. number of iptables rules on a node
ssh node-1
$ sudo iptables -t nat -L KUBE-SERVICES | wc -l
# 2000000  <-- 2 million rules

# 2. connection setup time is slow
$ curl -w "%{time_connect}\n" -sS http://web-service:8080
# 8.234
```

**Fix:** switch kube-proxy to IPVS or eBPF mode.

```yaml
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "ipvs"
```

IPVS uses hash-based lookups, O(1) regardless of rule count.

## 9. Service type confusion

You wanted a NodePort but created a ClusterIP. Or vice versa.

**Signatures:**

```bash
$ kubectl get svc web-service
NAME           TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)
web-service    ClusterIP   10.96.0.42     <none>        80/TCP

# you tried:
$ curl http://node-1:30080
curl: (7) Failed to connect to node-1 port 30080: Connection refused
```

The Service is ClusterIP, not NodePort. There's no `nodePort: 30080` to listen on.

**Fix:** change the Service type:

```bash
kubectl patch svc web-service -p '{"spec":{"type":"NodePort"}}'
```

## 10. Cross-node routing broken

Pod A on node 1 can't reach pod B on node 2.

**Signatures:**

```bash
# same-node traffic works
$ kubectl exec -it pod-A -- curl http://pod-B-IP-on-node-1:8080
# works

# cross-node traffic fails
$ kubectl exec -it pod-A -- curl http://pod-C-IP-on-node-2:8080
curl: (28) Connection timed out
```

**Common sub-causes:**

1. **CNI tunnel broken.** VXLAN/Geneve/IPSEC between nodes isn't set up.
2. **AWS VPC CNI — subnets don't allow pod IPs.** When using the AWS VPC CNI, pods get IPs from the VPC. Pod traffic between nodes requires the subnets to be routable to each other.
3. **IP-in-IP encapsulation broken.** Calico in IPIP mode, etc.
4. **MTU mismatch.** Overlay has 50-100 bytes of overhead, underlying network doesn't fragment.
   ```bash
   # check MTU
   ip link show eth0
   # typical overlay: 1450
   # typical underlay: 1500
   ```
5. **NetworkPolicy blocking.** Default-deny Egress.

**Diagnosis:**

```bash
# 1. can a pod ping another pod on a different node?
kubectl exec -it pod-A -- ping -c 3 <pod-B-IP-on-different-node>

# 2. can a pod ping the node itself?
kubectl exec -it pod-A -- ping -c 3 <node-IP>

# 3. trace the path
kubectl exec -it pod-A -- traceroute <pod-B-IP-on-different-node>
```

## The "is it the Service or the app?" test

```bash
# 1. port-forward the pod directly (bypasses the Service)
kubectl port-forward pod/web-1 8080:8080
# from your machine: curl http://localhost:8080

# 2. if port-forward works, the app is fine — Service is the issue
# 3. if port-forward doesn't work, the app is the issue
```

## The "is it the Service or DNS?" test

```bash
# resolve the Service name to a ClusterIP
kubectl exec -it client -- nslookup web-service
# Server:    10.96.0.10
# Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local
# Name:      web-service
# Address 1: 10.96.0.42   <-- ClusterIP

# 1. can you reach the ClusterIP?
kubectl exec -it client -- curl -sS -m 5 http://10.96.0.42:8080
# works → DNS + Service both fine
# fails → Service is the issue

# 2. can you reach a pod IP directly?
kubectl exec -it client -- curl -sS -m 5 http://10.244.1.5:8080
# works → ClusterIP routing is the issue (kube-proxy, iptables, etc.)
# fails → app or pod networking is the issue
```

## Common gotchas

* **`kubectl get endpoints` shows the right pods, but traffic still fails** — check `kubectl get endpointslices`. EndpointSlices are the modern equivalent and can sometimes be out of sync.
* **Headless Services** (`clusterIP: None`) don't get a ClusterIP. They return pod IPs from DNS. Make sure you're using the right name pattern.
  ```bash
  $ kubectl exec -it client -- nslookup web-service
  Name:      web-service
  Address 1: 10.244.1.5     <-- direct pod IP (headless)
  Address 2: 10.244.2.6
  Address 3: 10.244.3.7
  ```
* **Cross-namespace Service** — Service is in `ns-a`, you call it from `ns-b`. Use `<service>.<namespace>.svc.cluster.local`.
* **The Service has endpoints, traffic flows, but the response is wrong** — that's an app bug, not a Service bug. Check the backend pod's logs.
* **The Service was created, traffic works, then it stops** — check the endpoints. The pod was killed (OOM, evicted, scaled down) and the readiness probe removed it.
* **Service created with a typo in the namespace** — `kubectl apply -f service.yaml` in a different namespace than expected.
* **Service is on the right port, but iptables rules are wrong** — restart kube-proxy on the affected node.
* **The Service exists in code, but not in the cluster** — Helm chart, kustomize, or CI didn't apply it. Check `kubectl get svc -A | grep web`.
* **Egress SNAT port exhaustion** — every outbound connection from a pod uses a SNAT port. AWS has a limit (~64K ports per node). If you have many short-lived outbound connections, you can run out.
* **Service-to-Service traffic is faster than Pod-to-Pod** — that's expected. The Service is iptables-natted locally; the pod IP goes through routing.
* **The Service's `sessionAffinity: ClientIP`** — all requests from a single client go to the same backend. If that backend is unhealthy, all requests fail. Check if you need to disable it.

## A worked example

```bash
$ kubectl get pods
NAME    READY   STATUS    RESTARTS   AGE
web-1   1/1     Running   0          10m
web-2   1/1     Running   0          10m

$ kubectl get svc web-service
NAME           TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)
web-service    ClusterIP   10.96.0.42     <none>        80/TCP

$ kubectl get endpoints web-service
NAME           ENDPOINTS
web-service    10.244.1.5:80,10.244.2.6:80    <-- endpoints exist

$ kubectl exec -it client -- curl http://web-service
curl: (7) Failed to connect to web-service port 80: Connection refused
```

Endpoints are there, but connection is refused. Investigate:

```bash
$ kubectl exec -it client -- curl -v http://10.96.0.42:80
*   Trying 10.96.0.42:80...
* Connected to 10.96.0.42 (10.96.0.42) port 80
* ALPN: offers h2,http/1.1
* (read error: Connection reset by peer)

$ kubectl describe svc web-service -o jsonpath='{.spec.ports}' | jq .
[{"port": 80, "targetPort": 80, "protocol": "TCP"}]
# looks right

$ kubectl get pod web-1 -o jsonpath='{.spec.containers[0].ports}' | jq .
[{"containerPort": 8080, "protocol": "TCP"}]   <-- pod listens on 8080

# Aha — Service targetPort: 80, pod listens on 8080
```

Fix:

```bash
kubectl patch svc web-service -p '{"spec":{"ports":[{"port":80,"targetPort":8080,"protocol":"TCP"}]}}'
```

## See also

* [[Kubernetes/guides/troubleshooting/dns-resolution|dns-resolution]] — when the name itself doesn't resolve
* [[Kubernetes/guides/troubleshooting/crashloop-backoff|crashloop-backoff]] — when the pod itself is broken
* [[Kubernetes/guides/troubleshooting/ingress-404|ingress-404]] — when external traffic is the problem
* [[Kubernetes/concepts/L04-services-networking/02-services|services]] — how Services work
* [[Kubernetes/concepts/L04-services-networking/05-network-policy|network-policy]] — when NetworkPolicy is the cause
