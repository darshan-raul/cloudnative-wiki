---
title: "Runbook: OOMKilled Containers and Node Memory Pressure"
description: "Containers restart with OOMKilled, Pods get Evicted for memory, or nodes report MemoryPressure or SystemOOM. Separate a container hitting its own limit from a node running out of memory, and fix the right one."
tags:
  [
    kubernetes/eks/operator-runbook,
    eks,
    runbook,
    memory,
    oom,
    resources,
    incident,
  ]
date: 2026-10-20
aliases: [EKS OOMKilled runbook, Kubernetes memory pressure eviction]
---

# Runbook: OOMKilled Containers and Node Memory Pressure

**Applies to:** Linux nodes with cgroup v2 (AL2023 and Bottlerocket) on any EKS compute type. Fargate Pods can only hit their own limit; there's no shared node.
**Typical severity:** Sev 3 for one workload restarting. Sev 2 when memory pressure on nodes evicts unrelated Pods.
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

There are three different events. Find out which one you have:

| You see                                                                                                                        | What happened                                                                                              |
| ------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| `Last State: Terminated, Reason: OOMKilled, Exit Code: 137`; restarts climbing                                                 | **Container OOM**: the container exceeded its own memory **limit**; the kernel killed it inside its cgroup |
| Pod `Status: Failed, Reason: Evicted`, `The node was low on resource: memory. Container app was using 1.8Gi, request is 512Mi` | **Node-pressure eviction**: the kubelet freed memory on a node under pressure                              |
| Node event `SystemOOM` (`System OOM encountered, victim process: ...`); node condition `MemoryPressure=True`                   | **Node OOM**: the whole node ran out before the kubelet could react                                        |

**Exit code 137 alone isn't proof of OOM.** It means SIGKILL, which also happens when a liveness probe fails or a container ignores SIGTERM past its grace period. Then the reason is `Error`, not `OOMKilled`, and the events show `Liveness probe failed` or `Killing`.

## Impact

- **Container OOM:** only that workload. It restarts with back-off, and in-flight work is lost.
- **Eviction and node OOM:** other workloads on the node lose Pods too. The kubelet evicts in order **BestEffort** (no requests), then **Burstable** using the most memory above its request, and last **Guaranteed**. A node OOM can also kill the kubelet or containerd and take the node NotReady.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export NS=<namespace> POD=<pod> NODE=<node>
```

## Triage

**1. Confirm the kind of kill:**

```bash
kubectl get pod "$POD" -n "$NS" -o json | jq '.status.containerStatuses[] |
  {name, restartCount, reason: .lastState.terminated.reason, exitCode: .lastState.terminated.exitCode, finishedAt: .lastState.terminated.finishedAt}'
