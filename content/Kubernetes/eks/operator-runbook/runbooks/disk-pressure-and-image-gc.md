---
title: "Runbook: Node Disk Pressure and Image Garbage Collection Failures"
description: "Nodes report DiskPressure, Pods get evicted for ephemeral storage, or the kubelet logs ImageGCFailed. Find whether images, logs, emptyDir or container layers fill the disk, and fix it at the source."
tags:
  [
    kubernetes/eks/operator-runbook,
    eks,
    runbook,
    nodes,
    disk,
    ephemeral-storage,
    incident,
  ]
date: 2026-10-20
aliases: [EKS DiskPressure runbook, ImageGCFailed, ephemeral-storage eviction]
---

# Runbook: Node Disk Pressure and Image Garbage Collection Failures

**Applies to:** EC2 nodes (AL2023 with one root volume, Bottlerocket with a separate data volume) in managed node groups, self-managed groups and Karpenter.
**Typical severity:** Sev 3 for one node; Sev 2 when it repeats across a fleet (usually one workload or one image causes it).
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

```text
Node condition:  DiskPressure  True  KubeletHasDiskPressure  kubelet has disk pressure
Taint:           node.kubernetes.io/disk-pressure:NoSchedule
Pod:             Status: Failed  Reason: Evicted  Message: The node was low on resource: ephemeral-storage.
                 Container app was using 4Gi, which exceeds its request of 0.
Node event:      ImageGCFailed  failed to garbage collect required amount of images.
                 Attempted to free 4294967296 bytes, but only found 0 bytes eligible to free.
Node event:      FreeDiskSpaceFailed / EvictionThresholdMet
```

## Impact

