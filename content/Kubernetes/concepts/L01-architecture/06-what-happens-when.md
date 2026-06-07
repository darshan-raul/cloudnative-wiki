# What Happens When You `kubectl apply`

*"https://kubernetes.io/docs/reference/using-api/api-concepts/"*

A trace of what happens between you pressing Enter on `kubectl apply -f deployment.yaml` and the Pod actually running, with traffic. This is the L01 capstone — it ties together everything in the architecture level.

## The cast of characters

A reminder of who's in the cluster:

* **kubectl** — your client. Talks to the apiserver over HTTPS.
* **kube-apiserver** — the front door. Validates, authenticates, authorizes, admits, persists.
* **etcd** — the source of truth. Stores every object.
* **kube-scheduler** — decides which node a Pod runs on.
* **kube-controller-manager** — runs the core control loops (Deployment, ReplicaSet, Node, etc.).
* **cloud-controller-manager** — cloud-specific integrations (LB, Routes, Nodes).
* **kubelet** — the per-node agent. Starts containers.
* **kube-proxy** — the per-node networker. Programs iptables/IPVS for Services.
* **CNI plugin** — per-node, gives Pods IPs and L3 connectivity.
* **container runtime** (containerd / CRI-O) — actually runs the containers.

## The trace

```bash
kubectl apply -f deployment.yaml
```

