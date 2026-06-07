# Pause Container

*"https://kubernetes.io/docs/concepts/workloads/pods/#workload-resources-for-managing-pods"*

Every Pod has a **pause container** (also called the "sandbox container"). It's a tiny init process that holds the Pod's network namespace and is the basis for the Pod's container runtime. The pause container is what makes the multi-container Pod pattern work.

## What it is

The pause container is a **statically-linked binary** that does almost nothing — it just sleeps. Its job is to:

* **Hold the network namespace** for the Pod
* **Be PID 1** of the namespace (so it doesn't exit)
* **Receive SIGTERM** and shut down cleanly (so the Pod can be torn down)

The binary is from the `k8s.gcr.io/pause` image (now `registry.k8s.io/pause`):

```bash
# the binary
registry.k8s.io/pause:3.9
# ~500KB
```

The actual `pause` binary is ~30KB. It compiles to a single syscall: `pause()` (which sleeps until a signal is received).

```c
// the entire pause.c
#include <signal.h>
#include <unistd.h>

static void sigdown(int signo) {
    psignal(signo, "Shutting down, got signal");
    exit(0);
}

int main() {
    signal(SIGINT, sigdown);
    signal(SIGTERM, sigdown);
    for (;;) pause();
    return 0;
}
```

(Plus a few includes and `psignal` for clean shutdown messages.)

That's the whole program. The pause container is literally a program that does nothing but wait for a signal.

## Why it exists

The pause container is what makes a Pod a **unit of network identity**. Without it:

* If you start a container, it has a network namespace
* If you start a second container, it has a separate network namespace
* They can't share `localhost`

The pause container creates the **Pod's network namespace first**. The other containers in the Pod are then started with `network: container:<pause-container-id>`, which puts them in the **same namespace** as the pause container.

```
Pod's network namespace (created by pause)
  ├── eth0 (veth pair to host)
  ├── lo (loopback)
  ├── container A's network stack (shares with Pod)
  ├── container B's network stack (shares with Pod)
  └── container C's network stack (shares with Pod)
```

This is why all containers in a Pod:

* Share the same IP
* Can reach each other on `localhost`
* Share the same ports (with caveats)
* Share the same network interfaces

## Where it shows up

You never create a pause container in your YAML. The kubelet / CRI runtime does it for you. But you can see it:

```bash
# all containers in a Pod, including the pause
kubectl get pod web-abc -o jsonpath='{.spec.containers[*].name}'
# web

# hmm, no pause in the spec — it's not in the Pod spec

# but on the node, crictl shows it
# (crictl is a CLI for the container runtime, like docker but for k8s)
crictl ps
# CONTAINER    IMAGE                  ...
# web          nginx:1.27
# web-pause    registry.k8s.io/pause:3.9
```

The pause container is a **runtime detail**, not a k8s object. It's in the container runtime's namespace, not the k8s Pod spec.

## Lifecycle

The pause container is the **first** container started in a Pod. The order is:

1. kubelet asks the CRI runtime to create a **sandbox** (via `RunPodSandbox`)
2. The CRI runtime creates the pause container, which holds the Pod's network namespace, cgroup, etc.
3. kubelet asks the CRI to create the other containers (via `CreateContainer` + `StartContainer`)
4. The other containers are started in the pause container's namespace

When the Pod is terminated:

1. kubelet sends SIGTERM to the Pod
2. The CRI runtime sends SIGTERM to each container (in reverse order of starting)
3. **The pause container is the last to receive SIGTERM** — it stays running while the other containers shut down
4. After the other containers have exited, the pause container is told to stop
5. The Pod's network namespace is torn down

This ordering is important: the pause container outlives the app containers, so the app's `preStop` hooks can complete (e.g. drain in-flight requests) before the network is gone.

## CRI implementation

The Container Runtime Interface (CRI) defines the pause container via the **sandbox**:

```protobuf
// CRI gRPC service
service RuntimeService {
  rpc RunPodSandbox(RunPodSandboxRequest) returns (RunPodSandboxResponse);
  rpc CreateContainer(CreateContainerRequest) returns (CreateContainerResponse);
  rpc StartContainer(StartContainerRequest) returns (StartContainerResponse);
  // ...
}
```

`RunPodSandbox` is what creates the pause container + the Pod's network namespace. The runtime knows how to do this:

* **containerd** — uses the `cri` plugin
* **CRI-O** — uses `cri-o` directly
* **Docker** — uses `dockershim` (removed in k8s 1.24+)

Each runtime has its own way of implementing the sandbox, but the result is the same: a pause container, a network namespace, a cgroup, and a place for the other containers to live.

## Why not just put the network namespace in the first container?

The naive approach: start container A first, use its network namespace for container B. This breaks because:

* If A crashes, B has no network namespace
* If A is replaced, B's network namespace changes
* If A is in a Pod with `restartPolicy: Always`, the namespace might be reused or not

By having a **dedicated pause container**:

* The network namespace is independent of any app container
* The pause container is "infrastructure" — kubelet restarts it if it dies (it shouldn't, but the safety is there)
* Multiple containers can be added / removed without affecting the network namespace

## The /pause process from inside the container

If you exec into a Pod and look at the process list:

```bash
kubectl exec -it web-abc -- ps aux
# (or use /proc)

# from inside the container, you don't see the pause container
# it's in a different namespace (the container's PID namespace)
# but if you use --share-processes:
kubectl debug -it web-abc --image=busybox --target=web --share-processes

# now you can see the pause process
ps aux
# PID   USER     COMMAND
# 1     root     /pause
# 7     root     nginx: master process
# 8     www-data nginx: worker process
```

The `1` PID is the pause container. The `nginx` process is your app. They share the network namespace (via the pause container's namespace).

## The "shareProcessNamespace" Pod option

A Pod spec has a `shareProcessNamespace` field:

```yaml
apiVersion: v1
kind: Pod
metadata: { name: web }
spec:
  shareProcessNamespace: true   # containers share PID namespace
  containers:
  - name: app
    image: app:1.0
  - name: sidecar
    image: sidecar:1.0
```

With this, all containers in the Pod share the **PID namespace** too. Now your app can see the sidecar's processes, and vice versa. The pause container is still PID 1 in the shared namespace.

`shareProcessNamespace: true` is useful for:

* Debugging (see all processes in the Pod)
* Sidecars that need to inspect the main app's processes
* Cooperative shutdown (sending signals to peer containers)

But it has security implications: a compromised container can see and signal other containers' processes. Don't enable it unless you need it.

## The "no PID 1" problem

A common question: "why does the pause container have PID 1?". The answer is **PID 1 semantics in Linux**:

* PID 1 is special — signals to it are NOT delivered by default (kernel only sends signals it doesn't ignore)
* When a container's PID 1 exits, the container is considered "stopped"
* A non-PID-1 process that becomes an orphan is reparented to PID 1 (or systemd, or another init)

If the pause container weren't PID 1:

* If the app container's main process died, the pause process would be reparented to something else (or be orphaned)
* The container wouldn't shut down cleanly
* The Pod's network namespace would be torn down prematurely

By having the pause container as PID 1, the network namespace is anchored to a process that **never dies** (until the Pod is being torn down). This makes the lifecycle predictable.

## The image

The pause image is intentionally tiny. It needs to:

* Be downloadable fast (every Pod needs it)
* Have no vulnerabilities (every Pod uses it)
* Work on every architecture

```bash
# what's in the pause image
docker pull registry.k8s.io/pause:3.9
docker save registry.k8s.io/pause:3.9 -o pause.tar
tar -xf pause.tar
ls
# 5f5e8a9d7c4...   <- layer with the binary
# manifest.json
# repositories
```

It's a single static binary on a scratch (empty) image. No shell, no package manager, no nothing.

## How the kubelet knows about it

The kubelet has a flag for the pause image:

```bash
# in the kubelet config
--pod-infra-container-image=registry.k8s.io/pause:3.9
```

This defaults to `k8s.gcr.io/pause` (now `registry.k8s.io/pause`). On most clusters, you don't need to change it.

The kubelet passes this image to the CRI runtime when calling `RunPodSandbox`. The runtime pulls it (if not cached) and uses it.

## Why this matters in practice

Most of the time, you don't think about the pause container. But it matters when:

* **Debugging Pod networking**: "all containers in the Pod share the network namespace" — because of the pause container
* **Multi-container Pods**: the sidecar can `localhost` to the main app — because of the pause container
* **Pod startup time**: pulling the pause image is part of every Pod's startup. If the image is in a slow registry, every Pod is slow to start
* **Pod security**: the pause container is PID 1 in the shared namespace. A bug in pause could (theoretically) affect every Pod
* **Container runtime bugs**: pause container lifecycle issues manifest as weird network namespace behavior

## Gotchas

* **You can't customize the pause image via the Pod spec.** It's set at the kubelet level. (You can change the kubelet's `--pod-infra-container-image`, but that's a node-level setting.)
* **The pause image must be in every node's cache** for fast Pod startup. If your cluster is air-gapped, mirror the image.
* **The pause container uses no resources (no CPU, no memory).** It's a sleeping process, not a workload. The cgroup is empty.
* **You can see the pause container in `crictl ps` but not in `kubectl get pod -o jsonpath='{.spec.containers}'`.** It's a runtime detail, not a spec.
* **The pause container is invisible from inside the app container** (unless `shareProcessNamespace: true`).
* **The pause container's logs are usually empty.** If it has any output, something has gone wrong.
* **Some runtimes (older Docker) had a different sandbox model.** With dockershim removed in k8s 1.24+, all runtimes use the pause-container sandbox model.
* **CNI plugins interact with the pause container's network namespace**, not the app container's. The CNI gets the Pod's netns via the pause container.
* **The pause container doesn't have a security context.** It runs as root, has no capabilities, etc. (It doesn't need them — it does nothing.)
* **The image tag is part of the kubelet version compatibility.** Pause 3.9 is for k8s 1.27+. Older pause images may have issues with newer runtimes.

## When to think about the pause container

* **Air-gapped clusters**: make sure the pause image is in your private registry
* **Custom container runtimes**: ensure the runtime supports the pause-container sandbox model
* **CNI development**: you're working with the pause container's netns
* **Performance tuning**: if Pod startup is slow, check pause image pull time
* **Debugging weird Pod issues**: "I can reach localhost from the sidecar, but not the other way" — pause container lifecycle

## See also

* [[Kubernetes/concepts/L03-workloads/01-pods|Pods]] — the parent concept
* [[Kubernetes/concepts/L03-workloads/09-multi-container-pods|Multi-Container Pods]] — the pattern that depends on the pause container
* [[Kubernetes/concepts/L04-services-networking/06-cni|CNI]] — uses the pause container's netns
