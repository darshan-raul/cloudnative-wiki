---
title: "Lab CKAD-13 — Quotas, LimitRanges & Probes"
tags: [kubernetes, labs, ckad, resourcequota, limitrange, probes, startup-probe]
date: 2026-10-13
description: Constrain a namespace with a ResourceQuota and a LimitRange, read the rejections they cause, and design startup, readiness and liveness probes for a slow-starting application.
---

# Lab CKAD-13 — Quotas, LimitRanges & Probes

Two CKAD objectives are easy to read about and easy to get wrong in practice: "understand requests, limits and quotas" and "implement probes and health checks". This lab has two independent parts. In the first, a namespace quota rejects workloads until they declare resources. In the second, a liveness probe kills an application that is only slow, and you fix it with the right probe for the job.

Concepts: [[Kubernetes/concepts/L05-config-storage/08-resource-quota|Resource Quotas]], [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits|Resource Requests and Limits]] and [[Kubernetes/concepts/L03-workloads/10-probes|Probes]].

Tested 2026-10-13 on kind v0.33.0 with Kubernetes v1.37.0.

---

## 1. Prerequisites & Starting State

- Working `k8s-lab` cluster from **[[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]]**. No other lab is required.

```bash
kubectl create namespace quota-lab
kubectl config set-context --current --namespace=quota-lab
```

---

## 2. ResourceQuota: A Budget for the Namespace

```bash
kubectl create quota team \
  --hard=pods=4,requests.cpu=500m,requests.memory=512Mi,limits.memory=1Gi,configmaps=5
kubectl describe quota team
```

```
Resource         Used  Hard
--------         ----  ----
configmaps       1     5
limits.memory    0     1Gi
pods             0     4
requests.cpu     0     500m
requests.memory  0     512Mi
```

A quota counts two kinds of thing: **objects** (`pods`, `configmaps`, `services`, `persistentvolumeclaims`) and **compute totals** (`requests.cpu`, `limits.memory`, and so on). `configmaps` already shows `1` because every namespace has `kube-root-ca.crt`.

### Controlled failure 1: the quota demands that Pods declare resources

```bash
kubectl run nolimits --image=busybox:1.36 -- sleep 3600
```

```
Error from server (Forbidden): pods "nolimits" is forbidden: failed quota: team: must specify limits.memory for: nolimits; requests.cpu for: nolimits; requests.memory for: nolimits
```

Once a quota covers a compute resource, every new Pod must state a value for it, or the quota could not be counted. The message lists exactly the three fields the quota tracks.

A Deployment fails differently:

```bash
kubectl create deployment web --image=ghcr.io/stefanprodan/podinfo:6.7.1 --replicas=2
kubectl get deployment web
kubectl describe replicaset -l app=web | grep FailedCreate | tail -n 1
```

```
deployment.apps/web created

NAME   READY   UP-TO-DATE   AVAILABLE   AGE
web    0/2     0            0           4s

Warning  FailedCreate  4s  replicaset-controller  Error creating: pods "web-9647fbd87-gbffv" is forbidden: failed quota: team: must specify limits.memory for: podinfo; requests.cpu for: podinfo; requests.memory for: podinfo
```

The Deployment is **created without any error**, and there are no Pods to describe. The rejection happens when the ReplicaSet tries to create a Pod, so the only evidence is in the ReplicaSet's events (or `kubectl get events`). A Deployment at `0/2` with no Pods is the signature of an admission rejection.

---

## 3. LimitRange: Defaults and Bounds per Container

You could add resources to every manifest. A LimitRange does it for the whole namespace, and also sets the smallest and largest value a container may ask for:

```bash
cat << 'EOF' > limits.yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: defaults
spec:
  limits:
    - type: Container
      defaultRequest:
        cpu: 100m
        memory: 64Mi
      default:
        memory: 128Mi
      max:
        memory: 256Mi
      min:
        cpu: 50m
EOF

kubectl apply -f limits.yaml
kubectl describe limitrange defaults
```

```
Type        Resource  Min  Max    Default Request  Default Limit  Max Limit/Request Ratio
----        --------  ---  ---    ---------------  -------------  -----------------------
Container   memory    -    256Mi  64Mi             128Mi          -
Container   cpu       50m  -      100m             -              -
```

`defaultRequest` fills in a missing request and `default` fills in a missing **limit**. The names are easy to swap.

A LimitRange applies when a Pod is created, so restart the rollout and look at what the Pods were given:

```bash
kubectl rollout restart deployment/web
kubectl rollout status deployment/web --timeout=90s

kubectl get pods -l app=web -o jsonpath='{range .items[*]}{.metadata.name} {.spec.containers[0].resources}{"\n"}{end}'
kubectl describe quota team | tail -n 6
```

