---
title: "Procedure: Upgrade the EKS Control Plane One Minor Version"
description: "Pre-check deprecated APIs, add-ons, skew and subnet space; upgrade the control plane; then align add-ons and the data plane, with stop points at each stage."
tags: [kubernetes/eks/operator-runbook, eks, procedure, upgrades, control-plane]
date: 2026-10-20
aliases: [EKS cluster upgrade procedure, EKS control plane upgrade]
---

# Procedure: Upgrade the EKS Control Plane One Minor Version

**Applies to:** any EKS cluster moving from 1.N to 1.N+1. Repeat the whole procedure for each minor version; EKS doesn't skip versions.
**Duration:** control plane ~10–25 minutes; add-ons and data plane depend on fleet size.
**Risk:** medium. EKS can roll the control plane back one minor version within **7 days** of an in-place upgrade (see Abort criteria), but plan to fix forward; rollback is the emergency exit.
**Tested:** not run on a live cluster; commands checked for syntax.

## When to use

- The current version approaches end of standard support (check below). Extended support costs more.
- You need a feature or fix only in the next minor.

Run this in a non-production cluster with the same add-ons and workloads first, and keep its notes.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=my-cluster REGION=us-east-1
export CURRENT=$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query cluster.version --output text)
export TARGET_VERSION=<next minor, e.g. 1.37>
```

## Pre-checks

Any failed check is a **stop**. Fix it, then re-run the checks.

**1. Target is supported and is exactly one minor ahead.**

```bash
aws eks describe-cluster-versions --region "$REGION" \
  --query "clusterVersions[?clusterVersion=='$TARGET_VERSION'].[clusterVersion,versionStatus,endOfStandardSupportDate]" --output table
```

**2. EKS upgrade insights are clear.**

```bash
aws eks list-insights --cluster-name "$CLUSTER" --region "$REGION" \
  --filter '{"categories":["UPGRADE_READINESS"]}' \
  --query 'insights[].[name,insightStatus.status,id]' --output table
aws eks describe-insight --cluster-name "$CLUSTER" --region "$REGION" --id <id>   # for anything not PASSING
```

- **Expect:** every insight `PASSING`. Statuses are `PASSING`, `WARNING`, `ERROR` and `UNKNOWN`.
- **If** an insight isn't passing, `describe-insight` says why and what to do. For deprecated APIs, `deprecationDetails` lists each API, its replacement, and the client user agents that called it, with request counts and the last call time over the last 30 days. Find the client by its user agent (a controller, an old `kubectl`, a Helm-managed operator), upgrade or reconfigure it, and confirm the calls stop with the `apiserver_requested_deprecated_apis` metric in pre-check 3.
- Insights refresh every 24 hours. After fixing something, trigger a refresh with `aws eks start-insights-refresh --cluster-name "$CLUSTER" --region "$REGION"`, or the console's Refresh button. Usage older than 30 days doesn't appear, so a CronJob that runs monthly can be missed; pre-check 3's static scan catches those.
- `update-cluster-version` can refuse to start while upgrade-readiness checks fail. It has a `--force` flag to override them; don't use it to get past a real finding, because the removed API will start failing the moment the upgrade completes.

**3. No deprecated or removed APIs in use.** Check the manifests in Git and in Helm releases too, not just live calls:

```bash
kubectl get --raw /metrics | grep '^apiserver_requested_deprecated_apis' | grep "removed_release=\"$TARGET_VERSION\""
# Static scan of manifests and Helm releases, e.g. with pluto:
pluto detect-helm -o wide --target-versions k8s=v$TARGET_VERSION.0
pluto detect-files -d ./manifests --target-versions k8s=v$TARGET_VERSION.0
```

Read the Kubernetes changelog for `$TARGET_VERSION`, and the EKS release notes, for removed features and changed defaults. The wiki tracks these in [[Kubernetes/updates-along-the-versions|updates along the versions]].

**4. Add-ons and controllers have versions for the target.**

```bash
for a in $(aws eks list-addons --cluster-name "$CLUSTER" --region "$REGION" --query 'addons[]' --output text); do
  cur=$(aws eks describe-addon --cluster-name "$CLUSTER" --region "$REGION" --addon-name "$a" --query addon.addonVersion --output text)
  def=$(aws eks describe-addon-versions --addon-name "$a" --kubernetes-version "$TARGET_VERSION" --region "$REGION" \
    --query 'addons[0].addonVersions[?compatibilities[?defaultVersion==`true`]].addonVersion | [0]' --output text)
  echo "$a current=$cur target-default=$def"
