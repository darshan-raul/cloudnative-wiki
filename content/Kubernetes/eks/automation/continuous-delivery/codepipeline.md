---
title: AWS CodePipeline for EKS
tags: [eks, ci-cd, codepipeline, codebuild, continuous-delivery]
date: 2026-05-17
description: Building and deploying to EKS with AWS CodePipeline and CodeBuild — pipeline shape, the EKS deploy action, cluster access for pipeline roles, private clusters, image tagging and when to hand deployment to GitOps.
---

# AWS CodePipeline for EKS

CodePipeline orchestrates stages; CodeBuild runs the commands inside them. Together they give a fully AWS-native path from commit to cluster, with [[AWS/security/iam/README|IAM]] for every permission and no CI servers to run. This suits organisations that standardise on AWS tooling or need everything inside the account boundary. General pipeline design is in [[DevOps/ci-cd/README|CI/CD]] and [[Kubernetes/guides/delivery/ci-cd-integration|CI/CD integration for Kubernetes]].

## Pipeline shape

```
Source ──► Build ──► Deploy (staging) ──► Approval ──► Deploy (production)
 GitHub     CodeBuild:                     manual        EKS action or
 via        test, build image,             or automated  CodeBuild
 connection scan, push to ECR              gate
```

- **Source** uses a CodeConnections connection to GitHub, GitLab or Bitbucket, or an S3/ECR trigger.
- **Build** produces an immutable image in ECR and passes its digest forward as a pipeline variable.
- **Deploy** applies manifests or upgrades a Helm release.

Use pipeline type **V2**: it adds triggers filtered by branch, tag and file path, pipeline-level variables, and per-execution billing.

## Build stage

```yaml
# buildspec.yml
version: 0.2
env:
  variables:
    REPO: 111122223333.dkr.ecr.eu-west-1.amazonaws.com/payments-api
  exported-variables: [IMAGE_URI]
phases:
  pre_build:
    commands:
      - aws ecr get-login-password | docker login --username AWS --password-stdin ${REPO%%/*}
      - TAG=${CODEBUILD_RESOLVED_SOURCE_VERSION:0:12}
  build:
    commands:
      - docker build -t $REPO:$TAG .
      - docker push $REPO:$TAG
  post_build:
    commands:
      - DIGEST=$(aws ecr describe-images --repository-name payments-api --image-ids imageTag=$TAG --query 'imageDetails[0].imageDigest' --output text)
      - export IMAGE_URI=$REPO@$DIGEST
```

Tag with the commit SHA and deploy by **digest**. `latest` makes rollbacks ambiguous and lets a node pull a different image from the one that was tested. Turn on ECR enhanced scanning ([[AWS/security/inspector/README|Inspector]]) and fail the build on critical findings — see [[DevOps/devsecops/stage2-build/09-container-image-scanning|container image scanning]]. Building the image well is covered in [[Containers/dockerfile-best-practices|Dockerfile best practices]].

## Deploy stage: two options

**The EKS action.** CodePipeline has a native `EKS` deploy action that runs `kubectl apply` on manifests or `helm upgrade --install` on a chart from the source artifact. You give it the cluster name, namespace and file paths; it handles authentication and, for private clusters, connects through subnets and security groups you specify.

**CodeBuild with kubectl or Helm.** More flexible — Kustomize, smoke tests, custom ordering:

```yaml
version: 0.2
phases:
  build:
    commands:
      - aws eks update-kubeconfig --name prod --region eu-west-1
      - helm upgrade --install payments-api ./chart
        --namespace payments
        --set image.repository=${IMAGE_URI%@*}
        --set image.digest=${IMAGE_URI#*@}
        --atomic --timeout 5m
      - kubectl rollout status deploy/payments-api -n payments --timeout=5m
```

`--atomic` rolls the release back if pods do not become ready, so a bad image fails the pipeline instead of half-deploying.

## Giving the pipeline access to the cluster

The deploy role is an IAM role, so it needs an [[Kubernetes/eks/security/access/cluster-access-management|access entry]] like any other principal:

```bash
aws eks create-access-entry --cluster-name prod \
  --principal-arn arn:aws:iam::111122223333:role/codebuild-deploy-payments

aws eks associate-access-policy --cluster-name prod \
  --principal-arn arn:aws:iam::111122223333:role/codebuild-deploy-payments \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy \
  --access-scope type=namespace,namespaces=payments
```

Scope it to the namespaces the pipeline deploys to. A single shared deploy role with cluster admin means any repository can change anything.

The role also needs `eks:DescribeCluster` in IAM to build a kubeconfig. For clusters in other accounts, the pipeline role assumes a deploy role in the target account, and that role holds the access entry.

## Private clusters

If the API endpoint is private ([[Kubernetes/eks/security/access/endpoint-access|endpoint access]]), CodeBuild must run **inside the VPC**: configure the project with private subnets and a security group that the cluster security group allows on 443. Those subnets need NAT or VPC endpoints for ECR, S3, STS and CloudWatch Logs, or the build cannot pull its own image.

## Push or pull?

CodePipeline deploying with `kubectl` is the **push** model: the pipeline holds credentials for the cluster. The **pull** model has the pipeline stop after publishing the image and updating a manifest in Git, and lets [[Kubernetes/eks/automation/gitops/argocd|Argo CD]] or [[Kubernetes/eks/automation/gitops/flux|Flux]] apply it.

|                           | Push (CodePipeline deploys)   | Pull (GitOps)                    |
| :------------------------ | :---------------------------- | :------------------------------- |
| Cluster credentials in CI | Yes                           | No                               |
| Drift correction          | None between deployments      | Continuous                       |
| Audit trail               | Pipeline execution history    | Git history                      |
| Ordered multi-stage gates | Native stages and approvals   | Needs promotion tooling          |
| Many clusters             | One deploy action per cluster | Each cluster converges by itself |

A common hybrid keeps CodePipeline for build, test, scan and approvals, and ends with a commit to the environment repository.

## Operating notes

- **Rollback** on stage failure can be automatic in V2 pipelines; for Helm, `--atomic` already covers the release.
- **Progressive delivery** — canary and blue-green with automated analysis — is easier with [[Kubernetes/guides/delivery/progressive-delivery/argo-rollouts|Argo Rollouts]] than with pipeline logic.
- **Docker layer caching** in CodeBuild (local or ECR-backed cache) cuts build time substantially.
- **Costs** are per pipeline execution minute and per build minute; Arm build fleets are cheaper and match [[Kubernetes/eks/compute/managed-node-groups/graviton|Graviton]] nodes.
- Send pipeline state changes through EventBridge to chat, and failed production deployments to on-call.

## Related

- [[Kubernetes/eks/automation/README|Automation on EKS]]
- [[DevOps/ci-cd/pipeline-design|Pipeline design]] and [[DevOps/ci-cd/deployment-strategies|deployment strategies]]
- [[DevOps/ci-cd/github-actions|GitHub Actions]] — the usual alternative
- [CodePipeline EKS deploy action](https://docs.aws.amazon.com/codepipeline/latest/userguide/action-reference-EKS.html)

## Across the wiki

- [[DevOps/devsecops/stage2-build/11-cicd-pipeline-hardening|M11: CI/CD Pipeline Hardening]] — CI/CD pipelines (DevOps)