```
web-77f99bdb9c-845vv {"limits":{"memory":"128Mi"},"requests":{"cpu":"100m","memory":"64Mi"}}
web-77f99bdb9c-c6xfk {"limits":{"memory":"128Mi"},"requests":{"cpu":"100m","memory":"64Mi"}}

Resource         Used   Hard
--------         ----   ----
configmaps       1      5
limits.memory    256Mi  1Gi
pods             2      4
requests.cpu     200m   500m
requests.memory  128Mi  512Mi
```

The manifest still has no `resources`. The values were injected at admission, and the quota's `Used` column adds them up.

### Controlled failure 2: the budget runs out

```bash
kubectl scale deployment web --replicas=6
kubectl get deployment web
kubectl describe replicaset -l app=web | grep FailedCreate | tail -n 1
```

```
NAME   READY   UP-TO-DATE   AVAILABLE   AGE
web    4/6     4            4           13s

Warning  FailedCreate  4s (x16 over 6s)  replicaset-controller  (combined from similar events): Error creating: pods "web-77f99bdb9c-mwmw5" is forbidden: exceeded quota: team, requested: pods=1, used: pods=4, limited: pods=4
```

`exceeded quota` names the resource and gives the arithmetic: requested, used, limited. Here the `pods` count ran out first. The four running Pods are untouched; a quota never removes anything. Either lower the replica count or raise the quota with `kubectl edit quota team`.

### Controlled failure 3: outside the LimitRange's bounds

```bash
kubectl run big --image=busybox:1.36 --restart=Never --overrides='{
  "spec": {"containers": [{"name": "big", "image": "busybox:1.36", "command": ["sleep", "60"],
    "resources": {"limits": {"memory": "512Mi"}}}]}}'

kubectl run tiny --image=busybox:1.36 --restart=Never --overrides='{
  "spec": {"containers": [{"name": "tiny", "image": "busybox:1.36", "command": ["sleep", "60"],
    "resources": {"requests": {"cpu": "10m"}}}]}}'
```

```
Error from server (Forbidden): pods "big" is forbidden: maximum memory usage per Container is 256Mi, but limit is 512Mi
Error from server (Forbidden): pods "tiny" is forbidden: minimum cpu usage per Container is 50m, but request is 10m
```

Three rejections, three different causes. Read the first words of the message:

| Message starts with                            | Cause                                              | Fix                                       |
| :--------------------------------------------- | :------------------------------------------------- | :---------------------------------------- |
| `failed quota: ... must specify`               | A quota tracks a resource the Pod does not declare | Add the request or limit, or a LimitRange |
| `exceeded quota: ... requested, used, limited` | The namespace total would go over                  | Use less, or raise the quota              |
| `maximum ... per Container` / `minimum ...`    | One container is outside the LimitRange            | Change that container's value             |

```bash
kubectl delete deployment web
kubectl delete quota team
kubectl delete limitrange defaults
```

---

## 4. Probes for a Slow-Starting Application

| Probe         | Question it answers                    | When it fails                                                   |
| :------------ | :------------------------------------- | :-------------------------------------------------------------- |
| **Startup**   | Has the application finished starting? | The container is restarted. Other probes wait until it succeeds |
| **Readiness** | Can it serve traffic right now?        | The Pod is removed from Service endpoints. **No restart**       |
| **Liveness**  | Is it stuck beyond recovery?           | The container is restarted                                      |

The application below takes 25 seconds to load before it listens. It has only a liveness probe, written by someone who assumed a fast start:

```bash
cat << 'EOF' > slow.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: slow
spec:
  replicas: 1
  selector:
    matchLabels:
      app: slow
  template:
    metadata:
      labels:
        app: slow
    spec:
      containers:
        - name: app
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              echo "loading data for 25 seconds"; sleep 25
              mkdir -p /www && echo ok > /www/healthz
              echo "listening"; exec httpd -f -p 8080 -h /www
          ports:
            - name: http
              containerPort: 8080
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
            periodSeconds: 5
            failureThreshold: 2
EOF

kubectl apply -f slow.yaml
sleep 50
kubectl get pods -l app=slow
kubectl describe pod -l app=slow | grep -A 9 "Events:"
```

```
NAME                    READY   STATUS    RESTARTS      AGE
slow-6bcc44cd64-mk7dk   1/1     Running   1 (10s ago)   50s

  Normal   Scheduled  50s                default-scheduler  Successfully assigned quota-lab/slow-6bcc44cd64-mk7dk to k8s-lab-worker
  Normal   Killing    40s                kubelet            spec.containers{app}: Container app failed liveness probe, will be restarted
  Normal   Started    10s (x2 over 50s)  kubelet            spec.containers{app}: Container started
  Warning  Unhealthy  5s (x3 over 45s)   kubelet            spec.containers{app}: Liveness probe failed: Get "http://10.244.2.45:8080/healthz": dial tcp 10.244.2.45:8080: connect: connection refused
```

### Diagnose it

