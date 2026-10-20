---
title: "Runbook: Regression After an EKS Upgrade"
description: "Something broke after a control-plane, node, add-on or controller upgrade. Narrow it to the layer that changed, mitigate by rolling that layer back where possible, and fix forward on the control plane."
tags:
  [
    kubernetes/eks/operator-runbook,
    eks,
    runbook,
    upgrades,
    regression,
    incident,
  ]
date: 2026-10-20
aliases: [EKS post-upgrade issues, EKS upgrade broke something]
---

# Runbook: Regression After an EKS Upgrade

**Applies to:** problems that start during or after any step of an [[Kubernetes/eks/operator-runbook/procedures/control-plane-upgrade|upgrade]]: control plane, add-ons, node AMIs or kubelet, or self-managed controllers.
**Typical severity:** varies; often Sev 2 with a clear start time.
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

A clear "it worked before the change" story, with one of these:

| Symptom                                                                                         | Likely layer                                     |
| ----------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| `no matches for kind "X" in version "Y"`, or `the server could not find the requested resource` | **Removed API.** Control plane                   |
| A controller or operator crash-loops after the control-plane upgrade                            | **Controller incompatible** with the new version |
| Failures only on **new** nodes; old nodes are fine                                              | **Node AMI or kubelet**                          |
| Networking, DNS or proxying changed cluster-wide right after an add-on update                   | **Add-on**                                       |
| Helm upgrades fail with `unable to build kubernetes objects from current release manifest`      | **Removed API in a stored Helm release**         |

## Impact

Add-ons, AMIs, controllers and manifests can each be rolled back or forward on their own. The control plane can be rolled back one minor version, but only within 7 days of the upgrade, and only after rolling back nodes and incompatible add-ons (see [[Kubernetes/eks/operator-runbook/procedures/control-plane-upgrade|Control-plane upgrade]], Abort criteria). So the first job is to find the layer; rolling back only what broke is faster and less risky.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=my-cluster REGION=us-east-1
```

## Triage

**1. What changed, and when?** Line the start of the problem up with the changes:

```bash
aws eks list-updates --name "$CLUSTER" --region "$REGION" --query 'updateIds' --output text | tr '\t' '\n' | head -5 \
  | while read id; do aws eks describe-update --name "$CLUSTER" --region "$REGION" --update-id "$id" \
    --query 'update.[createdAt,type,status,params[?type==`Version`].value|[0]]' --output text; done
for ng in $(aws eks list-nodegroups --cluster-name "$CLUSTER" --region "$REGION" --query 'nodegroups[]' --output text); do
  aws eks list-updates --name "$CLUSTER" --region "$REGION" --nodegroup-name "$ng" --query "updateIds[0]" --output text | sed "s/^/$ng /"
done
for a in $(aws eks list-addons --cluster-name "$CLUSTER" --region "$REGION" --query 'addons[]' --output text); do
  aws eks describe-addon --cluster-name "$CLUSTER" --region "$REGION" --addon-name "$a" --query 'addon.[addonName,addonVersion,modifiedAt]' --output text
done
helm list -A --date | tail -10
```

**2. Does it follow the nodes?**

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,KUBELET:.status.nodeInfo.kubeletVersion,OS:.status.nodeInfo.osImage,KERNEL:.status.nodeInfo.kernelVersion,RUNTIME:.status.nodeInfo.containerRuntimeVersion
kubectl get pods -A -o wide | grep -Ev 'Running|Completed' | awk '{print $8}' | sort | uniq -c   # failing Pods by node
```

If failures cluster on nodes with the new kubelet, AMI or kernel, it's the node layer. Confirm by cordoning a new node and running the workload on an old one.

**3. Is a removed or changed API involved?**

```bash
kubectl get --raw /metrics | grep '^apiserver_requested_deprecated_apis'
kubectl api-resources | grep -i <kind>
kubectl logs -n <ns> deploy/<crash-looping-controller> --previous | grep -iE 'failed to list|no matches for kind|could not find the requested resource' | head
```

