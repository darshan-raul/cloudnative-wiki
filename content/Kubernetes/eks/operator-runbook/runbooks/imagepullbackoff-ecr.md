---
title: "Runbook: ImagePullBackOff (ECR and Other Registries)"
description: "Pods sit in ErrImagePull or ImagePullBackOff. Use the exact pull error to separate a wrong image reference, missing registry permissions, no network path to ECR, rate limits and architecture mismatches."
tags: [kubernetes/eks/operator-runbook, eks, runbook, ecr, images, incident]
date: 2026-10-20
aliases: [EKS ImagePullBackOff runbook, ECR pull failures EKS]
---

# Runbook: ImagePullBackOff (ECR and Other Registries)

**Applies to:** EC2 nodes (AL2023, Bottlerocket, Karpenter, managed node groups), Auto Mode and Fargate, pulling from Amazon ECR, ECR Public or third-party registries.
**Typical severity:** Sev 3 for one image. Sev 1 if it blocks a rollout, a system DaemonSet or every new node (for example, ECR unreachable).
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

```text
Warning  Failed   kubelet  Failed to pull image "111122223333.dkr.ecr.us-east-1.amazonaws.com/orders:1.4.2": ...
Warning  Failed   kubelet  Error: ErrImagePull
Normal   BackOff  kubelet  Back-off pulling image "..."
```

The pod status shows `ErrImagePull`, then `ImagePullBackOff`. The back-off grows to five minutes between attempts, so a fixed problem can take a few minutes to clear.

## Impact

Running Pods keep their images. Anything that needs a pull fails: new replicas, rollouts and Pods moving to a fresh node. If the cause is network-wide (ECR unreachable), new nodes can't even start `aws-node` and `kube-proxy`.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=my-cluster REGION=us-east-1 NS=<namespace> POD=<pod>
export IMAGE=$(kubectl get pod "$POD" -n "$NS" -o jsonpath='{.spec.containers[0].image}')
export NODE=$(kubectl get pod "$POD" -n "$NS" -o jsonpath='{.spec.nodeName}')
```

## Triage

**1. Read the full pull error.** The tail of the message decides the path:

```bash
kubectl describe pod "$POD" -n "$NS" | grep -A3 'Failed to pull image' | head -8
```

| Error contains                                                                        | Cause                                                         |
| ------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `not found`, `manifest unknown`, `repository ... does not exist`                      | A. Wrong image reference                                      |
| `403 Forbidden`, `no basic auth credentials`, `authorization failed`, `denied`        | B. Registry permission                                        |
| `dial tcp ...:443: i/o timeout`, `context deadline exceeded`, `TLS handshake timeout` | C. No network path to the registry                            |
| `toomanyrequests`, `429`                                                              | D. Registry rate limit (usually Docker Hub)                   |
| `no match for platform in manifest`                                                   | E. Image doesn't have a build for the node's CPU architecture |

**2. Does the image exist?** For ECR:

```bash
REPO=$(echo "$IMAGE" | sed -E 's#^[^/]+/##; s#[:@].*$##')
TAG=$(echo "$IMAGE" | sed -nE 's#.*:([^/@]+)$#\1#p')
aws ecr describe-images --region "$REGION" --repository-name "$REPO" --image-ids imageTag="$TAG" \
  --query 'imageDetails[].[imageTags,imagePushedAt,imageSizeInBytes]'
