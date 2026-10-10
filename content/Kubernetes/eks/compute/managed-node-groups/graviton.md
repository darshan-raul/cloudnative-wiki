---
title: Graviton (Arm) Nodes on EKS
tags: [eks, compute, graviton, arm64, cost-optimization]
date: 2026-05-17
description: Running EKS workloads on AWS Graviton — why it is cheaper, building multi-architecture images, creating Arm node groups, steering pods safely during a migration, and the compatibility problems to expect.
---

# Graviton (Arm) Nodes on EKS

Graviton is AWS's family of Arm-based processors. Graviton instances (`m7g`, `c8g`, `r8g`, `t4g` and so on) cost roughly 20% less per hour than comparable x86 instances and often do more work per vCPU, because each vCPU is a full physical core rather than a hyper-thread. For most services the combined price-performance gain is 20–40%, which makes it one of the larger cost levers available on EKS.

The cost is that every image you run must exist for `arm64`.

## What has to be true

1. **Every container image is multi-architecture** (or Arm-only): your applications, their base images, sidecars and init containers.
2. **Every DaemonSet and add-on supports Arm.** The EKS add-ons (VPC CNI, CoreDNS, kube-proxy, CSI drivers) and most mainstream tools do. Check third-party agents — commercial security and APM agents are the usual stragglers.
3. **Native dependencies are available for Arm**: compiled libraries, language wheels with C extensions, database drivers.

An image without an `arm64` variant fails on a Graviton node with `exec format error` or `no matching manifest for linux/arm64`. See [[Containers/images-and-layers|images and layers]] for how multi-architecture manifests work.

## Building multi-architecture images

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t 111122223333.dkr.ecr.eu-west-1.amazonaws.com/checkout:1.4.2 \
  --push .
```

Emulated builds (QEMU) are slow. Two better options:

- **Cross-compile** in the build stage for languages that support it: `FROM --platform=$BUILDPLATFORM` with `GOARCH=$TARGETARCH` — see [[Containers/dockerfile-best-practices|Dockerfile best practices]].
- **Build natively on Arm runners** (CodeBuild Arm fleets, GitHub Arm runners) and combine the per-architecture images into one manifest list.

Verify before deploying:

```bash
docker buildx imagetools inspect <image>   # should list linux/amd64 and linux/arm64
```

## Creating Arm capacity

**Managed node group:**

```yaml
managedNodeGroups:
  - name: graviton
    amiFamily: AmazonLinux2023
    instanceTypes: ["m7g.large", "m6g.large", "m8g.large"]
    minSize: 2
    maxSize: 10
```

EKS picks the Arm AMI automatically from the instance type. A node group cannot mix architectures. See [[Kubernetes/eks/compute/managed-node-groups/basics|node group basics]].

**Karpenter or Auto Mode:** allow both architectures in one NodePool and let it choose the cheapest that fits:

```yaml
requirements:
  - key: kubernetes.io/arch
    operator: In
    values: ["arm64", "amd64"]
```

With multi-arch images this usually results in Graviton being selected, because it is cheaper. Spot Graviton pools are also often less contended — [[Kubernetes/eks/compute/managed-node-groups/spot|Spot on EKS]].

## Steering pods during migration

Every node carries the label `kubernetes.io/arch`. Until all images are multi-arch, protect yourself:

```yaml
# For a workload that is x86-only today
nodeSelector:
  kubernetes.io/arch: amd64
```

A safe sequence:

1. **Taint the Graviton nodes** (`arch=arm64:NoSchedule`) so nothing lands there by accident.
2. **Move one stateless service**: add a toleration and an `arm64` node selector, run both architectures side by side behind the same Service.
3. **Compare** latency, error rate and CPU per request under real traffic.
4. **Shift replicas** gradually, then repeat per service.
5. **Remove the taint** when everything, including DaemonSets, is multi-arch. An x86-only DaemonSet pod in `CrashLoopBackOff` on every Arm node is the classic leftover.

An admission policy that rejects single-architecture images in mixed clusters prevents regressions — [[Kubernetes/eks/security/policy-management|policy management]].

## Compatibility notes

| Area                        | What to check                                                                                |
| :-------------------------- | :------------------------------------------------------------------------------------------- |
| Go, Rust                    | Cross-compile cleanly; nothing special                                                       |
| Java, .NET, Node.js, Python | Runtimes are fine; check native modules (JNI libraries, `node-gyp` addons, wheels)           |
| Older JVMs                  | Use a recent JDK; Arm optimisations improved substantially in newer releases                 |
| Hand-written assembly, SIMD | x86 intrinsics (AVX) need Arm (NEON/SVE) equivalents or a portable fallback                  |
| Performance tuning          | Results differ per workload: measure rather than assume, especially for single-threaded code |
| Memory ordering             | Arm's weaker memory model can expose latent concurrency bugs that x86 happened to hide       |

## Expected savings

For a service that moves unchanged, expect roughly the list-price difference (about 20%). For CPU-bound services that benefit from real cores, fewer replicas may be needed as well. Savings Plans and Spot stack on top. Track cost per request before and after rather than instance cost alone — [[AWS/cost-management/ec2-cost-optimization|EC2 cost optimization]] and [[Kubernetes/eks/advanced/cost-optimization|EKS cost optimization]].

## Related

- [[Kubernetes/eks/compute/managed-node-groups/README|Managed node groups]]
- [[Kubernetes/eks/compute/karpenter/README|Karpenter]]
- [[Kubernetes/concepts/L06-scheduling-scaling/02-scheduling|Scheduling]] — node selectors, taints and tolerations
- [[Kubernetes/eks/automation/continuous-delivery/codepipeline|CodePipeline]] — Arm build fleets
- [AWS Graviton getting started guide](https://github.com/aws/aws-graviton-getting-started)
