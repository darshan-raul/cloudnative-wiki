---
title: "Runbook: GitOps Drift and Live Fixes That Keep Reverting"
description: "An Argo CD or Flux application is stuck OutOfSync, a live hotfix keeps getting undone, or two tools fight over the same object. Find who owns each field, make emergency changes safely, and stop the fight."
tags:
  [
    kubernetes/eks/operator-runbook,
    eks,
    runbook,
    gitops,
    argocd,
    flux,
    incident,
  ]
date: 2026-10-20
aliases:
  [
    Argo CD reverts my change,
    GitOps drift runbook,
    Flux overwrites kubectl edit,
  ]
---

# Runbook: GitOps Drift and Live Fixes That Keep Reverting

**Applies to:** Argo CD and Flux managing workloads or platform components, alongside other writers: HPA, VPA, admission webhooks, Helm, Terraform, EKS add-ons.
**Typical severity:** Sev 2 when it blocks an incident fix; Sev 3 for a permanent OutOfSync.
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

- You `kubectl edit` or `patch` something during an incident, and minutes later it's back.
- An application shows `OutOfSync` forever, even right after a sync.
- An object's `resourceVersion` changes every few seconds, and replicas or annotations flip back and forth.

## Impact

Reconcilers are working as designed: Git is the source of truth. The risk is during incidents, when a needed live change disappears, or when two controllers fight and cause rolling restarts.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export NS=<namespace> KIND=<kind> NAME=<object name>
```

## Triage

**1. Who owns the object?**

```bash
kubectl get "$KIND" "$NAME" -n "$NS" -o jsonpath='{.metadata.labels}{"\n"}{.metadata.annotations}{"\n"}' | tr ',' '\n' \
  | grep -E 'argocd.argoproj.io|kustomize.toolkit.fluxcd.io|helm.toolkit.fluxcd.io|app.kubernetes.io/managed-by|meta.helm.sh|eks.amazonaws.com'
```

| Marker                                                                             | Owner                                                                                                  |
| ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `argocd.argoproj.io/tracking-id` annotation, or `app.kubernetes.io/instance` label | Argo CD application                                                                                    |
| `kustomize.toolkit.fluxcd.io/name` / `helm.toolkit.fluxcd.io/name` labels          | Flux Kustomization or HelmRelease                                                                      |
| `app.kubernetes.io/managed-by: Helm` with no GitOps markers                        | Plain Helm (CI or a person)                                                                            |
| `app.kubernetes.io/managed-by: eks` or EKS add-on labels                           | EKS managed add-on (see [[Kubernetes/eks/operator-runbook/procedures/add-on-upgrade\|Add-on upgrade]]) |

**2. Which manager owns which field?**

```bash
kubectl get "$KIND" "$NAME" -n "$NS" --show-managed-fields -o json \
  | jq -r '.metadata.managedFields[] | "\(.manager)\t\(.operation)\t\(.time)"'
```

Two or more managers updating the same object often (look at the `time` values) means a fight.

**3. What does the reconciler think is different?**

```bash
argocd app diff <app> --hard-refresh          # Argo CD
argocd app get <app> -o json | jq '.spec.syncPolicy'
flux diff kustomization <name> --path <path>  # Flux, from a checkout of the repo
flux get kustomizations -A; flux get helmreleases -A
```

## Diagnosis

| Signal                                                                               | Cause                                  | Fix   |
| ------------------------------------------------------------------------------------ | -------------------------------------- | ----- |
| You need an emergency change that Git doesn't have yet                               | A. Live fix vs reconciler              | Fix A |
| `spec.replicas` flips between Git's value and the HPA's                              | B. Git sets a field an autoscaler owns | Fix B |
| Permanent OutOfSync on fields added by a webhook, controller or defaulting           | C. Diff noise from mutation            | Fix C |
| Two managers (Argo and Helm, Flux and Terraform, GitOps and an EKS add-on) alternate | D. Two owners for the same object      | Fix D |

## Fix

### A. Emergency change during an incident

**Best:** commit the change to Git, and sync. With an expedited review, that's often just as fast, and nothing has to be reconciled afterwards.

**If you can't wait:** pause the reconciler for **only** the affected application, make the live change, then put the change in Git and resume.

```bash
# Argo CD: turn off automated sync for one app
argocd app set <app> --sync-policy none
# Flux
flux suspend kustomization <name> -n flux-system      # or: flux suspend helmrelease <name> -n <ns>
```

If the application itself is managed by a parent ("app of apps", or an `ApplicationSet`) with self-heal, the parent restores the child's sync policy. Pause the parent as well, or make the change in the parent's Git source.

**Undo (required):** after the change is in Git:

```bash
argocd app set <app> --sync-policy automated --self-heal     # match the app's original policy
flux resume kustomization <name> -n flux-system
```

Record every paused application in the incident log, and check them all at incident close.

### B. Git sets a field an autoscaler owns

Remove `spec.replicas` from the manifest for any Deployment or StatefulSet that has an HPA (or KEDA). If you can't, tell the reconciler to ignore it:

```yaml
# Argo CD Application
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers: ["/spec/replicas"]
  syncPolicy:
    syncOptions: ["RespectIgnoreDifferences=true"]
```

The same applies to resource requests changed by VPA in `Auto` mode.

### C. Diff noise from mutation

Admission webhooks (sidecar injection, defaulting) and controllers add fields that aren't in Git. Use server-side diff in Argo CD, which compares against what the API server would actually store (`argocd.argoproj.io/compare-options: ServerSideDiff=true` on the Application, or set globally). Otherwise, add targeted `ignoreDifferences` with `managedFieldsManagers` for that controller. Flux uses server-side apply and only reverts fields it manages, so extra fields from other managers don't show as drift.

### D. Two owners for the same object

Pick one owner per object. Common fights:

- **Argo CD and Helm in CI** both installing the same chart → remove one of them.
- **GitOps managing a resource the EKS add-on manages** (for example the `aws-node` DaemonSet) → configure it through the add-on's `--configuration-values`, and remove it from Git.
- **Terraform's Kubernetes or Helm provider and GitOps** on the same objects → move them to one tool.

Until it's fixed, suspend the less authoritative writer.

## Verify recovery

- `argocd app get <app>` shows `Synced` and `Healthy`, or `flux get kustomizations` shows `Ready True` with the latest revision.
- `managedFields` show one regular writer per field.
- No paused applications remain: `argocd app list -o json | jq -r '.[] | select(.spec.syncPolicy.automated == null) | .metadata.name'`, and `flux get all -A --status-selector ready=false`.

## Escalate

These are ownership problems in your platform. Escalate to the platform team that owns the GitOps setup, with the managedFields output and the app's diff.

## Prevent

- Document an emergency-change procedure: who can pause sync, how, and the obligation to resume it.
- Alert on applications that stay `OutOfSync` or suspended longer than an hour.
- Never set `replicas` in Git for autoscaled workloads.
- One owner per object, enforced in review.

## Background

- [[Kubernetes/eks/automation/gitops/argocd|Argo CD on EKS]]
- [[Kubernetes/eks/automation/gitops/flux|Flux on EKS]]
- [Argo CD diffing customization](https://argo-cd.readthedocs.io/en/stable/user-guide/diffing/)
