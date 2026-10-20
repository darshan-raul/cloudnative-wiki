---
title: "Runbook: Karpenter Not Launching Nodes"
description: "Pods stay Pending and Karpenter creates no node, or creates one that never becomes Ready. Follow the Pod through NodePool, EC2NodeClass and NodeClaim to the failing step."
tags:
  [
    kubernetes/eks/operator-runbook,
    eks,
    runbook,
    karpenter,
    autoscaling,
    incident,
  ]
date: 2026-10-20
aliases: [Karpenter not scaling runbook, Karpenter pods pending]
---

# Runbook: Karpenter Not Launching Nodes

**Applies to:** self-managed Karpenter v1.x (`karpenter.sh/v1` NodePool and NodeClaim, `karpenter.k8s.aws/v1` EC2NodeClass). EKS Auto Mode uses the same NodePool and NodeClaim model with a managed controller; the NodeClaim steps apply, but you can't read the controller logs.
**Typical severity:** Sev 2. Running workloads are fine; scale-out, rollouts and node replacement stall.
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

- Pods stay `Pending` with `FailedScheduling` from the default scheduler, and no new nodes appear.
- Karpenter events on the Pod, for example:

  ```text
  Warning  FailedScheduling  karpenter  Failed to schedule pod, incompatible requirements, key karpenter.sh/capacity-type, ...
  Warning  FailedScheduling  karpenter  Failed to schedule pod, no instance type met the scheduling requirements or had enough resources, requirements=..., resources=...
  Warning  FailedScheduling  karpenter  Failed to schedule pod, all available instance types exceed limits for nodepool
  Normal   Nominated         karpenter  Pod should schedule on: nodeclaim/default-8x2kq"
  ```

- NodeClaims appear and disappear repeatedly, or stay `READY=Unknown`.

## Impact

Nothing that is already running breaks. Anything that needs new capacity waits: HPA scale-out, new deployments, and replacements for nodes that Karpenter itself is disrupting (drift, expiry or consolidation stall too).

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=my-cluster REGION=us-east-1
export NS=<namespace> POD=<pending pod>
export KARPENTER_NS=$(kubectl get deploy -A -l app.kubernetes.io/name=karpenter -o jsonpath='{.items[0].metadata.namespace}')
```

## Triage

Work down the chain: **Pod → Karpenter controller → NodePool → EC2NodeClass → NodeClaim → Node**. Stop at the first broken link.

**1. What does Karpenter say about the Pod?**

```bash
kubectl get events -n "$NS" --field-selector involvedObject.name="$POD" --sort-by=.lastTimestamp
```

- `Nominated` for a NodeClaim → Karpenter launched capacity for it. Go to step 5.
- `incompatible requirements`, or `no instance type met ...` → the Pod's requirements or requests don't match what any NodePool can offer (cause B). The message lists the requirements and resources Karpenter tried.
- `exceed limits for nodepool`, or `node limits have been exhausted for nodepool` → the NodePool `limits` have been reached (cause C).
- A `NoCompatibleInstanceTypes` event on the **NodePool** (`kubectl get events -A --field-selector reason=NoCompatibleInstanceTypes`) means its requirements filter out every instance type available (cause B).

Message wording comes from the Karpenter source at the time of writing; it changes between releases, so match on the key phrase.

- No Karpenter events at all → the controller isn't running or isn't seeing the Pod (cause A).

**2. Is the controller healthy?**

```bash
kubectl get pods -n "$KARPENTER_NS" -l app.kubernetes.io/name=karpenter
kubectl logs -n "$KARPENTER_NS" -l app.kubernetes.io/name=karpenter --tail=300 \
  | grep -iE '"level":"error"|AccessDenied|Unauthorized|InsufficientInstanceCapacity|VcpuLimitExceeded|InvalidParameter' | tail -20