done
helm list -A
```

Self-managed controllers (AWS Load Balancer Controller, Karpenter, cert-manager, ingress controllers, policy engines, service meshes) each publish a Kubernetes compatibility matrix. Note any that must be upgraded **before** the control plane.

**5. Nodes are within skew after the upgrade.** After the upgrade, every kubelet must be at most 3 minors behind `$TARGET_VERSION`:

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,KUBELET:.status.nodeInfo.kubeletVersion --no-headers \
  | awk '{print $2}' | sort | uniq -c
```

**6. Cluster subnets have free IPs.** EKS needs up to 5 free addresses in the cluster subnets:

```bash
aws ec2 describe-subnets --region "$REGION" --subnet-ids $(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
  --query 'cluster.resourcesVpcConfig.subnetIds' --output text) \
  --query 'Subnets[].[SubnetId,AvailableIpAddressCount]' --output table
```

**7. Workloads can be disrupted safely** (for the data-plane stage). No PDB should sit at `ALLOWED DISRUPTIONS 0` for a healthy workload:

```bash
kubectl get pdb -A | awk 'NR==1 || $(NF-1)=="0"'
```

**8. Backups and a baseline.** Recent backups exist, and you've recorded a baseline of error rate and latency for the main services. Freeze unrelated deploys for the window.

## Steps

**1. Upgrade self-managed controllers that must go first** (from pre-check 4), one at a time, checking each one's health.

**2. Upgrade the control plane.**

```bash
UPDATE_ID=$(aws eks update-cluster-version --name "$CLUSTER" --region "$REGION" \
  --kubernetes-version "$TARGET_VERSION" --query update.id --output text)
echo "$UPDATE_ID" | tee -a "$EVIDENCE_DIR/actions.md"
watch -n 30 "aws eks describe-update --name $CLUSTER --region $REGION --update-id $UPDATE_ID --query 'update.[status,errors]' --output text"
```

- **Checkpoint:** status `Successful`, and `kubectl version` shows the new server version. Workloads keep running throughout; the API may briefly return errors while API server instances are replaced.
- **If** the status is `Failed` → read `errors`. EKS leaves the cluster on the old version. Fix the cause (usually subnet IPs, or a security group or IAM change) and retry.

**3. Upgrade the core add-ons** to the target-compatible versions, one at a time: `vpc-cni`, then `kube-proxy` (match the node minor where possible), then `coredns`, then the rest. Follow [[Kubernetes/eks/operator-runbook/procedures/add-on-upgrade|Add-on upgrade]] for each.

- **Checkpoint:** every add-on is `ACTIVE` with no health issues, and the DNS and network smoke tests below pass.

**4. Upgrade the data plane.**

- **Managed node groups:** [[Kubernetes/eks/operator-runbook/procedures/managed-node-group-ami-rotation|Managed node group rotation]] with `--kubernetes-version "$TARGET_VERSION"`.
- **Karpenter:** if the EC2NodeClass uses `alias: al2023@latest`, nodes drift to the new version's AMI on their own; otherwise update the pin. Follow [[Kubernetes/eks/operator-runbook/procedures/karpenter-node-rotation|Karpenter node rotation]].
- **Fargate:** restart the Deployments; new Pods get the new version.
- **Auto Mode:** EKS rolls the nodes itself, within NodePool disruption budgets. Watch progress with `kubectl get nodes`.

Do one node group or NodePool at a time, and watch the error-rate baseline between groups.

