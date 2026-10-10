---
title: Argo CD on EKS
tags: [eks, gitops, argocd, continuous-delivery]
date: 2026-05-17
description: Running Argo CD on EKS — installation choices, exposing it through an ALB, IAM-based access to other EKS clusters, ECR-hosted Helm charts, and the operational settings that matter at scale.
---

# Argo CD on EKS

Argo CD is a GitOps controller: it continuously compares what is declared in Git with what is running in the cluster, shows the difference, and can correct it. The concepts — Applications, sync, health, app-of-apps — are in [[Kubernetes/guides/delivery/gitops/argo-cd/README|the Argo CD guide]] and [[Kubernetes/guides/delivery/gitops/basics|GitOps basics]]. This page covers what is specific to running it on AWS.

## Three ways to get it

| Option                                                                           | You operate                | Notes                                                                                                                      |
| :------------------------------------------------------------------------------- | :------------------------- | :------------------------------------------------------------------------------------------------------------------------- |
| Helm chart / manifests                                                           | Everything                 | Full control, any version, any plugin                                                                                      |
| [[Kubernetes/guides/delivery/gitops/argo-cd/operator-install\|Argo CD Operator]] | The operator and instances | Declarative multi-instance management                                                                                      |
| EKS Capability for Argo CD (managed)                                             | Applications only          | AWS runs the controllers outside your cluster and integrates sign-in with IAM Identity Center; fewer customisation options |

The managed capability is attractive for a hub that deploys to many clusters, because the control plane is no longer a workload you patch. Self-manage when you need config management plugins, custom tooling images or tight version control.

## Self-managed install

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --values values.yaml
```

```yaml
# values.yaml — the parts that matter on EKS
global:
  domain: argocd.example.com
configs:
  params:
    server.insecure: true # TLS terminates at the ALB
redis-ha:
  enabled: true
controller:
  replicas: 2 # sharded across clusters
repoServer:
  autoscaling: { enabled: true, minReplicas: 2 }
server:
  autoscaling: { enabled: true, minReplicas: 2 }
  ingress:
    enabled: true
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internal
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/backend-protocol: HTTP
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
      alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:eu-west-1:111122223333:certificate/abc
```

Keep the load balancer **internal**. Argo CD holds credentials for every cluster it manages; it should not be reachable from the internet. The CLI uses gRPC, which works through an ALB when the target group protocol version is gRPC, or use `--grpc-web`.

## Deploying to other EKS clusters without static credentials

The hub-and-spoke pattern: one Argo CD in a management cluster deploys to many workload clusters. On EKS this is done with [[AWS/security/iam/README|IAM]], not long-lived tokens.

1. Give the `argocd-application-controller` and `argocd-server` service accounts an IAM role through [[Kubernetes/eks/security/pod-identity|Pod Identity]] or [[Kubernetes/eks/security/iam-roles-for-sa|IRSA]].
2. In each spoke account, create a role that the hub role may assume, and register it on the spoke cluster with an [[Kubernetes/eks/security/access/cluster-access-management|access entry]] and an access policy.
3. Register the cluster in Argo CD with a secret that tells it to fetch tokens through IAM:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: prod-eu-west-1
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    environment: production
stringData:
  name: prod-eu-west-1
  server: https://ABCDEF0123456789.gr7.eu-west-1.eks.amazonaws.com
  config: |
    {
      "awsAuthConfig": {
        "clusterName": "prod",
        "roleARN": "arn:aws:iam::444455556666:role/argocd-deployer"
      },
      "tlsClientConfig": { "caData": "<base64 CA>" }
    }
```

The hub needs network reachability to each spoke's API endpoint: private endpoints require peering or Transit Gateway — see [[Kubernetes/eks/security/access/endpoint-access|endpoint access]].

Grant the deployer role only what it deploys. Cluster admin on every spoke turns Argo CD into the single most valuable target in the organisation.

## Helm charts in ECR

ECR stores Helm charts as OCI artifacts. ECR tokens expire after 12 hours, so a static repository password stops working overnight. Either let the repo server authenticate with its IAM role, or refresh a repository secret on a schedule (External Secrets Operator has an ECR token generator for this). The chart side is covered in [[Kubernetes/guides/delivery/templating-patching/helm/oci|Helm OCI registries]].

## Bootstrapping a fleet

Use an `ApplicationSet` with the **cluster generator** to install the same add-ons on every registered cluster, selecting by the labels on the cluster secrets:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-addons
  namespace: argocd
spec:
  generators:
    - clusters:
        selector:
          matchLabels: { environment: production }
  template:
    metadata:
      name: "addons-{{name}}"
    spec:
      project: platform
      source:
        repoURL: https://github.com/example/platform.git
        path: "addons/overlays/{{metadata.labels.environment}}"
        targetRevision: main
      destination:
        server: "{{server}}"
        namespace: kube-system
      syncPolicy:
        automated: { prune: true, selfHeal: true }
```

A common companion is the "GitOps bridge": Terraform creates the cluster and writes account IDs, role ARNs and VPC IDs as annotations on the cluster secret, and the ApplicationSet injects them into Helm values. That removes the hand-copied ARNs from Git.

## Operating notes

- **Sharding.** One application controller struggles past a few hundred applications or a few dozen clusters. Increase controller replicas so clusters are distributed across shards.
- **Repo server** renders manifests and is CPU-bound during Helm and Kustomize builds; scale it horizontally and give it a cache.
- **Ignore differences** for fields that controllers legitimately mutate — HPA-managed `replicas`, webhook CA bundles — or applications stay `OutOfSync` forever.
- **Sync waves and hooks** order dependent resources: CRDs before custom resources, the [[Kubernetes/eks/storage/ebs-csi|CSI driver]] before workloads that need volumes.
- **Projects** are the tenancy boundary. Restrict each team's project to its repositories, clusters and namespaces.
- **Secrets** never go into Git in plain text — use [[Kubernetes/eks/security/secrets-management/secrets-manager|Secrets Manager integrations]] or [[Kubernetes/eks/security/secrets-management/sealed-secrets|Sealed Secrets]].

## Related

- [[Kubernetes/eks/automation/README|Automation on EKS]]
- [[Kubernetes/eks/automation/gitops/flux|Flux on EKS]] — the alternative
- [[Kubernetes/guides/delivery/progressive-delivery/argo-rollouts|Argo Rollouts]] — canary and blue-green on top of Argo CD
- [[DevOps/ci-cd/README|CI/CD]] — where GitOps fits in the pipeline
- [Argo CD documentation](https://argo-cd.readthedocs.io/)

## Across the wiki

- [[DevOps/ci-cd/git|Git Strategy, Trunk-Based Development & Configuration]] — GitOps (DevOps)