```

- **Expect:** pods `Running`, one of them the leader, and no repeating errors.
- **If** you see `AccessDenied` or `UnauthorizedOperation` on `ec2:CreateFleet`, `ec2:RunInstances`, `iam:PassRole` or `ssm:GetParameter` → controller IAM (cause A).

**3. Do the NodePools allow this Pod, and do they have headroom?**

```bash
kubectl get nodepools
kubectl get nodepool <name> -o jsonpath='{.spec.limits}{"\n"}{.status.resources}{"\n"}'
kubectl get nodepool <name> -o jsonpath='{.spec.template.spec.requirements}' | jq
kubectl get nodepool <name> -o jsonpath='{.spec.template.spec.taints}' | jq
kubectl get pod "$POD" -n "$NS" -o jsonpath='{.spec.nodeSelector}{"\n"}{.spec.affinity}{"\n"}{.spec.tolerations}{"\n"}' | jq -R
kubectl get pod "$POD" -n "$NS" -o jsonpath='{range .spec.containers[*]}{.resources.requests}{"\n"}{end}'
```

Compare each Pod constraint with the NodePool: `kubernetes.io/arch`, `karpenter.sh/capacity-type`, `topology.kubernetes.io/zone`, instance family or size, and taints the Pod doesn't tolerate. A request larger than the biggest allowed instance type, after DaemonSet overhead, can never be satisfied.

**4. Is the EC2NodeClass ready?**

```bash
kubectl get ec2nodeclasses
kubectl describe ec2nodeclass <name> | sed -n '/Conditions:/,/Events:/p'
```

- **Expect:** `READY=True`, and status conditions `SubnetsReady`, `SecurityGroupsReady`, `AMIsReady` and `InstanceProfileReady` all `True`.
- **If** one is `False` → selector or IAM problem (cause D). The condition message names which.

**5. Did a NodeClaim launch and join?**

```bash
kubectl get nodeclaims -o wide
kubectl describe nodeclaim <name> | sed -n '/Conditions:/,/Events:/p'
```

| NodeClaim condition                              | Meaning                                                                             |
| ------------------------------------------------ | ----------------------------------------------------------------------------------- |
| `Launched=False`                                 | EC2 refused the launch (cause E). The message carries the EC2 error                 |
| `Launched=True`, `Registered=False`              | The instance runs but the kubelet never joined (cause F)                            |
| `Registered=True`, `Initialized=False`           | The node joined but isn't usable yet: startup taint, CNI or device plugin (cause G) |
| NodeClaims created and deleted every ~15 minutes | Registration never succeeds; Karpenter gives up and retries (cause F)               |

## Diagnosis

| Signal                                                          | Cause                                                  | Fix   |
| --------------------------------------------------------------- | ------------------------------------------------------ | ----- |
| No Karpenter events; controller down or IAM errors              | A. Controller unhealthy or missing permissions         | Fix A |
| `incompatible requirements`, `no instance type met ...`         | B. Pod constraints match no NodePool                   | Fix B |
| `exceed limits for nodepool`, `node limits have been exhausted` | C. NodePool limits reached                             | Fix C |
| EC2NodeClass `READY=False`                                      | D. Subnet, security group, AMI or role selector broken | Fix D |
| NodeClaim `Launched=False`                                      | E. EC2 capacity, quota or launch error                 | Fix E |
| `Registered=False`                                              | F. Node can't join the cluster                         | Fix F |
| `Initialized=False`                                             | G. Node joined but isn't ready for Pods                | Fix G |

## Fix

### A. Controller unhealthy or missing permissions

- **Crash-looping:** read `kubectl logs ... --previous`. After an upgrade, check that the CRDs match the controller version. The Karpenter chart doesn't upgrade CRDs; they come from the separate `karpenter-crd` chart.
- **IAM:** find the controller role. With Pod Identity, run `aws eks list-pod-identity-associations --cluster-name "$CLUSTER" --namespace "$KARPENTER_NS"`; with IRSA, read the service account annotation. Compare its policy with the controller policy for your Karpenter version, especially `iam:PassRole` on the node role and the `ec2:CreateFleet` conditions. For workload credential problems, see [[Kubernetes/eks/operator-runbook/runbooks/workload-aws-access-denied|workload AccessDenied]].
- **Not the leader:** if all pods are running but none is acting, look for lease or leader-election errors. The controller needs to reach the API server.

**Verify:** after a restart, the Pod gets a `Nominated` event within a minute.

### B. Pod constraints match no NodePool

Decide which side is wrong:

- **The Pod asks for something you don't offer** (`arm64`, a GPU, an AZ the NodePool excludes, `on-demand` only) → fix the workload, or add a NodePool for that class of capacity.
- **The NodePool is too narrow** → widen `requirements`, for example add instance families or sizes, or allow `spot` and `on-demand`.
- **Taint mismatch** → the Pod needs a toleration for the NodePool's taints, or it belongs in another NodePool.

**Verify:** the Karpenter event changes to `Nominated`.
**Undo:** revert the NodePool change through its owner (GitOps or IaC).

### C. NodePool limits reached

Limits are a cost and blast-radius guard. Confirm the growth is legitimate, not a runaway HPA or a crash-looping Job creating Pods. Then raise `spec.limits.cpu` or `memory` on the NodePool, or add a weighted fallback NodePool.

```bash
kubectl get pods -A --field-selector status.phase=Pending --no-headers | awk '{print $1}' | sort | uniq -c | sort -rn | head
```

**Undo:** restore the previous limit once demand drops, if the raise was temporary.

### D. EC2NodeClass not ready

- `SubnetsReady` or `SecurityGroupsReady` false → the selector matches nothing. Usually a missing `karpenter.sh/discovery: <cluster>` tag, or a subnet ID that no longer exists. Check with `aws ec2 describe-subnets --filters Name=tag:karpenter.sh/discovery,Values="$CLUSTER"`.
- `AMIsReady` false → the `amiSelectorTerms` alias or ID doesn't resolve. For example, a pinned `al2023@v<date>` that isn't valid for the cluster version, or a custom AMI shared from another account.
- `InstanceProfileReady` false → the `role` doesn't exist, or the controller can't create its instance profile.

**Verify:** `READY=True`, then a NodeClaim appears for the pending Pods.

### E. EC2 refused the launch

Read the NodeClaim message and the controller log:

| Error                                                | Fix                                                                                                                                                                                                            |
| ---------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `InsufficientInstanceCapacity`                       | Karpenter retries other types and zones automatically. If every allowed type is exhausted, widen families, sizes, zones or capacity types. A NodePool restricted to one or two Spot types is the usual culprit |
| `VcpuLimitExceeded` / `MaxSpotInstanceCountExceeded` | Account quota. Request an increase in Service Quotas ("Running On-Demand Standard instances", "All Standard Spot Instance Requests"); meanwhile allow the other capacity type                                  |
| `InsufficientFreeAddressesInSubnet`                  | Subnet full; see [[Kubernetes/eks/operator-runbook/runbooks/pods-stuck-containercreating-ip-exhaustion\|IP exhaustion]]                                                                                        |
| Instance launches, then terminates within seconds    | Usually an encrypted EBS root volume whose KMS key policy doesn't allow the EC2 service or the node role to use it. Check `StateTransitionReason` with `aws ec2 describe-instances`                            |
| `UnauthorizedOperation`                              | Controller IAM (Fix A)                                                                                                                                                                                         |

### F. Node can't join

The instance is running but its kubelet can't register. Check these in order:

1. **Access entry for the node role:** `aws eks list-access-entries --cluster-name "$CLUSTER"` must include the EC2NodeClass `role` with type `EC2_LINUX`. On `aws-auth` clusters it needs a `mapRoles` entry. A missing entry gives `Unauthorized` in the kubelet log.
2. **Network:** the node's security groups and subnet routes must reach the cluster endpoint on 443, and reach ECR, S3 and STS (through a NAT or VPC endpoints) to pull `aws-node` and `kube-proxy`.
3. **User data:** custom `userData` in the EC2NodeClass (AL2023 `NodeConfig`) that's malformed stops `nodeadm`. Read the console output: `aws ec2 get-console-output --instance-id <id> --latest --output text | grep -i nodeadm`.

For a deeper look on the instance, follow [[Kubernetes/eks/operator-runbook/runbooks/node-not-ready|Node NotReady]] Triage step 4.

### G. Node joined but isn't initialized

- A `startupTaints` entry in the NodePool that nothing removes (for example a taint that a missing agent was supposed to clear).
- `aws-node` not ready on the new node: `cni plugin not initialized` (see [[Kubernetes/eks/operator-runbook/runbooks/node-not-ready|Node NotReady]], Fix step 1).
- An extended resource the Pod requests (such as `nvidia.com/gpu`) that never appears, because the device plugin DaemonSet doesn't run on that node.

## Verify recovery

```bash
kubectl get nodeclaims -o wide                       # READY=True for the new claims
kubectl get pods -A --field-selector status.phase=Pending
kubectl get events -A --field-selector reason=Nominated --sort-by=.lastTimestamp | tail
```

Pending Pods are bound and Running, and drift or consolidation (if they were paused behind the failure) resumes.

## Escalate

Open an AWS Support case for persistent `InsufficientInstanceCapacity` across a wide instance selection in an AZ, or for launch failures that are internal EC2 errors. Attach the NodeClaim YAML, controller log excerpts with request IDs, the region and AZs, and the instance types tried. Karpenter bugs go to the [Karpenter GitHub project](https://github.com/kubernetes-sigs/karpenter) or [aws/karpenter-provider-aws](https://github.com/aws/karpenter-provider-aws).

## Prevent

- Alert on Pods `Pending` longer than five minutes (`kube_pod_status_phase{phase="Pending"}`), and on NodePool usage approaching its limits.
- Allow many instance families and sizes per NodePool, especially for Spot. Narrow NodePools are the main cause of capacity errors.
- Keep the controller IAM policy, CRDs and controller version in one IaC module, and upgrade them together.
- Run the controller on capacity Karpenter doesn't manage (a small managed node group, or Fargate), so it can recover the cluster.

## Background

- [[Kubernetes/eks/compute/karpenter/README|Karpenter on EKS]]
- [[Kubernetes/concepts/L06-scheduling-scaling/08-karpenter|Karpenter concepts]]
- [[Kubernetes/guides/troubleshooting/pod-pending|Troubleshooting Pending Pods]]
- [Karpenter troubleshooting](https://karpenter.sh/docs/troubleshooting/)
