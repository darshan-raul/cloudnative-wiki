---
title: Container Registries
tags: [containers, registry, oci, ecr, supply-chain]
date: 2026-10-10
description: How container registries work — image naming, the pull and push protocol, tags versus digests, authentication on nodes, signing and admission, mirroring and pull-through caches, lifecycle policies and the failure modes seen in clusters.
---

# Container Registries

A registry stores and serves [[Containers/images-and-layers|images]]. It is a content-addressed blob store with an HTTP API, standardised as the OCI Distribution specification, so any compliant client can talk to any compliant registry: Docker Hub, GitHub Container Registry, Amazon ECR, Google Artifact Registry, Azure Container Registry, Quay, Harbor.

It is also a production dependency. If the registry is unreachable, new pods cannot start and nodes cannot scale out.

## Anatomy of an image reference

```
registry.example.com:5000/payments/checkout-api:1.4.2@sha256:9b2c…
└────── registry ───────┘ └──── repository ───┘ └tag┘ └── digest ──┘
```

| Part      | Default if omitted          |
| :-------- | :-------------------------- |
| Registry  | `docker.io`                 |
| Namespace | `library` (official images) |
| Tag       | `latest`                    |

So `nginx` means `docker.io/library/nginx:latest`. Write the full name in manifests: it removes ambiguity and makes it obvious which registry a cluster depends on.

## What a pull does

```
1. GET /v2/                                   → 401, with where to get a token
2. GET token from the auth service            → bearer token scoped to the repository
3. GET /v2/<repo>/manifests/<tag or digest>   → index or manifest
4. (if an index) pick the platform, GET that manifest
5. GET /v2/<repo>/blobs/<digest>              → config, then each layer not already present, in parallel
6. verify digests, unpack layers into the snapshotter
```

Step 5 is where deduplication pays off: layers already on the node are skipped, so pulling a new version of an application usually downloads only the top layer. A push is the reverse — upload missing blobs, then the manifest, then point the tag at it.

## Tags and digests

A tag is a movable name; a digest is the content.

|                                         | Tag (`:1.4.2`)         | Digest (`@sha256:…`) |
| :-------------------------------------- | :--------------------- | :------------------- |
| Mutable                                 | Yes — can be re-pushed | No                   |
| Human-readable                          | Yes                    | No                   |
| Guarantees the same bytes on every node | No                     | Yes                  |

Consequences for deployments:

- **`latest` is not a version.** Two nodes can run different code under the same tag, and a rollback has nothing to roll back to.
- **Use unique, immutable tags** — a semantic version or the Git commit SHA — and enable tag immutability on the repository so they cannot be overwritten.
- **Deploy by digest** in production. Let CI resolve the tag to a digest and write `image: repo@sha256:…` into the manifest.
- `imagePullPolicy` defaults to `Always` for `latest` and `IfNotPresent` otherwise. With mutable tags and `IfNotPresent`, a node keeps running whatever it cached.

## Authentication on nodes

| Mechanism                             | How it works                                                                                                                                          |
| :------------------------------------ | :---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Node identity                         | The kubelet's credential provider exchanges the node's cloud role for a registry token. ECR, Artifact Registry and ACR work this way with no secrets. |
| `imagePullSecrets`                    | A `kubernetes.io/dockerconfigjson` Secret referenced by the pod or its service account                                                                |
| Service account token for image pulls | The kubelet presents a workload-specific token, so pull rights follow the pod rather than the node                                                    |
| Registry mirror configuration         | containerd is configured with credentials for an upstream                                                                                             |

Prefer node or workload identity to static pull secrets. On EKS the node role needs ECR read permissions; cross-account pulls also need a repository policy. See [[AWS/security/iam/README|IAM]] and [[Kubernetes/eks/troubleshooting/common-issues|common EKS issues]].

## Trust: signing and verification

Pulling by digest proves you got the bytes you asked for. It does not prove who built them.

- **Signing.** Sigstore **cosign** signs an image digest and stores the signature in the registry beside it. Keyless signing ties the signature to a CI workload identity instead of a long-lived key. Notation is the alternative used with AWS Signer and Azure.
- **Attestations.** Signed statements about an image: its SBOM, its build provenance (SLSA), its scan result.
- **Verification at admission.** A policy engine checks signatures before a pod is admitted — Kyverno's `verifyImages`, Sigstore's policy controller, or Ratify with Gatekeeper.

```bash
cosign sign registry.example.com/payments/checkout-api@sha256:9b2c…
cosign verify --certificate-identity-regexp 'https://github.com/example/.+' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  registry.example.com/payments/checkout-api@sha256:9b2c…
```

