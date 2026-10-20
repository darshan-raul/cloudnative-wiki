---
title: "Procedure: Roll Back a Bad Deployment"
description: "Stop and reverse a bad release quickly with kubectl, Helm, Argo CD or Flux, without the reconciler undoing the rollback, and check that data changes allow it."
tags:
  [
    kubernetes/eks/operator-runbook,
    eks,
    procedure,
    deployments,
    rollback,
    incident,
  ]
date: 2026-10-20
aliases: [Kubernetes rollback procedure, rollout undo]
---

# Procedure: Roll Back a Bad Deployment

**Applies to:** Deployments (and, with the same tools, StatefulSets and DaemonSets) released by `kubectl`, Helm, Argo CD or Flux.
**Duration:** minutes.
**Risk:** low for stateless releases. Higher when the release ran a database migration or changed a data format.
**Tested:** not run on a live cluster; commands checked for syntax.

## When to use

Errors, latency or crashes started with a release. Rolling back first and investigating second is usually the fastest mitigation, even before the root cause is known.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export NS=<namespace> DEPLOY=<deployment>
```

## Pre-checks

**1. Does the timing match?**

```bash
kubectl rollout history deploy/"$DEPLOY" -n "$NS"
kubectl get rs -n "$NS" -l app=<label> --sort-by=.metadata.creationTimestamp \
  -o custom-columns=NAME:.metadata.name,CREATED:.metadata.creationTimestamp,DESIRED:.spec.replicas,READY:.status.readyReplicas,IMAGE:.spec.template.spec.containers[0].image
```

Compare the newest ReplicaSet's creation time with the start of the incident.

**2. Who released it?** That decides how to roll back. If you `kubectl rollout undo` an object that Argo CD or Flux owns, the reconciler puts the bad version back.

```bash
kubectl get deploy "$DEPLOY" -n "$NS" -o jsonpath='{.metadata.labels}{"\n"}{.metadata.annotations}{"\n"}' | tr ',' '\n' \
  | grep -E 'argocd|fluxcd|helm|managed-by'
```

**3. Is going back safe for data?** Ask the owner, or check the release notes: did the release run a schema migration, or start writing a new data format? If the old version can't read what the new one wrote, rolling back the code can corrupt or fail. Then fix forward, or roll back the data change first.

## Steps

**If the rollout is still in progress**, stop it first so no more Pods move to the bad version:

```bash
kubectl rollout pause deploy/"$DEPLOY" -n "$NS"
```

Then roll back with the tool that owns the release:

**kubectl-managed:**

```bash
kubectl rollout history deploy/"$DEPLOY" -n "$NS" --revision=<good revision>    # check its image
kubectl rollout undo deploy/"$DEPLOY" -n "$NS" --to-revision=<good revision>
kubectl rollout resume deploy/"$DEPLOY" -n "$NS" 2>/dev/null; true                # if you paused it
kubectl rollout status deploy/"$DEPLOY" -n "$NS" --timeout=5m
```

**Helm:**

```bash
helm history <release> -n "$NS"
helm rollback <release> <good revision> -n "$NS" --wait --timeout 5m
```

**Argo CD:** the fastest durable route is to revert the commit in Git and sync. `argocd app rollback <app> <history-id>` works only with automated sync turned off. Turn it off first (`argocd app set <app> --sync-policy none`), and turn it back on after Git has the revert.

**Flux:** revert the commit in Git, then `flux reconcile kustomization <name> --with-source` (or `flux reconcile helmrelease <name> -n <ns> --with-source`). To hold the old version while Git catches up, `flux suspend` the object first.

- **Checkpoint:** `kubectl rollout status` reports success, all Pods run the good image, and error rates drop.

## Abort criteria

If errors don't drop after the rollback, the release wasn't the cause (or not the only one). Keep the rollback in place, and go back to [[Kubernetes/eks/operator-runbook/reference/first-five-minutes|first five minutes]] to look for another change.

## Post-checks

```bash
kubectl get pods -n "$NS" -l app=<label> -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image,READY:.status.containerStatuses[0].ready
```

Every Pod runs the good image, and no Pods from the bad ReplicaSet remain.

## Clean-up

- Make Git (or the CI pipeline) match the rolled-back state, so the next deploy doesn't reintroduce the bad version.
- Resume any reconciler you paused.
- Keep the bad image tag for the investigation; don't delete it from the registry.

## Make rollbacks safe in advance

These Deployment settings make bad releases stop early and roll back cleanly:

```yaml
spec:
  revisionHistoryLimit: 5 # old ReplicaSets to roll back to
  minReadySeconds: 10 # a new Pod must stay Ready this long to count
  progressDeadlineSeconds: 600 # mark the rollout failed if it stalls
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0 # never drop below full capacity
  template:
    spec:
      containers:
        - name: app
          startupProbe: # slow starts don't trip liveness
            httpGet: { path: /startupz, port: http }
            periodSeconds: 5
            failureThreshold: 24
          readinessProbe: # traffic only to Pods that can serve
            httpGet: { path: /readyz, port: http }
            periodSeconds: 5
```

With `maxUnavailable: 0` and a real readiness probe, a release whose Pods never become Ready stalls without taking capacity away. For progressive delivery with automatic rollback on metrics, see Argo Rollouts or Flagger.

## Background

- [[Kubernetes/concepts/L03-workloads/03-deployments|Deployments]]
- [[Kubernetes/eks/operator-runbook/runbooks/gitops-drift-and-reverted-fixes|GitOps drift and reverted fixes]]
- [[Kubernetes/eks/operator-runbook/runbooks/post-upgrade-regression|Regression after an upgrade]] (for platform changes)
