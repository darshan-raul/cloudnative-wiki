---
title: Containers
tags: [containers, docker, oci, containerd, images]
date: 2026-10-10
description: Containers from the ground up — what a container really is, how images are built and distributed, the runtime stack beneath Docker and Kubernetes, container networking, and WebAssembly as a neighbouring technology.
---

# Containers 📦

Kubernetes schedules containers; it does not explain them. This section covers the layer underneath: what a container actually is on a Linux host, how an image is put together and shipped, and what runs it.

If you can explain why a container is "just a process", why a rebuild is sometimes instant and sometimes slow, and what happens between `kubectl apply` and a running process, [[Kubernetes]] becomes much easier to debug.

## Reading order

1. **[[Containers/namespaces-and-cgroups|Namespaces and cgroups]]** — A container is a process with a restricted view and a resource budget. Build one by hand.
2. **[[Containers/images-and-layers|Images and layers]]** — The OCI image format, content addressing, the layer cache, multi-architecture images.
3. **[[Containers/dockerfile-best-practices|Dockerfile best practices]]** — Small, fast, reproducible and secure builds.
4. **[[Containers/registries|Registries]]** — How push and pull work, tags versus digests, authentication, signing, mirroring.
5. **[[Containers/runtimes|Container runtimes]]** — Docker, containerd, runc and the CRI: who does what.
6. **[[Containers/container-networking|Container networking]]** — veth pairs, bridges, port publishing and how this becomes Kubernetes networking.
7. **[[Containers/wasm|WebAssembly]]** — A different sandbox, and where it does and does not replace containers.

## The stack at a glance

```
            docker CLI / nerdctl / kubectl
                        │
        dockerd                      kubelet
            │                           │  CRI (gRPC)
            └────────► containerd ◄─────┘        ← pulls images, manages snapshots and lifecycles
                           │
                    containerd-shim                ← one per container; survives containerd restarts
                           │
                         runc                      ← OCI runtime: sets up namespaces and cgroups, then exec()
                           │
                 your process (PID 1 in its own namespace)
        ──────────────── Linux kernel ────────────────
          namespaces · cgroups · overlayfs · seccomp · capabilities
```

## The Linux building blocks

These live in the Linux section and are worth reading alongside:

| Mechanism         | What it provides                     | Note                                                          |
| :---------------- | :----------------------------------- | :------------------------------------------------------------ |
| PID namespace     | A private process tree               | [[Linux/concepts/process-namespace\|Process namespace]]       |
| Mount namespace   | A private filesystem view            | [[Linux/virtualization/mount-namespace\|Mount namespace]]     |
| Network namespace | Private interfaces, routes and ports | [[Linux/virtualization/network-namespace\|Network namespace]] |
| User namespace    | Root inside, unprivileged outside    | [[Linux/virtualization/user-namespace\|User namespace]]       |
| cgroups           | CPU, memory, I/O and PID limits      | [[Linux/kernel/cgroups\|cgroups]]                             |
| OverlayFS         | Layered copy-on-write filesystems    | [[Linux/virtualization/overlayfs\|OverlayFS]]                 |
| Capabilities      | Root's power, split into pieces      | [[Linux/security/capabilities\|Capabilities]]                 |
| seccomp           | System call filtering                | [[Linux/security/seccomp\|seccomp]]                           |
| AppArmor          | Mandatory access control profiles    | [[Linux/security/apparmor\|AppArmor]]                         |

Related tools and comparisons: [[Linux/virtualization/container-runtimes|container runtimes on Linux]], [[Linux/virtualization/podman|Podman]], [[Linux/virtualization/systemd-nspawn|systemd-nspawn]], [[Linux/virtualization/hypervisors|hypervisors]] and [[Linux/virtualization/emulator-vs-virtualization|emulation versus virtualisation]].

## Security

- [[Linux/security/container-security|Container security on Linux]] — the isolation boundary and how it is weakened
- [[Kubernetes/concepts/L07-security/02-workload-sandboxing/19-image-hardening|Image hardening]]
- [[Kubernetes/concepts/L07-security/02-workload-sandboxing/05-security-context|Security context]]
- [[Kubernetes/concepts/L07-security/02-workload-sandboxing/17-runtime-sandboxing|Runtime sandboxing]] — gVisor, Kata and Firecracker
- [[DevOps/devsecops/stage2-build/09-container-image-scanning|Container image scanning]]
- [[Kubernetes/concepts/L07-security/04-admission-policy/23-sboms|SBOMs]]

## Where containers run

- ☸️ [[Kubernetes/concepts/L03-workloads/01-pods|Pods]] — the Kubernetes wrapper around one or more containers; see also [[Kubernetes/concepts/L09-advanced/09-pause-container|the pause container]]
- ☁️ [[AWS/compute/ecs/README|Amazon ECS]] and [[Kubernetes/eks/compute/fargate/README|Fargate]]
- 🔷 [[Azure|Azure compute]] — Container Apps and AKS
- 🟠 [[GCP|GCP compute]] — Cloud Run and GKE

## Related

- [[Linux]] — the operating system all of this is built from
- [[DevOps/ci-cd/README|CI/CD]] — where images are built and promoted
- [[Kubernetes/guides/troubleshooting/image-pull|Image pull failures]] and [[Kubernetes/guides/troubleshooting/crashloop-backoff|CrashLoopBackOff]]
