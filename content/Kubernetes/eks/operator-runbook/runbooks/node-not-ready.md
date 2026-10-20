---
title: "Runbook: Node NotReady"
description: "One or more EKS nodes report NotReady or Unknown. Find whether the instance, the kubelet's path to the API, the CNI or node resources failed, then recover or replace the node safely."
tags: [kubernetes/eks/operator-runbook, eks, runbook, nodes, kubelet, incident]
date: 2026-10-20
aliases: [EKS node NotReady runbook, Kubelet stopped posting node status]
---

# Runbook: Node NotReady

**Applies to:** EC2 Linux nodes in managed node groups, self-managed groups and Karpenter (AL2023 and Bottlerocket). Auto Mode differences are noted inline.
**Typical severity:** one node is Sev 3 if workloads have spare replicas. Many nodes at once is Sev 1; go straight to [[#Many nodes at once|Many nodes at once]].
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

- `kubectl get nodes` shows `NotReady`.
- `kubectl describe node` shows one of these `Ready` conditions:

  ```text
  Ready  Unknown  NodeStatusUnknown  Kubelet stopped posting node status.
  Ready  False    KubeletNotReady    container runtime network not ready: NetworkReady=false
                                     reason:NetworkPluginNotReady message:Network plugin returns error: cni plugin not initialized
  Ready  False    KubeletNotReady    PLEG is not healthy: pleg was last seen active 3m0s ago
  ```

- Pods on the node show `Terminating` or `Unknown`, and replacement Pods appear elsewhere about five minutes later.

## Impact and timeline

| Time after the kubelet goes quiet | What Kubernetes does                                                                                                                    |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| ~40–50 s                          | Node becomes `Ready=Unknown`; taint `node.kubernetes.io/unreachable:NoExecute` is added (or `not-ready` if the kubelet reports `False`) |
| 300 s                             | Pods using the default toleration (`tolerationSeconds: 300`) are evicted; Deployment/ReplicaSet replacements start on other nodes       |
| Indefinitely                      | **StatefulSet Pods and their volumes stay bound to the old node** until the node is deleted or marked out of service (see Fix step 4)   |

Containers on an unreachable node may still be running. A partitioned node can keep serving traffic or writing to external systems.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=my-cluster REGION=us-east-1 NODE=<node name>
export INSTANCE_ID=$(kubectl get node "$NODE" -o jsonpath='{.spec.providerID}' | awk -F/ '{print $NF}')
```

## Triage

**1. One node or many?**

```bash
kubectl get nodes -o wide | grep -v ' Ready '
kubectl get nodes -L topology.kubernetes.io/zone,eks.amazonaws.com/nodegroup,karpenter.sh/nodepool | grep -v ' Ready '
```

- **If** many nodes went NotReady at the same time → skip to [[#Many nodes at once|Many nodes at once]].
- **If** they all share an AZ → check AWS Health for that AZ, and consider [[Kubernetes/eks/operator-runbook/procedures/zonal-shift|zonal shift]].

**2. Read the condition and the last heartbeat.**

```bash
kubectl describe node "$NODE" | sed -n '/Conditions:/,/Addresses:/p'
kubectl get lease "$NODE" -n kube-node-lease -o jsonpath='{.spec.renewTime}{"\n"}'
kubectl get events -A --field-selector involvedObject.name="$NODE" --sort-by=.lastTimestamp | tail -20
```

- `Ready=Unknown` with a stale lease → the kubelet can't reach the API, or the instance is down. Go to step 3.
- `Ready=False` → the kubelet is talking to the API and telling you what's wrong. Read the message and go to [[#Diagnosis|Diagnosis]].
- `MemoryPressure`, `DiskPressure` or `PIDPressure` = `True` → resource exhaustion (cause E).

**3. Is the instance alive?**

```bash
aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[].Instances[].{state:State.Name,reason:StateTransitionReason,lifecycle:InstanceLifecycle,launch:LaunchTime}'
aws ec2 describe-instance-status --region "$REGION" --instance-ids "$INSTANCE_ID" --include-all-instances \
  --query 'InstanceStatuses[].{system:SystemStatus.Status,instance:InstanceStatus.Status,events:Events}'
```

- **If** the state is `shutting-down` or `terminated`, or the lifecycle is `spot` with a recent interruption → the node is being removed (cause A). Usually nothing to fix.
- **If** the system or instance status is `impaired` → EC2 or host failure (cause A).
- **If** the instance is `running` and status checks pass → the problem is inside the OS or on the network path. Go to step 4.

**4. Get on the node.**

```bash
aws ec2 get-console-output --region "$REGION" --instance-id "$INSTANCE_ID" --latest --output text | tail -50
aws ssm start-session --region "$REGION" --target "$INSTANCE_ID"
```

The console output works even when the OS is too broken for SSM. Look for `Out of memory: Killed process`, `kernel panic`, `hung_task` or filesystem errors.

On **AL2023**:

```bash
sudo systemctl status kubelet containerd --no-pager
sudo journalctl -u kubelet --since "-30min" --no-pager | grep -Ei 'error|unauthorized|timeout|pleg' | tail -40
free -m; df -h / /var/lib/containerd; df -i /; ps -eLf | wc -l
```

On **Bottlerocket**, SSM lands in the control container. Run `enter-admin-container`, then `sudo sheltie` for a host shell; the same `systemctl` and `journalctl` commands work there.

Before restarting anything, collect logs, because a restart can destroy the evidence:

```bash
curl -sO https://raw.githubusercontent.com/awslabs/amazon-eks-ami/main/log-collector-script/linux/eks-log-collector.sh
sudo bash eks-log-collector.sh      # writes /var/log/eks_<instance>_<date>.tar.gz
```

If SSM won't connect either, the instance is effectively lost. Treat it as cause A.

## Diagnosis

| Signal                                                                                | Cause                                             | Fix                                                                |
| ------------------------------------------------------------------------------------- | ------------------------------------------------- | ------------------------------------------------------------------ |
| Instance terminated, impaired, or Spot-interrupted                                    | A. Instance gone or failed                        | Replace (step 3)                                                   |
| Kubelet log: `Unauthorized`, `x509`, `dial tcp ... i/o timeout` to the API endpoint   | B. Kubelet can't authenticate to or reach the API | [[#Many nodes at once\|Many nodes at once]] — usually cluster-wide |
| `cni plugin not initialized` / `NetworkPluginNotReady`                                | C. `aws-node` not running on the node             | Step 1                                                             |
| `PLEG is not healthy`; `containerd` unresponsive                                      | D. Container runtime hung                         | Step 2                                                             |
| Pressure condition `True`; OOM in console output; disk or inodes full; PIDs exhausted | E. Node resource exhaustion                       | Step 2, then the prevention steps                                  |

## Fix

**1. CNI not ready (cause C).**

```bash
kubectl get pods -n kube-system -o wide --field-selector spec.nodeName="$NODE" | grep -E 'aws-node|kube-proxy'
kubectl logs -n kube-system <aws-node-pod> -c aws-node --tail=100
kubectl logs -n kube-system <aws-node-pod> -c aws-vpc-cni-init
```

Common reasons: the `aws-node` image can't be pulled (no route to ECR from a private subnet without VPC endpoints), the CNI role lacks `AmazonEKS_CNI_Policy`, or IMDS is unreachable (hop limit too low for a container: `HttpPutResponseHopLimit` must be ≥ 2 if `aws-node` uses IMDS). Fix the cause; the node turns Ready on its own once `aws-node` is `2/2`. For IP allocation errors, see [[Kubernetes/eks/operator-runbook/runbooks/pods-stuck-containercreating-ip-exhaustion|IP exhaustion]].

**2. Runtime hung or node exhausted (causes D, E).** Once you've collected evidence:

```bash
sudo systemctl restart containerd && sudo systemctl restart kubelet
```

- **If** the node returns to `Ready` → find what ate the resource before it recurs. Look for Pods without memory limits, log volume under `/var/log/pods`, runaway images, or a fork bomb. Fix that workload, then consider replacing the node anyway.
- **If** disk is full of images: `sudo crictl rmi --prune`. If it's full of logs or `emptyDir` data, find the owning Pod first (`sudo du -sh /var/lib/kubelet/pods/* | sort -h | tail`).
- **If** restarting doesn't work, or the OS is unresponsive → replace the node (step 3). Replacement is usually faster than repair, and you have the logs.

**3. Replace the node.** First check whether something else is already replacing it, so you don't race it:

- **Managed node group with node auto repair** enabled (`aws eks describe-nodegroup ... --query nodegroup.nodeRepairConfig`), or **Auto Mode**: these replace unhealthy nodes themselves after a grace period. Watch before you act.
- **Karpenter:** delete the NodeClaim. Karpenter drains what it can, terminates the instance and launches a replacement if Pods need it.

  ```bash
  kubectl get nodeclaims -o wide | grep "$NODE"
  kubectl delete nodeclaim <nodeclaim-name>
  ```

- **Managed or self-managed node group:** drain, then terminate through the Auto Scaling group so it launches a replacement.

  ```bash
  kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data --timeout=5m
  aws autoscaling terminate-instance-in-auto-scaling-group --region "$REGION" \
    --instance-id "$INSTANCE_ID" --no-should-decrement-desired-capacity
  ```

  On an unreachable node the drain can time out, because evictions are accepted but the kubelet never confirms them. That's expected; terminate anyway once the instance is confirmed bad.

**4. Release stateful Pods and volumes.** StatefulSet Pods and their EBS volumes stay stuck on an unreachable node. Kubernetes won't start a second copy while the first might still be writing.

**⚠ Destructive:** only after `describe-instances` shows the instance is `stopped` or `terminated`. If it's still running and partitioned, stop it first (`aws ec2 stop-instances --force`) so the old copy can't keep writing.

```bash
kubectl taint node "$NODE" node.kubernetes.io/out-of-service=nodeshutdown:NoExecute
```

This force-deletes the Pods on the node and lets the attach/detach controller detach their volumes immediately, instead of waiting about six minutes. Remove the taint if the node comes back (`kubectl taint node "$NODE" node.kubernetes.io/out-of-service-`); normally the node object is deleted with the instance. Don't use `kubectl delete pod --force` on StatefulSet Pods as a shortcut: it skips the volume detach and the stop-the-instance safety check.

## Many nodes at once

Many nodes going NotReady together is almost never many separate node faults. Look for one shared dependency.

```bash
aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
  --query 'cluster.{status:status,endpointPublic:resourcesVpcConfig.endpointPublicAccess,endpointPrivate:resourcesVpcConfig.endpointPrivateAccess,publicCidrs:resourcesVpcConfig.publicAccessCidrs,clusterSG:resourcesVpcConfig.clusterSecurityGroupId}'
aws eks list-access-entries --cluster-name "$CLUSTER" --region "$REGION"
kubectl get configmap aws-auth -n kube-system -o yaml 2>/dev/null
aws cloudtrail lookup-events --region "$REGION" --start-time "$(date -u -d '-2 hours' +%FT%TZ)" \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=eks.amazonaws.com \
  --query 'Events[].[EventTime,EventName,Username]' --output table
```

| Look for                                                                                                                   | Cause and fix                                                                                                                                                                                                                                                                                                |
| -------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Kubelet logs `Unauthorized`; the node role is missing from access entries (type `EC2_LINUX`) or from `aws-auth` `mapRoles` | The node role mapping was removed or `aws-auth` was overwritten. Restore it: `aws eks create-access-entry --cluster-name "$CLUSTER" --principal-arn <node-role-arn> --type EC2_LINUX`, or restore the `mapRoles` entry with groups `system:bootstrappers` and `system:nodes`. Nodes recover within a minute. |
| Kubelet logs `i/o timeout` to the endpoint; recent `UpdateClusterConfig` event                                             | Endpoint access changed (private access turned off, or the public CIDR list no longer includes the NAT IPs). Revert it with `aws eks update-cluster-config --resources-vpc-config ...`.                                                                                                                      |
| Timeouts, no EKS change                                                                                                    | Security group, NACL, route table or Transit Gateway change between the node subnets and the cluster ENIs. The nodes need TCP 443 to the cluster security group. Check CloudTrail for `ec2.amazonaws.com` events such as `RevokeSecurityGroupIngress`, `ReplaceRoute` and `ReplaceNetworkAclEntry`.          |
| All nodes from one launch template or AMI version                                                                          | Bad AMI or user-data rollout. Stop the rollout, and roll the node group back to the previous launch template version.                                                                                                                                                                                        |
| Nodes in one AZ only                                                                                                       | AZ impairment. Check AWS Health; shift traffic away from the AZ.                                                                                                                                                                                                                                             |

Don't replace nodes in bulk until you've found the shared cause. New nodes hit the same wall, and churn adds evictions on top.

## Verify recovery

```bash
kubectl get nodes                                   # all Ready, including replacements
kubectl get pods -A -o wide | grep -Ev 'Running|Completed'
kubectl get pdb -A                                  # ALLOWED DISRUPTIONS back above 0
```

Check that StatefulSet members rejoined their clusters (database replication, quorum), not just that the Pods are `Running`. Remove any `out-of-service` taints left on nodes that still exist.

## Escalate

Open an AWS Support case when:

- system status checks fail on several instances;
- several nodes in one AZ fail without any change on your side;
- the kubelet can't reach a healthy-looking endpoint and you can't find a network or IAM change.

Attach the cluster ARN, instance IDs, the UTC time window, the `eks-log-collector` tarball and console output from one affected node, and relevant CloudTrail events.

## Prevent

- Alert on `kube_node_status_condition{condition="Ready",status!="true"}` lasting more than 2 minutes, and on node count dropping below the expected minimum.
- Set memory limits or `LimitRange` defaults. Keep `kubeReserved` and `systemReserved` at the EKS defaults or higher, so workloads can't starve the kubelet.
- Manage access entries (or `aws-auth`) through IaC only, and alert on CloudTrail `DeleteAccessEntry` and on `aws-auth` edits.
- Enable node auto repair on managed node groups, or rely on Karpenter or Auto Mode, so single-node failures fix themselves.
- Roll AMIs one node group at a time, and stop if new nodes don't reach `Ready`.

## Background

- [[Kubernetes/concepts/L08-operations/03-common-failure-modes|Common failure modes]]
- [[Kubernetes/eks/security/access/cluster-access-management|Cluster access management (access entries)]] and [[Kubernetes/eks/security/access/aws-auth-legacy|aws-auth (legacy)]]
- [[Kubernetes/eks/compute/managed-node-groups/README|Managed node groups]] and [[Kubernetes/eks/compute/karpenter/README|Karpenter]]
- [Non-graceful node shutdown](https://kubernetes.io/docs/concepts/cluster-administration/node-shutdown/#non-graceful-node-shutdown)
- [EKS node health and auto repair](https://docs.aws.amazon.com/eks/latest/userguide/node-health.html)
