---
title: "Runbook: Cluster Autoscaler Not Scaling Up"
description: "Pods stay Pending and Cluster Autoscaler doesn't add nodes, or adds them and they never arrive. Read its decision, then fix node group limits, discovery, templates, IAM or AZ placement."
tags:
  [
    kubernetes/eks/operator-runbook,
    eks,
    runbook,
    cluster-autoscaler,
    autoscaling,
    incident,
  ]
date: 2026-10-20
aliases: [EKS Cluster Autoscaler runbook, pod didn't trigger scale-up]
---

# Runbook: Cluster Autoscaler Not Scaling Up

**Applies to:** Cluster Autoscaler (CA) with managed or self-managed node groups (Auto Scaling groups). For Karpenter, use [[Kubernetes/eks/operator-runbook/runbooks/karpenter-not-launching-nodes|Karpenter not launching nodes]].
**Typical severity:** Sev 2. New capacity is blocked; running workloads are fine.
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

CA writes its decision as an event on each Pending Pod:

```text
Normal   NotTriggerScaleUp  cluster-autoscaler  pod didn't trigger scale-up: 3 node(s) didn't match Pod's node affinity/selector,
                                                2 max node group size reached, 1 node(s) had untolerated taint {dedicated: gpu}
Normal   TriggeredScaleUp   cluster-autoscaler  pod triggered scale-up: [{eks-general-2a3b... 4->6 (max: 10)}]
```

`TriggeredScaleUp` without new nodes means the ASG tried and failed. No CA event at all means CA isn't running, or doesn't see the Pod as unschedulable.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=my-cluster REGION=us-east-1 NS=<namespace> POD=<pending pod>
```

## Triage

**1. What did CA decide?**

```bash
kubectl get events -n "$NS" --field-selector involvedObject.name="$POD" --sort-by=.lastTimestamp | grep -i cluster-autoscaler
kubectl get configmap cluster-autoscaler-status -n kube-system -o jsonpath='{.data.status}' | head -60
```

The status ConfigMap shows each node group CA knows, its min, max and target size, and its health. `Backoff` means recent scale-ups failed.

**2. Is CA healthy and the right version?**

```bash
kubectl get deploy cluster-autoscaler -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler
kubectl logs -n kube-system deploy/cluster-autoscaler --tail=200 | grep -iE 'error|failed|backoff|AccessDenied' | tail -20
```

The CA minor version should match the cluster's Kubernetes minor version.

**3. Does CA discover the node groups?** With auto-discovery, the ASGs need these tags (managed node groups add them automatically):

```bash
aws autoscaling describe-auto-scaling-groups --region "$REGION" \
  --filters Name=tag-key,Values=k8s.io/cluster-autoscaler/"$CLUSTER" \
  --query 'AutoScalingGroups[].[AutoScalingGroupName,MinSize,DesiredCapacity,MaxSize,length(Instances)]' --output table
```

Both `k8s.io/cluster-autoscaler/enabled` and `k8s.io/cluster-autoscaler/<cluster>` are required.

**4. If it scaled the ASG but no node arrived, why?**

```bash
aws autoscaling describe-scaling-activities --region "$REGION" --auto-scaling-group-name <asg> --max-items 5 \
  --query 'Activities[].[StartTime,StatusCode,StatusMessage]' --output table
```

## Diagnosis

| CA message or signal                                                                                       | Cause                                         | Fix   |
| ---------------------------------------------------------------------------------------------------------- | --------------------------------------------- | ----- |
| `max node group size reached`                                                                              | A. Node group at `maxSize`                    | Fix A |
| `didn't match Pod's node affinity/selector`, `untolerated taint`, `Insufficient cpu/memory` on every group | B. No node group fits the Pod                 | Fix B |
| Group missing from the status ConfigMap                                                                    | C. Discovery tags or IAM                      | Fix C |
| Pod has an EBS volume; `volume node affinity conflict`; group spans several AZs                            | D. AZ mismatch                                | Fix D |
| Group at size 0 never chosen for Pods with special labels, taints or resources                             | E. Scale-from-zero needs template information | Fix E |
| `TriggeredScaleUp`; scaling activity failed; group in `Backoff`                                            | F. EC2 launch failure                         | Fix F |

## Fix

### A. Node group at maxSize

Confirm the demand is legitimate, then raise the maximum through the group's owner (IaC, or the CLI):

```bash
aws eks update-nodegroup-config --cluster-name "$CLUSTER" --region "$REGION" --nodegroup-name <ng> \
  --scaling-config minSize=<min>,maxSize=<new max>,desiredSize=<current>
```

Check that subnet IPs and EC2 quota can support the new maximum. Undo: lower `maxSize` again later if the raise was temporary.

### B. No node group fits the Pod

Read each part of the `NotTriggerScaleUp` message. It counts node groups rejected for each reason. Either fix the Pod (selector, toleration, smaller request) or add a node group with matching labels, taints and instance size. A request larger than the biggest instance in any group, minus DaemonSet overhead, can never fit.

All instance types in one node group must have the **same CPU and memory**. CA builds its template from one type, and assumes the rest are the same.

### C. Discovery or IAM

- Add the missing ASG tags (self-managed groups).
- The CA role needs `autoscaling:DescribeAutoScalingGroups`, `DescribeScalingActivities`, `SetDesiredCapacity`, `TerminateInstanceInAutoScalingGroup`, `ec2:DescribeLaunchTemplateVersions`, `ec2:DescribeInstanceTypes`, and `eks:DescribeNodegroup`. `AccessDenied` in the logs names the missing action. Check which role CA uses with `aws eks list-pod-identity-associations --cluster-name "$CLUSTER" --namespace kube-system`, or the service account annotation.

### D. AZ mismatch for EBS volumes

CA can't choose an AZ inside a multi-AZ ASG. For a Pod whose EBS volume is in `us-east-1b`, CA may scale a group that launches in `us-east-1a`, and the Pod stays Pending. For stateful workloads, run **one node group per AZ**, and set `--balance-similar-node-groups=true` so they grow evenly.

### E. Scale from zero

At size 0, CA has no node to copy labels, taints or extended resources from. Managed node groups provide them through `eks:DescribeNodegroup`. For self-managed groups, add ASG tags:

```text
k8s.io/cluster-autoscaler/node-template/label/<label-key>       = <value>
k8s.io/cluster-autoscaler/node-template/taint/<taint-key>       = <value>:NoSchedule
k8s.io/cluster-autoscaler/node-template/resources/nvidia.com/gpu = 1
```

### F. EC2 launch failure

The scaling activity message gives the EC2 error: `InsufficientInstanceCapacity` (add instance types or AZs), quota (`VcpuLimitExceeded`: request an increase), subnet full ([[Kubernetes/eks/operator-runbook/runbooks/pods-stuck-containercreating-ip-exhaustion|IP exhaustion]]), or a launch template problem. CA backs the group off for several minutes after a failure. Once the cause is fixed, the next loop retries.

If instances launch but never join, see [[Kubernetes/eks/operator-runbook/runbooks/node-not-ready|Node NotReady]]. CA removes unregistered nodes after `--max-node-provision-time` (15 minutes by default).

## Verify recovery

```bash
kubectl get events -A --field-selector reason=TriggeredScaleUp --sort-by=.lastTimestamp | tail -5
kubectl get nodes --sort-by=.metadata.creationTimestamp | tail -5
kubectl get pods -A --field-selector status.phase=Pending
```

## Escalate

Open an AWS Support case for persistent `InsufficientInstanceCapacity` across several instance types, or ASG launch errors that aren't explained. Attach the ASG name, scaling activity IDs and the time window. CA bugs go to the [kubernetes/autoscaler](https://github.com/kubernetes/autoscaler) project.

## Prevent

- Alert on Pods `Pending` longer than five minutes, and on node groups at `maxSize`.
- Keep CA's version in step with the cluster version during upgrades.
- Use one node group per AZ for stateful workloads, and same-sized instance types within each group.
- Consider Karpenter, which picks instance types and AZs per Pod and avoids several of these failure modes.

## Background

- [[Kubernetes/eks/compute/managed-node-groups/cluster-autoscaler|Cluster Autoscaler on EKS]]
- [[Kubernetes/guides/troubleshooting/pod-pending|Troubleshooting Pending Pods]]
- [Cluster Autoscaler FAQ](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md)
