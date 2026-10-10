---
title: Container Images and Layers
tags: [containers, images, oci, layers, build-cache]
date: 2026-10-10
description: What a container image is made of — the OCI manifest, config and layers, content addressing, how layers stack through a union filesystem, how the build cache decides what to rebuild, multi-architecture images, and how to inspect and shrink them.
---

# Container Images and Layers

A container image is a packaged root filesystem plus instructions for running a process in it. It is not a disk image or a single file. It is a small tree of **content-addressed** documents, defined by the Open Container Initiative (OCI) image specification, which is why images built by Docker, Buildah, Kaniko or Bazel all run on containerd, CRI-O or Podman.

## Anatomy

```
image index (optional)             "this tag has variants for several platforms"
 ├── manifest  linux/amd64
 │    ├── config      (JSON)       env, entrypoint, cmd, user, workdir, labels, layer diff IDs, history
 │    ├── layer 1     (tar.gz)     base OS files
 │    ├── layer 2     (tar.gz)     + runtime
 │    └── layer 3     (tar.gz)     + your application
 └── manifest  linux/arm64
      └── …
```

| Object       | Contains                                                                |
| :----------- | :---------------------------------------------------------------------- |
| **Layer**    | A tar archive of filesystem _changes_: files added, modified or deleted |
| **Config**   | How to run the image, and the ordered list of layers                    |
| **Manifest** | References to the config and layers, each by digest and size            |
| **Index**    | A list of manifests, one per platform                                   |

Inspect one without pulling it:

```bash
docker buildx imagetools inspect nginx:1.27
crane manifest nginx:1.27 | jq
skopeo inspect docker://nginx:1.27
```

## Content addressing

Every object is named by the SHA-256 hash of its bytes: `sha256:4f53cda1…`. Three properties follow, and they explain most image behaviour:

- **Immutable.** Change one byte and the digest changes. A digest always refers to exactly the same content.
- **Deduplicated.** Two images built on the same base share those layers. They are stored once in the registry and once on each node, and pulled once.
- **Verifiable.** The client hashes what it downloads and rejects mismatches.

A **tag** such as `nginx:1.27` is only a mutable pointer to a manifest digest. It can be moved. This is the reason to deploy by digest — covered in [[Containers/registries|registries]].

## How layers become a filesystem

Layers are stacked with a union filesystem, normally [[Linux/virtualization/overlayfs|OverlayFS]]:

```
container layer   (read-write, per container, discarded on removal)   ← "upperdir"
───────────────────────────────────────────────────────────────────
layer 3: app      (read-only)                                         ┐
layer 2: runtime  (read-only)                                         ├ "lowerdir"
layer 1: base OS  (read-only)                                         ┘
                          ▼ merged view = the container's /
```

- **Reads** fall through to the highest layer that has the file.
- **Writes** are copy-on-write: the first modification copies the file up to the container layer. Editing one byte of a 1 GB file copies 1 GB.
- **Deletes** are recorded as _whiteout_ markers in the upper layer. The file still exists in the lower layer.

That last point has an important consequence: **a later layer cannot shrink an image.** If one instruction adds a 500 MB archive and the next deletes it, the image still carries 500 MB. It also means a secret copied in one layer and removed in the next is still in the image for anyone to extract.

The writable container layer is slow and ephemeral. Anything that must persist, or that is written heavily, belongs in a volume — see [[Kubernetes/concepts/L05-config-storage/03-volumes|volumes]].

## Dockerfile instructions and layers

| Instruction                                                      | Creates a filesystem layer?       |
| :--------------------------------------------------------------- | :-------------------------------- |
| `FROM`                                                           | Brings in the base image's layers |
| `RUN`, `COPY`, `ADD`                                             | Yes — one each                    |
| `ENV`, `WORKDIR`, `USER`, `EXPOSE`, `CMD`, `ENTRYPOINT`, `LABEL` | No — they only change the config  |

```bash
docker history --no-trunc myapp:1.4.2     # each step and its size
dive myapp:1.4.2                          # browse layers and see wasted space
```