**`deployment.yaml` contains:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 80
```

### 1. kubectl builds the request

kubectl parses the YAML, looks at `kind: Deployment` and `apiVersion: apps/v1`, and constructs a **POST to the apiserver's `/apis/apps/v1/namespaces/default/deployments` endpoint** (or PUT, if updating).

The request includes:

* The **object spec** (your YAML)
* **kubectl's credentials** (from your kubeconfig — usually a client cert, bearer token, or OIDC token)
* **The kubectl version** in the User-Agent
* Optional: **server-side apply** flags, **dry-run** flags, **field-manager** identity

The payload is sent over **HTTPS** to the apiserver (default port 6443).

### 2. The apiserver authenticates

The apiserver runs a chain of **authenticators** in order:

1. **X.509 client certs** — the kubeconfig's `client-certificate` / `client-key`
2. **Bearer tokens** — for ServiceAccount tokens, OIDC tokens
3. **Bootstrap tokens** — for `kubeadm join`
4. **Webhook token authentication** — for external auth (OIDC providers like Okta, Google, etc.)
5. **Anonymous auth** — if nothing matched and `anonymous-auth=true`

If authentication fails: `401 Unauthorized`. kubectl shows the error.

The result of authentication is a **User** object attached to the request context:

```
system:user:alice            (from a client cert)
system:serviceaccount:...    (from a ServiceAccount token)
```

### 3. The apiserver authorizes

**RBAC** (the most common mode) checks: "does this user have permission to create Deployments in the `default` namespace?"

```bash
# you can check yourself
kubectl auth can-i create deployments --namespace=default --as=alice
```

If unauthorized: `403 Forbidden`. The request never reaches etcd.

### 4. Mutating admission

The apiserver runs all **mutating admission controllers / webhooks** in order. These can change the request before it's stored.

Built-in mutating admission:

* `DefaultStorageClass` — adds a default StorageClass to PVCs
* `DefaultTolerationSeconds` — adds tolerations for not-ready / unreachable nodes
* `LimitRanger` — applies LimitRange defaults
* `ServiceAccount` — auto-mounts the default ServiceAccount token
* `MutatingAdmissionWebhook` — calls out to your configured webhooks

Custom webhooks might:

* **Istio's sidecar injector** — adds the envoy sidecar to Pods (this is what you see in the trace below)
* **cert-manager's mutating webhook** — adds a `cert-manager.io/inject-ca-from` annotation
* **OPA / Kyverno** — adds labels, sidecars, defaults

If a webhook is slow or unavailable, the request hangs. Some webhooks are configured with `failurePolicy: Ignore` so they fail-open, but most default to `Fail`.

### 5. Object schema validation

The apiserver validates the request against the **OpenAPI schema** for the object type. A `replicas: -1` would be rejected here, before persistence.

### 6. Validating admission

All **validating admission controllers / webhooks** run in parallel. They can accept or reject the request, but **cannot change it**.

* `PodSecurity` — rejects Pods that violate the namespace's PSS profile
* `ResourceQuota` — checks the request against the namespace's quota
* `ValidatingAdmissionWebhook` — your custom webhooks (OPA, policy engines, etc.)

If any validating admission controller rejects: the request fails with a specific error, and the object is **not stored**.

### 7. etcd write

The apiserver serializes the object to protobuf and writes it to **etcd**:

```
/registry/deployments/default/web
```

The write is **fsynced** — this is what makes etcd durable. On a typical SSD, this is sub-millisecond; on a slow disk, it can dominate apiserver latency.

If etcd is unavailable or loses quorum: the apiserver returns `503 Service Unavailable`. The request never completes.

### 8. apiserver returns 201 Created

The apiserver returns the persisted object (with `resourceVersion` set by etcd) to kubectl. kubectl prints:

```
deployment.apps/web created
```

The apiserver also **emits a watch event** to anyone watching Deployments (e.g., `kubectl get deployments -w`).

### 9. The Deployment controller notices

The `kube-controller-manager` runs the **Deployment controller**, which is a control loop:

```
loop {
  watch <- list Deployments
  for each Deployment:
    observed = current state (ReplicaSets, Pods)
    desired = spec.replicas, spec.template, ...
    diff = desired - observed
    if diff != 0: reconcile(diff)
}
```

The controller sees the new Deployment, decides it needs **3 Replicas**, and creates a **ReplicaSet** with `replicas: 3`.

This is another POST to the apiserver (a new object). The apiserver goes through steps 2-7 again. **Every state change goes through the apiserver.**

### 10. The ReplicaSet controller notices

The ReplicaSet controller (also in kube-controller-manager) sees the new ReplicaSet, sees no Pods, and creates **3 Pods**.

The Pod creation is the interesting part — this is the first time we have a "thing to schedule".

### 11. The scheduler runs

The **kube-scheduler** is a control loop:

```
loop {
  Pods that have spec.nodeName=""  →  these need scheduling
  for each unscheduled Pod:
    filtered = nodes that pass all Filter plugins
    scored = score each candidate node
    chosen = highest-scoring node
    bind: POST /api/v1/pods/<name>/binding
}
```

The scheduler evaluates the Pod against every node using a series of **Filter plugins** (drop nodes that can't run the Pod) and **Score plugins** (rank the rest).

Filter plugins check:
* **NodeResourcesFit** — does the node have enough CPU/memory?
* **NodeName** / **NodeSelector** — does the node match the Pod's selectors?
* **NodeAffinity** — does the node match the Pod's affinity rules?
* **TaintToleration** — does the Pod tolerate the node's taints?
* **NodeUnschedulable** — is the node cordoned?
* **VolumeRestrictions** — do the Pod's volumes fit on the node?
* ... and more

Score plugins rank:
* **NodeResourcesFit** (least allocated, most allocated, balanced)
* **NodeAffinity** (preferredDuringScheduling)
* **TopologySpread** — prefer even spread across zones
* **TaintToleration** (preferred)
* **ImageLocality** — prefer nodes that already have the image
* ... and more

The highest-scoring node is selected. The scheduler **binds the Pod to the node** by POSTing a Binding object to the apiserver:

```
PUT /api/v1/namespaces/default/pods/web-abcde/binding
{
  "apiVersion": "v1",
  "kind": "Binding",
  "metadata": { "name": "web-abcde" },
  "target": { "apiVersion": "v1", "kind": "Node", "name": "node-1" }
}
```

The apiserver updates the Pod's `spec.nodeName` to `node-1` and writes to etcd.

### 12. The kubelet notices

The **kubelet** on `node-1` is running a control loop:

```
loop {
  Pods assigned to this node, not yet running  →  these need to start
  for each such Pod:
    if image not present: pull it
    call CRI to create containers
    call CNI to set up networking
    start containers
}
```

The kubelet sees the new Pod assigned to it.

#### 12a. Image pull

The kubelet calls the **image puller** (delegated to the container runtime). For `nginx:1.27`:

1. Check local image cache. If present, skip.
2. Resolve `nginx:1.27` to a digest (e.g. `sha256:abc...`)
3. Authenticate to the registry (using `imagePullSecrets` if private)
4. Pull the image layers
5. Unpack to the container runtime's storage

The kubelet records the image pull status in the Pod's events.

#### 12b. Sandbox creation

The kubelet calls the container runtime (via **CRI — Container Runtime Interface**) to create the **Pod sandbox** (the thing that holds the network namespace, cgroup, etc.):

```bash
# equivalent to (in containerd)
crictl runp \
  --runtime=runc \
  --network=cnibridge \
  pod-config.json
