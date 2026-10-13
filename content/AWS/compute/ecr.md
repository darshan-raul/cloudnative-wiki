---
title: "Amazon ECR and image lifecycle"
description: "Publish a sandbox image, pin its digest, review repository access/scanning and remove unused versions safely."
tags:
  - cloud/aws/compute/containers
date: 2026-10-12
---

# Amazon ECR and image lifecycle

ECR stores container artifacts; [[AWS/compute/ecs/README|ECS]], [[AWS/compute/eks/README|EKS]] and other consumers run them. A registry lifecycle rule is not a workload rollback strategy.

## Access and versioning

Use scoped repository/identity permissions and temporary authentication. Private image pull may require ECR API/Docker endpoints and an S3 path as well as IAM; reachability and authorization are separate.

Tags are convenient names. Deploy immutable digests when reproducibility matters; review immutability and supported exclusions rather than assuming a tag can never move. Replication and pull-through cache need explicit permissions/configuration and do not imply identical retention everywhere.

Basic and enhanced scanning have different coverage and billing; enhanced scanning uses Inspector. A finding needs assessment/remediation, not just a green deployment check. Record base-image and application dependency ownership.

## Sandbox publish exercise

Prerequisites: Docker, a small locally tested image, sandbox ECR permissions and approved Region. Set ECR_LAB_ACCOUNT and ECR_LAB_REGION after verifying GetCallerIdentity.

```bash
aws ecr create-repository \
  --repository-name wiki-ecr-lab \
  --image-tag-mutability IMMUTABLE \
  --region "$ECR_LAB_REGION"
aws ecr get-login-password --region "$ECR_LAB_REGION" | \
  docker login --username AWS --password-stdin \
  "$ECR_LAB_ACCOUNT.dkr.ecr.$ECR_LAB_REGION.amazonaws.com"
docker tag wiki-local:lab \
  "$ECR_LAB_ACCOUNT.dkr.ecr.$ECR_LAB_REGION.amazonaws.com/wiki-ecr-lab:v1"
docker push \
  "$ECR_LAB_ACCOUNT.dkr.ecr.$ECR_LAB_REGION.amazonaws.com/wiki-ecr-lab:v1"
aws ecr describe-images --repository-name wiki-ecr-lab \
  --region "$ECR_LAB_REGION"
```

Expected: v1 and an image digest. Pull using the digest and run the same local test. Try republishing changed bytes under the immutable v1 tag; expect rejection.

Configure scanning through the appropriate repository/basic or registry/enhanced API. Do not send enhanced registry configuration to the repository scan-on-push endpoint.

## Retention and cleanup

Preview a lifecycle policy before applying it. Verify that rollback images and active digests are protected by your release/retention process; “untagged” does not prove unused. Pricing includes storage and applicable transfer/scanning features.

Delete only lab images, then the empty lab repository, and log out of the lab registry. Do not force-delete a shared repository to make cleanup convenient.

## References

- [Repository creation](https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-create.html).
- [Private authentication](https://docs.aws.amazon.com/AmazonECR/latest/userguide/registry_auth.html).
- [Image scanning](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning.html).
- [Lifecycle preview](https://docs.aws.amazon.com/AmazonECR/latest/userguide/lifecycle_policy_preview.html).
- [Pricing](https://aws.amazon.com/ecr/pricing/).
