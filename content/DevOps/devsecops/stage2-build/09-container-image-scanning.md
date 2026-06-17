---
title: "M09: Container Image Scanning & Hardening"
tags: [devsecops, stage2, build, containers, docker, distroless, trivy, grype, hardening]
date: 2026-06-16
description: "Module 9 of 20 — building and scanning container images. Multi-stage builds, distroless/minimal bases, non-root users, image scan gates, and the diff between the developer Dockerfile and the production image."
---

# M09: Container Image Scanning & Hardening

The container image is the unit of deployment. Every vulnerability in the image ships to production. This module covers building lean images (less surface area = fewer vulns), hardening what you build, and gating the image at every checkpoint. The 80/20 of image security is in the Dockerfile, not the scanner.

## Learning Objectives

By the end of this module you should be able to:

  - Build a hardened image (distroless, non-root, no shell) using a multi-stage build
  - Run an image scan (Trivy, Grype) and interpret the findings by layer
  - Set an image-scan policy that fails the build on critical CVEs
  - Distinguish OS-package vulns from application-dependency vulns
  - Implement a base-image update strategy
  - Map CIS Docker Benchmark controls onto a Dockerfile

## 1. The Image Is a Dependency Graph

A container image is a stack of layers. Each layer is a filesystem delta. Vulnerabilities live in those layers.

```
+------------------+
|   Your app       |  (your code, your deps)
+------------------+
|   Runtime        |  (e.g., python:3.12-slim, node:20)
+------------------+
|   OS packages   |  (apt, apk, dnf installed)
+------------------+
|   Base image    |  (debian:bookworm, alpine:3.20)
+------------------+
```

A typical application image has 50–500 installed packages. Of those, 30% are pulled in by the base image and never used by your app. Each one is a potential CVE.

The fix: use minimal bases (distroless, alpine, scratch) and only install what you need.

## 2. The Dockerfile Patterns

### Multi-Stage Builds

The single biggest security improvement you can make to a Dockerfile. Compile in one stage with full toolchain; copy only the artifact to a minimal runtime stage.

```dockerfile
# ---- Build stage ----
FROM golang:1.22-bookworm AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/app ./

# ---- Runtime stage ----
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/app /app
USER nonroot:nonroot
ENTRYPOINT ["/app"]
```

What the runtime stage contains:
  - The compiled binary
  - CA certificates (from `gcr.io/distroless/static-debian12` base)
  - `/etc/passwd` with a `nonroot` user
  - Nothing else

Total image size: ~10 MB. Total packages: 0 (the runtime has no shell, no package manager).

### Base Image Tier List

```
Most secure                                                    Least secure
   |                                                              |
   v                                                              v
scratch > distroless > alpine > debian-slim > debian > ubuntu > full distro
```

| Base | Size | Vuln count (typical) | Use case |
| ---- | ---- | -------------------- | -------- |
| scratch | 0 MB | 0 | Static binaries (Go, Rust) |
| distroless/static | ~2 MB | 0–2 | Go, Rust, C++ |
| distroless/base | ~20 MB | 10–20 | JVM, Python with C extensions |
| alpine | ~5 MB | 0–5 | Anything with a libc; watch for musl issues |
| debian-slim | ~80 MB | 30–50 | When alpine/distroless is not viable |
| debian | ~120 MB | 50–100 | Avoid |
| ubuntu | ~300 MB | 100+ | Avoid for production |

Pick the smallest base that runs your app. The size is a proxy for attack surface; smaller is better.

### The "FROM scratch" Pattern (Static Binaries)

For Go, Rust, Zig, and other languages that produce static binaries:

```dockerfile
FROM golang:1.22-bookworm AS build
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /out/app ./

FROM scratch
COPY --from=build /out/app /app
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
ENTRYPOINT ["/app"]
```

The final image has no shell, no package manager, no /etc/passwd. There is nothing to attack. The trade-off: no `docker exec` for debugging, no `apt` for emergency patches. For production, that's a feature.

## 3. Hardening Knobs in the Dockerfile