## The build cache

For each instruction the builder computes a key from the previous layer, the instruction text and — for `COPY`/`ADD` — the content of the files being copied. If the key matches a cached layer, the step is skipped. **The first cache miss invalidates everything after it.**

```dockerfile
# Slow: any source change invalidates the dependency install
COPY . .
RUN npm ci

# Fast: dependencies are reinstalled only when the lockfile changes
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
```

Order instructions from least to most frequently changing. This single habit accounts for most of the difference between a ten-second and a ten-minute rebuild. BuildKit adds **cache mounts** (`RUN --mount=type=cache,target=/root/.npm …`) that persist package-manager caches across builds without putting them in a layer, and registry-backed cache export for CI runners that start empty. More in [[Containers/dockerfile-best-practices|Dockerfile best practices]].

## Multi-architecture images

A tag can point to an index with a manifest per platform. The runtime picks the entry matching the node, so the same `image:` line works on x86 and Arm.

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t registry.example.com/app:1.4.2 --push .
```

Cross-building uses emulation (slow) or, better, cross-compilation in a builder stage with `--platform=$BUILDPLATFORM` and `GOARCH=$TARGETARCH`. An image that lacks the node's architecture fails at start with `exec format error` — a frequent surprise when adding [[Kubernetes/eks/compute/managed-node-groups/graviton|Graviton]] nodes.

## Size

Smaller images pull faster, start faster, and contain fewer packages to patch.

| Base                   | Approximate size | Contents                                                |
| :--------------------- | :--------------- | :------------------------------------------------------ |
| `ubuntu`, `debian`     | 30–120 MB        | Full distribution user space                            |
| `debian:*-slim`        | ~30 MB           | Trimmed Debian                                          |
| `alpine`               | ~8 MB            | musl libc and BusyBox — occasional compatibility issues |
| Distroless, Chainguard | 2–30 MB          | Runtime only: no shell, no package manager              |
| `scratch`              | 0                | Nothing — for fully static binaries                     |

The most effective technique is a **multi-stage build**: compile in a large image, copy only the artifact into a minimal one. A Go service typically drops from over 800 MB to under 20 MB.

## Beyond the filesystem

The same registry machinery stores other artifacts attached to an image by digest: signatures, SBOMs, provenance attestations and vulnerability reports, as well as Helm charts and WebAssembly modules. See [[Kubernetes/concepts/L07-security/04-admission-policy/23-sboms|SBOMs]] and [[Kubernetes/guides/delivery/templating-patching/helm/oci|Helm OCI registries]].

**Lazy pulling** addresses large images: with formats such as eStargz or SOCI, a container starts as soon as the files it needs first are fetched, instead of waiting for the full download.

## Related

- [[Containers|Containers hub]]
- [[Containers/registries|Registries]] — distribution, tags and digests
- [[Containers/runtimes|Container runtimes]] — what unpacks and mounts the layers
- [[Kubernetes/concepts/L07-security/02-workload-sandboxing/19-image-hardening|Image hardening]]
- [[Kubernetes/guides/troubleshooting/image-pull|Image pull failures]]
- [OCI image specification](https://github.com/opencontainers/image-spec)

## Across the wiki

- [[Linux/virtualization/container-runtimes|Container Runtimes]] — container internals (Linux)
- [[Kubernetes/concepts/L09-advanced/09-pause-container|The Pause Container]] — container internals (Kubernetes)
- [[Kubernetes/concepts/L07-security/02-workload-sandboxing/17-runtime-sandboxing|Runtime Sandboxing (gVisor, Kata Containers)]] — container internals (Kubernetes)
- [[Linux/packaging/README|Linux Packaging]] — packaging (Linux)
- [[Kubernetes/guides/delivery/templating-patching/helm/charts|Helm Charts]] — packaging (Kubernetes)
- [[DevOps/ci-cd/release-and-versioning|Release and Versioning]] — packaging (DevOps)
- [[Linux/concepts/05-package-management|05 — Package Management]] — packaging (Linux)
