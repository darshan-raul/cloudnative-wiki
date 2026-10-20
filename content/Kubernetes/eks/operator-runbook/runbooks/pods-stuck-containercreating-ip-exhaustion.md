---
title: "Runbook: Pods Stuck ContainerCreating (VPC CNI IP Exhaustion)"
description: "New Pods stay in ContainerCreating with 'failed to assign an IP address to container'. Find whether the subnet, the node or the CNI is out of addresses, and fix it."
tags:
  [kubernetes/eks/operator-runbook, eks, runbook, vpc-cni, networking, incident]
date: 2026-10-20
aliases:
  [EKS IP exhaustion runbook, failed to assign an IP address to container]
---

# Runbook: Pods Stuck ContainerCreating (VPC CNI IP Exhaustion)

**Applies to:** Linux nodes on managed node groups, self-managed groups and Karpenter, using the Amazon VPC CNI (`aws-node`) in secondary-IP or prefix mode. Auto Mode and Fargate assign addresses differently; see the note at the end.
**Typical severity:** Sev 2. Running Pods are fine; new Pods, rollouts and scale-ups stall.
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

- Pods stay `ContainerCreating`, and `kubectl describe pod` shows:

  ```text
  Warning  FailedCreatePodSandBox  kubelet  Failed to create pod sandbox: rpc error: code = Unknown
  desc = failed to setup network for sandbox "...": plugin type="aws-cni" name="aws-cni" failed (add):
  add cmd: failed to assign an IP address to container
  ```

- Rollouts hang at partial progress; HPA scales out but new replicas never become Ready.
- The ipamd log on the node contains EC2 errors such as `InsufficientFreeAddressesInSubnet`, `InsufficientCidrBlocks` (prefix mode) or `UnauthorizedOperation`.

## Impact

Existing Pods keep their addresses and keep serving. Anything that needs a new Pod is blocked: deploys, scale-out, node replacement and evictions all make it worse, because each rescheduled Pod needs a new address.

**Don't** restart `aws-node` across the cluster or roll nodes to "clear" it. Restarting doesn't create addresses, and new nodes need more of them.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=my-cluster REGION=us-east-1
export NS=<namespace> POD=<stuck pod>
export NODE=$(kubectl get pod "$POD" -n "$NS" -o jsonpath='{.spec.nodeName}')
export INSTANCE_ID=$(kubectl get node "$NODE" -o jsonpath='{.spec.providerID}' | awk -F/ '{print $NF}')
```

## Triage

**1. How widespread is it?**

```bash
kubectl get events -A --field-selector reason=FailedCreatePodSandBox \
  -o custom-columns=NS:.metadata.namespace,POD:.involvedObject.name,MSG:.message --no-headers \
  | grep 'failed to assign an IP' | wc -l
kubectl get pods -A --field-selector status.phase=Pending -o wide | awk '{print $8}' | sort | uniq -c
```

- **If** the failures are spread across many nodes in the same AZ → the subnet is likely full (cause A).
- **If** they're all on one or a few nodes → that node is at its own limit (cause B) or its `aws-node` is broken (cause C).

**2. How many free addresses are left in the node subnets?**

```bash
kubectl get nodes -o jsonpath='{range .items[*]}{.spec.providerID}{"\n"}{end}' \
  | awk -F/ '{print $NF}' > /tmp/instances
aws ec2 describe-instances --region "$REGION" --instance-ids $(cat /tmp/instances) \
  --query 'Reservations[].Instances[].SubnetId' --output text | tr '\t' '\n' | sort -u > /tmp/subnets
aws ec2 describe-subnets --region "$REGION" --subnet-ids $(cat /tmp/subnets) \
  --query 'Subnets[].[SubnetId,AvailabilityZone,CidrBlock,AvailableIpAddressCount]' --output table