```dockerfile
# 1. Pin the base image by digest, not tag
FROM [email protected]:abc123... AS build
# Tags are mutable. Digests are not. A new CVE may not change the digest,
# but a malicious re-publish would.

# 2. Set a non-root user
RUN adduser --system --no-create-home --uid 10001 appuser
USER 10001

# 3. Read-only filesystem at runtime (compose/k8s enforces)
# In Dockerfile: avoid storing state in /tmp or /var; design for RO_ROOT

# 4. No secrets in the build context
# Use BuildKit secrets:
# RUN --mount=type=secret,id=npmrc,target=/root/.npmrc npm ci
# (secrets are mounted at build time, not baked into layers)

# 5. Drop capabilities
# (in compose/k8s, not Dockerfile)
# securityContext:
#   capabilities:
#     drop: ["ALL"]
#   readOnlyRootFilesystem: true
#   runAsNonRoot: true
#   runAsUser: 10001

# 6. Set a HEALTHCHECK
HEALTHCHECK --interval=30s --timeout=3s \
  CMD wget -qO- http://localhost:8080/healthz || exit 1

# 7. Declare EXPOSE for documentation; do not bind privileged ports
EXPOSE 8080
```

## 4. Image Scan Tools

### Trivy (the default)

```bash
# Scan a local image
trivy image my-app:v1.2.3

# Fail on critical vulns
trivy image --severity CRITICAL --exit-code 1 my-app:v1.2.3

# Output SARIF for GitHub Security tab
trivy image --format sarif --output trivy.sarif my-app:v1.2.3

# Scan a remote registry
trivy image registry.example.com/my-app:v1.2.3
```

Output is grouped by:
  - OS packages (apt/apk/dnf)
  - Language packages (npm, pip, gem, jar)
  - Misconfigurations (Dockerfile)
  - Secrets (in image layers)
  - License issues

### Grype (Anchore)

```bash
# Install
brew install grype

# Scan
grype my-app:v1.2.3

# Output SARIF
grype my-app:v1.2.3 -o sarif
```

Grype reads SBOMs directly — pair with Syft for fast incremental scans.

### Docker Scout

Built into Docker Desktop. Good UX, integrates with Docker Hub. Limited to Docker ecosystem.

### Snyk Container

Commercial, deep analysis, good fix-recommendations. Free tier for OSS.

## 5. Reading an Image Scan Report

A typical Trivy report:

```
my-app:v1.2.3 (debian 12.4)
==============================
Total: 47 (CRITICAL: 2, HIGH: 12, MEDIUM: 28, LOW: 5)

CRITICAL
--------
CVE-2024-12345  libssl3  3.0.11-1~deb12u1 → 3.0.13-1~deb12u1
  /usr/lib/x86_64-linux-gnu/libssl.so.3
  pkgPath: libssl3 → openssl → base layer
  Fix: update base image to [email protected]:... or apply apt update

HIGH
----
CVE-2024-67890  libcurl4  8.4.0-1 → 8.5.0-1
  ...
```

The actionable parts:
  - The `pkgPath` tells you *why* the package is there (base image, runtime, your dep)
  - The `Fix` line tells you what to do
  - The `Severity` tells you whether to drop everything

For 80% of CVEs in a typical image, the fix is "bump the base image." Module M07's Renovate/Dependabot handles application deps; the base image is a separate concern.

## 6. The Base Image Update Strategy

Base images go stale fast. A `debian:bookworm` from January 2024 has different CVE counts than one from December 2024. Strategies:

### Strategy 1: Pin and Update Quarterly

```dockerfile
FROM [email protected]:abc123... AS build
```

Quarterly review: scan the latest `debian:bookworm`, compare CVE counts, bump if the diff is meaningful. Document the bump in a CHANGELOG entry.

### Strategy 2: Renovate for Base Images

Renovate can watch Docker Hub for new base image tags and open PRs.

```json5
{
  "packageRules": [
    {
      "matchDatasources": ["docker"],
      "matchPackageNames": ["node", "python", "golang", "debian"],
      "schedule": ["before 6am on monday"],
      "automerge": true
    }
  ]
}
```

Caveat: Renovate opens the PR but does not run image scans on the resulting image. You need a CI step that re-builds and re-scans.

### Strategy 3: Distroless + Auto-Rebuild

Distroless images are rebuilt on every Google base-image update. Subscribe to the distroless-announce mailing list or watch the GitHub repo. When a new tag drops, rebuild and re-scan.

## 7. Scan Gates in the Pipeline

```
Source → Build → [Image scan] → [Sign] → [Registry] → [Admission scan] → [Deploy]
            |          |            |          |              |              |
            |       fail:critical  sign       tag         fail:critical   run
            |       fail:high*    cosign    digest        fail:high*
            |
            * = configurable
```

Three scan points, each with a different purpose:

### Build-Time Scan
Catches vulns before the image is pushed. Fast feedback. Fails the build on critical; warns on high (or fails, depending on policy).

### Pre-Deploy Scan (Admission Controller)
Re-scans the image at deploy time. Catches the case where a CVE was disclosed between build and deploy. Tools: Kyverno, Connaisseur, Ratify, Notary v2.

