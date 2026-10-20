---
title: "Reference: First Five Minutes of an EKS Incident"
description: "A fixed triage sequence for any EKS page: confirm the cluster, check control plane, nodes, system Pods and add-ons, find recent changes, then pick the runbook."
tags: [kubernetes/eks/operator-runbook, eks, reference, incident, triage]
date: 2026-10-20
aliases: [EKS on-call triage, EKS incident first steps]
---

# Reference: First Five Minutes of an EKS Incident

Use this when you've been paged and don't yet know which runbook applies. It takes about five minutes, makes no changes, and ends with a runbook to open.

## 1. Set up and confirm the cluster (30 s)

```bash
export CLUSTER=<name> REGION=<region>
export EVIDENCE_DIR=~/incidents/$(date -u +%Y%m%dT%H%MZ)-$CLUSTER; mkdir -p "$EVIDENCE_DIR"
aws sts get-caller-identity --query Arn --output text
kubectl config current-context
```

If kubectl fails with `Unauthorized`, go to [[Kubernetes/eks/operator-runbook/runbooks/kubectl-unauthorized-or-forbidden|kubectl Unauthorized]]. If it times out, check the endpoint from AWS (step 2) before anything else.

## 2. Control plane (30 s)

```bash
aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
  --query 'cluster.{status:status,version:version,health:health.issues}'
aws eks list-updates --name "$CLUSTER" --region "$REGION" --max-results 5
kubectl get --raw='/readyz?verbose' | tail -3
```

- **Expect:** `status: ACTIVE`, no health issues, `readyz check passed`.
- `UPDATING` → someone is changing the cluster right now. Find the update: `aws eks describe-update --name "$CLUSTER" --update-id <id>`.

## 3. Nodes (30 s)

```bash
kubectl get nodes --no-headers | awk '{print $2}' | sort | uniq -c
kubectl get nodes -L topology.kubernetes.io/zone --no-headers | grep -v ' Ready ' | head
```

Any `NotReady` → [[Kubernetes/eks/operator-runbook/runbooks/node-not-ready|Node NotReady]]. Note whether they share an AZ.

## 4. What isn't running (1 min)

```bash
kubectl get pods -A --no-headers | grep -Ev 'Running|Completed' | awk '{print $1, $4}' | sort | uniq -c | sort -rn | head -20
kubectl get pods -n kube-system -o wide | grep -Ev 'Running|Completed'
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp 2>/dev/null | tail -30 \
  | tee "$EVIDENCE_DIR/warning-events.txt"
```

The most common warning reasons, and where they lead:

| Event reason or status                       | Runbook                                                                                                   |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `FailedCreatePodSandBox`                     | [[Kubernetes/eks/operator-runbook/runbooks/pods-stuck-containercreating-ip-exhaustion\|IP exhaustion]]    |
| `FailedScheduling`, Pods `Pending`           | [[Kubernetes/eks/operator-runbook/runbooks/karpenter-not-launching-nodes\|Karpenter not launching nodes]] |
| `FailedCreate` with `failed calling webhook` | [[Kubernetes/eks/operator-runbook/runbooks/webhook-blocking-deployments\|Webhook blocking deployments]]   |
| `FailedAttachVolume`, `FailedMount`          | [[Kubernetes/eks/operator-runbook/runbooks/ebs-volume-stuck-attaching\|EBS volume stuck attaching]]       |
| CoreDNS Pods not Running                     | [[Kubernetes/eks/operator-runbook/runbooks/dns-timeouts-coredns\|DNS timeouts]]                           |

## 5. Add-ons (30 s)

```bash
for a in $(aws eks list-addons --cluster-name "$CLUSTER" --region "$REGION" --query 'addons[]' --output text); do
  aws eks describe-addon --cluster-name "$CLUSTER" --region "$REGION" --addon-name "$a" \
    --query 'addon.[addonName,addonVersion,status,length(health.issues)]' --output text
done
```

Anything other than `ACTIVE` with 0 issues needs a look: `aws eks describe-addon ... --query addon.health`.

## 6. What changed? (1–2 min)

Most incidents follow a change. Look at the last few hours:

```bash
# Kubernetes rollouts: every Deployment rollout creates a ReplicaSet,
# every DaemonSet/StatefulSet rollout a ControllerRevision
kubectl get rs -A --sort-by=.metadata.creationTimestamp | tail -10
kubectl get controllerrevisions -A --sort-by=.metadata.creationTimestamp | tail -10
helm list -A --date | tail -10
# AWS-side changes to the cluster
aws cloudtrail lookup-events --region "$REGION" --start-time "$(date -u -d '-6 hours' +%FT%TZ)" \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=eks.amazonaws.com \
  --query 'Events[?!starts_with(EventName,`Describe`) && !starts_with(EventName,`List`)].[EventTime,EventName,Username]' --output table
```

Also check the deploy channel for your GitOps tool (`argocd app list`, `flux get all -A`) and the AWS Health Dashboard for the region.

## 7. Decide

By now you know whether the problem is the **control plane** (step 2), **nodes** (3), **specific workloads** (4), an **add-on** (5), or a **recent change** (6). Open the matching runbook from the [[Kubernetes/eks/operator-runbook/index|handbook index]]. If a recent change lines up with the start of the incident, rolling it back is usually the fastest mitigation, whatever the root cause turns out to be.

## Across the wiki

- [[Kubernetes/eks/operator-runbook/reference/command-conventions|Command conventions]]
- [[Kubernetes/eks/operator-runbook/reference/control-plane-logs-and-metrics|Control-plane logs and metrics]]
- [[Kubernetes/concepts/L08-operations/01-troubleshooting|Kubernetes troubleshooting]]
