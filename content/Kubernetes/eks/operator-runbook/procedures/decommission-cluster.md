---
title: "Procedure: Decommission an EKS Cluster"
description: "Retire a cluster in the right order so controllers clean up the load balancers, volumes, DNS records and instances they created, data you need is kept, and nothing billable is left behind."
tags:
  [kubernetes/eks/operator-runbook, eks, procedure, decommission, cleanup, cost]
date: 2026-10-20
aliases: [Delete EKS cluster safely, EKS cluster teardown]
---

# Procedure: Decommission an EKS Cluster

**Applies to:** any EKS cluster being retired, including after a migration to a new cluster.
**Duration:** an hour or two of work, plus a waiting period before final deletion of data and keys.
**Risk:** high: deletion is permanent. The order of steps matters, because controllers can only clean up what they created while they're still running.
**Tested:** not run on a live cluster; commands checked for syntax.

## Why order matters

The AWS Load Balancer Controller deletes ALBs and NLBs, ExternalDNS deletes DNS records, the EBS CSI driver deletes volumes, and Karpenter terminates its instances. Each does this **only while it's running and the Kubernetes objects are deleted**. Delete the cluster first, and they're all orphaned: they keep costing money, and their ENIs and security groups block VPC deletion.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=<cluster to retire> REGION=us-east-1
kubectl config current-context        # must be the cluster you're retiring
```

## Pre-checks

**1. It's really unused.** Load balancer request counts are at zero over a representative period (`RequestCount` for ALBs, `ActiveFlowCount` for NLBs), and no DNS names in use point at the cluster's load balancers:

```bash
kubectl get ingress,svc -A -o json | jq -r '.items[] | .status.loadBalancer.ingress[]?.hostname // empty' | sort -u
```

**2. Data to keep is kept.** Final backups or snapshots of every PV you might need, exported logs, and a record of the cluster configuration (`aws eks describe-cluster`, add-on versions, `kubectl get all -A -o yaml` into an archive). Restore one backup to prove it works.

**3. Owners have signed off**, and dependencies are gone: other clusters, VPC peering or Transit Gateway routes, IAM roles trusted by other accounts, and applications calling its endpoints.

**4. Nothing will recreate it.** Remove the cluster from GitOps (Argo CD cluster secret or `ApplicationSet` generator, Flux bootstrap repository), and from IaC pipelines that would recreate it on the next apply.

## Steps

**1. Stop GitOps inside the cluster** so it doesn't recreate what you delete:

```bash
argocd app list -o name | xargs -r -n1 argocd app set --sync-policy none   # if Argo CD runs in this cluster
flux suspend kustomization --all -A                                         # if Flux runs in this cluster
```

**2. Delete load-balanced entry points** while the controllers still run:

```bash
kubectl delete ingress -A --all
kubectl get svc -A -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"' \
  | while read ns name; do kubectl delete svc "$name" -n "$ns"; done
kubectl get targetgroupbindings -A          # wait until empty
```

- **Checkpoint:** `aws elbv2 describe-load-balancers` no longer lists the cluster's load balancers. Those created by the controller are tagged `elbv2.k8s.aws/cluster=<cluster>`. If ExternalDNS runs with `--policy=sync`, it removes the DNS records for the deleted Ingresses now; with `upsert-only`, delete those records yourself.

**3. Delete workloads and volumes deliberately.**

```bash
kubectl get pv -o custom-columns=NAME:.metadata.name,CLAIM:.spec.claimRef.name,POLICY:.spec.persistentVolumeReclaimPolicy,HANDLE:.spec.csi.volumeHandle
```

**⚠ Destructive:** PVCs with reclaim policy `Delete` take their EBS volumes and EFS access points with them. Confirm the snapshots from pre-check 2 first. PVs with `Retain` keep their volumes, which you'll delete or keep by hand in step 7.

```bash
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -vE '^(kube-system|kube-public|kube-node-lease|default)$'); do
  kubectl delete deploy,sts,ds,job,cronjob,pvc -n "$ns" --all
