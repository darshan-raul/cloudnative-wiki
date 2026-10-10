---
title: Pod Security Standards on EKS
tags: [eks, security, pod-security, admission]
date: 2026-05-17
description: Applying Kubernetes Pod Security Standards on EKS with Pod Security Admission — rollout strategy, what EKS system components require, exemptions and where the built-in controller stops.
---

# Pod Security Standards on EKS

Pod Security Standards (PSS) define three levels of pod hardening. **Pod Security Admission** (PSA) is the built-in admission controller that enforces them per namespace. Both are standard Kubernetes and enabled on every EKS cluster; there is nothing to install. The definitions are covered in [[Kubernetes/concepts/L07-security/02-workload-sandboxing/06-pod-security-standards|Pod Security Standards (concepts)]] — this page is about rolling them out on EKS without breaking it.

## The three levels

| Level        | Blocks                                                                                        | Use for                                   |
| :----------- | :-------------------------------------------------------------------------------------------- | :---------------------------------------- |
| `privileged` | Nothing                                                                                       | `kube-system`, CNI, CSI, security agents  |
| `baseline`   | Privileged containers, host namespaces, `hostPath`, host ports, added capabilities            | The minimum for any application namespace |
| `restricted` | Also requires non-root, dropped capabilities, `seccompProfile: RuntimeDefault`, no escalation | The target for application namespaces     |

Each namespace sets a level for three **modes**: `enforce` rejects the pod, `audit` records a violation in the audit log, `warn` returns a warning to the client.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: payments
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/enforce-version: v1.33
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

Pin `enforce-version`. With `latest`, a control plane upgrade can tighten the rules and start rejecting pods that were fine the day before.

## The EKS default is "allow everything"

A namespace without labels falls back to the cluster-wide default, and on EKS that default is `privileged` for all three modes. You cannot change it, because EKS does not expose the API server's admission configuration file. In practice:

- every namespace needs labels — nothing is protected until you add them;
- new namespaces start unprotected, so label them at creation through your namespace template, GitOps repo or a policy engine that mutates or rejects unlabelled namespaces.

## What must stay privileged

EKS system components genuinely need host access, so `kube-system` stays `privileged`:

| Component                                   | Why it cannot meet `baseline`                                |
| :------------------------------------------ | :----------------------------------------------------------- |
| `aws-node` (VPC CNI)                        | Host network, privileged init, manipulates ENIs and iptables |
| `kube-proxy`                                | Host network, writes iptables/nftables rules                 |
| EBS / EFS CSI node plugins                  | Privileged, mount host paths to attach and mount volumes     |
| Pod Identity agent                          | Host network                                                 |
| GuardDuty agent, Fluent Bit, node exporters | Read host paths and processes                                |

Put your own infrastructure add-ons in dedicated namespaces labelled `privileged`, and tightly control who can deploy there with [[Kubernetes/concepts/L07-security/01-api-access/03-rbac|RBAC]]. A privileged namespace anyone can deploy into defeats the whole scheme.

## Rollout that does not cause an outage

1. **See what would break.** A server-side dry run evaluates existing pods against a level without changing anything:

   ```bash
   kubectl label --dry-run=server --overwrite ns --all \
     pod-security.kubernetes.io/enforce=baseline
   ```

2. **Start with `warn` and `audit` at `restricted`** on application namespaces. Developers see warnings on `kubectl apply`; you see violations in the audit log (query them in [[Kubernetes/eks/observability/logging/control-plane-logs|control plane logs]] by the `pod-security.kubernetes.io/audit-violations` annotation).
3. **Enforce `baseline`.** Most well-behaved applications pass unchanged.
4. **Fix manifests, then enforce `restricted`.** The usual changes are in the pod's [[Kubernetes/concepts/L07-security/02-workload-sandboxing/05-security-context|security context]]:

   ```yaml
   securityContext:
     runAsNonRoot: true
     seccompProfile: { type: RuntimeDefault }
   containers:
     - name: app
       securityContext:
         allowPrivilegeEscalation: false
         capabilities: { drop: ["ALL"] }
   ```

Note that PSA evaluates **pods**. A Deployment that violates the policy is accepted with a warning and then silently fails to create pods; look at the ReplicaSet's events when replicas stay at zero.

## Where PSA stops

PSA is deliberately simple. It cannot:

- exempt a single workload inside a namespace (exemptions are by namespace, user or runtime class, set in the API server config that EKS does not expose);
- mutate pods to add missing defaults;
- express anything outside the three profiles: allowed registries, required labels, resource limits, image signatures.

For those, add a policy engine — see [[Kubernetes/eks/security/policy-management|policy management on EKS]]. A common pattern is PSA `baseline` everywhere as a safety net that cannot be bypassed by a webhook outage, plus Kyverno or a `ValidatingAdmissionPolicy` for the fine-grained rules.

## History: PodSecurityPolicy

Clusters created before Kubernetes 1.25 used PodSecurityPolicy with a permissive default named `eks.privileged`. PSP was removed in 1.25. Anything still referencing it is dead configuration and can be deleted.

## Related

- [[Kubernetes/eks/security/README|EKS security overview]]
- [[Kubernetes/guides/non-functional/security-baseline|Security baseline]]
- [[Linux/security/seccomp|seccomp]] and [[Linux/security/capabilities|capabilities]] — what the restricted profile actually removes
- [[Security/kubernetes-security/pod-security/README|Pod security (Security section)]]
- [EKS best practices: pod security](https://docs.aws.amazon.com/eks/latest/best-practices/pod-security.html)

## Across the wiki

- [[Containers/namespaces-and-cgroups|Namespaces and cgroups — What a Container Really Is]] — kernel sandboxing (Containers)
- [[Linux/security/apparmor|AppArmor]] — kernel sandboxing (Linux)
