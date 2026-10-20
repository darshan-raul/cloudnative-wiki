---
title: "Procedure: Rotate Karpenter Nodes with Drift and Disruption Budgets"
description: "Roll Karpenter-managed nodes to a new AMI or configuration through drift, controlled by disruption budgets, with a pause switch and protection for sensitive Pods."
tags:
  [kubernetes/eks/operator-runbook, eks, procedure, karpenter, ami, upgrades]
date: 2026-10-20
aliases: [Karpenter AMI rotation, Karpenter drift procedure]
---

# Procedure: Rotate Karpenter Nodes with Drift and Disruption Budgets

**Applies to:** Karpenter v1.x (`NodePool` and `EC2NodeClass`). Auto Mode uses the same NodePool budgets, but EKS chooses the AMI.
**Duration:** depends on budgets and fleet size; typically tens of minutes to a few hours.
**Risk:** medium. Every Pod on a drifted node is evicted once.
**Tested:** not run on a live cluster; commands checked for syntax.

## How it works

When the EC2NodeClass or NodePool changes in a way that affects nodes (a new AMI from `amiSelectorTerms`, user data, subnets, security groups, labels, taints or requirements), Karpenter marks existing NodeClaims `Drifted`. It then replaces them, launching the new node before draining the old one, at the pace the NodePool's disruption budgets allow. The default budget is `nodes: 10%`.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export NODEPOOL=<nodepool> NODECLASS=<ec2nodeclass>
export KARPENTER_NS=$(kubectl get deploy -A -l app.kubernetes.io/name=karpenter -o jsonpath='{.items[0].metadata.namespace}')
```

## Pre-checks

**1. Know how the AMI is selected.**

```bash
kubectl get ec2nodeclass "$NODECLASS" -o jsonpath='{.spec.amiSelectorTerms}{"\n"}{.status.amis}' | jq -R
```

- `alias: al2023@latest` → nodes drift automatically every time AWS publishes an AMI. Convenient, but every AMI release reaches production without a gate.
- `alias: al2023@v<YYYYMMDD>`, or an explicit AMI ID → nothing drifts until you change the pin. That's the controlled option for production.

**2. Set budgets for this rollout.**

```bash
kubectl get nodepool "$NODEPOOL" -o jsonpath='{.spec.disruption}' | jq
```

A conservative production example: one node at a time, only drift, and only during business hours:

```yaml
spec:
  disruption:
    budgets:
      - nodes: "1"
        reasons: ["Drifted"]
      - nodes: "0"
        reasons: ["Drifted"]
        schedule: "0 18 * * *" # block drift from 18:00 UTC...
        duration: 14h # ...until 08:00 UTC
```

**3. Protect Pods that must not be interrupted** (long batch jobs, single-replica stateful services under maintenance):

```bash
kubectl annotate pod <pod> -n <ns> karpenter.sh/do-not-disrupt=true
```

Karpenter won't voluntarily drain a node running such a Pod. Use this sparingly, or nodes never roll.

**4. PDBs allow disruption** for healthy workloads: `kubectl get pdb -A | awk 'NR==1 || $(NF-1)=="0"'`.

**5. Canary.** Point a small NodePool (or a staging cluster) at the new AMI first, and run representative workloads on it.

## Steps

**1. Change the pin** in Git, or directly:

```bash
kubectl patch ec2nodeclass "$NODECLASS" --type=merge \
  -p '{"spec":{"amiSelectorTerms":[{"alias":"al2023@v<YYYYMMDD>"}]}}'
kubectl get ec2nodeclass "$NODECLASS" -o jsonpath='{.status.amis}' | jq    # resolved AMI IDs
```

**2. Watch drift and replacement.**

```bash
kubectl get nodeclaims -l karpenter.sh/nodepool="$NODEPOOL" \
  -o 'custom-columns=NAME:.metadata.name,NODE:.status.nodeName,IMAGE:.status.imageID,DRIFTED:.status.conditions[?(@.type=="Drifted")].status,READY:.status.conditions[?(@.type=="Ready")].status'
kubectl get events -A --field-selector source=karpenter --sort-by=.lastTimestamp | tail -20
kubectl logs -n "$KARPENTER_NS" -l app.kubernetes.io/name=karpenter --tail=100 | grep -iE 'disrupt|drift' | tail
```

- **Checkpoint:** replacement nodes reach `Ready` with the new image ID, the evicted Pods run elsewhere, and service error rates stay at the baseline.

## Pause and rollback

**Pause immediately**, without reverting anything, by setting a zero budget:

```bash
kubectl patch nodepool "$NODEPOOL" --type=merge \
  -p '{"spec":{"disruption":{"budgets":[{"nodes":"0"}]}}}'
```

This stops voluntary disruption: drift, consolidation and expiry. It doesn't stop replacement of nodes that fail.

**Roll back** by restoring the previous AMI pin. Nodes already on the new AMI now drift back at the budget's pace. Once you're satisfied, restore the original budgets from Git.

If GitOps manages the NodePool, make these changes in Git, or pause sync first (see [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]).

## Post-checks

```bash
kubectl get nodeclaims -l karpenter.sh/nodepool="$NODEPOOL" -o custom-columns=NAME:.metadata.name,IMAGE:.status.imageID --no-headers \
  | awk '{print $2}' | sort | uniq -c
```

All NodeClaims show the new image. If some don't, look for `do-not-disrupt` Pods or blocking PDBs on them.

## Clean-up

- Remove temporary `do-not-disrupt` annotations.
- Restore the normal budgets.
- Commit the new AMI pin to Git, if you patched it live.

## Background

- [[Kubernetes/eks/compute/karpenter/README|Karpenter on EKS]]
- [[Kubernetes/eks/operator-runbook/runbooks/karpenter-not-launching-nodes|Karpenter not launching nodes]]
- [Karpenter disruption](https://karpenter.sh/docs/concepts/disruption/)
