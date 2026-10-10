---
title: AWS Fargate on EKS
tags: [eks, compute, fargate, serverless]
date: 2026-05-17
description: Running EKS pods on AWS Fargate — how Fargate profiles select pods, the isolation and sizing model, what is not supported, logging, networking and when Fargate is the wrong tool.
---

# AWS Fargate on EKS

Fargate runs each pod on its own AWS-managed micro-VM. There are no EC2 nodes to patch, scale or right-size: you declare which pods go to Fargate and AWS supplies exactly enough compute for each one.

It suits clusters with a few long-running services, bursty batch jobs, and teams that want strong per-pod isolation without operating nodes. It is a poor fit for anything that depends on the node: DaemonSets, GPUs, privileged containers, or high pod churn where start-up time matters.

## How pods end up on Fargate

A **Fargate profile** tells the EKS scheduler which pods to place on Fargate. A profile has:

- up to five **selectors**, each a namespace plus optional pod labels,
- the **private subnets** to launch into (public subnets are rejected),
- a **pod execution role**.

```bash
eksctl create fargateprofile \
  --cluster my-cluster \
  --name batch \
  --namespace batch \
  --labels compute=fargate
```

When a pod is created, a mutating webhook checks it against the profiles. A match sets `schedulerName: fargate-scheduler`, and Fargate launches a micro-VM, registers it as a node named `fargate-ip-…`, and runs the pod there. One pod, one node, always.

Profiles are immutable. To change a selector, create a new profile and delete the old one. Pods already running are not moved; they pick up the new profile when recreated.

## Two roles, not one

| Role               | Used by                    | Needs                                                                                      |
| :----------------- | :------------------------- | :----------------------------------------------------------------------------------------- |
| Pod execution role | The Fargate infrastructure | `AmazonEKSFargatePodExecutionRolePolicy` — pull from ECR, write logs, register the node    |
| Application role   | Your containers            | Whatever the app calls, granted through [[Kubernetes/eks/security/iam-roles-for-sa\|IRSA]] |

[[Kubernetes/eks/security/pod-identity|EKS Pod Identity]] relies on a node agent DaemonSet and is not available on Fargate, so Fargate workloads still use IRSA.

## Sizing and billing

You do not pick an instance type. Fargate adds up the pod's container **requests** (the largest init container counts if it is bigger), adds 256 MiB for Kubernetes components, and rounds up to the nearest supported vCPU/memory combination. You are billed per second for that rounded size.

Practical consequences:

- A pod with no requests gets the smallest size, 0.25 vCPU and 0.5 GiB, and will be throttled or OOM-killed under load. Always set [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits|requests]].
- Limits above requests buy nothing: the micro-VM is sized from requests.
- Each pod gets 20 GiB of ephemeral storage by default, which can be raised by requesting `ephemeral-storage`.
- The `CapacityProvisioned` annotation on the pod shows what you are actually paying for.

For steady workloads Fargate costs more per vCPU-hour than EC2; it wins when the alternative is half-empty nodes. Compute Savings Plans apply — see [[AWS/cost-management/savings-plans|Savings Plans]] and [[Kubernetes/eks/compute/fargate/fargate-vs-ec2|Fargate vs EC2]].

## What is not supported

| Not available                                                                                                       | What to do instead                                                        |
| :------------------------------------------------------------------------------------------------------------------ | :------------------------------------------------------------------------ |
| DaemonSets                                                                                                          | Run agents as sidecars, or use the built-in log router                    |
| Privileged containers, `hostNetwork`, `hostPort`, `hostPath`                                                        | Keep those workloads on EC2 nodes                                         |
| GPUs, Arm, Windows                                                                                                  | EC2 node groups or [[Kubernetes/eks/compute/karpenter/README\|Karpenter]] |
| EBS volumes                                                                                                         | [[Kubernetes/eks/storage/efs-csi\|EFS]] with static provisioning          |
| Pod Identity agent                                                                                                  | IRSA                                                                      |
| [[Kubernetes/eks/networking/vpc-cni/security-groups-for-pods\|Security groups for pods]] via the usual ENI trunking | `SecurityGroupPolicy` still works, applied to the pod's own ENI           |

Start-up is also slower than on a warm node: expect 30–60 seconds before the image pull even begins, because a VM has to boot. Scale-out with [[Kubernetes/concepts/L06-scheduling-scaling/03-horizontalpodautoscaler|HPA]] therefore reacts more slowly, so keep more headroom.

## Networking

Each Fargate pod gets an ENI and a private IP from the profile's subnets, exactly like a pod under the [[Kubernetes/eks/networking/vpc-cni/README|VPC CNI]]. Because the subnets are private, image pulls and AWS API calls need a NAT gateway or [[AWS/networking/vpc/README|VPC endpoints]] for ECR, S3, STS and CloudWatch Logs.

By default Fargate pods use the cluster security group. Ingress works through the AWS Load Balancer Controller with **IP targets**; instance targets cannot work because there is no instance.

## Logging

There are no nodes to run Fluent Bit on, so Fargate has a built-in log router. Create a namespace called `aws-observability` with the label `aws-observability: enabled` and a ConfigMap named `aws-logging` holding Fluent Bit `output.conf`, `filters.conf` and `parsers.conf`. The pod execution role must be allowed to write to the destination. Details in [[Kubernetes/eks/observability/logging/pod-logging|pod logging]].

## Running CoreDNS on Fargate

In a Fargate-only cluster the default CoreDNS Deployment stays `Pending`, because it expects EC2 nodes. Create a profile that selects `kube-system` with the CoreDNS labels; `eksctl create cluster --fargate` does this for you.

## Patching

AWS patches the Fargate runtime, but a running pod is never modified. To pick up a patch, the pod has to be replaced. AWS may evict pods that run on a vulnerable platform version, so protect services with a [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget|PodDisruptionBudget]] and more than one replica.

## Related

- [[Kubernetes/eks/compute/README|Compute options on EKS]]
- [[Kubernetes/eks/compute/eks-auto-mode/README|EKS Auto Mode]] — managed nodes without Fargate's restrictions
- [[Kubernetes/concepts/L07-security/02-workload-sandboxing/17-runtime-sandboxing|Runtime sandboxing]] — why per-pod VMs isolate better than shared kernels
- [AWS Fargate on EKS user guide](https://docs.aws.amazon.com/eks/latest/userguide/fargate.html)

## Across the wiki

- [[Azure/compute/container-apps/README|Azure Container Apps (ACA), KEDA, and Dapr Microservices]] — serverless containers (Azure)
- [[GCP/compute/cloud-run|GCP Cloud Run]] — serverless containers (GCP)
- [[AWS/serverless/app-runner/README|AWS App Runner]] — serverless containers (AWS)
- [[Azure/compute/app-service/README|Azure App Service Architecture, Deployment Slots, and VNet Integration]] — serverless containers (Azure)