```

If you use **custom networking**, Pods get their addresses from the ENIConfig subnets, not the node subnets. Check those too:

```bash
kubectl get eniconfigs -o custom-columns=NAME:.metadata.name,SUBNET:.spec.subnet
```

- **Expect:** hundreds of free addresses per AZ.
- **If** `AvailableIpAddressCount` is near 0 in one or more subnets → cause A.

**3. Is the node at its own address limit?**

```bash
kubectl get node "$NODE" -o jsonpath='{.status.capacity.pods}{"\n"}'
kubectl get pods -A --field-selector spec.nodeName="$NODE" -o json \
  | jq '[.items[] | select(.spec.hostNetwork != true)] | length'
TYPE=$(kubectl get node "$NODE" -o jsonpath='{.metadata.labels.node\.kubernetes\.io/instance-type}')
aws ec2 describe-instance-types --region "$REGION" --instance-types "$TYPE" \
  --query 'InstanceTypes[].NetworkInfo.{maxENI:MaximumNetworkInterfaces,ipv4PerENI:Ipv4AddressesPerInterface}'
```

In secondary-IP mode a node can hold **ENIs × (IPv4 per ENI − 1)** Pod addresses (each ENI's primary address is not used for Pods). EKS sets `max-pods` to that number **+ 2** for host-network Pods. An `m5.large` is 3 × (10 − 1) + 2 = **29**.

- **If** non-host-network Pods ≈ address capacity, and `capacity.pods` is higher than that capacity → max-pods is set too high for this instance type (cause B). This is common with a custom launch template, a hand-set `maxPods` in a Karpenter `EC2NodeClass`, or after turning prefix delegation off.

**4. What does ipamd say?**

```bash
AWS_NODE=$(kubectl get pods -n kube-system -l k8s-app=aws-node \
  --field-selector spec.nodeName="$NODE" -o jsonpath='{.items[0].metadata.name}')
kubectl get pod "$AWS_NODE" -n kube-system
kubectl logs "$AWS_NODE" -n kube-system -c aws-node --tail=200
```

The detailed log is on the node. Open a shell with `aws ssm start-session --target "$INSTANCE_ID"`, then:

```bash
sudo grep -E 'InsufficientFreeAddressesInSubnet|InsufficientCidrBlocks|AttachmentLimitExceeded|UnauthorizedOperation|RequestLimitExceeded' \
  /var/log/aws-routed-eni/ipamd.log | tail -20
curl -s http://localhost:61679/v1/enis | jq '.' | head -50   # ipamd's view of ENIs and assigned IPs
```

| ipamd shows                         | Meaning                                                                      |
| ----------------------------------- | ---------------------------------------------------------------------------- |
| `InsufficientFreeAddressesInSubnet` | Subnet is full (cause A)                                                     |
| `InsufficientCidrBlocks`            | Prefix mode: no free contiguous /28 in the subnet (cause A)                  |
| `AttachmentLimitExceeded`           | Node already has its maximum ENIs (cause B)                                  |
| `UnauthorizedOperation`             | The CNI role lacks EC2 permissions (cause C)                                 |
| `RequestLimitExceeded`              | EC2 API throttling: often caused by warm settings that are too low (cause D) |
| `aws-node` not `Running 2/2`        | CNI agent is down on this node (cause C)                                     |

## Diagnosis

| Signal                                                                   | Cause                                      | Fix   |
| ------------------------------------------------------------------------ | ------------------------------------------ | ----- |
| Subnet `AvailableIpAddressCount` ≈ 0, failures across many nodes         | A. Subnet exhausted                        | Fix A |
| One node; Pod count = address capacity; max-pods higher                  | B. Node at ENI/IP limit                    | Fix B |
| `aws-node` crashing, or `UnauthorizedOperation`                          | C. CNI agent or its IAM permissions broken | Fix C |
| Addresses free everywhere; failures only during bursts, clear in minutes | D. Warm pool too small or EC2 throttling   | Fix D |

## Fix

### A. Subnet exhausted

Start with the fast fixes, then make the durable one.

**1. Delete leaked ENIs.** ENIs that the CNI created for nodes that are now gone stay in the subnet holding addresses:

```bash
aws ec2 describe-network-interfaces --region "$REGION" \
  --filters Name=subnet-id,Values=<subnet-id> Name=status,Values=available \
            Name=description,Values='aws-K8S-*' \
  --query 'NetworkInterfaces[].[NetworkInterfaceId,Description,length(PrivateIpAddresses)]' --output table