**4. Read the release notes** for the exact versions that changed: the Kubernetes changelog's "Urgent upgrade notes" and deprecations, the EKS version release notes, the EKS AMI release notes, and the add-on and controller release notes. Most regressions are a documented change in a default.

## Diagnosis

| Signal                                                        | Cause                                          | Fix   |
| ------------------------------------------------------------- | ---------------------------------------------- | ----- |
| Errors name an API version that no longer exists              | A. Removed API in manifests, charts or clients | Fix A |
| Controller crash-loops on new API server                      | B. Controller too old for the new version      | Fix B |
| Only new nodes fail                                           | C. AMI, kernel or kubelet change               | Fix C |
| Started with an add-on update                                 | D. Add-on change                               | Fix D |
| Behaviour change with no error (scheduling, probes, defaults) | E. Changed default or feature graduation       | Fix E |

## Fix

### A. Removed API

- **Manifests and charts:** update to the replacement API version (the deprecation guide lists them) and redeploy.
- **Stored Helm releases** still record the old API, so `helm upgrade` fails even after the chart is fixed. Rewrite the stored manifest with the `mapkubeapis` plugin, then upgrade:

  ```bash
  helm plugin install https://github.com/helm/helm-mapkubeapis
  helm mapkubeapis <release> -n <ns> --dry-run
  helm mapkubeapis <release> -n <ns>
  ```

- **Clients and scripts:** upgrade `kubectl`, SDKs and CI tools that call the old API.

### B. Controller too old

Upgrade the controller to a version that supports the new Kubernetes minor (check its compatibility matrix). If it uses CRDs, upgrade the CRDs as its upgrade notes say; many charts don't upgrade CRDs automatically.

### C. Node layer

Roll the affected node group or NodePool back to the previous AMI. For managed node groups, run `update-nodegroup-version` with the previous `--release-version` or launch template version (see [[Kubernetes/eks/operator-runbook/procedures/managed-node-group-ami-rotation|node group rotation]]). For Karpenter, re-pin the previous `amiSelectorTerms` alias, after pausing disruption budgets (see [[Kubernetes/eks/operator-runbook/procedures/karpenter-node-rotation|Karpenter node rotation]]). Old kubelets are within skew of the new control plane, so this is safe. Then find what changed in the AMI (kernel, cgroup settings, containerd version) before rolling forward again.

### D. Add-on change

Follow the add-on's abort path in [[Kubernetes/eks/operator-runbook/procedures/add-on-upgrade|Add-on upgrade]]. Fix forward with configuration where you can. Common examples: a `vpc-cni` environment variable whose default changed, a CoreDNS Corefile change, or a kube-proxy mode change.

### E. Changed default

Find the change in the release notes, then either adapt the workload to it, or set the old behaviour explicitly where Kubernetes still allows it (a field, a kubelet setting, an add-on configuration value). Record it as technical debt for the next upgrade.

## Verify recovery

- The failing workload or controller is healthy, and error rates are back at the pre-upgrade baseline.
- Re-run the smoke tests from [[Kubernetes/eks/operator-runbook/procedures/control-plane-upgrade|Control-plane upgrade]].

## Escalate

Open an AWS Support case if the regression is in an EKS-managed component (the control plane, EKS AMIs, managed add-ons) and isn't a documented change. Attach the cluster ARN, the update IDs, the versions before and after, and a minimal reproduction.

## Prevent

- Run every upgrade in a staging cluster with the same add-ons and representative workloads first.
- Upgrade one layer at a time, with an observation period between layers, so the layer is obvious when something breaks.
- Pin AMIs in production rather than following the latest release automatically.
- Scan manifests and Helm releases for deprecated APIs as part of CI, not just before upgrades.

## Background

- [[Kubernetes/updates-along-the-versions|Updates along the versions]]
- [[Kubernetes/guides/non-functional/deprecations|Deprecations]]
- [[Kubernetes/eks/cluster-upgrades/upgrade-process|EKS upgrade process]]
- [Kubernetes deprecated API migration guide](https://kubernetes.io/docs/reference/using-api/deprecation-guide/)