The node stops accepting new Pods, and the kubelet evicts Pods to free space. If the cause is a single workload that keeps writing, it gets rescheduled and fills the next node: a rolling eviction loop across the fleet.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export NODE=<node>
export INSTANCE_ID=$(kubectl get node "$NODE" -o jsonpath='{.spec.providerID}' | awk -F/ '{print $NF}')
```

## Triage

**1. Which Pods use the most ephemeral storage?** The kubelet's summary API answers without a shell on the node:

```bash
kubectl get --raw "/api/v1/nodes/$NODE/proxy/stats/summary" | jq -r '
  .pods[] | [.podRef.namespace, .podRef.name,
    ((.["ephemeral-storage"].usedBytes // 0) / 1048576 | floor | tostring) + " MiB"] | @tsv' \
  | sort -t$'\t' -k3 -rn | head -15
kubectl get --raw "/api/v1/nodes/$NODE/proxy/stats/summary" | jq '.node.fs, .node.runtime.imageFs'
```

Pod ephemeral storage counts writable container layers, `emptyDir` volumes (not memory-backed) and the Pod's logs.

**2. On the node, where's the space?**

```bash
aws ssm start-session --target "$INSTANCE_ID"
df -h / /var/lib/containerd; df -i /
sudo du -xsh /var/lib/containerd /var/lib/kubelet /var/log 2>/dev/null
sudo du -xsh /var/lib/kubelet/pods/* 2>/dev/null | sort -h | tail -5      # emptyDir, per Pod UID
sudo du -xsh /var/log/pods/* 2>/dev/null | sort -h | tail -5              # container logs
sudo crictl images | sort -k4 -h | tail -10                               # largest images
sudo crictl stats -a 2>/dev/null | sort -k5 -h | tail -10                 # writable layer usage
```

- **If** `df -i` shows inodes at 100% while bytes are free → millions of small files (cause D).

**3. Can image GC free anything?** If almost all images belong to running containers (common with very large images, or many different images per node), GC has nothing to delete. That's what `found 0 bytes eligible to free` means.

## Diagnosis

| Signal                                                                  | Cause                             | Fix   |
| ----------------------------------------------------------------------- | --------------------------------- | ----- |
| One Pod's ephemeral usage dominates (emptyDir or writable layer)        | A. Workload writing to local disk | Fix A |
| `/var/log/pods` large; one container very chatty                        | B. Logs                           | Fix B |
| `/var/lib/containerd` large; `ImageGCFailed`; many or very large images | C. Images don't fit the disk      | Fix C |
| Inodes exhausted                                                        | D. Too many small files           | Fix D |

## Fix

### A. Workload writing to local disk

1. **Now:** delete or evict that Pod (`kubectl delete pod`). The space under its UID goes with it.
2. **Contain it:** give the container an ephemeral-storage request and limit. The kubelet then evicts only that Pod when it exceeds the limit, instead of the node going into pressure:

   ```yaml
   resources:
     requests:
       ephemeral-storage: 1Gi
     limits:
       ephemeral-storage: 4Gi
   ```

   And set `sizeLimit` on `emptyDir` volumes.

3. **Fix the source:** if the workload needs scratch space, give it a generic ephemeral volume (an EBS-backed volume per Pod) or a PVC instead of the node's root disk. If it writes temporary files it never deletes, fix that in the application.

### B. Logs

The kubelet rotates container logs at `containerLogMaxSize` (default 10Mi), keeping `containerLogMaxFiles` (default 5) files per container. Large `/var/log/pods` usually means many containers on the node, or an application writing log **files** inside the container instead of stdout (those count as writable layer, see A). Fix the noisy logger: lower its log level, or sample. Tune the kubelet settings through `NodeConfig` or `EC2NodeClass` `spec.kubelet` if your log volume is legitimate.

### C. Images don't fit the disk

The default root volume is small (20 GiB on many EKS node groups and Karpenter defaults).

- **Grow the disk.** For managed node groups, set `diskSize`, or the launch template's block device mapping. For Karpenter:

  ```yaml
  spec:
    blockDeviceMappings:
      - deviceName: /dev/xvda
        ebs:
          volumeSize: 80Gi
          volumeType: gp3
          encrypted: true
  ```

  On Bottlerocket, size the **data volume** (`/dev/xvdb`), not the OS volume. New nodes pick it up; roll or drift the existing ones.

- **Shrink the images:** multi-stage builds and slim base images. Fewer distinct images per node also helps (fewer sidecar variants, aligned base images).
- **Clean now:** `sudo crictl rmi --prune` removes images no container uses. It's safe, but frees little if everything is in use.

### D. Inodes exhausted

Find the directory with the most files (`sudo find /var/lib/kubelet/pods -xdev -type f | cut -d/ -f6 | sort | uniq -c | sort -rn | head`) and map the UID to a Pod (`kubectl get pods -A -o custom-columns=UID:.metadata.uid,NS:.metadata.namespace,NAME:.metadata.name | grep <uid>`). Then fix it as in A.

## Verify recovery

```bash
kubectl describe node "$NODE" | grep -E 'DiskPressure|disk-pressure'   # False, taint gone
kubectl get events -A --field-selector reason=Evicted --sort-by=.lastTimestamp | tail -5
```

Watch that the same workload doesn't move to another node and start the cycle again.

## Escalate

These are workload and node-configuration issues. Escalate to the workload owner with the ephemeral usage figures from Triage step 1.

## Prevent

- Alert on node filesystem usage above 80%, and on `ImageGCFailed` events.
- Require ephemeral-storage requests and limits for workloads that write locally (a `LimitRange` default works).
- Size root or data volumes for the images you actually run, plus headroom.
- Applications log to stdout and write scratch data to volumes, never to the container filesystem.

## Background

- [[Kubernetes/eks/operator-runbook/reference/node-access-and-logs|Node access and log locations]]
- [[Kubernetes/eks/operator-runbook/reference/limits-and-formulas|Limits and defaults]] (eviction and GC thresholds)
- [Local ephemeral storage](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/#local-ephemeral-storage)