```

**⚠ Destructive:** delete only ENIs with status `available` (unattached) and an `aws-K8S-<instance-id>` description whose instance no longer exists:

```bash
aws ec2 delete-network-interface --region "$REGION" --network-interface-id <eni-id>
```

**2. Release warm addresses.** The default `WARM_ENI_TARGET=1` keeps a whole spare ENI's worth of addresses on every node: 9 per `m5.large`, 29 per `m5.4xlarge`. Across 200 nodes that can be thousands of idle addresses. Switch to address-based warm targets. If `vpc-cni` is an EKS-managed add-on, change it through the add-on, or the next add-on update overwrites a DaemonSet edit:

```bash
aws eks describe-addon --cluster-name "$CLUSTER" --region "$REGION" --addon-name vpc-cni \
  --query 'addon.{version:addonVersion,config:configurationValues}'

aws eks update-addon --cluster-name "$CLUSTER" --region "$REGION" --addon-name vpc-cni \
  --configuration-values '{"env":{"WARM_IP_TARGET":"2","MINIMUM_IP_TARGET":"10"}}' \
  --resolve-conflicts PRESERVE
```

Set `MINIMUM_IP_TARGET` to roughly the usual Pod count per node. Self-managed CNI: `kubectl set env daemonset aws-node -n kube-system WARM_IP_TARGET=2 MINIMUM_IP_TARGET=10`.

Trade-off: ipamd calls EC2 more often, and Pods start a little slower during sharp bursts. In very large clusters, watch for `RequestLimitExceeded`.

- **Verify:** `AvailableIpAddressCount` climbs within a few minutes as ipamd releases spare addresses.
- **Undo:** run `update-addon` again with the previous `configurationValues` (saved by the `describe-addon` call above).

**3. Add address space (the durable fix).** Exhaustion comes back if the subnets are simply too small:

- Add a secondary VPC CIDR (often from `100.64.0.0/10`) and create new subnets per AZ.
- Either point Pods at those subnets with [[Kubernetes/eks/networking/vpc-cni/custom-networking|custom networking]] (one `ENIConfig` per AZ), or move nodes there. For a managed node group, create a new node group in the new subnets, since an existing group's subnets can't be changed. For Karpenter, update the `EC2NodeClass` `subnetSelectorTerms`; drift replaces the nodes.

Turning on prefix delegation doesn't fix exhaustion. It allocates in /28 blocks, so it needs _more_ contiguous free space, and fragmented subnets fail with `InsufficientCidrBlocks`.

### B. Node at its address limit

1. Cordon the node so it stops receiving Pods it can't network: `kubectl cordon "$NODE"`.
2. Fix max-pods at its source so new nodes are right:
   - **Managed node group with a custom launch template / AL2023:** set `maxPods` in the `NodeConfig` kubelet section, or remove the override so EKS computes it.
   - **Karpenter:** remove or correct `spec.kubelet.maxPods` in the `EC2NodeClass`.
   - **Need more Pods per node:** enable prefix delegation (`ENABLE_PREFIX_DELEGATION=true`, Nitro instances only). It applies to new nodes; roll the node group after. See [[Kubernetes/eks/networking/vpc-cni/prefix-delegation|prefix delegation]].
3. Replace or drain the over-packed nodes once correctly sized capacity exists.

- **Verify:** on a new node, `capacity.pods` ≤ the address capacity worked out in Triage step 3.
- **Undo:** uncordon if you don't replace the node.

### C. aws-node unhealthy or missing permissions

1. Find which role the CNI uses:

   ```bash
   aws eks describe-addon --cluster-name "$CLUSTER" --region "$REGION" --addon-name vpc-cni \
     --query 'addon.serviceAccountRoleArn'
   ```

   If it's empty, the CNI uses the node instance role.

2. Make sure that role has `AmazonEKS_CNI_Policy` (or `AmazonEKS_CNI_IPv6_Policy` for IPv6 clusters) attached. Fix the attachment through whatever owns the role (Terraform, CDK and so on).
3. If `aws-node` is crash-looping for another reason, read `kubectl logs "$AWS_NODE" -n kube-system -c aws-node --previous`. A recent add-on update is the usual suspect; see the abort and rollback section of [[Kubernetes/eks/operator-runbook/procedures/add-on-upgrade|Add-on upgrade]].

- **Verify:** `aws-node` on the node is `2/2 Running`, and stuck Pods move to `Running` without being deleted.

### D. Warm pool too small for bursts

Addresses are available, but a burst of Pods arrives faster than ipamd attaches ENIs. Raise `MINIMUM_IP_TARGET` to the burst size per node, or use `WARM_ENI_TARGET=1` (the default) if subnets have plenty of room. Change it through the add-on as in Fix A step 2.

## Verify recovery

```bash
kubectl run ip-test -n "$NS" --image=public.ecr.aws/docker/library/busybox:1.36 --restart=Never \
  --overrides="{\"spec\":{\"nodeName\":\"$NODE\"}}" -- sleep 300