### Continuous Re-Scan
Re-scans images in the registry on every vuln-DB update. Tools: Trivy Operator (K8s), Snyk, JFrog Xray.

## 8. CIS Docker Benchmark → Dockerfile

The CIS Docker Benchmark is a 100+ item checklist. Most items are runtime (enforced by k8s/compose), not Dockerfile. The Dockerfile-relevant subset:

| CIS ref | Control | Dockerfile pattern |
| ------- | ------- | ------------------ |
| 4.1 | Create a user for the container | `USER 10001` |
| 4.2 | Use trusted base images | Pin to a digest, prefer distroless |
| 4.3 | Do not install unnecessary packages | `apk add --no-cache <only-what-you-need>` |
| 4.4 | Pin packages to specific versions | `apk add [email protected]` |
| 4.5 | Remove setuid/setgid bits | `RUN find / -xdev -perm /6000 -type f -exec chmod a-s {} \;` |
| 4.6 | Use COPY instead of ADD | `COPY` doesn't fetch URLs or extract tarballs |
| 4.7 | Do not use `update` without `install` | `apt-get install -y` (no `apt-get update` alone) |
| 4.8 | Use multi-stage builds | See above |
| 4.9 | Do not store secrets in Dockerfile | Use BuildKit secrets, not ENV |
| 4.10 | Use HEALTHCHECK | Add HEALTHCHECK |

The other 90+ items are enforced at runtime (compose, k8s securityContext, pod security standards).

## 9. Image Provenance

When you scan an image, you want to know *where it came from*. Provenance is the metadata that answers: which source commit, which build, which CI run.

  - **SLSA Level 1** — provenance exists (build script recorded)
  - **SLSA Level 2** — provenance is signed and verified (SLSA + Sigstore)
  - **SLSA Level 3** — provenance is generated by a hardened build platform (e.g., GitHub Actions, Tekton Chains)

Module M14 covers provenance in depth.

## 10. Image Scan Anti-Patterns

| Anti-pattern | Symptom | Fix |
| ------------ | ------- | --- |
| Scan only on push | Misses new CVEs | Continuous re-scan |
| Use the `latest` tag | Image mutates, scan results lie | Pin to a digest |
| Allow criticals with no SLA | Vulns age out | SLA: critical in 7d, high in 30d |
| "We'll fix it in the next sprint" (forever) | Backlog of 200 criticals | Track per-finding, not in aggregate |
| Scan only the final image | Miss the build-time base | Scan the build stage too (multi-stage) |
| Allow root in the Dockerfile | Compromise = root in container | `USER 10001` non-negotiable |

## 11. The 1-Week Image Hardening Plan

  - **Day 1** — Scan every production image with Trivy. Sort by critical count. Pick the worst.
  - **Day 2** — Convert that image to multi-stage. Use distroless or alpine.
  - **Day 3** — Add `USER 10001`. Add `HEALTHCHECK`. Drop capabilities in the runtime config.
  - **Day 4** — Add image scan to the build pipeline. Fail on critical.
  - **Day 5** — Pin the base image to a digest. Set up Renovate for base images.
  - **Day 6** — Re-scan the new image. Document the CVE-count reduction.
  - **Day 7** — Repeat for the next-worst image. By the end of the quarter, all images pass.

## 12. Self-Check

  1. Pick your largest production image. Run `trivy image <name>`. How many critical vulns? Of those, how many are in the base layer?
  2. Does your Dockerfile use multi-stage builds? If not, what's the runtime image size?
  3. Does your image run as root? If yes, what's the blast radius of a container escape?

## 13. The Runtime Image: Beyond the Build

The build produces the image. The runtime is what matters. The runtime configuration is separate from the image:

### Kubernetes SecurityContext

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        fsGroup: 10001
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: my-app
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          resources:
            limits:
              cpu: "1"
              memory: "512Mi"
            requests:
              cpu: "100m"
              memory: "128Mi"
