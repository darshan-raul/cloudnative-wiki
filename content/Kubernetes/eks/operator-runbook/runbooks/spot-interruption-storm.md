---
title: "Runbook: Spot Interruption Storm"
description: "Many Spot nodes are reclaimed at once and capacity, error rates or batch progress suffer. Confirm it's Spot, make sure the two-minute notice is being used, and fall back to other capacity safely."
tags:
  [
    kubernetes/eks/operator-runbook,
    eks,
    runbook,
    spot,
    karpenter,
    capacity,
    incident,
  ]
date: 2026-10-20
aliases: [EKS Spot interruptions runbook, Spot reclaim storm]
---

# Runbook: Spot Interruption Storm

**Applies to:** Spot capacity through Karpenter, managed node groups (`capacityType: SPOT`), or self-managed groups with the AWS Node Termination Handler.
**Typical severity:** Sev 2. Sev 1 if critical workloads run only on Spot.
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

- Several nodes disappear within minutes; replacement Pods go Pending, or land on fresh nodes that are reclaimed again.
- Load balancer 502 or 503 spikes as Pods die.
- Instances show `StateReason` `Server.SpotInstanceTermination`.
- Karpenter or the Node Termination Handler logs interruption or rebalance events.

## Impact

EC2 gives a **two-minute notice** before reclaiming a Spot instance, and sometimes an earlier **rebalance recommendation**. With the notice handled, Pods are drained gracefully and replaced. Without it, nodes vanish, and their Pods die without a graceful shutdown. Spot terminations are involuntary, so **PodDisruptionBudgets don't stop them**.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=my-cluster REGION=us-east-1
export KARPENTER_NS=$(kubectl get deploy -A -l app.kubernetes.io/name=karpenter -o jsonpath='{.items[0].metadata.namespace}')   # if you use Karpenter
```

## Triage

**1. Is it really Spot?**

```bash
aws ec2 describe-instances --region "$REGION" \
  --filters Name=tag-key,Values="kubernetes.io/cluster/$CLUSTER" Name=instance-state-name,Values=shutting-down,terminated \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,Placement.AvailabilityZone,StateReason.Code,LaunchTime]' --output table
```

`Server.SpotInstanceTermination` confirms it. Other reasons (`Client.UserInitiatedShutdown`, scale-in) point elsewhere: consolidation, an ASG change, or someone terminating instances. Managed node groups, Karpenter and most self-managed setups tag cluster instances with `kubernetes.io/cluster/<cluster>`; adjust the filter if yours don't.

**2. Which pools are being reclaimed?** Group by instance type and AZ in the output above. Storms are usually concentrated in a few instance types in one or two AZs.

**3. Is the notice being handled?**

```bash
# Karpenter: interruption queue configured?
kubectl get deploy -n "$KARPENTER_NS" karpenter -o json | jq -r '.spec.template.spec.containers[0].env[] | select(.name=="INTERRUPTION_QUEUE")'
kubectl logs -n "$KARPENTER_NS" -l app.kubernetes.io/name=karpenter --tail=300 | grep -iE 'interrupt|rebalance' | tail
# Self-managed groups: Node Termination Handler running?
kubectl get ds,deploy -A | grep -i termination-handler
```

Managed node groups handle the notice themselves (they enable Capacity Rebalancing for Spot groups).

**4. How much of the workload depends on Spot?**

```bash
kubectl get nodes -L karpenter.sh/capacity-type,eks.amazonaws.com/capacityType --no-headers \
  | awk '{print $(NF-1) $NF}' | sort | uniq -c
```

## Diagnosis

| Signal                                                      | Cause                         | Fix   |
| ----------------------------------------------------------- | ----------------------------- | ----- |
| Many terminations; few instance types or AZs allowed        | A. Shallow Spot pools         | Fix A |
| Pods die without draining; no interruption queue or handler | B. Notice not handled         | Fix B |
| Critical or stateful workloads affected                     | C. Wrong workloads on Spot    | Fix C |
| Replacements also reclaimed quickly                         | A, with no on-demand fallback | Fix A |

## Fix

### A. Shallow Spot pools: widen and fall back

- **Karpenter:** allow both capacity types, so Karpenter falls back to on-demand when Spot is short, and allow many instance families and sizes:

  ```yaml
  requirements:
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["spot", "on-demand"]
    - key: karpenter.k8s.aws/instance-category
      operator: In
      values: ["c", "m", "r"]
    - key: karpenter.k8s.aws/instance-generation
      operator: Gt
      values: ["5"]
  ```

- **Managed node groups:** add more instance types to the Spot group (same CPU and memory if you use Cluster Autoscaler), and temporarily raise an on-demand group's size to carry the load.
- Check which pools are healthier with Spot placement scores:

  ```bash
  aws ec2 get-spot-placement-scores --region "$REGION" --target-capacity 20 --single-availability-zone \
    --instance-types m6i.xlarge m7i.xlarge m6a.xlarge c6i.2xlarge r6i.large --region-names "$REGION"
  ```

**Undo:** once the storm passes, Karpenter consolidation moves work back to Spot. For node groups, lower the on-demand size again.

### B. Notice not handled

- **Karpenter:** create the SQS interruption queue and its EventBridge rules (Spot interruption, rebalance recommendation, instance state change, scheduled change), using the CloudFormation or Terraform from the Karpenter getting-started guide. Then set `settings.interruptionQueue` in the Helm values. Karpenter then cordons, drains and replaces nodes within the two minutes.
- **Self-managed groups:** install the AWS Node Termination Handler, in queue mode for production.
- **Workloads:** keep `terminationGracePeriodSeconds` well under two minutes, and handle SIGTERM, so a drain finishes before the instance goes.

### C. Wrong workloads on Spot

Pin critical, singleton or slow-to-restart workloads (databases, stateful sets with long recovery, controllers like Karpenter itself) to on-demand:

```yaml
nodeSelector:
  karpenter.sh/capacity-type: on-demand # or eks.amazonaws.com/capacityType: ON_DEMAND
```

Spread stateless replicas across AZs and capacity types, so one reclaim wave can't take them all.

## Verify recovery

- New terminations with `Server.SpotInstanceTermination` drop back to the background rate.
- Pending Pods schedule (possibly on on-demand), and error rates return to baseline.
- On the next interruption, you see a drain (Karpenter or NTH logs) before the node disappears.

## Escalate

Spot reclaims are expected behaviour, not a fault, so there's nothing to escalate. If on-demand fallback also fails with `InsufficientInstanceCapacity`, follow [[Kubernetes/eks/operator-runbook/runbooks/karpenter-not-launching-nodes|Karpenter not launching nodes]] Fix E.

## Prevent

- Allow at least 10–15 instance types per Spot NodePool or node group, across several families and every AZ.
- Always configure the interruption queue (Karpenter) or the termination handler (self-managed).
- Keep a baseline of on-demand capacity for critical workloads.
- Alert on the interruption rate, for example an EventBridge rule on `EC2 Spot Instance Interruption Warning` sending to a metric.

## Background

- [[Kubernetes/eks/compute/managed-node-groups/spot|Spot with managed node groups]]
- [[Kubernetes/eks/compute/karpenter/README|Karpenter on EKS]]
- [Spot Instance interruptions](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-interruptions.html)
- [Karpenter interruption handling](https://karpenter.sh/docs/concepts/disruption/#interruption)