kubectl get pod ip-test -n "$NS" -o wide     # Running with a Pod IP within a few seconds
kubectl delete pod ip-test -n "$NS"
kubectl get pods -A --field-selector status.phase=Pending   # stuck Pods have cleared
```

Then confirm the stalled rollouts finished (`kubectl rollout status deploy/<name> -n <ns>`) and that the subnet's free count keeps a margin above your largest expected scale-out.

## Escalate

Open an AWS Support case if EC2 returns errors the subnet and instance data don't explain, or if persistent `RequestLimitExceeded` throttling blocks recovery. Attach the cluster ARN, the affected subnet IDs and instance IDs, the time window, ipamd log excerpts, and the output of `/opt/cni/bin/aws-cni-support.sh` from an affected node (it writes a tarball under `/var/log/`).

## Prevent

- Alert when any node or ENIConfig subnet drops below the address count needed for your largest scale-out plus one node rotation. Use a scheduled job over `describe-subnets`, VPC IPAM, or the CNI metrics helper (`awscni_total_ip_addresses`, `awscni_assigned_ip_addresses`).
- Size Pod subnets for **max nodes × (max Pods per node + warm addresses)**, then add room for a full node-group rotation, which briefly doubles nodes.
- Keep CNI settings in the add-on configuration under version control, not hand-edited on the DaemonSet.

**Auto Mode and Fargate:** neither runs `aws-node`. Auto Mode takes Pod addresses from the subnets in its `NodeClass`; Fargate uses one address per Pod from the Fargate profile subnets. Subnet exhaustion (Triage step 2, Fix A step 3) applies to both; the node-level steps don't.

## Background

- [[Kubernetes/eks/networking/vpc-cni/eni-allocation|ENI and IP allocation]]: how ipamd attaches ENIs and keeps a warm pool.
- [[Kubernetes/eks/networking/vpc-cni/configuration-reference|VPC CNI configuration reference]]: every `WARM_*` and `MINIMUM_*` variable.
- [[Kubernetes/eks/networking/vpc-cni/troubleshooting|VPC CNI troubleshooting]].
- [Amazon EKS best practices: VPC and subnet considerations](https://docs.aws.amazon.com/eks/latest/best-practices/subnets.html)
