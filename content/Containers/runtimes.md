---
title: Container Runtimes
tags: [containers, containerd, runc, cri, oci, docker]
date: 2026-10-10
description: The software stack that turns an image into a running process — Docker, containerd, shims, runc and the CRI — with the path from kubectl to exec(), the OCI runtime spec, sandboxed runtimes and the commands for debugging on a node.
---

# Container Runtimes

"Container runtime" is used for three different layers, which causes a lot of confusion. From the top:

| Layer                       | Job                                                                | Examples                                |
| :-------------------------- | :----------------------------------------------------------------- | :-------------------------------------- |
| **Engine / developer tool** | Build images, a friendly CLI, local networking and volumes         | Docker Engine, Podman, nerdctl, Finch   |
| **High-level runtime**      | Pull and unpack images, manage container lifecycles, expose an API | containerd, CRI-O                       |
| **Low-level (OCI) runtime** | Create one container: namespaces, cgroups, then `exec()`           | runc, crun, youki, gVisor `runsc`, Kata |

Each layer calls the one below. The kernel features at the bottom are described in [[Containers/namespaces-and-cgroups|namespaces and cgroups]].

## From `kubectl apply` to a process

```
kubectl ─► API server ─► scheduler binds the pod to a node
                              │
                           kubelet (on that node)
                              │  CRI — gRPC over a Unix socket
                              ▼
                          containerd
                 1. RunPodSandbox      → create network namespace, start the pause container,
                                         call the CNI plugin to wire up networking
                 2. PullImage          → fetch manifest and layers, unpack into the snapshotter
                 3. CreateContainer    → write an OCI bundle: rootfs + config.json
                 4. StartContainer
                              │
                     containerd-shim-runc-v2     (one per pod; stays alive)
                              │
                            runc                 (sets everything up, exec()s your binary, exits)
                              │
                       your process, PID 1
```

The numbered steps are the **Container Runtime Interface (CRI)**: the gRPC API the kubelet uses so that it does not care which runtime is installed. The network step is covered in [[Containers/container-networking|container networking]]; the image step in [[Containers/registries|registries]].

## The pieces

**containerd** is a daemon that manages images, snapshots, containers and tasks. It is the default runtime of nearly every managed Kubernetes service and also what Docker Engine uses internally. Its main parts:

