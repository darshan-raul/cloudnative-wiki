---
title: Upgrade Strategy
tags:
  - Kubernetes
  - Non-Functional
  - Upgrades
  - Lifecycle
---

K8s releases four minor versions a year. Each release has ~9 months of support, then 1 month of "you really should upgrade" support. **Skipping a minor version is not supported** — you must upgrade sequentially.

## The release cadence

```
2024-04      v1.30 ←── newest
2024-01      v1.29
2023-12      v1.28 ←── supported
2023-08      v1.27 ←── end of support soon
2023-04      v1.26 ←── EOL, no patches
```

| Phase | Duration | Patches |
|-------|----------|---------|
| Active support | ~12 months | Yes |
| Maintenance | ~1 month | Critical security only |
| End of life | Forever | None |

**k8s supports ~3 minor versions at any time.** If you're on 1.27 and 1.30 is out, you're approaching EOL.

## The k8s version skew

The kubelet on a node can be **up to 3 minor versions behind** the apiserver (and 1 minor version ahead of older kubelets). This lets you upgrade nodes one at a time without breaking the cluster.

But the rule **applies per-node**. If you have a 5-node cluster and start with all nodes on 1.27:
1. Drain node-1
2. Upgrade node-1 to 1.28
3. Bring node-1 back into the cluster
4. Repeat for node-2, 3, 4, 5

