---
title: "Runbook: GPU Pods Pending or Failing"
description: "Pods requesting nvidia.com/gpu stay Pending, land on nodes that never advertise GPUs, or start and fail with CUDA or driver errors. Check capacity, NodePools, the device plugin and driver compatibility."
tags:
  [
    kubernetes/eks/operator-runbook,
    eks,
    runbook,
    gpu,
    nvidia,
    accelerators,
    incident,
  ]
date: 2026-10-20
aliases: [EKS GPU runbook, Insufficient nvidia.com/gpu]
---

# Runbook: GPU Pods Pending or Failing

**Applies to:** NVIDIA GPU instances (`g` and `p` families) on managed node groups, Karpenter and Auto Mode, with the EKS-optimized accelerated AMIs (AL2023 NVIDIA or Bottlerocket NVIDIA variants). AWS Trainium and Inferentia use the Neuron device plugin and `aws.amazon.com/neuron`; the same steps apply with those names.
**Typical severity:** Sev 2–3. Usually training or inference capacity, not the whole cluster.
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

```text
Warning  FailedScheduling  default-scheduler  0/12 nodes are available: 12 Insufficient nvidia.com/gpu.
```

Or a GPU node exists but shows no allocatable GPUs, or the container starts and fails with:

```text
CUDA driver version is insufficient for CUDA runtime version
Failed to initialize NVML: Unknown Error
```

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export REGION=us-east-1 NS=<namespace> POD=<pod>
```

## Triage

**1. Do any nodes advertise GPUs?**

```bash
kubectl get nodes -L node.kubernetes.io/instance-type \
  -o 'custom-columns=NAME:.metadata.name,TYPE:.metadata.labels.node\.kubernetes\.io/instance-type,GPU:.status.allocatable.nvidia\.com/gpu'
```

- **If** a GPU instance type shows `<none>` → the device plugin isn't running or isn't working on it (cause B).
- **If** no GPU nodes exist → provisioning (cause A).

**2. Is the device plugin running on the GPU nodes?**

```bash
kubectl get ds -A | grep -iE 'nvidia|device-plugin|gpu-operator'
kubectl get pods -A -o wide | grep -iE 'nvidia-device-plugin' | head
```

Bottlerocket NVIDIA variants and Auto Mode provide the device plugin themselves. AL2023 NVIDIA AMIs include the driver and container toolkit, but **not** the device plugin; you install it (NVIDIA device plugin chart, or the GPU Operator with its driver installation turned off).

**3. On the node, does the driver see the GPUs?**

```bash
aws ssm start-session --target <instance-id>
nvidia-smi
sudo dmesg -T | grep -i xid | tail       # Xid errors indicate GPU hardware or driver faults
```

## Diagnosis

| Signal                                                                           | Cause                                       | Fix   |
| -------------------------------------------------------------------------------- | ------------------------------------------- | ----- |
| No GPU nodes; Karpenter `incompatible` or ICE; ASG launch failures               | A. No GPU capacity provisioned              | Fix A |
| GPU node, `allocatable` has no `nvidia.com/gpu`                                  | B. Device plugin missing or not on the node | Fix B |
| Pod lands on the GPU node but other Pods fill it; GPU nodes running non-GPU work | C. GPU nodes not reserved                   | Fix C |
| `CUDA driver version is insufficient`                                            | D. Image CUDA newer than the node driver    | Fix D |
| `nvidia-smi` fails or Xid errors; GPU count dropped                              | E. GPU hardware or driver fault             | Fix E |

## Fix

### A. No GPU capacity

- **Karpenter:** a NodePool must allow GPU instance types, for example `karpenter.k8s.aws/instance-family In [g5, g6, p4d, p5]`, or `karpenter.k8s.aws/instance-gpu-count Gt 0`. With an `al2023` or `bottlerocket` alias, Karpenter chooses the accelerated AMI variant for GPU instances automatically.
- **Quota:** GPU instances have separate quotas ("Running On-Demand G and VT instances", "Running On-Demand P instances", and Spot equivalents), counted in vCPUs. Check with `aws service-quotas list-service-quotas --service-code ec2 --query "Quotas[?contains(QuotaName,'G and VT') || contains(QuotaName,' P ')].[QuotaName,Value]"`.
- **Capacity:** large GPU types are often short in some AZs. Allow several types and all AZs, or use On-Demand Capacity Reservations or EC2 Capacity Blocks for ML (referenced from the EC2NodeClass `capacityReservationSelectorTerms` in recent Karpenter versions).

### B. Device plugin missing

Install the device plugin DaemonSet. If GPU nodes carry a taint (recommended, see C), the DaemonSet needs the matching toleration, or it never runs there. That's the most common reason for a GPU node with no allocatable GPUs.

```bash
kubectl get ds <device-plugin-ds> -n <ns> -o jsonpath='{.spec.template.spec.tolerations}{"\n"}{.spec.template.spec.nodeSelector}{"\n"}'
kubectl describe node <gpu-node> | grep -A3 Taints
```

### C. GPU nodes not reserved

Taint GPU capacity (`nvidia.com/gpu=true:NoSchedule`, in the NodePool or node group), so ordinary Pods don't fill it. Then give GPU workloads the toleration. Requesting `nvidia.com/gpu` alone doesn't keep other Pods off.

### D. CUDA driver mismatch

The CUDA **runtime** in the image needs a minimum **driver** version on the host. Either use an image built for an older CUDA, or move the workload to nodes with a newer driver: a newer accelerated AMI release, pinned through the EC2NodeClass or launch template. Check the driver with `nvidia-smi` (top line) against NVIDIA's CUDA compatibility table.

### E. GPU fault

Cordon and replace the node. GPU faults usually need a new instance, not a reboot. The EKS node monitoring agent detects many accelerator faults, and node auto repair (or Karpenter or Auto Mode repair) can replace those nodes automatically when enabled. Long training jobs should checkpoint, so a replaced node costs minutes, not days.

## Verify recovery

```bash
kubectl get pod "$POD" -n "$NS" -o wide
kubectl exec "$POD" -n "$NS" -- nvidia-smi -L
```

## Escalate

Open an AWS Support case for repeated Xid errors or GPUs missing on fresh instances of the same type, and for capacity planning of large reservations. Attach the instance IDs, the `nvidia-smi` output and the dmesg excerpts.

## Prevent

- Keep separate, tainted NodePools or node groups for GPU capacity, with the device plugin tolerating that taint.
- Pin accelerated AMI versions, and test new ones with your CUDA images before rolling them out.
- Alert on GPU nodes whose allocatable `nvidia.com/gpu` is 0, and on Pending GPU Pods.
- Use time-slicing or MIG for small inference workloads, so they don't each hold a whole GPU.

## Background

- [[Kubernetes/eks/compute/karpenter/README|Karpenter on EKS]]
- [[Kubernetes/eks/compute/eks-auto-mode/README|EKS Auto Mode]]
- [Amazon EKS accelerated AMIs](https://docs.aws.amazon.com/eks/latest/userguide/ml-eks-optimized-ami.html)
- [NVIDIA CUDA compatibility](https://docs.nvidia.com/deploy/cuda-compatibility/)