Together with a rule that images may only come from your own registry, this closes the gap between "what CI built" and "what the cluster runs". See [[Kubernetes/eks/security/policy-management|policy management]], [[Kubernetes/concepts/L07-security/04-admission-policy/23-sboms|SBOMs]] and the [[DevOps/devsecops/README|DevSecOps curriculum]].

## Scanning

Registries scan images for known vulnerabilities on push and, more usefully, **continuously** — a new CVE can affect an image built months ago. Scan in CI to block bad builds, and in the registry to learn about running ones. Triage by exploitability and whether the package is actually loaded, not by raw counts. Details in [[DevOps/devsecops/stage2-build/09-container-image-scanning|container image scanning]].

## Mirrors and pull-through caches

Depending directly on a public registry has three problems: rate limits (Docker Hub limits anonymous pulls per source IP, and a whole cluster behind one NAT gateway shares one IP), availability, and the upstream changing or deleting an image.

| Approach                    | How                                                                                                                      |
| :-------------------------- | :----------------------------------------------------------------------------------------------------------------------- |
| **Pull-through cache**      | Your registry fetches from upstream on first request and caches it. ECR, Artifact Registry, ACR and Harbor support this. |
| **Explicit mirroring**      | A job copies approved images into your registry (`crane copy`, `skopeo sync`)                                            |
| **Runtime mirror config**   | containerd is told to try a mirror first, so manifests need no changes                                                   |
| **In-cluster peer-to-peer** | Nodes share layers with each other (Spegel, Dragonfly), reducing registry load at scale-out                              |

Mirroring everything you run into a registry you control is also the prerequisite for air-gapped and private clusters — [[Kubernetes/eks/advanced/advanced-networking|private EKS clusters]].

## Lifecycle and cost

Every CI build pushes layers that are never deleted by default.

- **Lifecycle policies**: keep the last N tagged images, expire untagged ones after a few days, keep anything matching release tags indefinitely.
- **Never expire what is running.** Base retention on what clusters reference, or keep generously.
- **Garbage collection** reclaims blobs no manifest references; managed registries do it for you.
- **Replication** to other regions shortens pulls and survives a regional outage.
- **Network path.** Pulls through a NAT gateway are billed per GB. Use private endpoints for the registry and its blob storage — [[AWS/cost-management/network-cost-optimization|network cost optimization]].

## Failure modes in clusters

| Symptom                                                 | Likely cause                                                            |
| :------------------------------------------------------ | :---------------------------------------------------------------------- |
| `ErrImagePull` / `ImagePullBackOff`, `manifest unknown` | Wrong tag, or the image was expired by a lifecycle policy               |
| `unauthorized` / `no basic auth credentials`            | Missing or expired credentials; node role without pull rights           |
| `toomanyrequests`                                       | Public registry rate limit                                              |
| `no matching manifest for linux/arm64`                  | Single-architecture image on a different-architecture node              |
| `i/o timeout`                                           | No route: private subnet without NAT or registry endpoints              |
| `x509: certificate signed by unknown authority`         | Private registry CA not trusted by the node's runtime                   |
| Pods slow to start during scale-out                     | Large images, cold nodes — shrink images, pre-pull, or use lazy pulling |

The diagnosis flow is in [[Kubernetes/guides/troubleshooting/image-pull|image pull failures]].

## Tools worth knowing

```bash
crane ls registry.example.com/payments/checkout-api      # list tags
crane digest nginx:1.27                                   # resolve a tag
crane copy nginx:1.27 registry.example.com/mirror/nginx:1.27
skopeo inspect docker://registry.example.com/app:1.4.2
oras push registry.example.com/config/policy:v1 policy.yaml   # arbitrary OCI artifacts
```

All of these work without a Docker daemon, which makes them suitable for CI.

## Related

- [[Containers|Containers hub]]
- [[Containers/dockerfile-best-practices|Dockerfile best practices]]
- [[Containers/runtimes|Container runtimes]] — the client side of a pull
- [[DevOps/ci-cd/pipeline-design|Pipeline design]] — build once, promote the same digest
- [OCI distribution specification](https://github.com/opencontainers/distribution-spec)

## Across the wiki

- [[Security/kubernetes-security/vulnerability-scanning/README|Kubernetes Vulnerability Scanning]] — software supply chain (Security)
- [[Kubernetes/concepts/L07-security/02-workload-sandboxing/19-image-hardening|Image Hardening]] — software supply chain (Kubernetes)
- [[AWS/security/inspector/README|AWS Inspector]] — software supply chain (AWS)
