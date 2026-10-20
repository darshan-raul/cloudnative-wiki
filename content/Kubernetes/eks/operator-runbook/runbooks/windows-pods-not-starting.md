---
title: "Runbook: Windows Pods Not Starting"
description: "Windows Pods stay Pending or ContainerCreating, or fail with an OS version mismatch. Check Windows IPAM, node mapping, placement and the image's Windows build."
tags: [kubernetes/eks/operator-runbook, eks, runbook, windows, nodes, incident]
date: 2026-10-20
aliases: [EKS Windows node runbook, container operating system does not match]
---

# Runbook: Windows Pods Not Starting

**Applies to:** EKS clusters with Windows Server nodes (managed or self-managed node groups, and Karpenter with Windows AMI families) running alongside the Linux nodes that every cluster still needs.
**Typical severity:** Sev 3, unless a Windows-only application is down.
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

| Message                                                                    | Cause                                                    |
| -------------------------------------------------------------------------- | -------------------------------------------------------- |
| `The container operating system does not match the host operating system`  | Image built for another Windows Server version (cause C) |
| `FailedCreatePodSandBox ... failed to setup network`, or no IP for the Pod | Windows IPAM not enabled, or out of addresses (cause A)  |
| Windows node never `Ready`, or kubelet `Unauthorized`                      | Node role mapping (cause B)                              |
| A Linux Pod lands on a Windows node and fails, or the other way round      | Placement (cause D)                                      |
| `ContainerCreating` for many minutes, then success                         | Large Windows image pulls; expected (Prevent)            |

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=my-cluster REGION=us-east-1 NS=<namespace> POD=<pod>
```

## Triage

```bash
kubectl get nodes -L kubernetes.io/os,node.kubernetes.io/windows-build -o wide
kubectl describe pod "$POD" -n "$NS" | sed -n '/Node-Selectors:/,/Tolerations:/p;/Events:/,$p'
kubectl get configmap amazon-vpc-cni -n kube-system -o yaml | grep -i windows
```

`node.kubernetes.io/windows-build` (for example `10.0.20348` for Windows Server 2022, or `10.0.17763` for 2019) is what the image has to match.

## Fix

### A. Windows IPAM not enabled

Windows Pod networking is configured by the VPC resource controller in the EKS control plane, not by an `aws-node` DaemonSet. It must be turned on in the `amazon-vpc-cni` ConfigMap:

```bash
kubectl patch configmap amazon-vpc-cni -n kube-system --type merge -p '{"data":{"enable-windows-ipam":"true"}}'
```

Windows nodes in secondary-IP mode use only their **primary ENI**, so they hold far fewer Pods than a Linux node of the same size (about IPv4 addresses per ENI − 1). For more Pods per node, set `enable-windows-prefix-delegation: "true"` in the same ConfigMap. Subnet exhaustion applies as on Linux; see [[Kubernetes/eks/operator-runbook/runbooks/pods-stuck-containercreating-ip-exhaustion|IP exhaustion]].

### B. Node role mapping

Windows node roles need the Windows mapping, or the node can't register:

- **Access entries:** `aws eks create-access-entry --cluster-name "$CLUSTER" --principal-arn <windows-node-role> --type EC2_WINDOWS`.
- **aws-auth:** the role's `groups` must include `eks:kube-proxy-windows`, as well as `system:bootstrappers` and `system:nodes`.

For instance-level logs, connect with `aws ssm start-session` (PowerShell), or run `EKS-Log-Collector.ps1` from the amazon-eks-ami repository's Windows log collector.

### C. Windows version mismatch

Windows containers with process isolation must match the host's Windows Server version. Use an image tag for the node's build (`ltsc2022` for 2022 nodes, `ltsc2019` for 2019), or a multi-arch manifest that includes both. Pin workloads to the right build:

```yaml
nodeSelector:
  kubernetes.io/os: windows
  node.kubernetes.io/windows-build: "10.0.20348"
```

### D. Placement

- Taint Windows nodes (for example `os=windows:NoSchedule`) and give Windows workloads the toleration plus `nodeSelector: {kubernetes.io/os: windows}`.
- Give **every Linux workload and DaemonSet** `nodeSelector: {kubernetes.io/os: linux}`. Broad DaemonSets (log shippers, security agents) otherwise try to run on Windows nodes and fail.
- CoreDNS, controllers and most add-ons run on Linux only. Keep at least two Linux nodes in every mixed cluster.

## Verify recovery

```bash
kubectl get pod "$POD" -n "$NS" -o wide       # Running, with a Pod IP, on a Windows node
kubectl exec "$POD" -n "$NS" -- powershell -Command "Resolve-DnsName kubernetes.default.svc.cluster.local"
```

## Escalate

Open an AWS Support case if Windows Pods can't get addresses with `enable-windows-ipam` set and subnets having free IPs (the VPC resource controller is part of the managed control plane). Attach the node and Pod names and the ConfigMap.

## Prevent

- Build Windows images for every Windows Server version in your node groups, and label node groups by build.
- Taint Windows nodes and set `kubernetes.io/os` selectors on everything.
- Pre-pull large Windows base images (for example with a DaemonSet on Windows nodes) or use AMIs with fast launch, to cut multi-minute pulls.

## Background

- [[Kubernetes/eks/compute/managed-node-groups/README|Managed node groups]]
- [Windows support in Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/windows-support.html)
- [Windows container version compatibility](https://learn.microsoft.com/en-us/virtualization/windowscontainers/deploy-containers/version-compatibility)