```

**3. Is it one node or every node?**

```bash
kubectl get pods -A --no-headers | grep -E 'ErrImagePull|ImagePullBackOff' | wc -l
kubectl get pods -A -o wide --no-headers | grep -E 'ErrImagePull|ImagePullBackOff' | awk '{print $8}' | sort | uniq -c
```

Many images failing on many nodes points at the network or the node role (C or B). One image everywhere points at that image or its repository (A, B or E).

**4. Try the pull on the node.** This separates the node's path and credentials from Kubernetes:

```bash
aws ssm start-session --target <instance-id>
sudo crictl pull --creds "AWS:$(aws ecr get-login-password --region <region>)" <image>
```

`crictl` doesn't use the kubelet's credential provider, hence `--creds`. If this works but the kubelet's pull doesn't, look at the credential provider (cause B).

## Diagnosis

| Signal                                       | Cause                                  | Fix   |
| -------------------------------------------- | -------------------------------------- | ----- |
| `not found`; `describe-images` finds nothing | A. Wrong tag, repository or account    | Fix A |
| `403`, `no basic auth credentials`           | B. Node role, repository policy or KMS | Fix B |
| Timeouts, many images, many nodes            | C. Network path to ECR                 | Fix C |
| `toomanyrequests`                            | D. Rate limit                          | Fix D |
| `no match for platform`                      | E. Architecture mismatch               | Fix E |

## Fix

### A. Wrong image reference

Fix the tag or digest in the workload, through the pipeline that sets it. Look for a CI job that pushed to another account or region, a tag that was overwritten or removed by an ECR lifecycle policy, or a typo. Pin by digest (`@sha256:...`) for production, so a tag can't change underneath you.

### B. Registry permission

ECR pulls on EC2 nodes use the **node role**, through the kubelet's ECR credential provider. Pod Identity and IRSA roles are **not** used for image pulls.

1. **Node role policy:** the role needs `AmazonEC2ContainerRegistryReadOnly`, or `AmazonEC2ContainerRegistryPullOnly`:

   ```bash
   aws iam list-attached-role-policies --role-name <node-role> --query 'AttachedPolicies[].PolicyName'
   ```

2. **Cross-account repository:** the repository policy in the owning account must allow `ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer` and `ecr:BatchCheckLayerAvailability` for your node role, or your account:

   ```bash
   aws ecr get-repository-policy --region "$REGION" --repository-name "$REPO" --registry-id <owner-account>
   ```

3. **KMS-encrypted repository:** the node role also needs `kms:Decrypt` on the key.
4. **Credential provider broken on the node:** `sudo journalctl -u kubelet | grep -i credential` shows it. The configuration is under `/etc/eks/image-credential-provider/`. A custom AMI or user data that changes kubelet flags can drop it.
5. **Non-ECR private registries:** need an `imagePullSecrets` entry on the Pod or its service account, and the secret must be in the Pod's namespace.

**Fargate:** pulls use the **Fargate pod execution role**, which needs the same ECR permissions.

### C. No network path to ECR

Nodes in private subnets need one of these:

- a NAT gateway route; or
- VPC endpoints for **`com.amazonaws.<region>.ecr.api`** and **`ecr.dkr`** (interface endpoints, with private DNS), **plus an S3 gateway endpoint**. Image layers are served from S3; without the S3 endpoint, manifests work but layer downloads time out.

Check the endpoints and their security groups. They must allow 443 from the node security group:

```bash
aws ec2 describe-vpc-endpoints --region "$REGION" --filters Name=vpc-id,Values=<vpc-id> \
  --query 'VpcEndpoints[].[ServiceName,VpcEndpointType,State,PrivateDnsEnabled]' --output table
```

Also check for recent route table, NACL or security group changes in CloudTrail, and for a DNS problem on the node (`dig <account>.dkr.ecr.<region>.amazonaws.com`).

### D. Rate limit

Docker Hub limits anonymous and free-tier pulls. Move the image into ECR: either copy it there in CI, or set up an **ECR pull-through cache** rule for Docker Hub and change the image reference to `<account>.dkr.ecr.<region>.amazonaws.com/<cache-prefix>/library/nginx:1.27`. Use `public.ecr.aws/docker/library/...` for official images, which isn't rate limited in the same way.

### E. Architecture mismatch

The image was built for `amd64` and the node is `arm64` (Graviton), or the other way round. Check with `docker buildx imagetools inspect <image>`, or `aws ecr batch-get-image` for the manifest list. Either build a multi-arch image, or constrain the workload with `nodeSelector: {kubernetes.io/arch: amd64}`. In Karpenter, a NodePool allowing both architectures makes this appear only on some nodes.

## Verify recovery

```bash
kubectl delete pod "$POD" -n "$NS"     # skip the back-off; the controller recreates it
kubectl get pods -n "$NS" -w
```

The new Pod passes `ContainerCreating` and starts. Confirm the stalled rollout finished: `kubectl rollout status deploy/<name> -n "$NS"`.

## Escalate

Open an AWS Support case if ECR returns 5xx errors or pulls time out with correct endpoints, routes and permissions (check the AWS Health Dashboard for ECR first). Attach the image URI, node instance ID, UTC times, the kubelet log excerpt, and the VPC endpoint IDs.

## Prevent

- Keep all production images in ECR (with pull-through cache for public ones), in the same region as the cluster.
- In private clusters, manage the ECR and S3 endpoints in the same IaC as the subnets.
- Alert on Pods in `ImagePullBackOff` for more than five minutes (`kube_pod_container_status_waiting_reason{reason="ImagePullBackOff"}`).
- Build multi-arch images if any NodePool allows both architectures.
- Make sure ECR lifecycle policies never expire images that running workloads reference.

## Background

- [[Kubernetes/guides/troubleshooting/image-pull|Troubleshooting image pulls]]
- [[AWS/compute/ecr|Amazon ECR]]
- [Amazon ECR interface VPC endpoints](https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html)
- [ECR pull-through cache](https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache.html)