- the **content store** — blobs by digest;
- **snapshotters** — turn layers into a mountable filesystem, normally with [[Linux/virtualization/overlayfs|OverlayFS]];
- the **CRI plugin** — the endpoint the kubelet talks to;
- **namespaces** (containerd's own, unrelated to kernel or Kubernetes namespaces) — Kubernetes containers live in `k8s.io`, Docker's in `moby`.

**The shim** sits between containerd and each container. It holds the container's stdio and exit status and reaps it when it dies. Because the shim, not containerd, is the parent, **containerd can be restarted or upgraded without killing running containers**.

**runc** is the reference OCI runtime. It reads `config.json`, creates the namespaces and cgroups, mounts the root filesystem, applies capabilities and seccomp, executes the process — and exits. It is not a daemon.

**CRI-O** is an alternative high-level runtime built only for Kubernetes, with nothing extra; it is the default on OpenShift.

## The OCI runtime specification

The contract between high-level and low-level runtimes is a directory called a **bundle**:

```
bundle/
├── config.json      # process args and env, user, capabilities, namespaces, mounts,
│                    # cgroup limits, seccomp profile, hooks
└── rootfs/          # the merged image filesystem
```

Anything that can run a bundle is an OCI runtime, which is what makes runtimes swappable:

```bash
runc spec                  # generate a default config.json
sudo runc run demo         # run the bundle in the current directory
```

Together with the image and distribution specifications, this is the standard that made "build with one tool, run with another" true.

## What happened to Docker in Kubernetes

Kubernetes originally talked to Docker Engine through a built-in adapter called dockershim, which was removed in Kubernetes 1.24. This changed less than the headlines suggested:

- Images built with Docker are OCI images and run exactly as before.
- Nodes run containerd directly, removing a layer.
- What stopped working: mounting `/var/run/docker.sock` to build images or inspect containers from a pod. Use Kaniko, BuildKit or Buildah to build, and `crictl` to inspect.

On a workstation, Docker Desktop, Podman, Rancher Desktop, Colima and Finch are all reasonable choices. [[Linux/virtualization/podman|Podman]] is daemonless and rootless by default, and can run pods from Kubernetes YAML.

## Sandboxed runtimes

runc containers share the host kernel, so a kernel vulnerability is a container escape. Sandboxed runtimes add a stronger boundary while still accepting OCI bundles:

| Runtime             | Technique                                                    | Trade-off                                                  |
| :------------------ | :----------------------------------------------------------- | :--------------------------------------------------------- |
| **gVisor**          | A user-space kernel intercepts and reimplements system calls | Syscall overhead; some incompatibilities                   |
| **Kata Containers** | Each pod runs in a lightweight VM with its own kernel        | Memory overhead; needs nested or bare-metal virtualisation |
| **Firecracker**     | Minimal microVMs with very fast boot                         | The basis of AWS Fargate and Lambda                        |

Kubernetes selects one per pod through a `RuntimeClass`:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
---
apiVersion: v1
kind: Pod
metadata:
  name: untrusted
spec:
  runtimeClassName: gvisor
  containers:
    - name: app
      image: registry.example.com/untrusted:1.0
```

See [[Kubernetes/concepts/L07-security/02-workload-sandboxing/17-runtime-sandboxing|runtime sandboxing]] and [[Linux/virtualization/hypervisors|hypervisors]]. The same mechanism runs [[Containers/wasm|WebAssembly]] workloads through a Wasm shim.

## Debugging on a node

`docker` is usually not installed on Kubernetes nodes. Use `crictl`, which speaks CRI and understands pods:

```bash
crictl pods                              # pod sandboxes
crictl ps -a                             # containers, including exited ones
crictl logs <container-id>
crictl inspect <container-id> | jq '.info.pid'    # host PID → use with nsenter
crictl images
crictl stats
crictl rmi --prune                       # reclaim disk from unused images
```

`ctr` is containerd's low-level client (`ctr -n k8s.io containers ls`), and `nerdctl` offers a Docker-compatible CLI on top of containerd.

| Symptom on the node                                        | Where to look                                                                                   |
| :--------------------------------------------------------- | :---------------------------------------------------------------------------------------------- |
| Pods stuck `ContainerCreating`                             | `journalctl -u containerd` and `-u kubelet`; sandbox or CNI errors                              |
| `failed to create shim task` / `OCI runtime create failed` | The message after it: bad entrypoint, missing binary, permission, wrong architecture            |
| Node `NotReady`, `container runtime is down`               | Is containerd running? Is its socket path what the kubelet expects?                             |
| Disk pressure                                              | `/var/lib/containerd` full of images and snapshots; kubelet image garbage collection thresholds |
| Containers killed, exit code 137                           | OOM kill — `dmesg`, and the cgroup's `memory.events`                                            |

A configuration detail that still catches self-managed clusters: the kubelet and containerd must agree on the **cgroup driver**. Both should use `systemd` on systemd hosts with cgroup v2; a mismatch causes unstable nodes. See [[Linux/kernel/cgroups|cgroups]] and [[Linux/observability/journalctl|journalctl]].

## Choosing

For Kubernetes nodes, use what your distribution ships — containerd in most cases — and do not customise it without a reason. The meaningful choices are _which sandbox for which workload_ and, on developer machines, which engine fits your licence and security constraints.

## Related

- [[Containers|Containers hub]]
- [[Linux/virtualization/container-runtimes|Container runtimes on Linux]] — a comparison at the host level
- [[Kubernetes/concepts/L01-architecture/06-what-happens-when|What happens when you create a pod]]
- [[Kubernetes/concepts/L09-advanced/09-pause-container|The pause container]]
- [[Kubernetes/guides/troubleshooting/node-not-ready|Node NotReady]]