done
```

**4. Remove Karpenter capacity before Karpenter.** Deleting NodePools makes Karpenter terminate their nodes:

```bash
kubectl delete nodepools --all
kubectl get nodeclaims -w            # wait until empty
kubectl delete ec2nodeclasses --all
```

Only then uninstall Karpenter (or let cluster deletion remove it).

**5. Delete EKS-side resources:**

```bash
for ng in $(aws eks list-nodegroups --cluster-name "$CLUSTER" --region "$REGION" --query 'nodegroups[]' --output text); do
  aws eks delete-nodegroup --cluster-name "$CLUSTER" --region "$REGION" --nodegroup-name "$ng"; done
for fp in $(aws eks list-fargate-profiles --cluster-name "$CLUSTER" --region "$REGION" --query 'fargateProfileNames[]' --output text); do
  aws eks delete-fargate-profile --cluster-name "$CLUSTER" --region "$REGION" --fargate-profile-name "$fp"; done
aws eks wait nodegroup-deleted --cluster-name "$CLUSTER" --region "$REGION" --nodegroup-name <last-nodegroup>
```

**6. Delete the cluster.**

```bash
aws eks delete-cluster --name "$CLUSTER" --region "$REGION"
aws eks wait cluster-deleted --name "$CLUSTER" --region "$REGION"
```

If the cluster was created by IaC (Terraform, CDK, eksctl), run the deletion through that tool instead, so its state matches reality.

**7. Find and clean up leftovers.** Search by the tags EKS, the controllers and Karpenter apply:

```bash
for tag in "kubernetes.io/cluster/$CLUSTER" "eks:cluster-name" "elbv2.k8s.aws/cluster" "karpenter.sh/discovery"; do
  echo "== $tag"
  aws resourcegroupstaggingapi get-resources --region "$REGION" --tag-filters Key="$tag" \
    --query 'ResourceTagMappingList[].ResourceARN' --output text | tr '\t' '\n'
done
aws ec2 describe-network-interfaces --region "$REGION" --filters Name=description,Values='aws-K8S-*' Name=status,Values=available \
  --query 'NetworkInterfaces[].NetworkInterfaceId'
aws ec2 describe-volumes --region "$REGION" --filters Name=tag-key,Values=kubernetes.io/created-for/pvc/name Name=status,Values=available \
  --query 'Volumes[].[VolumeId,Size,Tags[?Key==`kubernetes.io/created-for/pvc/name`].Value|[0]]' --output table
```

Some tag filters match resources of other clusters too (for example `eks:cluster-name` with any value); check each ARN belongs to `$CLUSTER` before deleting. Also check:

- **IAM:** the cluster role, node roles, Pod Identity and IRSA roles, and the cluster's IAM OIDC provider (`aws iam list-open-id-connect-providers`).
- **Logs:** CloudWatch log groups `/aws/eks/$CLUSTER/cluster` and Container Insights groups. Set a retention, or export and delete them.
- **Karpenter interruption queue:** the SQS queue and its EventBridge rules.
- **KMS key** for Secrets encryption. Schedule deletion only after the waiting period you set for the cluster's data, with the maximum pending window (30 days).
- **Security groups** created for the cluster and its load balancers; **Route 53** records; **ECR** repositories used only by this cluster; the **VPC**, if it was dedicated to the cluster.

## Abort criteria

Stop at any step if traffic appears on a load balancer you're about to delete, or a dependency you didn't know about breaks. Before step 6, everything except deleted volumes and load balancers can be recreated from Git.

## Post-checks

- No resources tagged for the cluster remain (step 7 shows nothing).
- Billing shows the cluster's costs stopping over the next days: EKS cluster hours, EC2, ELB, EBS and NAT data.

## Clean-up

Archive the configuration export and the decommissioning record with the backups. Remove the cluster from dashboards, alerting, the CMDB and on-call documentation.

## Background

- [[Kubernetes/eks/operator-runbook/procedures/restore-namespace-from-backup|Restore from backup]]
- [[DevOps/platform-engineering/finops-and-cost-allocation|FinOps and cost allocation]]
- [Deleting an Amazon EKS cluster](https://docs.aws.amazon.com/eks/latest/userguide/delete-cluster.html)
