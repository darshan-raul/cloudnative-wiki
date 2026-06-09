# Image Hardening

*"https://kubernetes.io/docs/concepts/containers/images/"*

**Image hardening** is the practice of making container images **smaller, simpler, and harder to attack**. A 1 GB image with a full Linux userspace has more attack surface than a 20 MB `distroless` image. The goal: ship only what's needed to run the application, nothing more. This is the **shift-left** of runtime security — every layer of bloat is a potential vulnerability or backdoor.

### Table of Contents

1. [The Threat Image Hardening Solves](#1-the-threat-image-hardening-solves)
2. [The Layer Model of Container Images](#2-the-layer-model-of-container-images)
3. [Base Image Selection](#3-base-image-selection)
4. [The "distroless" Pattern](#4-the-distroless-pattern)
5. [The "scratch" Image](#5-the-scratch-image)
6. [Multi-Stage Builds](#6-multi-stage-builds)
7. [The Image Vulnerability Scanner](#7-the-image-vulnerability-scanner)
8. [Image Signing (cosign, Notary)](#8-image-signing-cosign-notary)
9. [The "Trusted Registry" Pattern](#9-the-trusted-registry-pattern)
10. [SBOM (Software Bill of Materials)](#10-sbom-software-bill-of-materials)
11. [Common CVEs and Their Fixes](#11-common-cves-and-their-fixes)
12. [The "no :latest" rule](#12-the-no-latest-rule)
13. [Image Pull Policy and Caching](#13-image-pull-policy-and-caching)
14. [Operations and Debugging](#14-operations-and-debugging)
15. [Gotchas and Common Mistakes](#15-gotchas-and-common-mistakes)

---

## 1. The Threat Image Hardening Solves

A container image is a **filesystem snapshot** with metadata. The contents are:

* **OS userspace** — libc, openssl, busybox, shell, package manager, etc.
* **Application** — your code + dependencies.
* **Build artifacts** — compilers, headers, dev packages (often).
* **Config** — env files, default configs, etc.

The "OS userspace" is the **attack surface** that's not under your control. Every package, every library, every binary is a potential vulnerability. The Equifax breach (2017) was a vulnerability in Apache Struts. The Log4Shell (2021) was a vulnerability in `log4j`. Both were in the dependency tree of an image, not in the application code.

**Image hardening** reduces this surface. The principle: **only what you need, nothing more**.

## 2. The Layer Model of Container Images

A container image is a **stack of layers**. Each layer is a diff against the previous. The final image is the union of all layers.

```
FROM ubuntu:22.04                # layer 1: Ubuntu base (~70 MB)
RUN apt-get install -y python3   # layer 2: Python
RUN pip install flask            # layer 3: Flask
COPY . /app                      # layer 4: your code
```

The image is ~200 MB. The layers are cached separately. If you change a layer, the layers above it are rebuilt.

**The image's total size = sum of layer sizes.** Every `RUN`, `COPY`, `ADD` adds a layer. The base image is usually the largest layer.

### 2.1 The implications

* **Smaller images** — fewer layers, smaller base, fewer `RUN`s. Each `RUN` is a layer; combine them.
* **Cached layers** — if a layer doesn't change, it's reused. **Order matters**: put stable layers first (base image, dependencies), then the changing layer (your code).
* **Vulnerabilities** — every layer adds vulnerabilities. Fewer layers = fewer vulnerabilities.

The Dockerfile best practices:

```dockerfile
# bad: many layers, big image
FROM ubuntu:22.04
RUN apt-get update
RUN apt-get install -y python3
RUN pip install flask
COPY . /app
RUN apt-get install -y curl    # more packages

# better: fewer layers, smaller image
FROM python:3.12-slim
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r /app/requirements.txt
COPY . /app
```

The `slim` base is smaller. `--no-cache-dir` removes pip's cache. The `requirements.txt` is a separate layer (cached if the deps don't change).

## 3. Base Image Selection

The base image is the **biggest decision**. Options:

| Base | Size | Has shell? | Has package manager? | Use case |
|---|---|---|---|---|
| `ubuntu:22.04` | ~70 MB | Yes | Yes | General purpose |
| `ubuntu:22.04-slim` | ~30 MB | Yes | Yes | Smaller variant |
| `debian:bookworm-slim` | ~25 MB | Yes | Yes | Smaller Debian |
| `alpine:3.19` | ~5 MB | Yes | Yes (apk) | Minimal |
| `gcr.io/distroless/*` | ~2-20 MB | No | No | Production, security-sensitive |
| `scratch` | 0 MB | No | No | Static binaries (Go) |

The trade-off:

* **Bigger base** (Ubuntu) — easy to debug, has all the tools. More attack surface.
* **Alpine** — small, fast, but uses `musl` libc (not glibc). Some apps may have issues.
* **Distroless** — minimal, no shell, no package manager. Harder to debug. Best for production.
* **Scratch** — empty. For static binaries (Go, Rust).

For **production, security-sensitive** workloads: **distroless or scratch**.

For **development / debug** workloads: **Ubuntu / Debian** (you can `kubectl exec` and debug).

## 4. The "distroless" Pattern

*"https://github.com/GoogleContainerTools/distroless"*

**Distroless** images (from Google) are **minimal** — they contain only your application and its runtime dependencies. **No shell, no package manager, no OS utilities**.

```dockerfile
# multi-stage: build in a full image, run in distroless
FROM golang:1.22 AS build
WORKDIR /app
COPY . .
RUN go build -o myapp

FROM gcr.io/distroless/static-debian12
COPY --from=build /app/myapp /
CMD ["/myapp"]
```

The final image is ~10 MB. It has:

* The compiled `myapp` binary.
* `ca-certificates` (for HTTPS).
* `/etc/passwd` with the `nonroot` user.
* A minimal `tzdata` (for timezones).

It does **not** have:

* A shell (`/bin/sh`).
* A package manager (`apt`).
* `curl`, `wget`, `bash`, `vi`.
* Any OS utilities.

This is **the smallest practical production image**.

### 4.1 The distroless variants

| Image | Use case | Size |
|---|---|---|
| `gcr.io/distroless/static-debian12` | Static binaries (Go, Rust) | ~2 MB |
| `gcr.io/distroless/base-debian12` | Apps with libc but no shell | ~20 MB |
| `gcr.io/distroless/cc-debian12` | C / C++ apps, with glibc | ~25 MB |
| `gcr.io/distroless/java17-debian12` | Java apps | ~200 MB |
| `gcr.io/distroless/python3-debian12` | Python apps | ~50 MB |
| `gcr.io/distroless/nodejs20-debian12` | Node.js apps | ~150 MB |

For most languages, there's a distroless variant. For languages without one, use `cc` (with the runtime) or `base`.

### 4.2 The "no shell" problem

A distroless container has no shell. `kubectl exec -it <pod> -- sh` fails. This is **by design** — a shell is an attack vector. But it makes debugging harder.

Workarounds:

* **Debug images** — a sidecar with a full image (Ubuntu, etc.) for debugging. Switch to it temporarily.
* **kubectl debug** (k8s 1.20+) — creates an ephemeral debug container with a full image, sharing the Pod's volumes.
* **Init containers** — for setup that needs a shell, use a regular image as an init.

The standard pattern:

```yaml
# in the Pod
containers:
- name: app
  image: gcr.io/distroless/static-debian12
  # ... no shell
- name: debug       # only for debug builds
  image: alpine
  # ... with shell
```

The `debug` container is for development. In production, only `app` is deployed.

## 5. The "scratch" Image

The `scratch` image is **empty**. It's the "no base image" base. Used for static binaries that don't need libc:

```dockerfile
FROM golang:1.22 AS build
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 go build -o myapp

FROM scratch
COPY --from=build /app/myapp /
COPY --from=build /etc/ssl/certs /etc/ssl/certs
ENTRYPOINT ["/myapp"]
```

The final image is **just the binary** + certs. Size: ~5-10 MB. No shell, no libraries, no nothing.

**The `scratch` image is for static binaries only.** Go with `CGO_ENABLED=0` produces a static binary. Rust with `musl` target is static. C / C++ can be static with the right flags.

For dynamic binaries (most Java, Python, Node.js), you can't use `scratch` — you need a base with the runtime.

## 6. Multi-Stage Builds

*"https://docs.docker.com/develop/develop-images/multistage-build/"*

A **multi-stage build** uses **two or more `FROM`s** in a Dockerfile. The earlier stages are for building; the later stages are for the final image.

```dockerfile
# Stage 1: build
FROM golang:1.22 AS build
WORKDIR /app
COPY . .
RUN go build -o myapp

# Stage 2: runtime
FROM gcr.io/distroless/static-debian12
COPY --from=build /app/myapp /
CMD ["/myapp"]
```

The final image has only the `myapp` binary. The `golang:1.22` image (with the compiler) is not in the final image.

The benefits:

* **Smaller final image** — only the runtime, not the build tools.
* **Fewer vulnerabilities** — the compiler, headers, dev packages are not in the final image.
* **No leaked secrets** — secrets used in `RUN` (e.g. `pip install` with credentials) are in the build stage, not the final image.

The cost: the build is in one image, the runtime in another. Slightly more complex Dockerfile.

For most production apps, **multi-stage is the standard**.

## 7. The Image Vulnerability Scanner

Image scanners check the image's packages against **vulnerability databases** (CVE feeds). They report what's vulnerable.

Tools:

* **Trivy** — open source, scans OS packages + language deps. The most popular.
* **Grype** — open source, similar to Trivy. Anchore.
* **Snyk** — commercial, integrates with CI/CD.
* **Clair** — open source, used by Quay.
* **Docker Scout** — Docker's built-in scanner.
* **ECR Scan** — AWS's scanner (uses Clair under the hood).

The standard flow:

```
Build image
  │
  ▼
Scan with Trivy
  │
  ├── CRITICAL CVEs → block the build
  ├── HIGH CVEs → warn, don't block
  └── LOW / MEDIUM → log
  │
  ▼
Push to registry (if passed)
```

The scanner runs in CI (before the push) or in the registry (after the push). CI is preferred — block before the image is published.

### 7.1 The Trivy example

```bash
trivy image myapp:1.0
# shows: vulnerabilities, by severity, by package
```

In CI:

```yaml
# GitHub Actions example
- name: Scan image
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: myapp:1.0
    severity: 'CRITICAL,HIGH'
    exit-code: '1'   # fail the build on CRITICAL or HIGH
```

## 8. Image Signing (cosign, Notary)

*"https://docs.sigstore.dev/cosign/overview/"*

**Image signing** is the practice of cryptographically signing an image so consumers can verify the publisher. It's the **integrity** part of the supply chain.

**Cosign** (from Sigstore) is the modern tool:

```bash
# generate a keypair
cosign generate-key-pair

# sign an image
cosign sign --key cosign.key myapp:1.0

# verify
cosign verify --key cosign.pub myapp:1.0
```

The signature is stored in the registry (as a separate artifact). When the cluster pulls the image, it can verify the signature.

**Notary** (Docker's tool) is the older alternative. It's being deprecated in favor of cosign.

### 8.1 The verification at admission

The image is verified at admission (or at pull):

* **Kyverno** has a `verifyImages` rule that checks cosign signatures.
* **Connaisseur** is a dedicated admission controller for image verification.
* **Cosign's own admission controller** can be deployed as a webhook.

The flow:

```
Pod creation → admission
  │
  ▼
Verify image signature
  │
  ├── Valid signature from trusted key → allow
  └── Invalid signature / unsigned → reject
```

A Pod with an unsigned image is rejected. **Only signed images run**.

### 8.2 The key management

The signing key is the trust root. Where it lives:

* **Local file** — on the CI machine. The CI signs, the cluster verifies with the public key.
* **KMS** — AWS KMS, GCP KMS, etc. The key never leaves the KMS.
* **Sigstore's "keyless"** — uses ephemeral keys tied to an OIDC identity (e.g. GitHub Actions, Google Accounts). The signature is tied to the identity, not a long-lived key.

The "keyless" mode is the modern approach. **No long-lived keys to manage.** The signature is verified against an OIDC token.

## 9. The "Trusted Registry" Pattern

Limit which registries the cluster pulls from. Without restriction, a Pod can pull from any public registry (including malicious ones).

The enforcement:

* **Admission policy** (Kyverno / OPA) — reject Pods whose images are not from allowed registries.
* **ImagePolicyWebhook** (built-in, deprecated) — the older mechanism. Use admission policies instead.

```yaml
# Kyverno policy
- name: approved-registries
  match:
    any:
    - resources:
        kinds: ["Pod"]
  validate:
    message: "images must come from approved registries"
    pattern:
      spec:
        containers:
        - name: "?*"
          image: "gcr.io/my-project/* | 1234.dkr.ecr.us-east-1.amazonaws.com/*"
```

Only images from the approved registries are allowed. A Pod pulling from `docker.io/library/nginx` is rejected.

The standard:

* **Production** — only the org's private registry (ECR, GCR, Harbor, etc.).
* **Dev / test** — same plus a curated list of public registries (Docker Hub official, gcr.io/distroless, etc.).

## 10. SBOM (Software Bill of Materials)

*"https://www.cisa.gov/sbom"*

An **SBOM** is a list of all the components in an image. It's the "ingredient list". For each component:

* Name, version, license.
* Supplier.
* Dependencies.

The formats:

* **SPDX** — Linux Foundation's standard.
* **CycloneDX** — OWASP's standard.
* **Syft** generates SBOMs from images.

```bash
# generate an SBOM
syft myapp:1.0 -o spdx-json > myapp.spdx.json
```

SBOMs are required for:

* **Compliance** — auditors want to know what's in the image.
* **Vulnerability management** — when a new CVE is announced, you can find all affected images.
* **Supply chain** — the SBOM is the basis for the Software Supply Chain attestation (in-toto, SLSA).

The shift: every image should have an SBOM. The SBOM is published alongside the image (e.g. as a separate artifact in the registry).

## 11. Common CVEs and Their Fixes

Some CVEs are so common they have a pattern:

### 11.1 Log4Shell (CVE-2021-44228, CVE-2021-45046)

**Vulnerability**: `log4j` allowed remote code execution via JNDI lookups in log messages.

**Fix**: Update `log4j` to 2.17.1+. Or remove the `JndiLookup.class` from the classpath.

**Detection**: scan images for vulnerable `log4j-core` versions.

### 11.2 Spring4Shell (CVE-2022-22965)

**Vulnerability**: Spring Framework RCE via data binding.

**Fix**: Update Spring to 5.3.18+ or 5.2.20+.

### 11.3 Heartbleed (CVE-2014-0160)

**Vulnerability**: OpenSSL heartbeat extension leaked memory.

**Fix**: Update OpenSSL. (Ancient, but the pattern holds.)

### 11.4 The general pattern

* **OS package CVEs** — update the base image, rebuild.
* **Language runtime CVEs** — update the runtime (e.g. `python:3.12` instead of `python:3.10`).
* **Library CVEs** — update the library (`flask`, `requests`, etc.) in `requirements.txt`.
* **Application CVEs** — fix the application code.

**Rebuild the image frequently.** A `latest` tag in production is bad; a `latest` rebuild in CI is the answer.

## 12. The "no :latest" rule

`image: myapp:latest` is a footgun. Every pull gets the newest image. A "newest" can have a new vulnerability.

The standard:

* **Tag with version** — `image: myapp:1.2.3` (semver).
* **Tag with git SHA** — `image: myapp:abc1234` (the commit SHA).
* **Tag with build ID** — `image: myapp:build-4567` (the CI build ID).

The image is **immutable** per tag. A `1.2.3` always points to the same image (after publish).

For **rollbacks**: deploy the previous tag. The previous image is still in the registry.

For **continuous deployment**: tag with the git SHA, not `latest`. The image is reproducible.

## 13. Image Pull Policy and Caching

The `imagePullPolicy`:

* **`Always`** — pull every time. The image is fetched on every Pod start.
* **`IfNotPresent`** — pull only if the image is not on the node.
* **`Never`** — never pull. Use the local image.

The default:

* `Always` for `:latest` tags.
* `IfNotPresent` for other tags.

For production:

* **Tag with version** — `IfNotPresent` is the default. Good.
* **Tag with `latest`** — `Always` is the default. **Avoid `latest`**.

### 13.1 The kubelet's image cache

The kubelet caches images on the node's disk (`/var/lib/containerd/...` or similar). The cache is shared across all Pods on the node.

The cache can fill up. Watch the node's `allocatable.ephemeral-storage` and `used`. If the cache fills, the kubelet evicts old images (LRU).

## 14. Operations and Debugging

### 14.1 Common commands

```bash
# inspect an image's layers
docker history myapp:1.0
# or
dive myapp:1.0    # interactive, shows layer diffs

# scan an image
trivy image myapp:1.0

# check the SBOM
syft myapp:1.0

# check a Pod's image
kubectl get pod <pod> -o jsonpath='{.spec.containers[*].image}'

# check a Pod's image pull policy
kubectl get pod <pod> -o jsonpath='{.spec.containers[*].imagePullPolicy}'

# on the node, check the image cache
crictl images
```

### 14.2 The "image pull failing" case

A Pod is `ImagePullBackOff`.

```bash
# 1. Check the Pod's events
kubectl describe pod <pod>
# look for: "Failed to pull image", "unauthorized", "image not found"

# 2. Check the image name
kubectl get pod <pod> -o jsonpath='{.spec.containers[*].image}'
# typo in the name?

# 3. Check the registry credentials
# (for private registries)
kubectl get secret -n <ns>
# is there a dockerconfigjson secret?

# 4. Check the network
# can the node reach the registry?
curl https://gcr.io/v2/
# or
docker pull gcr.io/my-project/myapp:1.0
```

### 14.3 The "image is too large" case

A Pod's image is 1 GB. The image pull takes 5 minutes. The node's disk fills up.

```bash
# 1. Check the image size
docker image ls myapp:1.0

# 2. Use a smaller base (alpine, distroless, scratch)
# 3. Multi-stage build
# 4. Remove unnecessary files in the Dockerfile
# 5. Check the cache — large layers may be unnecessary
```

## 15. Gotchas and Common Mistakes

### 15.1 The 30+ common mistakes

1. **The base image is the biggest layer.** Choose carefully. `ubuntu` is 70 MB; `distroless` is 2-20 MB; `scratch` is 0.

2. **A `RUN apt-get update` without `&& rm -rf /var/lib/apt/lists/*`** keeps the apt cache. The image is larger than necessary.

3. **A `RUN` with multiple commands is one layer.** Combine to reduce layers. But too much in one `RUN` makes the image hard to maintain.

4. **A `COPY . .` copies the build context, including `node_modules`, `.git`, etc.** Use `.dockerignore`.

5. **A `latest` tag is not a version.** Don't use it in production.

6. **Image signing without verification is useless.** Sign, then verify at admission.

7. **The signing key is the trust root.** Lose the key, lose the trust. Use KMS or keyless.

8. **A scanner that runs only at build time misses later CVEs.** A CVE published yesterday isn't in yesterday's scan. Re-scan periodically.

9. **A scanner that only checks OS packages misses language deps.** Use a scanner that covers both (Trivy, Snyk, Grype).

10. **A `distroless` image has no shell.** Debugging is harder. Use `kubectl debug` or a sidecar.

11. **A `scratch` image has no `ca-certificates`.** HTTPS calls fail. Add the certs to the image.

12. **A `scratch` image has no `/etc/passwd`.** `runAsNonRoot: true` can't find a non-root user. Add a `passwd` file.

13. **A multi-stage build is more complex.** Worth it for production.

14. **Image caching is per-node.** A new image on 100 nodes = 100 pulls. The kubelet does them in parallel.

15. **An admission policy that rejects all but approved registries is strict.** Some legitimate use cases (debug images, init containers with curl) may need exceptions.

16. **SBOMs are large.** Storing them as image artifacts inflates the registry.

17. **The `imagePullPolicy: Always` is wasteful for versioned tags.** Default is `IfNotPresent` for versioned tags.

18. **The `imagePullPolicy: Never` requires the image to be pre-pulled.** Useful for air-gapped clusters.

19. **A vulnerability in the base image affects every Pod that uses it.** A common CVE in `ubuntu:22.04` affects every Ubuntu-based image.

20. **Re-building the image frequently is the answer to most CVEs.** Not "use a different base" — rebuild with the latest patched base.

21. **An image with `ARG` exposed in the env is a leak.** Use `ARG` only for build-time; `ENV` for runtime.

22. **A `USER root` in the Dockerfile is a default.** Many base images default to root. Add `USER nonroot` or `USER 1000`.

23. **A `WORKDIR` doesn't change the user.** Combine with `USER`.

24. **An `EXPOSE` in the Dockerfile is documentation, not enforcement.** It doesn't actually open ports.

25. **A `HEALTHCHECK` in the Dockerfile is the container's health check.** It's overridden by the Pod's `livenessProbe` / `readinessProbe` if defined.

26. **The `entrypoint` and `cmd` in the Dockerfile are defaults.** The Pod's `command` and `args` override them.

27. **A `COPY` with `--chown=nonroot:nonroot` changes ownership.** Saves a `chown` in `RUN`.

28. **An `ADD` with a URL is a security risk.** Use `RUN curl ... | tar -x` if you must, but `COPY` from the build context is safer.

29. **The build cache is local to the daemon.** A `docker build` in CI starts from scratch. A `BuildKit` cache can be remote (S3, etc.).

30. **A scanned image can still have a CVE at runtime.** The CVE was published after the scan. The defense is **continuous rescanning** + image rotation.

## See also

* [[Kubernetes/concepts/L07-security/06-pod-security-standards|PSS]] — the runtime enforcement
* [[Kubernetes/concepts/L07-security/12-kyverno|Kyverno]] — for image signature verification
* [[Kubernetes/concepts/L07-security/11-opa-gatekeeper|OPA / Gatekeeper]] — alternative policy engine
* [[Kubernetes/concepts/L07-security/18-runtime-detection|Runtime Detection]] — detect what's not prevented
