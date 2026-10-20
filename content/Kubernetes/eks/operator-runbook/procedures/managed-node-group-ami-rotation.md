---
title: "Procedure: Rotate a Managed Node Group to a New AMI or Kubernetes Version"
description: "Roll a managed node group to a new AMI release, launch template or kubelet version with controlled surge, PDB-aware draining, and a clean way back."
tags:
  [
    kubernetes/eks/operator-runbook,
    eks,
    procedure,
    managed-node-groups,
    ami,
    upgrades,
  ]
date: 2026-10-20
aliases: [EKS node group update procedure, EKS AMI rotation]
---

# Procedure: Rotate a Managed Node Group to a New AMI or Kubernetes Version

**Applies to:** EKS managed node groups, using either an EKS-optimized AMI release version or a custom launch template.
**Duration:** roughly 5–10 minutes per batch of nodes, plus drain time.
**Risk:** medium. Every Pod on the group is evicted once.
**Tested:** not run on a live cluster; commands checked for syntax.

## When to use

- A new EKS AMI release (security patches; roughly every two weeks).
- The data-plane stage of a [[Kubernetes/eks/operator-runbook/procedures/control-plane-upgrade|control-plane upgrade]].
- A launch template change (user data, instance type, volume size).

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=my-cluster REGION=us-east-1 NODEGROUP=<node group>
```

## Pre-checks

**1. Current state:**

```bash
aws eks describe-nodegroup --cluster-name "$CLUSTER" --region "$REGION" --nodegroup-name "$NODEGROUP" \
  --query 'nodegroup.{status:status,version:version,release:releaseVersion,lt:launchTemplate,scaling:scalingConfig,update:updateConfig,health:health.issues}' \
  | tee "$EVIDENCE_DIR/nodegroup-$NODEGROUP-before.json"
```

- **Expect:** `status: ACTIVE`, with no health issues. Note `releaseVersion` or the launch template version; that's your rollback target.

**2. Surge capacity.** The update launches new nodes before draining old ones, so there must be room for `maxUnavailable` extra nodes: in the group's `maxSize`, in the subnets' free IPs, and in EC2 quota.

**3. Drains won't block.** A PDB at `ALLOWED DISRUPTIONS 0` makes evictions fail. After 15 minutes the update fails with `PodEvictionFailure`.

```bash
kubectl get pdb -A | awk 'NR==1 || $(NF-1)=="0"'
kubectl get pods -A -o wide --field-selector spec.nodeName=<a node in the group> \
  -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,OWNER:.metadata.ownerReferences[0].kind
```

Fix PDBs whose workloads are unhealthy, and find bare Pods (no owner), which won't be recreated.

**4. Test the new AMI** in a canary node group, or in staging, first: node joins, DaemonSets start, and a representative workload runs.

## Steps

**1. Set the batch size.** Use a number or a percentage (maximum 100 nodes or 100%). Smaller is safer:

```bash
aws eks update-nodegroup-config --cluster-name "$CLUSTER" --region "$REGION" --nodegroup-name "$NODEGROUP" \
  --update-config maxUnavailablePercentage=10
```

**2. Start the update.** Pick the form that matches the group:

```bash
# EKS-optimized AMI: latest release for the cluster version (or pass --release-version)
UPDATE_ID=$(aws eks update-nodegroup-version --cluster-name "$CLUSTER" --region "$REGION" \
  --nodegroup-name "$NODEGROUP" --query update.id --output text)

# Kubernetes version change
UPDATE_ID=$(aws eks update-nodegroup-version --cluster-name "$CLUSTER" --region "$REGION" \
  --nodegroup-name "$NODEGROUP" --kubernetes-version "$TARGET_VERSION" --query update.id --output text)

# Custom launch template: create the new version first, then
UPDATE_ID=$(aws eks update-nodegroup-version --cluster-name "$CLUSTER" --region "$REGION" \
  --nodegroup-name "$NODEGROUP" --launch-template name=<lt-name>,version=<new-version> --query update.id --output text)