After all 5 nodes are on 1.28, you can upgrade the apiserver to 1.28 (or do it first — order doesn't matter as long as the apiserver is the latest).

## Upgrade order

The standard upgrade order:

```
1. Control plane (apiserver, scheduler, controller-manager, etcd)
2. Node components (kubelet, kube-proxy)
3. Add-ons (CNI, ingress controller, metrics-server, etc.)
4. Workloads (your apps)
```

**Why this order:** apiserver is the source of truth. kubelets need to be compatible. Add-ons depend on both. Workloads are last (and most teams auto-upgrade via their CI/CD).

For cloud-managed (EKS, GKE, AKS), the cloud handles 1-3. You only do 4.

## Cloud-managed upgrade patterns

### EKS

EKS has two planes:
- **Control plane** — managed by AWS, you choose the k8s version
- **Data plane** — your worker nodes (managed node groups, self-managed, Fargate)

**Control plane upgrade:**

```bash
# update-kubeconfig picks up the new version after the upgrade
aws eks update-cluster-version \
  --name my-cluster \
  --kubernetes-version 1.30

# takes 15-30 minutes
# AWS upgrades the control plane in place
```

**Data plane (managed node group) upgrade:**

```bash
# create a new node group with the new version
aws eks create-nodegroup \
  --cluster-name my-cluster \
  --nodegroup-name my-cluster-v130 \
  --kubernetes-version 1.30 \
  ...

# or update the launch template version
aws eks update-nodegroup-version \
  --cluster-name my-cluster \
  --nodegroup-name my-cluster-workers \
  --kubernetes-version 1.30
```

**Or use Karpenter** — its NodePool version follows the cluster version automatically.

### GKE

```bash
# regular channel (default, automated upgrades)
gcloud container clusters upgrade my-cluster \
  --master --cluster-version 1.30

# data plane (node upgrade)
gcloud container clusters upgrade my-cluster \
  --cluster-version 1.30

# or use a release channel (auto)
gcloud container clusters create my-cluster \
  --release-channel regular
```

**Release channels:**
- **Rapid** — newest versions first, most risk
- **Regular** — default, balanced
- **Stable** — older, more conservative
- **Extended** — pay extra to stay on older versions

### AKS

```bash
# upgrade control plane and nodes
az aks upgrade \
  --resource-group my-rg \
  --name my-cluster \
  --kubernetes-version 1.30.0
```

**AKS auto-upgrade:** set `--auto-upgrade-channel` to one of `rapid`, `stable`, `node-image`, `patch`.

## Self-managed (kubeadm) upgrade

For kubeadm-managed clusters, the upgrade is manual but scripted.

**On each control plane node:**

```bash
# 1. drain (optional, but recommended for clean upgrades)
kubectl drain <node-name> --ignore-daemonsets

# 2. upgrade kubeadm
sudo apt-get update
sudo apt-get install -y kubeadm=1.30.0-00

# 3. plan the upgrade
sudo kubeadm upgrade plan

# 4. apply
sudo kubeadm upgrade apply v1.30.0

# 5. upgrade kubelet and kubectl
sudo apt-get install -y kubelet=1.30.0-00 kubectl=1.30.0-00
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# 6. uncordon
kubectl uncordon <node-name>
```

**On each worker node:**

```bash
# 1. drain
kubectl drain <node-name> --ignore-daemonsets

# 2. upgrade kubeadm, kubelet, kubectl
sudo apt-get update
sudo apt-get install -y kubeadm=1.30.0-00 kubelet=1.30.0-00 kubectl=1.30.0-00

# 3. upgrade node config
sudo kubeadm upgrade node

# 4. restart kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# 5. uncordon
kubectl uncordon <node-name>
```

**The order matters:** upgrade control plane first, then nodes, one at a time.

## Add-on upgrades

Add-ons (CNI, ingress, metrics-server, etc.) need to be upgraded separately, after the control plane.

**Generic pattern:**

```bash
# 1. check current version
kubectl get deploy -n kube-system
# see what version of CNI, ingress, etc. is running

# 2. check the add-on's release notes for k8s compatibility
# (most add-ons have a compatibility matrix)

# 3. upgrade using the tool of choice (Helm, manifest, operator)

# example: ingress-nginx
helm repo update
helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --version 4.10.0 \
  --namespace ingress-nginx

# example: metrics-server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

**Common add-on upgrade gotchas:**

- **CNI upgrades** can be disruptive. Some require nodes to be drained.
- **Ingress controller** can be done in-place (it's a Deployment).
- **metrics-server** is usually a simple `kubectl apply`.
- **CRDs** need to be upgraded before or with the controller that uses them.
- **Operators** often have CRDs in a separate Helm chart (e.g., cert-manager's CRD chart).

## Deprecation awareness

Each k8s release deprecates APIs. If your workloads use a deprecated API, the upgrade will break them.

**Check before upgrading:**

```bash
# use the k8s deprecation checker
# https://github.com/kubernetes-sigs/kube-no-trouble

# install
curl -sSL https://raw.githubusercontent.com/kubernetes-sigs/kube-no-trouble/main/install.sh | bash

# run
kubent
# or
kube-no-trouble
```

Output:

```
2.0.0 has the following deprecated APIs:
─────────────────────────────────────
PodSecurityPolicy will be removed in v1.25
  ├─ default/redis-psp
  ├─ kube-system/csi-hostpath-psp
  └─ ...

Ingress will be removed in v1.22 (already removed)
  ├─ default/old-ingress
  └─ ...
```

**Common deprecations:**

- `policy/v1beta1/PodSecurityPolicy` — removed in 1.25, replaced by PSS
- `networking.k8s.io/v1beta1/Ingress` — removed in 1.22, replaced by v1
- `apps/v1beta1/Deployment` — removed long ago
- `rbac.authorization.k8s.io/v1beta1` — removed, use v1
- `apiextensions.k8s.io/v1beta1/CustomResourceDefinition` — removed in 1.22, use v1
- `admissionregistration.k8s.io/v1beta1/MutatingWebhookConfiguration` — removed, use v1

**Before upgrading, run `kubent` and fix any deprecated APIs in your workloads.**

See [[Kubernetes/guides/non-functional/deprecations|deprecations]] for the full list.

## Workload upgrades

Your apps (Deployments, StatefulSets, etc.) are upgraded via your normal CI/CD process — pushing a new image, bumping a tag. The k8s version doesn't change your workflow.

**But:** if you're using deprecated APIs, the upgrade breaks your app.

**Pre-upgrade checklist for workloads:**

1. Run `kubent` (or pluto, or kubernetes-deprecation-guide)
2. Fix deprecated APIs (usually `kubectl convert` or update manifests)
3. Test in staging
4. Apply via GitOps

## Upgrade strategies

### Blue-green (zero-downtime)

```bash
# 1. create a new node group with new version
aws eks create-nodegroup --kubernetes-version 1.30 ...

# 2. cordon old nodes
kubectl cordon --all
# (or specific old nodes)

# 3. drain old nodes
for node in $(kubectl get nodes -l kubernetes.io/version=1.29 -o name); do
  kubectl drain $node --ignore-daemonsets
done

# 4. delete old node group
aws eks delete-nodegroup --nodegroup-name old-v129
```

**Pros:** zero-downtime, easy rollback (cordon new, uncordon old).
**Cons:** temporarily 2x the node count, expensive.

### In-place rolling (smaller clusters)

```bash
# 1. upgrade one node at a time
for node in $(kubectl get nodes -o name); do
  kubectl drain $node --ignore-daemonsets
  # upgrade the node (kubeadm, AMI change, etc.)
  kubectl uncordon $node
done
```

**Pros:** no extra capacity needed.
**Cons:** if the upgrade fails, harder to roll back.

### Cluster API / managed

The most modern approach. Define clusters declaratively, let the controller handle upgrades.

```yaml
# Cluster API MachineDeployment
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDeployment
metadata:
  name: prod-workers
spec:
  template:
    spec:
      version: v1.30.0   # bumped
```

**Pros:** declarative, repeatable, canary rollouts.
**Cons:** requires CAPI infrastructure.

## Upgrade cadence

How often should you upgrade?

| Cadence | Pros | Cons |
|---------|------|------|
| **Every release** (4x/year) | Always current, smaller bumps | Constant work |
| **Quarterly** | Predictable, time to validate | May fall behind |
| **Every 6 months** | Less work | Larger jumps, more risk |
| **Annual** | Minimal work | Often EOL by the time you do it |

**Recommended:** every 3-4 months (quarterly), staying within 1 minor version of latest.

## The pre-upgrade checklist

Before any upgrade:

- [ ] **Read release notes** for all skipped versions
- [ ] **Check deprecations** with `kubent` or similar
- [ ] **Verify add-on compatibility** (CNI, ingress, operators)
- [ ] **Test in staging** that mirrors production
- [ ] **Have a rollback plan** (snapshots, AMI, etc.)
- [ ] **Backup etcd** (or trust cloud-managed)
- [ ] **Backup applications** (Velero)
- [ ] **Schedule the upgrade** during a low-traffic window
- [ ] **Notify the team** of the maintenance window
- [ ] **Have an upgrade runbook** with commands ready

## The post-upgrade verification

After upgrading, verify:

- [ ] **Cluster is healthy** — `kubectl get nodes`, all Ready
- [ ] **All workloads are running** — `kubectl get pods -A`, all Running/Ready
- [ ] **Add-ons are working** — ingress, metrics-server, CNI
- [ ] **Smoke tests pass** — basic app functionality
- [ ] **Monitoring is intact** — Prometheus, alerts firing
- [ ] **Logs are flowing** — central log aggregation working
- [ ] **No deprecated APIs in use** — `kubectl get --raw /api/v1` etc.

## Common gotchas

* **You can't skip minor versions.** 1.27 → 1.30 directly is not supported. Must go 1.27 → 1.28 → 1.29 → 1.30.
* **The kubelet skew rule is per-node, not per-cluster.** Some nodes can be ahead, some behind.
* **CNI upgrades can be disruptive.** Some CNIs require node restarts.
* **CRDs need to be updated with the controller that uses them.** Otherwise the controller might not recognize new fields.
* **Helm chart versions** don't always align with k8s versions. The chart's `appVersion` is the underlying software version.
* **etcd upgrades are critical.** A bad etcd upgrade can lose data. Always backup first.
* **Node OS upgrades** are separate from k8s upgrades. AMI updates for worker nodes.
* **Cloud-managed clusters still need workload-side upgrades.** The control plane is managed; your apps are yours.
* **The "extended support" channel** for cloud-managed clusters costs more and delays inevitable upgrades. Use it sparingly.
* **Custom controllers / operators** may have k8s version compatibility. Check before upgrading.
* **Network plugins and CSI drivers** are part of the cluster, but separate from k8s proper. They have their own upgrade cadence.

## A worked example

**Cluster:** EKS, currently on 1.28, want to upgrade to 1.29.
**Workers:** 2 managed node groups (prod, spot).
**Workloads:** 50 Deployments, all via GitOps.

**Plan:**

1. **Read 1.29 release notes** — check deprecations
2. **Run `kubent`** — no deprecated APIs in our workloads
3. **Check add-on compatibility** — Calico 3.27 supports 1.29, ingress-nginx 1.10 supports 1.29
4. **Backup** — Velero backup of cluster state, snapshot of any RDS
5. **Test in staging** — same upgrade on dev cluster, verify all apps work
6. **Schedule maintenance** — low-traffic window, 2-hour block
7. **Notify team** — Slack, calendar
8. **Run upgrade:**

```bash
# upgrade control plane
aws eks update-cluster-version \
  --name prod-cluster \
  --kubernetes-version 1.29
# wait for UPDATE_COMPLETE

# upgrade workers (new node group, blue-green)
aws eks create-nodegroup \
  --cluster-name prod-cluster \
  --nodegroup-name prod-v129 \
  --kubernetes-version 1.29 \
  --subnets subnet-xxx subnet-yyy \
  --node-role arn:aws:iam::xxx:role/EKSNodeRole \
  --instance-types m5.large \
  --desired-size 3 --min-size 1 --max-size 10

# wait for nodes to join
kubectl get nodes

# cordon old workers
for node in $(kubectl get nodes -l eks.amazonaws.com/nodegroup=prod-v128 -o name); do
  kubectl cordon $node
done

# drain old workers
for node in $(kubectl get nodes -l eks.amazonaws.com/nodegroup=prod-v128 -o name); do
  kubectl drain $node --ignore-daemonsets --delete-emptydir-data
done

# delete old node group
aws eks delete-nodegroup \
  --cluster-name prod-cluster \
  --nodegroup-name prod-v128
```

9. **Verify** — kubectl get nodes, all on 1.29; smoke tests pass
10. **Document** — note any issues, share with team

**Total time:** ~1 hour for the control plane, ~30 min for the node group migration.

## Cluster API for declarative upgrades

Cluster API (CAPI) treats clusters and machines as k8s objects. You can declaratively upgrade:

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDeployment
metadata:
  name: prod-md-0
spec:
  clusterName: prod
  replicas: 3
  template:
    spec:
      version: v1.30.0   # bumped
      bootstrap:
        configRef:
          apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
          kind: KubeadmConfigTemplate
          name: prod-md-0
      infrastructureRef:
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
        kind: AWSMachineTemplate
        name: prod-md-0
```

CAPI rolls new nodes with the new version, drains old, deletes. **Repeatable, version-controlled cluster lifecycle.**

## EKS upgrade specifics

EKS has its own upgrade paths and gotchas.

### Control plane upgrade

```bash
# 1. check current version
aws eks describe-cluster --name my-cluster \
  --query "cluster.version"

# 2. check what versions are available
aws eks list-cluster-versions \
  --query "clusterVersions[].clusterVersion"

# 3. update
aws eks update-cluster-version \
  --name my-cluster \
  --kubernetes-version 1.30

# 4. wait (15-30 min)
aws eks describe-cluster --name my-cluster \
  --query "cluster.status"
# ACTIVE means upgrade complete
```

**Note:** EKS supports 3 minor versions at a time. If you're on 1.27 and EKS supports up to 1.30, you can upgrade directly.

### Add-on upgrades

EKS add-ons (VPC CNI, kube-proxy, CoreDNS, EBS CSI) need separate upgrades:

```bash
# list add-ons
aws eks list-addons --cluster-name my-cluster

# update
aws eks update-addon \
  --cluster-name my-cluster \
  --addon-name vpc-cni \
  --addon-version v1.18.0-eksbuild.1

# or use the latest compatible version
aws eks update-addon \
  --cluster-name my-cluster \
  --addon-name vpc-cni \
  --resolve-conflicts PRESERVE
```

**Always check the EKS add-on compatibility** for the k8s version you're upgrading to.

### Karpenter

If using Karpenter, the controller and NodePool version should follow the cluster:

```bash
# upgrade Karpenter
helm upgrade karpenter karpenter/karpenter \
  --version 0.32.0 \
  --namespace karpenter

# update NodePool requirements if needed
kubectl edit nodepool default
```

## GKE upgrade specifics

### Release channels

GKE offers release channels that automate upgrades:

```bash
# create with a release channel
gcloud container clusters create my-cluster \
  --release-channel regular

# change release channel
gcloud container clusters update my-cluster \
  --release-channel stable
```

**Channels:**
- **Rapid** — newest versions first, most risk
- **Regular** — default, balanced
- **Stable** — older, more conservative (good for production)
- **Extended** — pay extra to stay on older versions

### Manual upgrade

```bash
# 1. see available versions
gcloud container get-server-config --region us-central1

# 2. upgrade master
gcloud container clusters upgrade my-cluster \
  --master \
  --cluster-version 1.30.0-gke.0

# 3. upgrade nodes
gcloud container clusters upgrade my-cluster \
  --cluster-version 1.30.0-gke.0
```

### Maintenance windows

Control when GKE does auto-upgrades:

```bash
# set a maintenance window
gcloud container clusters update my-cluster \
  --maintenance-window-start 2024-01-20T02:00:00Z \
  --maintenance-window-end 2024-01-20T06:00:00Z \
  --maintenance-window-recurrence "FREQ=WEEKLY;BYDAY=SA"
```

## AKS upgrade specifics

### Control plane upgrade

```bash
# available versions
az aks get-versions --location eastus --output table

# upgrade control plane and nodes
az aks upgrade \
  --resource-group my-rg \
  --name my-cluster \
  --kubernetes-version 1.30.0
```

### Auto-upgrade channel

```bash
# set auto-upgrade
az aks update \
  --resource-group my-rg \
  --name my-cluster \
  --auto-upgrade-channel stable
```

**Channels:** `rapid`, `stable`, `node-image`, `patch`.

## Self-managed cluster upgrade gotchas

### kubeadm upgrade pitfalls

1. **Don't skip versions.** 1.27 → 1.30 directly fails. Must go sequentially.
2. **Upgrade the control plane first.** Always. Apiserver should be ahead of kubelets.
3. **Drain before upgrade.** Don't upgrade kubelet on a node with running pods.
4. **Backup etcd before upgrading etcd.** Especially for major etcd versions.
5. **Check add-on compatibility.** CNI, ingress, etc. may need version bumps.
6. **Test CRD migrations.** Some CRDs change between k8s versions.
7. **Verify pod sandbox image.** The pause container has a version.

### etcd upgrade

etcd is a separate component with its own version. Check the k8s release notes for the etcd version:

```bash
# what's the current etcd version?
kubectl exec -n kube-system etcd-master-1 -- etcd --version

# check k8s release notes for new etcd version
# https://kubernetes.io/releases/

# upgrade etcd as part of the kubeadm upgrade
sudo kubeadm upgrade apply v1.30.0
# (etcd is upgraded automatically as part of kubeadm)
```

**For etcd data corruption:** restore from snapshot, don't try to fix.

## In-place vs blue-green

### In-place (smaller clusters)

```bash
# upgrade one node at a time
for node in $(kubectl get nodes -o name); do
  kubectl drain $node --ignore-daemonsets
  # upgrade kubelet
  ssh $node "sudo apt-get install -y kubelet=1.30.0-00"
  ssh $node "sudo systemctl restart kubelet"
  kubectl uncordon $node
done
```

**Pros:** no extra capacity
**Cons:** slow, hard to roll back

### Blue-green (production)

```bash
# 1. create new node group with new version
aws eks create-nodegroup \
  --cluster-name prod \
  --nodegroup-name prod-v130 \
  --kubernetes-version 1.30 \
  ...

# 2. wait for new nodes
kubectl get nodes
# 5+ nodes on 1.30

# 3. cordon old nodes
kubectl cordon --all
# or specific label
for node in $(kubectl get nodes -l kubernetes.io/version=1.29 -o name); do
  kubectl cordon $node
done

# 4. drain old nodes
for node in $(kubectl get nodes -l kubernetes.io/version=1.29 -o name); do
  kubectl drain $node --ignore-daemonsets
done

# 5. delete old node group
aws eks delete-nodegroup \
  --cluster-name prod \
  --nodegroup-name prod-v129
```

**Pros:** fast rollback (cordon new, uncordon old)
**Cons:** temporarily 2x nodes

## Rollback strategies

### The cluster is broken — what now?

**For cloud-managed:** the cloud can usually roll back to the previous version. Contact support.

**For self-managed:**
- etcd restore from snapshot (loses recent changes)
- Re-provision with the old version

**For workloads:** your app broke? Roll back the deployment:

```bash
kubectl rollout undo deployment/web
```

### Pre-upgrade snapshot

Always take a snapshot before any upgrade:

```bash
# etcd snapshot
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-before-upgrade.db

# Velero backup
velero backup create pre-upgrade-$(date +%Y%m%d)
```

If the upgrade fails, restore from the snapshot.

### GitOps rollback

If GitOps is the source of truth, rollback is just `git revert`:

```bash
git revert <bad-commit>
git push
# Argo CD / Flux rolls back
```

## Upgrade testing

### Pre-prod upgrade

Always test in a non-prod cluster first:

```bash
# upgrade dev cluster
az aks upgrade --name dev-cluster --kubernetes-version 1.30.0

# run smoke tests
./smoke-test.sh

# check deprecated APIs
kubent

# check for issues
kubectl get events -A --sort-by='.lastTimestamp' | head
```

**The dev cluster's upgrade should reveal:**
- Deprecated APIs you forgot to fix
- Add-on compatibility issues
- Workload-level bugs (image pulls, etc.)

### Pre-prod cluster parity

The dev cluster should mirror production:
- Same k8s version
- Same add-ons
- Same CNI
- Same ingress controller
- Sample workloads (not all of them)

**If dev and prod diverge:** the upgrade can fail in unexpected ways.

### Smoke tests

After every upgrade, run smoke tests:

```bash
# 1. can you deploy?
kubectl run smoke --image=busybox --rm -it --restart=Never -- echo "hello"

# 2. can you access services?
kubectl run smoke --image=curlimages/curl --rm -it --restart=Never -- \
  curl -sS -i http://web-service

# 3. can you read secrets?
kubectl get secret my-secret -o jsonpath='{.data.password}' | base64 -d
# (should work if RBAC is correct)

# 4. can you write?
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: smoke-test
data:
  key: value
EOF
```

## Common add-on upgrade patterns

### Calico

```bash
# upgrade Calico
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

# verify
kubectl get pods -n calico-system
```

**Warning:** Calico upgrades can disrupt network connectivity. Drain nodes first.

### ingress-nginx

```bash
# upgrade via Helm
helm repo update
helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --version 4.10.0 \
  --namespace ingress-nginx
```

**Note:** ingress-nginx has its own compatibility matrix. Check the chart's `appVersion`.

### cert-manager

```bash
# upgrade cert-manager
helm upgrade cert-manager jetstack/cert-manager \
  --version v1.14.0 \
  --namespace cert-manager
```

**Important:** cert-manager 1.14+ requires k8s 1.22+. Older k8s may need older cert-manager.

### metrics-server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

**Easy.** Replace in place. No data loss.

## Common upgrade scenarios

### Scenario 1: small cluster, manual upgrade

```bash
# 1. schedule maintenance
# 2. backup
# 3. upgrade control plane
# 4. upgrade nodes one at a time
# 5. upgrade add-ons
# 6. verify
```

### Scenario 2: large cluster, blue-green

```bash
# 1. create new node group
# 2. wait for nodes to join
# 3. cordon old, drain old
# 4. delete old node group
# 5. upgrade add-ons
# 6. verify
```

### Scenario 3: cloud-managed, automated

```bash
# 1. wait for cloud to schedule upgrade
# 2. verify auto-upgrade is configured
# 3. cloud does the upgrade
# 4. you verify
```

### Scenario 4: stuck on old version, can't upgrade

```bash
# 1. identify blocker
kubent

# 2. fix the blocker
# 3. test in dev
# 4. upgrade
```

## Upgrade schedule templates

### Quarterly upgrade (recommended)

```
Quarter 1: Upgrade to 1.30
Quarter 2: Upgrade to 1.31
Quarter 3: Upgrade to 1.32
Quarter 4: Upgrade to 1.33
```

**Always stay within 1 minor version of latest.**

### Annual upgrade (acceptable)

```
2024 Q1: Upgrade to 1.30
2025 Q1: Upgrade to 1.33
```

**Risk:** large jumps, more deprecated APIs to fix.

### "Never upgrade" (not recommended)

```
Production cluster: 1.20 (EOL)
```

**Cost:** extended support fees, security vulnerabilities, missing features.

## See also

* [[Kubernetes/guides/non-functional/deprecations|deprecations]] — what to watch
* [[Kubernetes/guides/non-functional/disaster-recovery|disaster-recovery]] — if upgrade goes wrong
* [[Kubernetes/guides/non-functional/high-availability|high-availability]] — designing for upgrade
* [k8s release notes](https://kubernetes.io/releases/)
