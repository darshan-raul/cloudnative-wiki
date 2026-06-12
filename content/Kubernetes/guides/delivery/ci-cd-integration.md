---
title: CI/CD Integration
tags:
  - Kubernetes
  - Delivery
  - CI/CD
  - GitHub Actions
  - GitLab CI
  - BuildKit
  - Kaniko
---

How CI/CD systems integrate with k8s. The CI does the build/test/scan/push; the GitOps controller does the deploy. This covers the patterns, the secrets handling, the image registry, and the common tools.

## The architecture

```
┌─────────────────┐      ┌──────────────────┐      ┌──────────────────┐
│  Source         │      │  CI              │      │  Registry        │
│  (GitHub)       │ ──>  │  (GitHub Actions)│ ──>  │  (ECR/GCR/ACR)   │
│                 │      │                  │      │                  │
│  - code         │      │  - test          │      │  - image:tag     │
│  - Dockerfile   │      │  - build         │      │                  │
│  - manifest     │      │  - scan          │      │                  │
└─────────────────┘      │  - sign          │      └──────────────────┘
                         │  - push          │
                         └────────┬─────────┘
                                  │ update git
                                  ↓
                         ┌──────────────────┐
                         │  GitOps repo     │
                         │  (kustomize)     │
                         │                  │
                         │  - new image tag │
                         └────────┬─────────┘
                                  │ sync
                                  ↓
                         ┌──────────────────┐
                         │  Argo CD / Flux  │
                         └────────┬─────────┘
                                  │ apply
                                  ↓
                         ┌──────────────────┐
                         │  Cluster         │
                         │  (k8s)           │
                         └──────────────────┘
```

**CI's job:** test, build, scan, sign, push image, update git.
**GitOps controller's job:** sync git to cluster.

## Image building

### Kaniko (build without Docker daemon)

```dockerfile
FROM golang:1.21 AS builder
WORKDIR /app
COPY . .
RUN go build -o myapp

FROM gcr.io/distroless/static-debian12
COPY --from=builder /app/myapp /myapp
ENTRYPOINT ["/myapp"]
```

```yaml
# GitHub Actions
- name: Build and push
  uses: gabriel-vasile/kustomize-action@1.0.0
  with:
    images: |
      myregistry/myapp=${{ env.IMAGE_TAG }}
```

```yaml
# In CI
- name: Build with kaniko
  uses: aevea/action-kaniko@v1
  with:
    image: myregistry/myapp:${{ github.sha }}
    registry: myregistry.example.com
    username: ${{ secrets.REGISTRY_USER }}
    password: ${{ secrets.REGISTRY_PASS }}
    build-args: |
      VERSION=${{ github.sha }}
```

Or use BuildKit:

```yaml
- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3

- name: Build and push
  uses: docker/build-push-action@v5
  with:
    context: .
    push: true
    tags: myregistry/myapp:${{ github.sha }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

**Kaniko vs Buildx vs Docker-in-Docker:**

| | Kaniko | Buildx | DinD |
|---|--------|--------|------|
| **Daemon** | None | None (uses buildkit) | Docker daemon |
| **Privileges** | None | None | Needs privileged |
| **Performance** | Good | Excellent | Best |
| **Multi-arch** | Yes | Yes (with QEMU) | Yes |
| **Caching** | Yes (registry, GCS, S3) | Yes (registry, GHA cache) | Local cache |
| **Complexity** | Medium | Low | High |

**For most:** Buildx is the right choice. Kaniko when you can't use Buildx (unprivileged, restricted env).

### BuildKit (best performance)

```yaml
- name: BuildKit
  uses: docker/setup-buildx-action@v3

- name: Build
  uses: docker/build-push-action@v5
  with:
    context: .
    push: true
    tags: myregistry/myapp:${{ github.sha }}
    cache-from: type=registry,ref=myregistry/myapp:cache
    cache-to: type=registry,ref=myregistry/myapp:cache,mode=max