```

The `securityContext` at the pod and container level enforces what the image *should* have set in its Dockerfile. The image sets the defaults; the runtime enforces the floor.

### Pod Security Standards

K8s has three Pod Security Standards:

  - **Privileged** — no restrictions (avoid for production)
  - **Baseline** — prevents known privilege escalations (default for most clusters)
  - **Restricted** — hardened, follows least privilege (target for production)

Set at the namespace level:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

A workload that violates `restricted` cannot run in the `production` namespace. The image must be hardened *or* the workload must be moved to a less-restricted namespace (with documented justification).

## 14. Image Provenance and Reproducible Builds

A reproducible build is one that, given the same source, produces the same bit-for-bit artifact. Reproducibility is a supply-chain property:

  - The customer can verify "this binary came from this source"
  - The auditor can verify "this build was performed by this CI"
  - The bit-for-bit identity enables content-addressable storage

### Reproducible Build Steps

  - **Pin all sources** — exact commit, exact dep version
  - **Set timestamps** — `SOURCE_DATE_EPOCH` env var
  - **Sort filesystem operations** — tar with `--sort=name`
  - **Strip build paths** — `-trimpath` for Go, `-fdebug-prefix-map` for C
  - **Lock the build environment** — same Go version, same libc, same OS

### Tools

  - **reproducible-builds.org** — community resources
  - **diffoscope** — diff two artifacts to find non-reproducible parts
  - **in-toto** — attestation that ties the build to the source

Reproducible builds are not required for most orgs but are required for high-assurance supply chains (FedRAMP High, defense, financial regulators). M14 covers the broader provenance story.

## 15. Image Signing in the Build Pipeline

The cosign integration with common build tools:

### BuildKit (Docker buildx)

```yaml
- name: Build and sign
  uses: docker/build-push-action@v5
  with:
    context: .
    push: true
    tags: ghcr.io/my-org/my-app:${{ github.sha }}
    provenance: true
    sbom: true
    sign: true  # requires cosign keyless
```

### Kaniko

```bash
# Build with kaniko
kaniko --context . --destination ghcr.io/my-org/my-app:$SHA

# Sign after build
cosign sign --yes ghcr.io/my-org/my-app@$DIGEST
```

### Buildah

```bash
buildah bud -t my-app:$SHA .
buildah push my-app:$SHA
cosign sign --yes my-app@$DIGEST
```

M13 covers the signing in depth; this module is the integration with the build.

## 16. The Container Image Supply Chain

The full supply chain for a container image:

```
  Source code (git)
       |
       v
  Dependencies (lockfile)
       |
       v
  Build (Dockerfile)
       |
       v
  Base image (digest)
       |
       v
  Image (digest)
       |
       v
  Signature (cosign)
       |
       v
  SBOM (Syft)
       |
       v
  Provenance (SLSA)
       |
       v
  Registry (OCI)
       |
       v
  Deploy (admission control)
       |
       v
  Runtime (K8s)
       |
       v
  Observability (logs, metrics, traces)
```

Each step produces evidence. Each step is auditable. The supply chain is a *chain of custody* for the artifact.

## 17. Image Security in Regulated Environments

FedRAMP, PCI-DSS, HIPAA, and similar frameworks have specific image requirements:

| Requirement | Implementation |
| ----------- | -------------- |
| FIPS-compliant crypto | Build with BoringSSL / OpenSSL FIPS |
| No privileged containers | K8s securityContext, PodSecurity |
| Read-only root filesystem | K8s securityContext, distroless image |
| Encrypted at rest | KMS-encrypted container registry |
| Audit logging | Falco + Wazuh (M17) |
| Vulnerability scanning | Trivy daily re-scan |
| Image signing | cosign + Kyverno (M13, M15) |
| No SSH in container | `RUN rm` the SSH client; distroless has no SSH |

The pipeline you build for FedRAMP satisfies most other frameworks. The cost of a hardened image pipeline is one-time; the benefit is permanent compliance.

## 18. Image Hardening ROI

The cost of a vulnerable image:

  - **Vuln re-scan cost** — every image scanned daily; if the image is bloated, the scan is slower
  - **Patch frequency** — a 500-package image needs patches more often than a 5-package image
  - **Incident likelihood** — more code = more potential vulns = more incidents
  - **Audit cost** — auditors ask "how many CVEs in your images?" A clean answer is fast; a long list is slow

The cost of a hardened image:

  - **Initial effort** — multi-stage build, base image selection
  - **Compatibility** — some apps don't run on alpine (musl vs. glibc)
  - **Debugging** — no shell in the container; you cannot `docker exec` to debug

The ROI: the initial effort is days; the ongoing savings are years.

## Related

  - [[DevOps/devsecops/stage1-code/07-sca-dependency-scanning|M07: SCA & Dependency Scanning]]
  - [[DevOps/devsecops/stage1-code/08-sbom-generation|M08: SBOM Generation]]
  - [[DevOps/devsecops/stage2-build/10-iac-security|M10: IaC Security]]
  - [[DevOps/devsecops/stage2-build/11-cicd-pipeline-hardening|M11: CI/CD Pipeline Hardening]]
  - [[DevOps/devsecops/stage2-build/README|Stage 2 — Build]]
