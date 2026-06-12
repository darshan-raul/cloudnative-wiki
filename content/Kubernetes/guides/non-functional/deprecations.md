---
title: Deprecations
tags:
  - Kubernetes
  - Non-Functional
  - Deprecations
  - APIs
---

K8s deprecates APIs in every release. Some deprecations are gentle (deprecated, still works for 9+ months). Some are sudden (removed in next release). **Knowing what's deprecated and what's removed is the difference between an upgrade that works and one that breaks everything.**

## The deprecation lifecycle

```
1. Marked deprecated   (in API; CLI shows warnings)
        ↓ 9-12 months
2. Removed              (apiserver returns 404 or rejects the request)
        ↓
3. Migration required   (your code must use the new API)
```

**The cycle varies:**

- Most APIs: deprecated, then 9-12 months later removed
- Beta APIs: deprecated, then 1 release later removed (faster cycle)
- Alpha APIs: can be removed at any time, no deprecation warning

**This is why pinning to a specific k8s version matters.** When you upgrade, check what's removed.

## How to check for deprecated APIs

Three tools, all useful:

### kubent (kube-no-trouble)

```bash
# install
curl -sSL https://raw.githubusercontent.com/kubernetes-sigs/kube-no-trouble/main/install.sh | sudo bash

# run against your current cluster
kubent
```

Output:

```
2.0.0 has the following deprecated APIs:
─────────────────────────────────────────────
PodSecurityPolicy will be removed in v1.25
  ├─ default/redis-psp
  └─ kube-system/csi-hostpath-psp

Ingress will be removed in v1.22 (already removed)
  ├─ default/old-ingress
  └─ ...
```

### pluto (by Fairwinds)

```bash
# install
brew install pluto

# run
pluto detect-all-in-cluster
```

### Built-in: the apiserver warns

```bash
# get all ingresses with deprecation warnings
kubectl get ingresses.v1.networking.k8s.io -A -o json | \
  jq '.items[].metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"]' | \
  grep -oE 'apiVersion:[^,]*' | sort -u
```

The apiserver returns warnings on responses for deprecated APIs. Many tools (kubectl, k9s) surface these.

## The "big" deprecations, organized by version

### v1.16 (deprecated, removed in v1.22)

**Networking v1beta1 Ingress** — gone in 1.22

```yaml
# old
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
# ...

# new
apiVersion: networking.k8s.io/v1
kind: Ingress
spec:
  rules:
  - host: example.com
    http:
      paths:
      - path: /
        pathType: Prefix   # required in v1
        backend:
          service:
            name: web
            port:
              number: 80
```

**Migration:** `kubectl convert` or rewrite the manifest.

### v1.22 (removed)

- `extensions/v1beta1/Ingress` — gone
- `apps/v1beta1/Deployment` — gone (long deprecated)
- `apiextensions.k8s.io/v1beta1/CustomResourceDefinition` — gone
- `admissionregistration.k8s.io/v1beta1/*` — gone
- `rbac.authorization.k8s.io/v1beta1/*` — gone
- `certificates.k8s.io/v1beta1/CertificateSigningRequest` — gone (use v1)
- `networking.k8s.io/v1beta1/Ingress` — gone

### v1.25 (removed)

**PodSecurityPolicy** — gone. Replaced by Pod Security Standards (PSS).

```yaml
# old (removed in 1.25)
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: restricted
spec:
  privileged: false
  # ...

# new: enforce via namespace label
apiVersion: v1
kind: Namespace
metadata:
  name: my-app
  labels:
    pod-security.kubernetes.io/enforce: restricted
```

**Migration:** see [[Kubernetes/guides/non-functional/security-baseline|security-baseline]] for the PSS migration path.

### v1.26 (removed)

**v1beta1 flowcontrol** — gone. Use `flowcontrol.apiserver.k8s.io/v1`.

### v1.27 (removed)

**v1beta1 storage** (StorageVersionMigration) — gone.

### v1.29 (removed)

**v1beta1 poddisruptionbudget** — gone. Use `policy/v1`.