```

**BuildKit features:**
- Parallel build steps
- Better layer caching
- Multi-arch builds (`--platform linux/amd64,linux/arm64`)
- Secret mounting without `ARG` (safer)
- SSH agent forwarding

## Image scanning

```yaml
- name: Scan with Trivy
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: myregistry/myapp:${{ github.sha }}
    format: 'table'
    exit-code: '1'   # fail build on HIGH/CRITICAL
    ignore-unfixed: true
    vuln-type: 'os,library'
    severity: 'CRITICAL,HIGH'
```

Other scanners:
- **Grype** (`anchore/scan-action`) — Anchore, fast
- **Snyk** (`snyk/actions/docker`) — commercial
- **Docker Scout** — built into Docker Hub
- **Clair** — Quay

**What to scan for:** CRITICAL and HIGH vulnerabilities. Lower often has too many false positives.

## Image signing (cosign)

```yaml
- name: Install cosign
  uses: sigstore/cosign-installer@v3

- name: Sign image
  env:
    COSIGN_KEY: ${{ secrets.COSIGN_KEY }}
    COSIGN_PASSWORD: ${{ secrets.COSIGN_PASSWORD }}
  run: |
    cosign sign --yes myregistry/myapp:${{ github.sha }}

- name: Verify signature
  run: |
    cosign verify --certificate-identity-regexp '.*' myregistry/myapp:${{ github.sha }}
```

**Cosign** (Sigstore) signs images. Kyverno/Conftest can enforce "only signed images run" in the cluster.

## Updating git from CI

After image is built, CI updates the GitOps repo to point to the new image.

### Using kustomize

```yaml
- name: Update kustomize image
  working-directory: gitops/overlays/prod
  run: |
    kustomize edit set image myregistry/myapp=myregistry/myapp:${{ github.sha }}
    git diff
    git config user.email "ci@example.com"
    git config user.name "CI Bot"
    git add -A
    git commit -m "ci: bump myapp to ${{ github.sha }}"
    git push
```

### Using sed

```bash
sed -i "s|tag: .*|tag: ${{ github.sha }}|" gitops/overlays/prod/kustomization.yaml
```

Quick and dirty. Use kustomize edit for safety.

### Using yq

```bash
yq -i ".images[0].newTag = \"${{ github.sha }}\"" gitops/overlays/prod/kustomization.yaml
```

## The secrets problem

CI has access to many secrets. Don't leak them.

### Common secrets

- **Registry credentials** (push images)
- **Cloud credentials** (deploy)
- **Git credentials** (push to gitops repo)
- **Test secrets** (run integration tests)
- **Signing keys** (cosign)

### Best practices

- **OIDC from cloud** (AWS, GKE, Azure) — no static creds
- **Short-lived tokens** for everything
- **Use repo Secrets** for sensitive values
- **Audit logs** in CI for who accessed what

### GitHub Actions example: OIDC to AWS

```yaml
permissions:
  id-token: write   # required for OIDC
  contents: read

- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::xxx:role/github-actions-role
    aws-region: us-east-1
```

**No static AWS keys.** GitHub's OIDC token is exchanged for AWS credentials.

### GitLab CI: OIDC to AWS

```yaml
- name: Assume AWS role
  id: assume
  shell: bash
  run: |
    aws sts assume-role-with-web-identity \
      --role-arn $AWS_ROLE_ARN \
      --role-session-name gitlab-ci \
      --web-identity-token $CI_JOB_JWT_V2 \
      --duration-seconds 3600
```

## The registry

Public registries (Docker Hub, GHCR, Quay) are easy. For production, **use a private registry** (ECR, GCR, ACR, Harbor, Quay, JFrog).

### Image retention policies

Most registries auto-prune:
- **Keep last N tags**
- **Keep tags newer than X days**
- **Keep tags matching patterns** (e.g., `v1.*`)

```bash
# ECR lifecycle policy
aws ecr put-lifecycle-policy \
  --repository-name myapp \
  --lifecycle-policy-text '{
    "rules": [{
      "rulePriority": 1,
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 50
      },
      "action": { "type": "expire" }
    }]
  }'