```

Don't add `--force` on the first attempt. It ignores PDBs and evicts anyway.

**3. Watch.**

```bash
watch -n 30 "aws eks describe-update --name $CLUSTER --region $REGION --nodegroup-name $NODEGROUP --update-id $UPDATE_ID --query 'update.[status,errors]' --output text; kubectl get nodes -l eks.amazonaws.com/nodegroup=$NODEGROUP -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[-1].type,KUBELET:.status.nodeInfo.kubeletVersion,AGE:.metadata.creationTimestamp"
```

- **Checkpoint per batch:** new nodes are `Ready` with the new kubelet or AMI, evicted Pods are Running elsewhere, and service error rates stay at the baseline.

## Abort criteria and rollback

Stop if new nodes don't become Ready, Pods on new nodes fail, or error rates rise.

- A managed node group update **can't be cancelled** midway. If new nodes fail to join, the update fails on its own and leaves the remaining old nodes in place.
- **To go back:** run `update-nodegroup-version` with the previous `--release-version`, or the previous `--launch-template` version from the pre-check. This is another rolling update.
- **`PodEvictionFailure`:** find the blocking PDB in the update's `errors`, fix the workload's health or capacity, and retry. Use `--force` only with the workload owner's agreement.

## If the update is stuck or fails

An update stays `InProgress` while it works through its phases: scale up, launch new nodes, drain old nodes, scale down. Read where it is and why:

```bash
aws eks describe-update --name "$CLUSTER" --region "$REGION" --nodegroup-name "$NODEGROUP" --update-id "$UPDATE_ID" \
  --query 'update.{status:status,errors:errors}'
aws eks describe-nodegroup --cluster-name "$CLUSTER" --region "$REGION" --nodegroup-name "$NODEGROUP" \
  --query 'nodegroup.{status:status,health:health.issues}'
ASG=$(aws eks describe-nodegroup --cluster-name "$CLUSTER" --region "$REGION" --nodegroup-name "$NODEGROUP" \
  --query 'nodegroup.resources.autoScalingGroups[0].name' --output text)
aws autoscaling describe-scaling-activities --region "$REGION" --auto-scaling-group-name "$ASG" --max-items 5 \
  --query 'Activities[].[StartTime,StatusCode,StatusMessage]' --output table
```

| Error or health code                                                             | Meaning and fix                                                                                                                                                                                                                                                         |
| -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PodEvictionFailure`                                                             | A PDB blocked eviction for 15 minutes. The error names the Pod. Fix the workload's health or capacity so the PDB allows a disruption, then retry. Use `--force` only with the owner's agreement                                                                         |
| `NodeCreationFailure`                                                            | New instances launched but didn't join. Treat one as [[Kubernetes/eks/operator-runbook/runbooks/node-not-ready\|Node NotReady]]: the usual causes are a missing node role access entry, user data errors in the new launch template, or no route to the endpoint or ECR |
| `AsgInstanceLaunchFailures`, `InstanceLimitExceeded`                             | EC2 couldn't launch: capacity for that instance type, or account quota. The scaling activities above show the EC2 message. Add instance types to the group, or raise the quota                                                                                          |
| `InsufficientFreeAddresses`                                                      | Subnets have no room for surge nodes. See [[Kubernetes/eks/operator-runbook/runbooks/pods-stuck-containercreating-ip-exhaustion\|IP exhaustion]], or lower `maxUnavailable`                                                                                             |
| `AmiIdNotFound`, `Ec2LaunchTemplateNotFound`, `Ec2LaunchTemplateVersionMismatch` | The launch template or AMI referenced by the update is gone or wrong. Fix the template version, and retry                                                                                                                                                               |
| `AccessDenied`, `IamInstanceProfileNotFound`                                     | The EKS service-linked role or the node role was changed. Restore the role and its policies from IaC                                                                                                                                                                    |
| `ClusterUnreachable`                                                             | The nodes can't reach the cluster endpoint: endpoint access settings, security groups or routes changed                                                                                                                                                                 |

A failed update leaves the group `ACTIVE` (or `DEGRADED`) with a mix of old and new nodes; both are within skew, so workloads keep running. Fix the cause, then run the same `update-nodegroup-version` again; it carries on from the current state.

## Post-checks

```bash
kubectl get nodes -l eks.amazonaws.com/nodegroup="$NODEGROUP" \
  -o custom-columns=NAME:.metadata.name,KUBELET:.status.nodeInfo.kubeletVersion,OS:.status.nodeInfo.osImage
kubectl get pods -A | grep -Ev 'Running|Completed'
```

All nodes are on the new version, and no Pods are stuck.

## Clean-up

- Put the batch size back if you changed it only for this rollout.
- Update the AMI release or launch template version in IaC.
- Delete old launch template versions you won't roll back to.

## Background

- [[Kubernetes/eks/compute/managed-node-groups/basics|Managed node group basics]]
- [[Kubernetes/eks/compute/managed-node-groups/README|Managed node groups]]
- [Updating a managed node group](https://docs.aws.amazon.com/eks/latest/userguide/update-managed-node-group.html)
