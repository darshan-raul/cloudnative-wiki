---
title: "Runbook: EFS Volume Mount Failures"
description: "Pods with EFS-backed volumes stay ContainerCreating with mount timeouts, DNS failures or access denied. Check mount targets, security groups, access points, IAM and POSIX permissions."
tags:
  [kubernetes/eks/operator-runbook, eks, runbook, efs, storage, csi, incident]
date: 2026-10-20
aliases: [EKS EFS mount runbook, EFS CSI mount timeout]
---

# Runbook: EFS Volume Mount Failures

**Applies to:** the Amazon EFS CSI driver (`efs.csi.aws.com`) on EC2 nodes, static and dynamic (access point) provisioning. Fargate supports static provisioning, with the driver built in.
**Typical severity:** Sev 2–3. Usually one workload, but a security group change can break every EFS consumer at once.
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

```text
Warning  FailedMount  kubelet  MountVolume.SetUp failed for volume "efs-pv" : rpc error: code = DeadlineExceeded
Output: mount.nfs4: Connection timed out
Output: Failed to resolve "fs-0abc1234.efs.us-east-1.amazonaws.com" - check that your file system ID is correct ...
Output: mount.nfs4: access denied by server while mounting 127.0.0.1:/
```

Or the Pod starts, and then the application gets `Permission denied` writing to the mount.

## Impact

EFS is regional with a **mount target per AZ**, so unlike EBS, Pods can move between AZs, provided there's a mount target in every AZ where they run.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export REGION=us-east-1 NS=<namespace> POD=<pod> PVC=<claim>
export PV=$(kubectl get pvc "$PVC" -n "$NS" -o jsonpath='{.spec.volumeName}')
export HANDLE=$(kubectl get pv "$PV" -o jsonpath='{.spec.csi.volumeHandle}')   # fs-xxxx or fs-xxxx::fsap-xxxx
export FS_ID=${HANDLE%%:*}
```

## Triage

**1. Read the mount error:**

```bash
kubectl describe pod "$POD" -n "$NS" | sed -n '/Events:/,$p' | grep -A4 FailedMount | head -12
NODE=$(kubectl get pod "$POD" -n "$NS" -o jsonpath='{.spec.nodeName}')
EFS_NODE_POD=$(kubectl get pods -n kube-system -l app=efs-csi-node --field-selector spec.nodeName="$NODE" -o name)
kubectl logs -n kube-system "$EFS_NODE_POD" -c efs-plugin --tail=50
```

**2. Is there a mount target in the node's AZ, and what does it allow?**

```bash
aws efs describe-mount-targets --region "$REGION" --file-system-id "$FS_ID" \
  --query 'MountTargets[].[MountTargetId,AvailabilityZoneName,SubnetId,IpAddress,LifeCycleState]' --output table
kubectl get node "$NODE" -L topology.kubernetes.io/zone --no-headers
aws efs describe-mount-target-security-groups --region "$REGION" --mount-target-id <mount-target-id>
```

The mount target's security group must allow **TCP 2049 inbound** from the node security group (or from the Pod's, with security groups for Pods).

**3. Access point and file system policy** (dynamic provisioning, or static with an access point):

```bash
aws efs describe-access-points --region "$REGION" --file-system-id "$FS_ID" \
  --query 'AccessPoints[].[AccessPointId,PosixUser,RootDirectory.Path,LifeCycleState]' --output table