```yaml
# old
apiVersion: policy/v1beta1
kind: PodDisruptionBudget
# new
apiVersion: policy/v1
kind: PodDisruptionBudget
```

### v1.30 (deprecated, removal expected in 1.32-1.33)

**flowcontrol v1beta3** — deprecated. Use `flowcontrol.apiserver.k8s.io/v1`.

**PodDisruptionBudget v1beta1** is already gone (in 1.27).

## Currently deprecated APIs (still work, removal coming)

As of v1.30, these are deprecated and will be removed:

| API | Status | Replacement | Removal expected |
|-----|--------|-------------|------------------|
| `flowcontrol.apiserver.k8s.io/v1beta3` FlowSchema | Deprecated | `flowcontrol.apiserver.k8s.io/v1` | 1.32-1.33 |
| `flowcontrol.apiserver.k8s.io/v1beta3` PriorityLevelConfiguration | Deprecated | `flowcontrol.apiserver.k8s.io/v1` | 1.32-1.33 |
| `admissionregistration/v1beta1` ValidatingAdmissionPolicy | Deprecated (in 1.30) | `admissionregistration/v1` | 1.34-1.35 |
| `admissionregistration/v1beta1` ValidatingAdmissionPolicyBinding | Deprecated | `admissionregistration/v1` | 1.34-1.35 |