- The liveness probe allows 2 failures 5 seconds apart, so the kubelet gives up after about 10 seconds. The application needs 25. It is killed every time before it finishes starting, and will never come up.
- `connection refused` in the probe message means nothing is listening yet. A timeout or an HTTP 500 would point at a different problem.
- The exit code of the killed container is `137` with reason `Error`, not `OOMKilled`: the kubelet sent SIGKILL after the grace period.
- **`READY` says `1/1` although nothing is listening.** With no readiness probe, a container counts as ready the moment it starts, so a Service would send traffic to it for those 25 seconds.

### Fix it with the right probes

Raising the liveness thresholds would work, and would also make the kubelet slow to notice a real hang later. A **startup probe** separates the two concerns: it allows a long start once, then hands over to a strict liveness probe.

```bash
kubectl patch deployment slow --type json -p '[
  {"op": "add", "path": "/spec/template/spec/containers/0/startupProbe",
   "value": {"httpGet": {"path": "/healthz", "port": "http"}, "periodSeconds": 5, "failureThreshold": 12}},
  {"op": "add", "path": "/spec/template/spec/containers/0/readinessProbe",
   "value": {"httpGet": {"path": "/healthz", "port": "http"}, "periodSeconds": 5}}
]'

sleep 15
kubectl get pods -l app=slow
kubectl rollout status deployment/slow --timeout=90s
kubectl get pods -l app=slow
kubectl describe pod -l app=slow | grep -E "Startup|Liveness|Readiness"
```

```
NAME                    READY   STATUS    RESTARTS      AGE
slow-6bcc44cd64-mk7dk   1/1     Running   1 (25s ago)   65s
slow-898754f48-hs9d2    0/1     Running   0             15s

deployment "slow" successfully rolled out

NAME                   READY   STATUS    RESTARTS   AGE
slow-898754f48-hs9d2   1/1     Running   0          31s

    Liveness:     http-get http://:http/healthz delay=0s timeout=1s period=5s #success=1 #failure=2
    Readiness:    http-get http://:http/healthz delay=0s timeout=1s period=5s #success=1 #failure=3
    Startup:      http-get http://:http/healthz delay=0s timeout=1s period=5s #success=1 #failure=12
```

- The startup probe allows `12 × 5 = 60` seconds. Size it from the slowest start you expect, with a margin.
- At 15 seconds the new Pod is `0/1 Running` with **no restarts**: it is starting, and the readiness probe keeps it out of service. The rollout waited for it, so the old Pod kept serving until the new one was really ready.
- The liveness probe is unchanged and still reacts within 10 seconds once the application is up.

Probe handlers are `httpGet`, `tcpSocket`, `exec` and `grpc`. Timing fields are `initialDelaySeconds`, `periodSeconds`, `timeoutSeconds`, `failureThreshold` and `successThreshold`. `kubectl explain pod.spec.containers.livenessProbe` lists them all.

---

## 5. Cleanup

```bash
kubectl config set-context --current --namespace=default
kubectl delete namespace quota-lab
rm -f limits.yaml slow.yaml
```

---

## Practice Without the Answer

Suggested time: 12 minutes. Namespace `tenant`.

1. Limit the namespace to 3 Pods, a total CPU request of 1 core and a total memory limit of 1Gi.
2. Make a container that states nothing get a `100m` CPU request, a `64Mi` memory request and a `128Mi` memory limit, and refuse any container with a memory limit above `512Mi`.
3. Create a Deployment `api` (image `ghcr.io/stefanprodan/podinfo:6.7.1`, 2 replicas) with no `resources` in its manifest, a readiness probe on `GET /readyz` port `9898`, and a liveness probe on `GET /healthz` that tolerates 3 failures 10 seconds apart.
4. Make one `api` Pod unready without restarting it, and confirm it left the endpoints. (`podinfo` accepts `POST /readyz/disable`.)

Check yourself:

```bash
kubectl -n tenant describe quota                       # pods 2/3, requests.cpu 200m/1, limits.memory 256Mi/1Gi
kubectl -n tenant get pods -o jsonpath='{.items[0].spec.containers[0].resources}{"\n"}'
kubectl -n tenant get deployment api -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.failureThreshold} {.spec.template.spec.containers[0].livenessProbe.periodSeconds}{"\n"}'   # 3 10
kubectl -n tenant get pods                             # after step 4: one 0/1 Running, RESTARTS 0
```

Reset with `kubectl delete namespace tenant`.

---

## Further reading

- [Resource quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [Limit ranges](https://kubernetes.io/docs/concepts/policy/limit-range/)
- [Configure liveness, readiness and startup probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

## Next Lab

This is the last CKAD lab. Return to the [[Kubernetes/certifications/ckad|CKAD Track]], or test yourself with the [[Kubernetes/certifications/ckad-mock-exam|CKAD practice set]].
