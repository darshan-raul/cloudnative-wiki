---
title: Amazon EKS Operator Handbook
description: "Runbooks, procedures and reference for operating Amazon EKS: symptom-first incident response, planned changes with rollback, and the limits and commands operators need."
tags:
  [kubernetes/eks/operator-runbook, platform-engineering/kubernetes, aws, eks]
date: 2026-10-20
aliases: [EKS Operator Handbook, Amazon EKS Operator Handbook, EKS Runbook]
---

# Amazon EKS Operator Handbook

What to do when something on an EKS cluster breaks, and how to make planned changes without breaking it. Every page is built to be used under pressure: real error strings, commands with the output to expect, a diagnosis table, and a fix with its verification and undo.

- **Paged and not sure where to start?** Run [[Kubernetes/eks/operator-runbook/reference/first-five-minutes|First five minutes]]. It ends with a pointer into the tables below.
- **Know the symptom?** Find it in [[#Runbooks|Runbooks]].
- **Planning a change?** Use [[#Procedures|Procedures]].

Every page uses the variables and safety checks in [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]], and assumes the wiki's Kubernetes baseline (1.37).

**Test status:** none of these pages has been run end to end on a live cluster yet. Commands are checked for syntax, and facts are written from AWS and Kubernetes documentation. The "Tested" column changes when a page is exercised for real. Rehearse a procedure in a non-production cluster before relying on it.

## Runbooks

One failure per page, named after what you see.

### Networking and traffic

| Symptom                                                                       | Runbook                                                                                                 | Tested               |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | -------------------- |
| Pods stuck `ContainerCreating`: `failed to assign an IP address to container` | [[Kubernetes/eks/operator-runbook/runbooks/pods-stuck-containercreating-ip-exhaustion\|IP exhaustion]]  | Not run; syntax only |
| DNS `i/o timeout`, `EAI_AGAIN`, 5-second latency spikes                       | [[Kubernetes/eks/operator-runbook/runbooks/dns-timeouts-coredns\|DNS timeouts]]                         | Not run; syntax only |
| ALB or NLB returning 502, 503 or 504                                          | [[Kubernetes/eks/operator-runbook/runbooks/load-balancer-5xx-errors\|Load balancer 5xx]]                | Not run; syntax only |
| Deploys fail with `failed calling webhook`                                    | [[Kubernetes/eks/operator-runbook/runbooks/webhook-blocking-deployments\|Webhook blocking deployments]] | Not run; syntax only |

### Nodes and capacity

| Symptom                                                        | Runbook                                                                                                     | Tested               |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | -------------------- |
| Node `NotReady` or `Unknown`                                   | [[Kubernetes/eks/operator-runbook/runbooks/node-not-ready\|Node NotReady]]                                  | Not run; syntax only |
| Pods `Pending`, Karpenter launches nothing or nodes never join | [[Kubernetes/eks/operator-runbook/runbooks/karpenter-not-launching-nodes\|Karpenter not launching nodes]]   | Not run; syntax only |
| Pods `Pending`, `NotTriggerScaleUp` from Cluster Autoscaler    | [[Kubernetes/eks/operator-runbook/runbooks/cluster-autoscaler-not-scaling\|Cluster Autoscaler not scaling]] | Not run; syntax only |
| Many Spot nodes reclaimed at once                              | [[Kubernetes/eks/operator-runbook/runbooks/spot-interruption-storm\|Spot interruption storm]]               | Not run; syntax only |
| `DiskPressure`, ephemeral-storage evictions, `ImageGCFailed`   | [[Kubernetes/eks/operator-runbook/runbooks/disk-pressure-and-image-gc\|Disk pressure]]                      | Not run; syntax only |

### Workloads

| Symptom                                        | Runbook                                                                                                   | Tested               |
| ---------------------------------------------- | --------------------------------------------------------------------------------------------------------- | -------------------- |
| `ErrImagePull` or `ImagePullBackOff`           | [[Kubernetes/eks/operator-runbook/runbooks/imagepullbackoff-ecr\|ImagePullBackOff]]                       | Not run; syntax only |
| `OOMKilled`, memory evictions, `SystemOOM`     | [[Kubernetes/eks/operator-runbook/runbooks/oomkilled-and-memory-pressure\|OOMKilled and memory pressure]] | Not run; syntax only |
| HPA shows `<unknown>`, doesn't scale, or flaps | [[Kubernetes/eks/operator-runbook/runbooks/hpa-not-scaling\|HPA not scaling]]                             | Not run; syntax only |

### Storage

| Symptom                                                                       | Runbook                                                                                             | Tested               |
| ----------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- | -------------------- |
| EBS `Multi-Attach error`, `FailedAttachVolume`, volume node affinity conflict | [[Kubernetes/eks/operator-runbook/runbooks/ebs-volume-stuck-attaching\|EBS volume stuck attaching]] | Not run; syntax only |
| EFS `FailedMount`: timeouts, DNS, access denied                               | [[Kubernetes/eks/operator-runbook/runbooks/efs-mount-failures\|EFS mount failures]]                 | Not run; syntax only |

### Access, identity and secrets

| Symptom                                                     | Runbook                                                                                                           | Tested               |
| ----------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | -------------------- |
| kubectl `Unauthorized` or `Forbidden`, or cluster lockout   | [[Kubernetes/eks/operator-runbook/runbooks/kubectl-unauthorized-or-forbidden\|kubectl Unauthorized or Forbidden]] | Not run; syntax only |
| Pod gets AWS `AccessDenied` (Pod Identity or IRSA)          | [[Kubernetes/eks/operator-runbook/runbooks/workload-aws-access-denied\|Workload AWS AccessDenied]]                | Not run; syntax only |
| Rotated secret doesn't reach the Pod; `SecretSyncedError`   | [[Kubernetes/eks/operator-runbook/runbooks/secrets-not-syncing\|Secrets not syncing]]                             | Not run; syntax only |
| Certificate expiring or expired; cert-manager `READY False` | [[Kubernetes/eks/operator-runbook/runbooks/certificates-not-renewing\|Certificates not renewing]]                 | Not run; syntax only |

### Control plane and platform changes

| Symptom                                         | Runbook                                                                                                    | Tested               |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------- | -------------------- |
| API `429 TooManyRequests` or slow responses     | [[Kubernetes/eks/operator-runbook/runbooks/api-server-throttling-and-latency\|API throttling and latency]] | Not run; syntax only |
| Something broke after an upgrade                | [[Kubernetes/eks/operator-runbook/runbooks/post-upgrade-regression\|Regression after an upgrade]]          | Not run; syntax only |
| Live fix keeps reverting; app stuck `OutOfSync` | [[Kubernetes/eks/operator-runbook/runbooks/gitops-drift-and-reverted-fixes\|GitOps drift]]                 | Not run; syntax only |

### Specialist compute

| Symptom                                               | Runbook                                                                                            | Tested               |
| ----------------------------------------------------- | -------------------------------------------------------------------------------------------------- | -------------------- |
| `Insufficient nvidia.com/gpu`, CUDA driver errors     | [[Kubernetes/eks/operator-runbook/runbooks/gpu-pods-not-schedulable\|GPU Pods Pending or failing]] | Not run; syntax only |
| Windows Pods don't start; OS version mismatch         | [[Kubernetes/eks/operator-runbook/runbooks/windows-pods-not-starting\|Windows Pods not starting]]  | Not run; syntax only |
| Hybrid node `NotReady`, not joining, Pods unreachable | [[Kubernetes/eks/operator-runbook/runbooks/hybrid-node-disconnected\|Hybrid node disconnected]]    | Not run; syntax only |

## Procedures

Planned changes, each with pre-checks, checkpoints, abort criteria and rollback.

| Task                                                                 | Procedure                                                                                                             | Tested               |
| -------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | -------------------- |
| Reverse a bad release                                                | [[Kubernetes/eks/operator-runbook/procedures/roll-back-a-deployment\|Roll back a deployment]]                         | Not run; syntax only |
| Upgrade the cluster one minor version                                | [[Kubernetes/eks/operator-runbook/procedures/control-plane-upgrade\|Control-plane upgrade]]                           | Not run; syntax only |
| Upgrade `vpc-cni`, `coredns`, `kube-proxy` or another managed add-on | [[Kubernetes/eks/operator-runbook/procedures/add-on-upgrade\|Add-on upgrade]]                                         | Not run; syntax only |
| Roll a managed node group to a new AMI or version                    | [[Kubernetes/eks/operator-runbook/procedures/managed-node-group-ami-rotation\|Managed node group rotation]]           | Not run; syntax only |
| Roll Karpenter nodes to a new AMI                                    | [[Kubernetes/eks/operator-runbook/procedures/karpenter-node-rotation\|Karpenter node rotation]]                       | Not run; syntax only |
| Move from `aws-auth` to access entries                               | [[Kubernetes/eks/operator-runbook/procedures/migrate-aws-auth-to-access-entries\|Migrate aws-auth to access entries]] | Not run; syntax only |
| Prepare and test emergency admin access                              | [[Kubernetes/eks/operator-runbook/procedures/break-glass-access-setup\|Break-glass access setup]]                     | Not run; syntax only |
| Rotate the cluster KMS key or an application secret                  | [[Kubernetes/eks/operator-runbook/procedures/rotate-kms-keys-and-secrets\|Rotate KMS keys and secrets]]               | Not run; syntax only |
| Move traffic and capacity out of an impaired AZ                      | [[Kubernetes/eks/operator-runbook/procedures/zonal-shift\|Zonal shift]]                                               | Not run; syntax only |
| Restore a namespace and its volumes                                  | [[Kubernetes/eks/operator-runbook/procedures/restore-namespace-from-backup\|Restore from Velero backup]]              | Not run; syntax only |
| Retire a cluster without leaving resources behind                    | [[Kubernetes/eks/operator-runbook/procedures/decommission-cluster\|Decommission a cluster]]                           | Not run; syntax only |

## Reference

- [[Kubernetes/eks/operator-runbook/reference/first-five-minutes|First five minutes of an incident]]: start here when you don't know which runbook applies.
- [[Kubernetes/eks/operator-runbook/reference/command-conventions|Command conventions and safety checks]]: variables used on every page.
- [[Kubernetes/eks/operator-runbook/reference/limits-and-formulas|Limits, defaults and formulas]]: max pods, address planning, timeouts, skew, quotas.
- [[Kubernetes/eks/operator-runbook/reference/node-access-and-logs|Node access and log locations]]
- [[Kubernetes/eks/operator-runbook/reference/control-plane-logs-and-metrics|Control-plane logs and metrics]]: audit queries and API server metrics.

## Concepts

The handbook doesn't re-teach how EKS works; each page links to the background it needs. For a broader grounding:

- [[Kubernetes/eks/README|EKS overview]], [[Kubernetes/eks/networking/README|networking]], [[Kubernetes/eks/compute/README|compute]], [[Kubernetes/eks/storage/README|storage]], [[Kubernetes/eks/security/README|security]], [[Kubernetes/eks/observability/README|observability]], [[Kubernetes/eks/automation/README|automation]] and [[Kubernetes/eks/cluster-upgrades/README|upgrades]]
- [[Kubernetes/eks/advanced/cost-optimization|Cost optimization]] and [[Kubernetes/guides/non-functional/multi-tenancy|multi-tenancy]] for cluster design decisions
- [[Kubernetes/concepts/00-hub|Kubernetes concepts curriculum]], especially [[Kubernetes/concepts/L08-operations/00-README|operations]]

## Maintaining the handbook

The editorial rules and templates are in `planning/eks-operator-runbook-spec.md`. When the wiki's Kubernetes baseline moves, re-check [[Kubernetes/eks/operator-runbook/reference/limits-and-formulas|limits and formulas]] and the upgrade procedures first.
