---
title: "Procedure: Shift an EKS Cluster Away from an Impaired AZ"
description: "Use ARC zonal shift to move EKS east-west traffic, new capacity and load-balancer traffic out of one Availability Zone, then return safely."
tags:
  [
    kubernetes/eks/operator-runbook,
    eks,
    procedure,
    resilience,
    zonal-shift,
    availability-zones,
  ]
date: 2026-10-20
aliases: [EKS zonal shift procedure, EKS AZ evacuation]
---

# Procedure: Shift an EKS Cluster Away from an Impaired AZ

**Applies to:** EKS clusters spread across at least three AZs, using Amazon Application Recovery Controller (ARC) zonal shift.
**Duration:** start in minutes; the shift lasts until it expires or is cancelled.
**Risk:** medium. You give up a third of your capacity on purpose, and zonal (EBS-backed) workloads in that AZ go down.
**Tested:** not run on a live cluster; commands checked for syntax.

## When to use

- Errors or latency are isolated to one AZ: AWS Health reports an AZ event, node or Pod failures cluster in one AZ, or per-AZ load-balancer metrics diverge.
- You're running a planned AZ-failure exercise.

Don't use it for problems that aren't AZ-specific; shifting just reduces capacity.

## What a shift does and doesn't do

| Layer                                      | Effect                                                                                                                                                          |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| EKS cluster shift (resource = cluster ARN) | EKS removes endpoints in that AZ from EndpointSlices, so in-cluster Service traffic avoids it, and managed node groups stop launching nodes there               |
| Load balancers                             | **Separate.** Each ALB or NLB needs its own zonal shift (resource = load balancer ARN), or ARC zonal autoshift. Otherwise inbound traffic still goes to that AZ |
| Karpenter                                  | Not shifted by the cluster shift. Exclude the AZ from NodePools yourself (step 4)                                                                               |
| Pods already in the AZ                     | Keep running; they're just not sent Service traffic. Evict them yourself if they do harm (writes to bad dependencies, for example)                              |
| EBS-backed StatefulSets in the AZ          | **Can't move.** Their volumes are zonal. Fail over at the application level (replicas in other AZs), or accept downtime                                         |

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=my-cluster REGION=us-east-1
export CLUSTER_ARN=$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query cluster.arn --output text)
aws ec2 describe-availability-zones --region "$REGION" --query 'AvailabilityZones[].[ZoneName,ZoneId]' --output table
export AZ_ID=<zone ID, e.g. use1-az4>     # zonal shift uses the AZ ID, not the name
export AZ_NAME=<matching zone name, e.g. us-east-1a>
```

AZ names map to different physical AZs in different accounts. Always use the **ID**.

## Pre-checks (do these before you need them)

**1. Zonal shift is enabled on the cluster.**

```bash
aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query cluster.zonalShiftConfig
aws eks update-cluster-config --name "$CLUSTER" --region "$REGION" --zonal-shift-config enabled=true   # if not
```

**2. The remaining AZs can carry the load.** With three AZs, you lose about a third of your capacity:

- Deployments have enough replicas, or HPA headroom, to serve full load from two AZs.
- Node groups have `maxSize` room, subnets have free IPs, and EC2 quota allows the extra nodes.
- Topology spread constraints use `whenUnsatisfiable: ScheduleAnyway`, or Pods will stay Pending when one AZ is excluded.

**3. Load balancers are registered with ARC.** List what can be shifted:

```bash
aws arc-zonal-shift list-managed-resources --region "$REGION" \
  --query 'items[].[name,arn]' --output table
```

## Steps

**1. Confirm it's one AZ.** Compare per-AZ error rates (load-balancer metrics by `AvailabilityZone`, Pod and node failures by `topology.kubernetes.io/zone`):

```bash
kubectl get nodes -L topology.kubernetes.io/zone --no-headers | awk '{print $NF, $2}' | sort | uniq -c
```

**2. Shift the cluster.**

```bash
aws arc-zonal-shift start-zonal-shift --region "$REGION" \
  --resource-identifier "$CLUSTER_ARN" --away-from "$AZ_ID" \
  --expires-in 3h --comment "INC-1234: errors isolated to $AZ_ID"
```

**3. Shift each internet-facing and internal load balancer** that serves the cluster:

```bash
aws arc-zonal-shift start-zonal-shift --region "$REGION" \
  --resource-identifier <load balancer ARN> --away-from "$AZ_ID" \
  --expires-in 3h --comment "INC-1234"
```

**4. Keep new Karpenter capacity out of the AZ.** Add a requirement to each NodePool, or patch it into the existing `topology.kubernetes.io/zone` requirement:

```bash
kubectl edit nodepool <name>
#   requirements:
#     - key: topology.kubernetes.io/zone
#       operator: NotIn
#       values: ["<AZ_NAME>"]
```

**5. Make sure capacity is growing in the other AZs.**

```bash
kubectl get pods -A --field-selector status.phase=Pending | wc -l
kubectl get nodes -L topology.kubernetes.io/zone --no-headers | awk '{print $NF}' | sort | uniq -c
```

- **Checkpoint:** error rates return to normal, Pending Pods are scheduling in the healthy AZs, and load-balancer traffic to the AZ drops to near zero.

**6. Extend the shift if needed.** It expires automatically, which is a safety net if you forget:

```bash
aws arc-zonal-shift list-zonal-shifts --region "$REGION" --status ACTIVE
aws arc-zonal-shift update-zonal-shift --region "$REGION" --zonal-shift-id <id> --expires-in 6h
```

## Return to the AZ

Only after AWS Health shows the event resolved and your own tests against the AZ pass:

1. Remove the Karpenter `NotIn` requirement.
2. Cancel the load-balancer shifts, then the cluster shift:

   ```bash
   aws arc-zonal-shift cancel-zonal-shift --region "$REGION" --zonal-shift-id <id>
   ```

3. Rebalance. Pods don't move back on their own. `kubectl rollout restart` the main Deployments during a quiet period, or let the descheduler or Karpenter consolidation rebalance.
4. Check StatefulSets in the AZ have recovered and re-synced their replicas.

## Abort criteria

Cancel the shift early if errors don't improve within about 10 minutes. The problem wasn't the AZ, and you're running with less capacity for nothing.

## Background

- [[Architecture/solution-architecture-concepts/reliability/resilience|Resilience]]
- [[Kubernetes/eks/operator-runbook/runbooks/node-not-ready|Node NotReady]] (many nodes in one AZ)
- [Learn about Amazon ARC zonal shift in Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/zone-shift.html)
