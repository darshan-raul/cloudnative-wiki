---
title: Flux on EKS
tags: [eks, gitops, flux, continuous-delivery]
date: 2026-05-17
description: Running Flux on EKS — the controller model, bootstrap, authenticating to ECR and CodeCommit with IAM, decrypting secrets with KMS and SOPS, image automation, and how it differs from Argo CD.
---

# Flux on EKS

Flux is a set of Kubernetes controllers that keep a cluster in sync with sources such as Git repositories, Helm repositories and OCI artifacts. It is a CNCF graduated project and the main alternative to [[Kubernetes/eks/automation/gitops/argocd|Argo CD]]. Where Argo CD is an application with a UI, Flux is a toolkit of small controllers driven entirely by custom resources. The underlying ideas are in [[Kubernetes/guides/delivery/gitops/basics|GitOps basics]].

## The controllers

| Controller                         | Custom resources                                             | Job                                                      |
| :--------------------------------- | :----------------------------------------------------------- | :------------------------------------------------------- |
| source-controller                  | `GitRepository`, `HelmRepository`, `OCIRepository`, `Bucket` | Fetches sources and exposes them as versioned artifacts  |
| kustomize-controller               | `Kustomization`                                              | Builds and applies manifests, prunes, health-checks      |
| helm-controller                    | `HelmRelease`                                                | Installs and upgrades Helm charts, rolls back on failure |
| notification-controller            | `Provider`, `Alert`, `Receiver`                              | Sends events out; receives webhooks to trigger syncs     |
| image-reflector / image-automation | `ImageRepository`, `ImagePolicy`, `ImageUpdateAutomation`    | Watches registries and commits new tags to Git           |

Everything is reconciled on an interval. A `Kustomization` can depend on another (`dependsOn`), which is how ordering is expressed: CRDs, then controllers, then applications.

## Bootstrap

```bash
flux bootstrap github \
  --owner=example \
  --repository=fleet \
  --branch=main \
  --path=clusters/prod-eu-west-1 \
  --personal=false
```

Bootstrap commits Flux's own manifests to the repository, installs them in the cluster, and points Flux at that path. From then on Flux manages itself: upgrading Flux is a commit. A typical repository layout:

```
fleet/
├── clusters/
│   ├── prod-eu-west-1/      # entry point: Kustomizations for this cluster
│   └── staging-eu-west-1/
├── infrastructure/          # controllers: ingress, cert-manager, CSI drivers
│   ├── base/
│   └── overlays/{prod,staging}/
└── apps/
    ├── base/
    └── overlays/{prod,staging}/
```

Flux is **pull-based and per-cluster**: every cluster runs its own Flux and pulls from Git. There is no central hub holding credentials for the fleet, which is a real security advantage and means a new cluster only needs bootstrap to converge.

## Authenticating to AWS services with IAM

Give Flux's service accounts a role through [[Kubernetes/eks/security/iam-roles-for-sa|IRSA]] or [[Kubernetes/eks/security/pod-identity|Pod Identity]] instead of storing credentials.

**ECR (images and OCI Helm charts).** Set `provider: aws` and Flux exchanges the pod's role for an ECR token automatically — no 12-hour token refresh job:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 5m
  url: oci://111122223333.dkr.ecr.eu-west-1.amazonaws.com/charts/podinfo
  provider: aws
  ref:
    semver: ">=6.0.0"
```

The source-controller role needs `ecr:GetAuthorizationToken` plus pull permissions on the repositories.

**S3.** A `Bucket` source with `provider: aws` reads manifests from [[AWS/storage/s3/README|S3]], useful in environments where Git is not reachable from the cluster.

**OCI artifacts instead of Git.** CI can package rendered manifests with `flux push artifact` to ECR and clusters pull from there. This removes the cluster's dependency on the Git provider and lets you sign and verify what is deployed.

## Secrets: SOPS with KMS

Flux decrypts SOPS-encrypted files natively, and SOPS can use an [[AWS/security/kms/README|AWS KMS]] key.

```yaml
# .sops.yaml in the repository
creation_rules:
  - path_regex: .*/secrets/.*\.yaml
    encrypted_regex: ^(data|stringData)$
    kms: arn:aws:kms:eu-west-1:111122223333:key/1234abcd-...
```

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 10m
  path: ./apps/overlays/prod
  prune: true
  sourceRef: { kind: GitRepository, name: flux-system }
  decryption:
    provider: sops
```

Developers encrypt with `sops -e`; the kustomize-controller's role needs `kms:Decrypt` on the key. Secrets live in Git encrypted, access is governed by the key policy, and every decryption is logged in [[AWS/security/cloudtrail/README|CloudTrail]]. Alternatives are compared in [[Kubernetes/eks/security/secrets-management/README|secrets management on EKS]].

## Helm releases

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: podinfo
  namespace: apps
spec:
  interval: 10m
  chartRef: { kind: OCIRepository, name: podinfo, namespace: flux-system }
  install: { remediation: { retries: 3 } }
  upgrade: { remediation: { retries: 3, remediateLastFailure: true } }
  driftDetection: { mode: enabled }
  values:
    replicaCount: 3
```

Unlike Argo CD, which renders charts to plain manifests, Flux uses the Helm SDK: releases are real Helm releases, `helm list` shows them, and hooks and rollbacks behave as Helm users expect.

## Image automation

The image controllers scan ECR for new tags, select one by policy (semver range, numeric order, regex), and commit the updated tag back to Git. Git stays the source of truth, and a deployment to staging becomes "CI pushed an image". Use it for lower environments; promote to production through a pull request.

## Flux or Argo CD

|               | Flux                                              | Argo CD                                      |
| :------------ | :------------------------------------------------ | :------------------------------------------- |
| Topology      | Agent in every cluster, pull only                 | Usually a central hub pushing to spokes      |
| UI            | None built in (third-party UIs exist)             | Rich web UI with diff and topology views     |
| Helm          | Native Helm releases                              | Renders templates, applies as manifests      |
| Secrets       | SOPS built in                                     | Plugins or external operators                |
| Multi-tenancy | Kubernetes RBAC and service-account impersonation | Projects and its own RBAC                    |
| Best for      | Platform teams automating fleets as code          | Teams that want visibility and click-to-sync |

Both are sound. The decision is mostly about whether people want a UI and whether a central control plane is acceptable.

## Operating notes

- `flux get all -A` and `flux events` are the first diagnostic commands; `flux reconcile kustomization <name> --with-source` forces a sync.
- Suspend, do not delete, when intervening by hand: `flux suspend kustomization apps`. Otherwise Flux reverts your change at the next interval.
- Set `spec.wait: true` and health checks so a `Kustomization` is only `Ready` when its workloads are.
- Use `spec.serviceAccountName` on tenant Kustomizations so they apply with the tenant's permissions, not Flux's cluster-admin.
- Send alerts to chat and commit statuses back to the Git provider through the notification-controller.

## Related

- [[Kubernetes/eks/automation/README|Automation on EKS]]
- [[Kubernetes/guides/delivery/templating-patching/kustomize|Kustomize]] and [[Kubernetes/guides/delivery/templating-patching/helm/gitops|Helm with GitOps]]
- [[DevOps/ci-cd/README|CI/CD]]
- [Flux documentation](https://fluxcd.io/flux/)

## Across the wiki

- [[DevOps/ci-cd/git|Git Strategy, Trunk-Based Development & Configuration]] — GitOps (DevOps)