```

The runtime creates a **pause container** (the `/pause` process — see [[Kubernetes/concepts/L09-advanced/09-pause-container|pause-container]]) that holds the Pod's network namespace. All the Pod's containers will share this namespace.

#### 12c. CNI setup

The runtime calls the **CNI plugin** to wire up the Pod's network:

1. Create a **veth pair** — one end in the Pod's netns, one end on the host (or bridge)
2. Assign an **IP address** to the Pod-side veth
3. Set up **routes** so the Pod can reach other Pods
4. Configure **iptables / eBPF** for Service virtual IPs

The Pod now has an IP. It's reachable from other Pods on the same network (assuming NetworkPolicies allow it).

#### 12d. Container start

For each container in the Pod:

1. Pull the image (if not already pulled)
2. Apply the Pod's **cgroup limits** (CPU quota, memory limit)
3. Apply the **security context** (runAsUser, capabilities, seccomp profile, etc.)
4. Mount the **volumes** (ConfigMap, Secret, PVC, hostPath, etc.)
5. Apply **environment variables** and **command / args**
6. Start the container

If the container has a `startupProbe`, `livenessProbe`, or `readinessProbe`, the kubelet starts running them at the configured intervals.

#### 12e. Status reporting

The kubelet reports the Pod's status back to the apiserver:

```
POST /api/v1/namespaces/default/pods/web-abcde/status
{
  "phase": "Running",
  "containerStatuses": [...],
  "conditions": [{ "type": "Ready", "status": "True" }, ...]
}
```

The apiserver writes this to etcd.

### 13. Service discovery

If you have a **Service** in the same manifest (or one already exists with the right selector), the **Endpoints controller** is watching the Pod. It sees:

* A Pod with `app: web` is now running
* The Service has `selector: { app: web }`
* The Pod's IP is in the Service's port range

It updates the Service's Endpoints (or EndpointSlices) to include the Pod.

**kube-proxy** watches Endpoints on every node. When it sees a change, it programs **iptables / IPVS rules** so that traffic to the Service's ClusterIP gets DNAT'd to the Pod's IP.

### 14. Ingress (if applicable)

If there's an **Ingress** routing traffic to the Service, the **Ingress controller** is watching Ingresses. When it sees a new Service, it configures the underlying reverse proxy (nginx, traefik, etc.) to route traffic.

The actual configuration depends on the controller. Most watch the Ingress + Service + Endpoints and re-render their config.

### 15. HPA / autoscaling (if applicable)

If there's an **HPA** watching the Deployment, it's polling the Metrics API every 15 seconds. If the metrics indicate load, it bumps `replicas` on the Deployment, which cascades through the same flow.

## The timeline

A rough timing for a single Pod:

```
t=0     kubectl apply
t=10ms  apiserver receives, authn, authz, admission
t=15ms  etcd write
t=20ms  apiserver returns 201
t=50ms  Deployment controller sees it, creates RS
t=100ms RS controller sees it, creates Pod
t=150ms Scheduler sees it, binds to a node
t=200ms kubelet on the node sees it
t=1-5s  Image pull (depends on network, image size, cache)
t=2-6s  Container start
t=2-7s  Readiness probe passes (if any)
t=7s    Service has the Pod in endpoints
t=7s    Traffic can reach the Pod
```

For a 3-replica Deployment, all 3 Pods go through this in parallel. By `t=10s` (assuming nothing breaks), all 3 are serving traffic.

## The places things can go wrong

| Failure | Where | Symptom |
|---|---|---|
| Auth fails | Step 2 | `401 Unauthorized` |
| RBAC denies | Step 3 | `403 Forbidden` |
| Mutating webhook down | Step 4 | timeout / `500` |
| Schema invalid | Step 5 | `400 Bad Request` with field error |
| Validating webhook denies | Step 6 | `403 Forbidden` with reason |
| etcd unavailable | Step 7 | `503 Service Unavailable` |
| No nodes can run the Pod | Step 11 | Pod stuck in `Pending`, events show why |
| Image pull fails | Step 12a | `ImagePullBackOff` |
| CNI fails | Step 12c | `ContainerCreating` forever |
| App crashes | Step 12d | `CrashLoopBackOff` |
| Readiness probe fails | Step 12e | Pod `Running` but not in Service endpoints |

See [[Kubernetes/concepts/L08-operations/03-common-failure-modes|common-failure-modes]] for the full triage guide.

## The end-to-end mental model

1. **kubectl** talks to **apiserver** (always)
2. **apiserver** talks to **etcd** (always, for state)
3. **Controllers** in **kube-controller-manager** watch the apiserver, reconcile state
4. **Scheduler** watches the apiserver for unscheduled Pods, binds them to nodes
5. **kubelet** on each node watches the apiserver for Pods assigned to it, runs them
6. **kube-proxy** on each node watches the apiserver for Services + Endpoints, programs iptables
7. **CNI** runs per-node, called by the runtime, gives Pods IPs
8. **DNS** (CoreDNS) watches the apiserver, serves Service DNS records
9. **The apiserver is the only thing that talks to etcd.** All components go through it.

This is the **declarative reconciliation** model. The state you declared in your YAML drives every action; controllers continuously drive the actual state toward the declared state.

## See also

* [[Kubernetes/concepts/L01-architecture/02-high-availability|High Availability]] — what happens when the apiserver is unavailable
* [[Kubernetes/concepts/L09-advanced/10-etcd|etcd]] — the storage layer
* [[Kubernetes/concepts/L09-advanced/02-custom-controllers|Custom Controllers]] — the pattern behind all of this
* [[Kubernetes/concepts/L08-operations/03-common-failure-modes|Common Failure Modes]] — what to do when things go wrong