```

### Image pull secrets

```yaml
# ServiceAccount with image pull secret
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app
imagePullSecrets:
- name: registry-creds
```

Or use a registry mirror (all nodes pull from a local proxy).

## GitHub Actions reference

### A complete pipeline

```yaml
name: ci
on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-go@v5
      with:
        go-version: '1.21'
    - run: go test ./...
    - run: go vet ./...

  build:
    needs: test
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    outputs:
      image-tag: ${{ steps.meta.outputs.tags }}
    steps:
    - uses: actions/checkout@v4

    - name: Login to ECR
      uses: aws-actions/amazon-ecr-login@v2

    - name: Set up Buildx
      uses: docker/setup-buildx-action@v3

    - name: Build and push
      uses: docker/build-push-action@v5
      with:
        context: .
        push: true
        tags: myregistry/myapp:${{ github.sha }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
        provenance: true
        sbom: true

    - name: Sign image
      uses: sigstore/cosign-installer@v3
    - run: |
        cosign sign --yes myregistry/myapp:${{ github.sha }}

    - name: Scan image
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: myregistry/myapp:${{ github.sha }}
        exit-code: '1'
        severity: 'CRITICAL,HIGH'

    - name: Update GitOps
      env:
        GH_TOKEN: ${{ secrets.GITOPS_TOKEN }}
      run: |
        git clone https://github.com/myorg/gitops.git
        cd gitops/overlays/prod
        kustomize edit set image myregistry/myapp=myregistry/myapp:${{ github.sha }}
        git config user.email "ci@example.com"
        git config user.name "CI Bot"
        git add -A
        git commit -m "ci: bump myapp to ${{ github.sha }}"
        git push
```

## GitLab CI reference

```yaml
# .gitlab-ci.yml
stages:
  - test
  - build
  - deploy

test:
  stage: test
  image: golang:1.21
  script:
    - go test ./...
    - go vet ./...

build:
  stage: build
  image: docker:24
  services:
    - docker:24-dind
  before_script:
    - apk add --no-cache git
  script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
    - docker build -t $CI_REGISTRY/myapp:$CI_COMMIT_SHA .
    - docker push $CI_REGISTRY/myapp:$CI_COMMIT_SHA
  only:
    - main

deploy:
  stage: deploy
  image: alpine:3.19
  before_script:
    - apk add --no-cache git
  script:
    - git clone https://oauth2:$GITOPS_TOKEN@gitlab.com/myorg/gitops.git
    - cd gitops/overlays/prod
    - kustomize edit set image $CI_REGISTRY/myapp=$CI_REGISTRY/myapp:$CI_COMMIT_SHA
    - git config user.email "ci@example.com"
    - git config user.name "CI Bot"
    - git commit -am "ci: bump myapp to $CI_COMMIT_SHA"
    - git push
  only:
    - main
```

## Multi-arch builds

For ARM nodes (Graviton, etc.), build for multiple architectures.

```yaml
- name: Set up QEMU
  uses: docker/setup-qemu-action@v3

- name: Set up Buildx
  uses: docker/setup-buildx-action@v3

- name: Build
  uses: docker/build-push-action@v5
  with:
    platforms: linux/amd64,linux/arm64
    push: true
    tags: |
      myregistry/myapp:${{ github.sha }}
      myregistry/myapp:latest
```

**Cost:** builds are slower (QEMU emulation). For pure ARM, use native ARM runners (Graviton-hosted).

## Build cache

Caching speeds up builds 5-10x.

```yaml
- name: Build with cache
  uses: docker/build-push-action@v5
  with:
    cache-from: |
      type=registry,ref=myregistry/myapp:cache
      type=gha
    cache-to: type=registry,ref=myregistry/myapp:cache,mode=max
```

**Cache types:**
- **GHA cache** — GitHub Actions, fast, free
- **Registry cache** — works with any registry, shareable
- **Local cache** — DinD only, doesn't share between runs

## Common gotchas

* **The build context size** matters. Use `.dockerignore` to exclude `.git`, `node_modules`, etc.
* **Multi-stage builds** are faster and smaller. The final image should have only the runtime.
* **Base image updates** are critical. Use `docker pull` regularly or Renovate/Dependabot.
* **Image tag strategy matters.** Use `latest` for dev, git SHA for prod. Floating tags are dangerous.
* **Build args vs env vars.** Build args are visible in image history, env vars are runtime-only.
* **Layer caching invalidates on file changes.** Order your Dockerfile carefully (least-changing first).
* **The image registry is a SPOF.** If it's down, no deploys. Replicate or use a registry proxy.
* **Pull rate limits** (Docker Hub) can break prod. Use a private registry for production images.
* **The CI runner needs enough disk** for layer caching. 50-100GB is common.
* **Secrets in CI logs** are a real risk. Mask them, audit logs.
* **Pipeline duration** is a hidden cost. Cache aggressively.
* **Long-running builds** block the queue. Parallelize or split into multiple jobs.

## A worked example

**Goal:** GitHub push → test → build multi-arch → scan → sign → push → update GitOps.

**The pipeline:**

```yaml
name: ci-cd
on:
  push:
    branches: [main]
  workflow_dispatch:

env:
  REGISTRY: myregistry.example.com
  IMAGE: myapp

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-go@v5
      with: {go-version: '1.21'}
    - run: go test ./...
    - run: go vet ./...

  build:
    needs: test
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      id-token: write
    steps:
    - uses: actions/checkout@v4

    - name: Login
      uses: docker/login-action@v3
      with:
        registry: ${{ env.REGISTRY }}
        username: ${{ secrets.REGISTRY_USER }}
        password: ${{ secrets.REGISTRY_PASS }}

    - name: Set up QEMU
      uses: docker/setup-qemu-action@v3
    - name: Set up Buildx
      uses: docker/setup-buildx-action@v3

    - name: Build and push
      uses: docker/build-push-action@v5
      with:
        context: .
        platforms: linux/amd64,linux/arm64
        push: true
        tags: ${{ env.REGISTRY }}/${{ env.IMAGE }}:${{ github.sha }}
        cache-from: type=registry,ref=${{ env.REGISTRY }}/${{ env.IMAGE }}:cache
        cache-to: type=registry,ref=${{ env.REGISTRY }}/${{ env.IMAGE }}:cache,mode=max
        provenance: true
        sbom: true

    - name: Sign
      uses: sigstore/cosign-installer@v3
    - run: |
        cosign sign --yes ${{ env.REGISTRY }}/${{ env.IMAGE }}:${{ github.sha }}

    - name: Scan
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE }}:${{ github.sha }}
        exit-code: '1'
        severity: 'CRITICAL,HIGH'

    - name: Update GitOps
      env:
        GH_TOKEN: ${{ secrets.GITOPS_TOKEN }}
      run: |
        git clone https://github.com/myorg/gitops.git
        cd gitops/overlays/prod
        kustomize edit set image ${{ env.REGISTRY }}/${{ env.IMAGE }}=${{ env.REGISTRY }}/${{ env.IMAGE }}:${{ github.sha }}
        git config user.email "ci@example.com"
        git config user.name "CI Bot"
        git add -A
        git commit -m "ci: bump myapp to ${{ github.sha }}"
        git push
```

**The flow:**
1. Push to main triggers CI
2. Tests run
3. Multi-arch image built, scanned, signed, pushed
4. GitOps repo updated with new tag
5. Argo CD detects change, syncs to cluster
6. Argo Rollouts does canary

## See also

* [[Kubernetes/guides/delivery/gitops/basics|gitops-basics]] — the model
* [[Kubernetes/guides/delivery/templating-patching/kustomize|kustomize]] — image updates
* [[Kubernetes/guides/delivery/progressive-delivery/argo-rollouts|argo-rollouts]] — safe deploys
* [[Kubernetes/guides/delivery/pipeline-workflows/argo-workflows|argo-workflows]] — full CI/CD
* [[Kubernetes/guides/non-functional/oidc-integration|oidc-integration]] — auth for CI
