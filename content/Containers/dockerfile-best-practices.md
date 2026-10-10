---
title: Dockerfile Best Practices
tags: [containers, docker, dockerfile, buildkit, security]
date: 2026-10-10
description: Writing Dockerfiles that build fast and produce small, reproducible, secure images — multi-stage builds, cache ordering and cache mounts, build secrets, non-root users, PID 1 and signals, health, and a review checklist.
---

# Dockerfile Best Practices

A Dockerfile is a build script for an [[Containers/images-and-layers|image]]. A good one optimises four things at once: **build speed**, **image size**, **reproducibility** and **security**. Most of the techniques serve several of these together.

## A reference Dockerfile

```dockerfile
# syntax=docker/dockerfile:1

# ---- build stage -----------------------------------------------------------
FROM --platform=$BUILDPLATFORM golang:1.24-bookworm AS build
ARG TARGETOS TARGETARCH
WORKDIR /src

# Dependencies first: this layer is reused until go.mod/go.sum change
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY . .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags="-s -w" -o /out/app ./cmd/app

# ---- runtime stage ---------------------------------------------------------
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/app /app
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/app"]
```

Everything below explains a line of it.

## Multi-stage builds

Compilers, package managers and source code are needed to _build_ an application and are a liability when _running_ it. A multi-stage build uses one stage with the full toolchain and copies only the result into a minimal final stage. Benefits: an image a fraction of the size, far fewer packages for scanners to flag, and no build-time credentials or source in what ships.

Interpreted languages use the same idea — install dependencies in one stage, copy the virtual environment or `node_modules` into a slim runtime stage.

## Order for the cache

The builder reuses a layer only if nothing before it changed. Put slow, stable steps first and fast-changing ones last:

1. Base image and system packages
2. Dependency manifests, then dependency installation
3. Application source
4. Build

**Cache mounts** keep package-manager caches between builds without storing them in the image:

```dockerfile
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends ca-certificates
```

In CI, where runners start empty, export the cache to a registry: `--cache-to type=registry,ref=…/app:buildcache,mode=max --cache-from type=registry,ref=…/app:buildcache`.

## A `.dockerignore` is not optional

Everything in the build context is sent to the builder, and `COPY . .` copies it into the image.

```
.git
node_modules
dist
*.env
.aws
**/*.pem
Dockerfile*
```

Without it, builds are slow, the cache is invalidated by irrelevant changes, and local secrets end up in layers.

## Choose and pin the base image

- Use a **minimal** base: distroless, Chainguard, `-slim` or Alpine. Fewer packages means fewer vulnerabilities and less to patch.
- **Pin a specific version**, never `latest`. For full reproducibility pin the digest: `FROM debian:12.9-slim@sha256:…`. Let Renovate or Dependabot propose updates so pinning does not mean stale.
- Prefer official or verified-publisher images, and rebuild regularly to pick up base-image patches.

A distroless image has no shell, which also means an attacker has none. Debug with an ephemeral container instead — [[Kubernetes/concepts/L08-operations/02-kubectl-debug|kubectl debug]].

## Never put secrets in a layer

`ARG` and `ENV` values are recorded in the image history, and a file deleted in a later layer is still present in the earlier one. Use build secrets, which are mounted only for the duration of one instruction:

```dockerfile
RUN --mount=type=secret,id=npm_token \
    NPM_TOKEN=$(cat /run/secrets/npm_token) npm ci
```

```bash
docker build --secret id=npm_token,env=NPM_TOKEN .
```

For private Git or SSH dependencies use `--mount=type=ssh`. Runtime secrets do not belong in the image at all; inject them when the container starts — [[Kubernetes/concepts/L05-config-storage/02-secrets|Secrets]].

## Run as a non-root user

By default the process runs as root. Combined with a container escape or a mounted host path, that is root on the node.

```dockerfile
RUN groupadd --system --gid 10001 app && useradd --system --uid 10001 --gid app app
COPY --chown=app:app . /app
USER 10001:10001
```

Use a **numeric** UID so Kubernetes can verify `runAsNonRoot` without resolving a name. Listen on a port above 1024. Make the application write only to explicit directories so the root filesystem can be mounted read-only — see [[Kubernetes/concepts/L07-security/02-workload-sandboxing/05-security-context|security context]] and [[Linux/security/container-security|container security]].

## PID 1, signals and shutdown

Your process becomes PID 1 in its [[Containers/namespaces-and-cgroups|PID namespace]], and PID 1 is special: signals without an installed handler are ignored, and it must reap orphaned children.