**5. Upgrade the remaining controllers** that needed the new version.

## Smoke tests (after steps 2, 3 and 4)

```bash
kubectl get nodes
kubectl get pods -A | grep -Ev 'Running|Completed'
kubectl run smoke -n default --image=public.ecr.aws/docker/library/busybox:1.36 --restart=Never --rm -it -- \
  sh -c 'nslookup kubernetes.default.svc.cluster.local && wget -qO- -T5 https://aws.amazon.com >/dev/null && echo OK'
kubectl create deployment smoke-wh --image=public.ecr.aws/docker/library/busybox:1.36 --dry-run=server -o name
```

Then check that the main services' error rate and latency match the baseline, and that a test Ingress or Service still gets a load balancer.

## Abort criteria and rollback

- **Before step 2:** abort freely.
- **Failed control-plane update:** the cluster stays on the old version. Nothing to roll back.
- **Regression after a successful control-plane update:** first try fixing forward: roll back the add-on, controller or workload that changed, adjust config for the changed default, or pin the old node AMI while you investigate.
- **Control-plane rollback**, if fixing forward isn't enough. EKS reverts the API server and control-plane components to the previous minor version, keeping etcd data, workloads and volumes. The conditions:
  - within **7 days** of the upgrade completing, and only one minor version back (N to N-1);
  - the cluster was upgraded in place to its current version (not created at it), is `ACTIVE`, and has no other update running;
  - going back to a version in extended support needs the cluster's upgrade policy set to `EXTENDED` first.

  Order matters, because kubelets must never be newer than the API server:
  1. Check `ROLLBACK_READINESS` insights. `ERROR` or `UNKNOWN` blocks the rollback.

     ```bash
     aws eks list-insights --cluster-name "$CLUSTER" --region "$REGION" \
       --filter '{"categories":["ROLLBACK_READINESS"]}' --query 'insights[].[name,insightStatus.status,id]' --output table
     ```

  2. Roll back worker nodes already on the new version. For managed node groups, run `update-nodegroup-version --kubernetes-version "$CURRENT"`. Self-managed and hybrid nodes are yours to roll back. Auto Mode nodes are rolled back by EKS automatically. Fargate Pods can't be rolled back; delete those running the new version first.
  3. Downgrade any add-on that's incompatible with the previous version (`update-addon --addon-version <compatible>`). Add-ons are **not** rolled back for you.
  4. Roll back the control plane and track the update. Its type is `VersionRollback`:

     ```bash
     UPDATE_ID=$(aws eks update-cluster-version --name "$CLUSTER" --region "$REGION" \
       --kubernetes-version "$CURRENT" --query update.id --output text)
     aws eks describe-update --name "$CLUSTER" --region "$REGION" --update-id "$UPDATE_ID" --query 'update.[type,status,errors]'
     ```

  `--force` bypasses the insight checks, but not the 7-day window or the other conditions. Don't use it unless you've read every `ERROR` insight and accepted the risk.

- **Data-plane regression:** stop the node rollout. The old nodes keep the old kubelet, which is within skew. Roll the node group back to its previous launch template or AMI version.

## Post-checks

- `aws eks list-insights` shows no new failures.
- All nodes run the target kubelet minor, or a deliberate exception is recorded.
- Monitoring, logging and policy agents report from every node.

## Clean-up

- Unfreeze deploys.
- Record the versions (control plane, platform version, add-ons, AMIs, controllers) in the cluster's change log.
- Update IaC so the next apply doesn't try to "revert" the version.

## Background

- [[Kubernetes/eks/cluster-upgrades/upgrade-process|EKS upgrade process]]
- [[Kubernetes/eks/cluster-upgrades/upgrade-journey|Upgrade journey]]
- [[Kubernetes/guides/non-functional/upgrade-strategy|Upgrade strategy]]
- [[Kubernetes/eks/operator-runbook/reference/limits-and-formulas|Version skew and support windows]]
- [Update an existing cluster to a new Kubernetes version](https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html)