aws efs describe-file-system-policy --region "$REGION" --file-system-id "$FS_ID" 2>/dev/null | jq -r .Policy | jq
```

**4. Is provisioning failing?** For PVCs stuck `Pending`:

```bash
kubectl describe pvc "$PVC" -n "$NS" | sed -n '/Events:/,$p'
kubectl logs -n kube-system deploy/efs-csi-controller -c efs-plugin --tail=50
```

## Diagnosis

| Signal                                                         | Cause                                                  | Fix   |
| -------------------------------------------------------------- | ------------------------------------------------------ | ----- |
| `Connection timed out`                                         | A. No mount target in that AZ, or port 2049 blocked    | Fix A |
| `Failed to resolve fs-...efs...amazonaws.com`                  | B. DNS: VPC DNS settings, or no mount target in the AZ | Fix B |
| `access denied by server`                                      | C. File system policy or IAM authorization             | Fix C |
| Mount works; application gets `Permission denied`              | D. POSIX user and ownership                            | Fix D |
| PVC `Pending`; controller `AccessDenied` or access point limit | E. Provisioning: controller IAM or limits              | Fix E |

## Fix

### A. Mount target or port

- Create a mount target in every AZ where nodes run (`aws efs create-mount-target --file-system-id "$FS_ID" --subnet-id <subnet> --security-groups <sg>`), and make sure Karpenter NodePools or node groups don't run in AZs without one.
- Allow TCP 2049 from the node security group on the mount target's security group. Check CloudTrail for a recent `RevokeSecurityGroupIngress` on either group.

### B. DNS

The file system DNS name resolves only with `enableDnsSupport` and `enableDnsHostnames` on the VPC, and only to a mount target in the client's AZ. Check with `aws ec2 describe-vpc-attribute --vpc-id <vpc> --attribute enableDnsHostnames`. If you use custom DNS servers, they must forward to the VPC resolver.

### C. Access denied

- A file system policy that requires IAM authorization (`elasticfilesystem:ClientMount`, `ClientWrite`) or TLS needs the PV's mount options to include `tls` and `iam`. The **node's** IAM role (or the driver's node service account role) must have those actions allowed by the policy.
- A policy that denies non-TLS connections rejects mounts without `tls`.

### D. POSIX permissions

EFS enforces ordinary Unix permissions, and Kubernetes `fsGroup` doesn't change ownership on EFS volumes. Use an **access point** with `PosixUser` (UID and GID) and a `RootDirectory` whose `CreationInfo` sets the owner and permissions. Alternatively, run the container as the UID that owns the directory. With dynamic provisioning, set `uid` and `gid` (or `gidRangeStart` and `gidRangeEnd`) in the StorageClass parameters.

### E. Provisioning

Dynamic provisioning (`provisioningMode: efs-ap`) creates one access point per PV. The controller's role needs `elasticfilesystem:CreateAccessPoint`, `DeleteAccessPoint`, `DescribeAccessPoints`, `DescribeFileSystems` and `DescribeMountTargets` (the AWS-managed `AmazonEFSCSIDriverPolicy` covers them), plus `TagResource` if tags are used. A file system has a quota on access points. Many short-lived PVCs with `reclaimPolicy: Retain` can exhaust it, so clean up retained access points.

## Verify recovery

```bash
kubectl get pod "$POD" -n "$NS"
kubectl exec "$POD" -n "$NS" -- sh -c 'df -h | grep -i efs; touch <mount-path>/.write-test && rm <mount-path>/.write-test && echo WRITE_OK'
```

## Escalate

Open an AWS Support case if mount targets are `available`, security groups and DNS are correct, and NFS connections still time out, or if EFS reports degraded performance. Attach the file system ID, mount target IDs, node instance ID and the efs-csi-node logs.

## Prevent

- Manage mount targets per AZ in the same IaC as node subnets, and add one whenever you add an AZ.
- Use access points for every workload; don't share the file system root.
- Prefer EFS elastic throughput for spiky workloads, and alert on `PercentIOLimit` and `BurstCreditBalance` in bursting mode.

## Background

- [[Kubernetes/eks/storage/efs-csi|EFS CSI driver on EKS]]
- [[Kubernetes/guides/troubleshooting/pvc-stuck|Troubleshooting stuck PVCs]]
- [Troubleshooting Amazon EFS mounts](https://docs.aws.amazon.com/efs/latest/ug/troubleshooting-efs-mounting.html)