```dockerfile
ENTRYPOINT ["/app"]                # exec form: your binary is PID 1 and receives SIGTERM
ENTRYPOINT /app                    # shell form: /bin/sh is PID 1 and does NOT forward SIGTERM
```

- Always use the **exec form** (JSON array). With the shell form, `docker stop` and Kubernetes pod termination wait out the grace period and then `SIGKILL` — every deploy drops in-flight requests.
- In a wrapper script, finish with `exec "$@"` so the application replaces the shell.
- If the application spawns children and does not reap them, add a minimal init such as `tini`.
- Handle `SIGTERM`: stop accepting work, finish what is in flight, exit. Background in [[Linux/kernel/signals|signals]] and [[Kubernetes/concepts/L03-workloads/01-pods-deep-dive|pod lifecycle]].

`ENTRYPOINT` sets the executable; `CMD` supplies default arguments that `docker run image args` or a pod's `args` replace.

## Smaller points that add up

| Do                                                                           | Why                                                                                            |
| :--------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------- |
| `COPY`, not `ADD`                                                            | `ADD` silently extracts archives and fetches URLs                                              |
| Combine `apt-get update` and `install` in one `RUN`; clean in the same `RUN` | Avoids stale cached package lists and leftover files in a layer                                |
| `--no-install-recommends`, `npm ci --omit=dev`, `pip install --no-cache-dir` | Leaves out what production does not need                                                       |
| `WORKDIR` instead of `RUN cd`                                                | Each `RUN` starts in a fresh shell                                                             |
| Log to stdout and stderr                                                     | The platform collects it — [[Observability/logging\|logging]]                                  |
| One concern per container                                                    | Scale, restart and upgrade independently                                                       |
| OCI labels: `org.opencontainers.image.source`, `.revision`, `.version`       | Trace any running image back to its commit                                                     |
| `HEALTHCHECK` for plain Docker; probes for Kubernetes                        | Kubernetes ignores `HEALTHCHECK` — use [[Kubernetes/concepts/L03-workloads/10-probes\|probes]] |

## Verify

```bash
hadolint Dockerfile                                # lint
docker build --check .                             # BuildKit's built-in checks
docker buildx build --sbom=true --provenance=mode=max -t app:1.4.2 .   # attach SBOM and provenance
trivy image app:1.4.2                              # vulnerabilities and misconfigurations
dive app:1.4.2                                     # wasted space per layer
docker run --rm --read-only --cap-drop=ALL --user 10001 app:1.4.2      # does it run locked down?
```

Wire the linter and scanner into CI and fail on critical findings — [[DevOps/devsecops/stage2-build/09-container-image-scanning|container image scanning]].

## Alternatives to writing a Dockerfile

- **Cloud Native Buildpacks** detect the language and produce an image with no Dockerfile.
- **ko** (Go), **Jib** (Java) build images directly from source without a Docker daemon.
- **Nix** and **Bazel** give bit-for-bit reproducible images at the cost of a steeper learning curve.
- **Kaniko** and **Buildah** build Dockerfiles without a privileged daemon, which suits CI inside Kubernetes.

## Review checklist

- [ ] Multi-stage, minimal final image
- [ ] Base image pinned to a version or digest
- [ ] `.dockerignore` present
- [ ] Dependencies copied and installed before source
- [ ] No secrets in `ARG`, `ENV` or files
- [ ] Non-root numeric `USER`
- [ ] Exec-form `ENTRYPOINT`; `SIGTERM` handled
- [ ] Scanned, with an SBOM attached

## Related

- [[Containers|Containers hub]]
- [[Containers/registries|Registries]]
- [[Kubernetes/concepts/L07-security/02-workload-sandboxing/19-image-hardening|Image hardening]]
- [[DevOps/ci-cd/pipeline-design|Pipeline design]]
- [Dockerfile reference](https://docs.docker.com/reference/dockerfile/)

## Across the wiki

- [[Linux/concepts/03-processes|03 — Processes]] — process lifecycle and signals (Linux)
- [[Kubernetes/concepts/L06-scheduling-scaling/06-restart-policy|Restart Policy]] — process lifecycle and signals (Kubernetes)
- [[Linux/users-groups/README|Linux Users & Groups]] — users and permissions (Linux)
- [[Linux/concepts/02-file-permissions|02 — File Permissions]] — users and permissions (Linux)
- [[Linux/concepts/04-users-and-groups|04 — Users and Groups]] — users and permissions (Linux)