**Always check the [deprecation guide](https://kubernetes.io/docs/reference/using-api/deprecation-guide/) for the latest.**

## Feature gates and removals

Some features go through a feature gate, then to GA, then sometimes removed. Watch for:

- **In-tree cloud providers** — removed in 1.31. Use out-of-tree (cloud-controller-manager).
- **Dockershim** — removed in 1.24. Use containerd/CRI-O.
- **PodSecurityPolicy** — removed in 1.25.
- **Legacy service account token secrets** — deprecated, removal coming.
- **`secret` + 3-way merge patches** — moved to strategic merge.
- **Default behavior of `kubectl run --port`** — changed.
- **`Kubectl --short` flag** — removed.
- **`--token` flag for many commands** — removed in favor of `--user`.

## Manifest migration tooling

**`kubectl convert`** (built-in):

```bash
# convert an old manifest to a new one
kubectl convert -f old-ingress.yaml --output-version networking.k8s.io/v1
```

**`kubectl apply` warning:**

```bash
kubectl apply -f old-manifest.yaml
# Warning: networking.k8s.io/v1beta1 Ingress is deprecated in v1.19+, unavailable in v1.22
# the apiserver will tell you
```

**Search-and-replace for simple cases:**

```bash
# replace v1beta1 with v1 (be careful, may need spec changes)
sed -i 's|policy/v1beta1|policy/v1|g' manifests/*.yaml
```

**Note:** not all v1beta1 → v1 migrations are spec-compatible. Some need spec changes (e.g., Ingress v1 requires `pathType`).

## The migration patterns

### PSP → PSS

PSP is removed. PSS is the replacement.

```bash
# find all PSPs
kubectl get psp

# for each PSP, find which policies map to PSS levels
# privileged PSP → PSS privileged
# restricted PSP → PSS restricted
# etc.

# remove PSP
kubectl delete psp <name>
kubectl delete clusterrole <psp-binding>
kubectl delete clusterrolebinding <psp-binding>

# enable PSS
kubectl label namespace my-app pod-security.kubernetes.io/enforce=restricted
```

### Ingress v1beta1 → v1

```yaml
# before
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: app
spec:
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        backend:
          serviceName: web   # v1beta1 syntax
          servicePort: 80     # v1beta1 syntax

# after
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
spec:
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix    # required in v1
        backend:
          service:
            name: web        # v1 syntax
            port:
              number: 80     # v1 syntax
```

### CRD v1beta1 → v1

```yaml
# before
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: widgets.example.com
spec:
  scope: Namespaced
  validation:
    openAPIV3Schema:
      # ...
  version: v1
  versions:
  - name: v1
    served: true
    storage: true

# after
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: widgets.example.com
spec:
  scope: Namespaced
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:    # moved under versions[].schema
        # ...
```

**Subtle differences** — the schema moves, some fields are renamed.

## The "what's my exposure?" question

```bash
# 1. run kubent
kubent

# 2. check the apiserver's audit log for warnings
kubectl get --raw /api/v1/namespaces 2>&1 | head

# 3. check your GitOps repo for old apiVersions
grep -rh "apiVersion:" manifests/ | sort -u
```

Common findings:
- `extensions/v1beta1` (entire API group gone in 1.16)
- `apps/v1beta1` (gone long ago)
- `policy/v1beta1` (PSP gone in 1.25, PDB gone in 1.27)
- `networking.k8s.io/v1beta1` (gone in 1.22)
- `rbac.authorization.k8s.io/v1beta1` (gone)
- `apiextensions.k8s.io/v1beta1` (gone in 1.22)
- `admissionregistration.k8s.io/v1beta1` (gone)

## Pre-upgrade deprecation check

Before upgrading:

```bash
# 1. install kubent
curl -sSL https://raw.githubusercontent.com/kubernetes-sigs/kube-no-trouble/main/install.sh | sudo bash

# 2. run
kubent

# 3. for each deprecated API, plan a migration
# 4. fix in GitOps repo
# 5. test in staging
# 6. upgrade
```

**Run this every 3 months** as part of your upgrade cycle. Don't wait for the upgrade to fail.

## Common migration gotchas

* **`kubectl convert` doesn't always work.** Some APIs changed spec significantly. Read the docs.
* **Helm charts may pin old API versions.** Update the chart, not just your overrides.
* **Operators / CRDs** lag behind k8s API changes. Check operator compatibility.
* **Some deprecated APIs have multiple replacements.** Ingress v1beta1 → v1 with different spec fields. Read the migration guide.
* **Beta APIs are removed faster.** `v1beta1` APIs can be removed in the next release.
* **Custom controllers using client-go** need to be updated to use the new API versions.
* **Third-party tools** may still use deprecated APIs. Pin k8s to a version that supports them, or replace the tools.
* **The apiserver's behavior is per-version.** A deprecated API in 1.28 may still be present in 1.29, then gone in 1.30. Track the deprecation timeline.

## The deprecation timeline (where to look)

Official sources:

- [Kubernetes Deprecation Guide](https://kubernetes.io/docs/reference/using-api/deprecation-guide/) — the authoritative list
- [Kubernetes Release Notes](https://kubernetes.io/releases/) — per-version changes
- [Kubernetes Blog](https://kubernetes.io/blog/) — announcement of major deprecations
- [SIG Architecture meeting notes](https://github.com/kubernetes/community/tree/master/sig-architecture) — discussions

## Long-running patterns

### When you have time

If you upgrade every release, you have time to migrate APIs as they're deprecated. This is the recommended approach.

### When you're behind

If you're 2+ minor versions behind, you have less time. Plan a bigger upgrade with more migration work.

### When you're stuck

If you can't upgrade (legacy code, vendor lock-in), you're on borrowed time. The APIs you depend on will eventually be removed.

**For stuck clusters:** some clouds offer "extended support" (EKS Extended Support, GKE Extended) for older versions. This costs extra but buys time.

## A worked example

**Cluster:** On 1.26. Want to upgrade to 1.30. Time: 1 quarter.

**Step 1: run kubent**

```bash
kubent

# output:
# 1.30 will remove the following deprecated APIs:
# ─────────────────────────────────────────────
# PodDisruptionBudget v1beta1 will be removed in v1.27
#   ├─ team-a/web-pdb
#   └─ team-b/api-pdb
#
# ValidatingAdmissionPolicy v1beta1 will be removed in v1.34
#   └─ cluster/cluster-baseline
```

**Step 2: fix the PDBs**

```bash
# for each PDB, change apiVersion
for f in $(grep -l "policy/v1beta1" manifests/); do
  sed -i 's|policy/v1beta1|policy/v1|g' $f
done

# verify
grep -r "apiVersion: policy/v1beta1" manifests/
# should be empty
```

**Step 3: plan the ValidatingAdmissionPolicy migration**

The cluster-baseline policy is in v1beta1. The replacement (v1) is available in 1.30 but `v1beta1` is also still present (deprecated). Defer to next quarter.

**Step 4: staged upgrade**

```
1.26 → 1.27:  Verify all workloads on 1.27
1.27 → 1.28:  Verify add-ons on 1.28
1.28 → 1.29:  Verify deprecated APIs don't bite
1.29 → 1.30:  Verify ValidatingAdmissionPolicy v1 (deferred)
```

**Each upgrade step:** one week. Total: 1 quarter.

**Lessons learned:** PSP removal (1.25) caught us off-guard last time. Now we have a quarterly `kubent` in our upgrade checklist.

## The full deprecation timeline (recent + upcoming)

### v1.16 (deprecated, removed in v1.22)

- **All `extensions/v1beta1` API group** — gone. Use `apps/v1`, `networking.k8s.io/v1`, etc.

### v1.18 (removed in v1.25)

- **PodSecurityPolicy (`policy/v1beta1`)** — gone. Use PSS.

### v1.22 (removed)

- `extensions/v1beta1/Ingress` → `networking.k8s.io/v1`
- `apps/v1beta1/Deployment` → `apps/v1`
- `apps/v1beta1/StatefulSet` → `apps/v1`
- `apps/v1beta1/ReplicationController` → `apps/v1`
- `apiextensions.k8s.io/v1beta1/CustomResourceDefinition` → `apiextensions.k8s.io/v1`
- `admissionregistration.k8s.io/v1beta1/MutatingWebhookConfiguration` → `admissionregistration.k8s.io/v1`
- `admissionregistration.k8s.io/v1beta1/ValidatingWebhookConfiguration` → `admissionregistration.k8s.io/v1`
- `rbac.authorization.k8s.io/v1beta1/Role` → `rbac.authorization.k8s.io/v1`
- `rbac.authorization.k8s.io/v1beta1/RoleBinding` → `rbac.authorization.k8s.io/v1`
- `rbac.authorization.k8s.io/v1beta1/ClusterRole` → `rbac.authorization.k8s.io/v1`
- `rbac.authorization.k8s.io/v1beta1/ClusterRoleBinding` → `rbac.authorization.k8s.io/v1`
- `certificates.k8s.io/v1beta1/CertificateSigningRequest` → `certificates.k8s.io/v1`
- `networking.k8s.io/v1beta1/Ingress` → `networking.k8s.io/v1`
- `storage.k8s.io/v1beta1/VolumeAttachment` → `storage.k8s.io/v1`

### v1.25 (removed)

- `policy/v1beta1/PodSecurityPolicy` → use PSS

### v1.26 (removed)

- `flowcontrol.apiserver.k8s.io/v1beta1/FlowSchema` → `flowcontrol.apiserver.k8s.io/v1`
- `flowcontrol.apiserver.k8s.io/v1beta1/PriorityLevelConfiguration` → `flowcontrol.apiserver.k8s.io/v1`

### v1.27 (removed)

- `policy/v1beta1/PodDisruptionBudget` → `policy/v1`
- `storage.k8s.io/v1beta1/CSIStorageCapacity` → `storage.k8s.io/v1`

### v1.29 (removed)

- `flowcontrol.apiserver.k8s.io/v1beta2/FlowSchema` → `flowcontrol.apiserver.k8s.io/v1`
- `flowcontrol.apiserver.k8s.io/v1beta2/PriorityLevelConfiguration` → `flowcontrol.apiserver.k8s.io/v1`

### v1.30 (deprecated, removal expected v1.32-1.33)

- `flowcontrol.apiserver.k8s.io/v1beta3/FlowSchema` → `flowcontrol.apiserver.k8s.io/v1`
- `flowcontrol.apiserver.k8s.io/v1beta3/PriorityLevelConfiguration` → `flowcontrol.apiserver.k8s.io/v1`

### v1.30 (deprecated, removal expected v1.34-1.35)

- `admissionregistration.k8s.io/v1beta1/ValidatingAdmissionPolicy` → `admissionregistration.k8s.io/v1`
- `admissionregistration.k8s.io/v1beta1/ValidatingAdmissionPolicyBinding` → `admissionregistration.k8s.io/v1`

## Feature gates and removals (not API deprecations)

These are config-level changes that affect upgrade behavior.

### Dockershim (removed in 1.24)

The in-tree Docker shim was removed. You must use a CRI-compatible runtime:

- **containerd** — most common, recommended
- **CRI-O** — Red Hat's, used in OpenShift
- **Mirantis Container Runtime** — for users needing Docker daemon compat

```bash
# verify your runtime
kubectl get nodes -o wide
# check for "Container Runtime Version: containerd://xxx"
```

### In-tree cloud providers (deprecated, removed in 1.31)

The cloud-specific controllers (`--cloud-provider=aws|gcp|azure`) were moved to out-of-tree:

- **AWS Cloud Controller Manager** — `kube-aws/k8s-cloud-provider-aws`
- **GCP CCM** — `kubernetes/cloud-provider-gcp`
- **Azure CCM** — `kubernetes-sigs/cloud-provider-azure`

**Required for k8s 1.31+.** If you're on in-tree, migrate to out-of-tree.

### Legacy service account tokens (deprecated)

```yaml
# old
apiVersion: v1
kind: Secret
type: kubernetes.io/service-account-token
# auto-created, long-lived
```

```yaml
# new
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-sa
# projected token, time-limited, audience-bound
```

**Projected tokens are the default in 1.21+.** Old auto-mounted tokens are deprecated.

### In-tree volume plugins (deprecated)

In-tree plugins (vSphere, AWS EBS, GCE PD, etc.) are being moved to CSI:

- **AWS EBS** — `ebs.csi.aws.com` (GA)
- **GCE PD** — `pd.csi.storage.gke.io` (GA)
- **vSphere** — `csi.vsphere.vmware.com` (GA)
- **Azure Disk** — `disk.csi.azure.com` (GA)
- **Azure File** — `file.csi.azure.com` (GA)
- **NFS** — `nfs.csi.k8s.io` (GA)

**Migrate to CSI drivers** before they become mandatory.

### kubectl deprecations

- `kubectl run --port` — behavior changed (port in spec, not flag)
- `--short` flag — removed
- `--token` flag — removed (use `--user` for kubeconfig contexts)
- `kubectl get componentstatuses` — removed
- `kubectl proxy --port` deprecated in favor of `--port=`

## The "I'm stuck on an old version" trap

If you're on 1.24 (or earlier), here's what you might have:

### PSP that you need to migrate

```bash
# find all PSPs
kubectl get psp
# you have PSPs → migrate to PSS

# for each PSP, classify
# - privileged → PSS privileged
# - default (limited) → PSS baseline
# - restrictive → PSS restricted
```

### Dockershim that you need to migrate

```bash
# check runtime
kubectl get nodes -o jsonpath='{.items[*].status.nodeInfo.containerRuntimeVersion}'
# if "docker://xxx" → migrate to containerd
```

### v1beta1 APIs

```bash
# run kubent
kubent
# fix all findings
```

## The "extended support" path

For clusters that can't upgrade immediately:

| Cloud | Extended support | Cost |
|-------|-----------------|------|
| **EKS** | K8s 1.23-1.28 (EKS Extended Support) | 0.10 USD/cluster/hour per supported version |
| **GKE** | K8s 1.26+ (GKE Extended) | 0.0008 USD/vCPU/hour per supported version |
| **AKS** | K8s 1.27+ (AKS Extended Support) | Free during preview, will charge |

**Use extended support as a bridge, not a destination.** Plan your upgrade.

## The "vendor lock-in" deprecations

Some deprecations only affect specific deployments:

### AWS-specific

- **In-tree AWS provider** (deprecated, removed in 1.31) — use AWS Cloud Provider
- **AWS EBS in-tree plugin** — use EBS CSI driver
- **EKS optimized AMI** — change per k8s version, custom AMIs need updates
- **Pod Security Policy** (gone in 1.25) — affects old EKS clusters
- **EKS-D** (deprecated EKS distro) — use EKS

### GCP-specific

- **GKE Dataplane V1** (deprecated) — use V2 (eBPF)
- **In-tree GCP provider** — use GCP Cloud Provider
- **GCE PD in-tree** — use PD CSI driver

### Azure-specific

- **AKS engine** (deprecated) — use AKS
- **In-tree Azure provider** — use Azure Cloud Provider
- **Azure Disk in-tree** — use Disk CSI driver
- **Azure File in-tree** — use File CSI driver

## Tools beyond kubent

### `kubectl-convert`

```bash
# convert a v1beta1 to v1
kubectl convert -f old-ingress.yaml \
  --output-version networking.k8s.io/v1
```

**Note:** doesn't work for all migrations. Some need spec changes.

### `pluto` (Fairwinds)

```bash
# install
brew install pluto

# detect deprecated APIs
pluto detect-all-in-cluster

# detect in a Helm chart
pluto detect-files -d charts/
```

### `kubernetes-deprecation-guide` (kubectl plugin)

```bash
kubectl krew install deprecations
kubectl deprecations
```

### `kubernetes-nfv`

```bash
# comprehensive check of API usage
# https://github.com/kubernetes-sigs/api-federation
```

## The migration cookbook

### PSP → PSS

**Step 1: audit your PSPs**

```bash
kubectl get psp -o yaml > psps.yaml
# review each PSP
# classify: privileged / baseline / restricted
```

**Step 2: enable PSS in audit mode**

```bash
# for each namespace
kubectl label namespace my-app \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/audit-version=latest
# audit mode logs violations but doesn't block
```

**Step 3: fix violations**

```bash
# check audit logs
kubectl get events -A --field-selector reason=FailedCreate
# fix each violation
```

**Step 4: enforce PSS**

```bash
kubectl label namespace my-app \
  pod-security.kubernetes.io/enforce=restricted \
  --overwrite
```

**Step 5: remove PSPs**

```bash
kubectl delete psp <name>
kubectl delete clusterrole <psp-binding>
kubectl delete clusterrolebinding <psp-binding>
```

### Ingress v1beta1 → v1

```bash
# automatic conversion
kubectl convert -f old-ingress.yaml > new-ingress.yaml

# verify
diff old-ingress.yaml new-ingress.yaml
```

**Manual fix-up:**

```yaml
# before
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: app
spec:
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /api
        backend:
          serviceName: api
          servicePort: 80

# after
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
spec:
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /api
        pathType: Prefix    # new in v1
        backend:
          service:
            name: api      # moved
            port:
              number: 80   # moved
```

**Key changes:**
- `pathType` is required (`Exact`, `Prefix`, or `ImplementationSpecific`)
- `backend.serviceName` and `servicePort` are now `backend.service.name` and `backend.service.port.number`

### CRD v1beta1 → v1

```yaml
# before
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: widgets.example.com
spec:
  scope: Namespaced
  validation:
    openAPIV3Schema:    # at top level
      type: object
      properties:
        spec:
          type: object
  versions:
  - name: v1
    served: true
    storage: true

# after
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: widgets.example.com
spec:
  scope: Namespaced
  versions:
  - name: v1
    served: true
    storage: true
    schema:                # moved under versions
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
```

**Key changes:**
- `validation` → `schema` (under each version)
- `subresources` moved to per-version
- `additionalPrinterColumns` is per-version

### PodDisruptionBudget v1beta1 → v1

```yaml
# before
apiVersion: policy/v1beta1
kind: PodDisruptionBudget
# ...

# after
apiVersion: policy/v1
kind: PodDisruptionBudget
# same spec
```

**Just a version bump.** PDB spec didn't change.

## See also

* [[Kubernetes/guides/non-functional/upgrade-strategy|upgrade-strategy]] — the upgrade process
* [[Kubernetes/guides/non-functional/security-baseline|security-baseline]] — PSP migration
* [k8s deprecation guide](https://kubernetes.io/docs/reference/using-api/deprecation-guide/)
* [kubent](https://github.com/kubernetes-sigs/kube-no-trouble)
