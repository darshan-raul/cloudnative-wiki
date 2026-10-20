---
title: "Reference: Command Conventions and Safety Checks"
description: "The shell variables every runbook and procedure uses, how to derive each one, and the checks to run before changing anything."
tags: [kubernetes/eks/operator-runbook, eks, reference, kubectl, aws-cli]
date: 2026-10-20
aliases: [EKS runbook variables]
---

# Reference: Command Conventions and Safety Checks

Every runbook and procedure in this handbook uses the same variable names, so commands can be pasted in any order. Set the ones a page lists under **Inputs**.

**Tools:** AWS CLI v2, `kubectl` within one minor version of the cluster, `jq`, and the Session Manager plugin for `aws ssm start-session`. Some procedures also use `eksctl`, `helm` or `velero`.

## Before you change anything

Run these and read the output. Most incident-making mistakes happen against the wrong cluster.

```bash
aws sts get-caller-identity --query '[Account,Arn]' --output text
kubectl config current-context
kubectl cluster-info | head -1
aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
  --query 'cluster.{arn:arn,version:version,platform:platformVersion,status:status,endpoint:endpoint}'
```

Check that the account, the cluster ARN and the endpoint in `kubectl cluster-info` belong to the same cluster. If they don't, run `aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" --alias "$CLUSTER"`, then `kubectl config use-context "$CLUSTER"`.

For anything destructive, put the cluster in your prompt, or pass `--context "$CLUSTER"` explicitly.

## Variables

| Variable                | Meaning                                   | How to get it                                                                                                    |
| ----------------------- | ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `CLUSTER`, `REGION`     | Cluster name and region                   | `aws eks list-clusters --region <region>`                                                                        |
| `NS`, `POD`             | Namespace and Pod name                    | `kubectl get pods -A`                                                                                            |
| `NODE`                  | Kubernetes node name                      | `kubectl get pod "$POD" -n "$NS" -o jsonpath='{.spec.nodeName}'`                                                 |
| `INSTANCE_ID`           | EC2 instance behind a node                | `kubectl get node "$NODE" -o jsonpath='{.spec.providerID}' \| awk -F/ '{print $NF}'`                             |
| `NODEGROUP`             | Managed node group                        | `kubectl get node "$NODE" -o jsonpath='{.metadata.labels.eks\.amazonaws\.com/nodegroup}'`                        |
| `NODEPOOL`, `NODECLAIM` | Karpenter NodePool and NodeClaim          | `kubectl get node "$NODE" -L karpenter.sh/nodepool`; `kubectl get nodeclaims -o wide`                            |
| `KARPENTER_NS`          | Karpenter's namespace                     | `kubectl get deploy -A -l app.kubernetes.io/name=karpenter`                                                      |
| `PVC`, `PV`, `VOL`      | Claim, volume object, EBS volume ID       | `kubectl get pvc -n "$NS"`; `.spec.volumeName`; PV `.spec.csi.volumeHandle`                                      |
| `PRINCIPAL_ARN`         | IAM role ARN (not the `sts` session ARN)  | `aws sts get-caller-identity`, then rewrite `assumed-role/<name>/<session>` as `arn:aws:iam::<acct>:role/<name>` |
| `TARGET_VERSION`        | Kubernetes minor version to move to       | `aws eks describe-cluster-versions --region "$REGION"`                                                           |
| `TG_ARN`, `LB_ARN`      | Target group and load balancer            | `kubectl get targetgroupbindings -A`; `aws elbv2 describe-load-balancers`                                        |
| `AZ_ID`                 | AZ **ID** (e.g. `use1-az1`), not the name | `aws ec2 describe-availability-zones --region "$REGION" --query 'AvailabilityZones[].[ZoneName,ZoneId]'`         |
| `EVIDENCE_DIR`          | Where to keep incident output             | See below                                                                                                        |

## Keep evidence

```bash
export EVIDENCE_DIR=~/incidents/$(date -u +%Y%m%dT%H%MZ)-$CLUSTER
mkdir -p "$EVIDENCE_DIR" && chmod 700 "$EVIDENCE_DIR"
kubectl get "$KIND" "$NAME" -n "$NS" -o yaml > "$EVIDENCE_DIR/$KIND-$NAME-before.yaml"   # before every change
```

Save the object before you patch it, and write each mutation and its undo into a running log (`$EVIDENCE_DIR/actions.md`) with UTC timestamps. Don't collect `Secret` contents.

## Conventions on these pages

- `<angle brackets>` are values you fill in. `$VARIABLES` come from the table above.
- **⚠ Destructive** marks a step that deletes, detaches, force-terminates or bypasses a control, together with its precondition.
- **Expect / If** after a command describe the healthy and unhealthy output.
- Change EKS-managed add-ons with `aws eks update-addon --configuration-values`, not by editing their Deployments or DaemonSets. Otherwise the next add-on update overwrites the edit.
- If GitOps (Argo CD, Flux) owns an object, either change it in Git or pause sync before a live edit; otherwise the edit is reverted within minutes.

## Across the wiki

- [[Kubernetes/eks/operator-runbook/reference/first-five-minutes|First five minutes]]
- [[Kubernetes/eks/operator-runbook/index|EKS Operator Handbook]]