kubectl get events -A --field-selector reason=Evicted --sort-by=.lastTimestamp | tail
kubectl get events -A --field-selector involvedObject.kind=Node,reason=SystemOOM --sort-by=.lastTimestamp | tail
```

**2. Compare usage with requests and limits:**

```bash
kubectl get pod "$POD" -n "$NS" -o jsonpath='{range .spec.containers[*]}{.name}{"\t"}{.resources}{"\n"}{end}'
kubectl top pod "$POD" -n "$NS" --containers
```

Look at the history too, not just now. With Prometheus: `max_over_time(container_memory_working_set_bytes{namespace="<ns>",pod=~"<prefix>.*",container!=""}[1d])`. The working set is what the limit is enforced against.

**3. Is the node overcommitted?**

```bash
kubectl describe node "$NODE" | sed -n '/Allocated resources:/,/Events:/p'
kubectl top node "$NODE"
```

Memory **limits** above 100% of allocatable are normal. But actual use near allocatable, with **requests** far below actual use, means the scheduler is packing Pods on numbers that don't reflect reality.

**4. Find the biggest users on the node:**

```bash
kubectl get pods -A --field-selector spec.nodeName="$NODE" -o json | jq -r '.items[] |
  [.metadata.namespace, .metadata.name, .status.qosClass,
   ([.spec.containers[].resources.requests.memory // "none"] | join(","))] | @tsv' | column -t
kubectl top pods -A --sort-by=memory | head -15
```

## Diagnosis

| Signal                                                              | Cause                                                | Fix   |
| ------------------------------------------------------------------- | ---------------------------------------------------- | ----- |
| `OOMKilled`; usage climbs steadily until the limit                  | A. Memory leak, or a limit below real need           | Fix A |
| `OOMKilled` right after start, or under load                        | B. Runtime not sized to the limit (JVM, Node.js, Go) | Fix B |
| `Evicted` for memory; requests far below actual use across the node | C. Requests too low, so the node is overpacked       | Fix C |
| `SystemOOM`; kubelet or containerd killed; node NotReady            | D. Node reservations too small for the system        | Fix D |

## Fix

### A. Leak, or limit too low

- **If usage rises without bound** until the kill, it's a leak. Raising the limit only delays the kill. Restarting on a schedule buys time; the fix is in the code. Take a heap profile before the kill.
- **If usage plateaus just above the limit**, the limit is too low. Raise it, through the workload's manifest, based on the observed peak plus margin. Check that the new value still fits on your nodes.
- **VPA in recommendation mode** gives data-driven values: `kubectl get vpa -n "$NS"`. See [[Kubernetes/concepts/L06-scheduling-scaling/07-vertical-pod-autoscaler|VPA]].
- **In-place resize:** on current Kubernetes versions you can change a running Pod's resources through the `resize` subresource, without a restart where the runtime supports it: `kubectl patch pod "$POD" -n "$NS" --subresource resize --patch '{"spec":{"containers":[{"name":"app","resources":{"limits":{"memory":"2Gi"}}}]}}'`. Treat it as a stopgap; put the value in the manifest too.

### B. Runtime not sized to the container

Many runtimes size their heap from the node's memory, or not at all:

| Runtime | Setting                                                                                                     |
| ------- | ----------------------------------------------------------------------------------------------------------- |
| JVM     | `-XX:MaxRAMPercentage=75` (container-aware). Leave room for metaspace, threads and direct buffers           |
| Node.js | `--max-old-space-size=<MiB>` at about 75% of the limit                                                      |
| Go      | `GOMEMLIMIT` at about 90% of the limit, so the GC works harder before the kernel kills it                   |
| Python  | No heap cap; find the growth (large responses, caches) or use worker recycling (`max_requests` in gunicorn) |

### C. Requests too low, node overpacked

The scheduler places Pods by **requests**. If a workload's request is 512Mi but it uses 2Gi, every node holding it is overpacked, and the kubelet evicts under pressure.

- Set memory requests close to typical working set, and limits close to the peak. For workloads that must never be evicted for memory, make requests equal to limits (Guaranteed QoS).
- Give every namespace a `LimitRange` with default requests, so Pods without requests don't end up BestEffort.
- Short term: cordon the hot node and spread the heaviest Pods out (`kubectl rollout restart` the biggest Burstable workloads after cordoning).

### D. Node reservations too small

The EKS AMIs reserve memory for the kubelet and system (`kubeReserved`, `systemReserved`) and evict at `memory.available<100Mi`. Heavy DaemonSets (log shippers, security agents, mesh proxies) or many Pods per node can exceed that budget.

- Raise `kubeReserved` or `systemReserved`, or the eviction threshold. On AL2023 that's the `NodeConfig` kubelet section; in Karpenter it's `EC2NodeClass` `spec.kubelet`. The change applies to new nodes, so roll the group or let drift replace them.
- Give DaemonSets memory requests and limits too. They count against the same node.
- Read the console output (`aws ec2 get-console-output`) for which process the kernel killed.

## Verify recovery

- Restart count stops rising for the workload over at least one traffic peak.
- `kubectl get events -A --field-selector reason=Evicted` shows no new memory evictions.
- No `SystemOOM` events, and node `MemoryPressure=False`.

## Escalate

These are workload and configuration issues; AWS Support is rarely needed. Escalate to the workload's owner with the restart history, the memory graph and the heap profile.

## Prevent

- Alert on `kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}` increases, and on node `MemoryPressure`.
- Require memory requests on every container (admission policy, plus a `LimitRange` default).
- Review VPA recommendations against configured requests every quarter.
- Size runtime heaps from the container limit, not the host.

## Background

- [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits|Resource requests and limits]]
- [[Kubernetes/guides/troubleshooting/crashloop-backoff|Troubleshooting CrashLoopBackOff]]
- [[Kubernetes/eks/operator-runbook/runbooks/node-not-ready|Node NotReady]] (when a node OOM takes the node down)
- [Node-pressure eviction](https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/)
