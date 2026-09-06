---
title: AKS SRE Troubleshooting & Incident Runbook — CrashLoopBackOff, Node NotReady, and CNI Leaks
description: Exhaustive SRE incident runbook for AKS — Exit code taxonomy, Node NotReady triage, OOMKilled remediation, CNI IP exhaustion, Azure Disk attachment deadlocks, and az aks diagnostic tooling.
tags:
  - azure
  - aks
  - troubleshooting
  - runbook
  - sre
  - incident-response
  - debugging
---

# AKS SRE Troubleshooting & Incident Runbook — CrashLoopBackOff, Node NotReady, and CNI Leaks 🚨🩺

During high-severity production incidents, Site Reliability Engineers (SREs) and platform architects must diagnose and remediate failures rapidly under tight SLA pressure. On Azure Kubernetes Service (AKS), outages generally originate from three interconnected infrastructure layers: **Container Workload Failures (OOMKills, Configuration drift)**, **Worker Node Health Failures (VMSS provisioning, OS disk exhaustion, PLEG deadlocks)**, and **Azure Platform Network/Storage Timeouts (CNI IP exhaustion, Azure Disk detach deadlocks)**. This runbook provides a battle-tested diagnostic workflow and tactical remediation commands.

---

## 1. Triage Decision Tree: The AKS Emergency Triage Flowchart

```
                            ALERT: INCIDENT DECLARED ON CLUSTER
                                          │
                  ┌───────────────────────┴───────────────────────┐
                  ▼                                               ▼
         POD-LEVEL FAILURES                              NODE-LEVEL FAILURES
                  │                                               │
      Is pod CrashLooping?                            Is node in "NotReady"?
      ┌───────────┴───────────┐                       ┌───────────┴───────────┐
      ▼                       ▼                       ▼                       ▼
Exit Code 137           Exit Code 1/143          DiskPressure?           PLEG Is Not Healthy?
(OOMKilled: Linux       (App error, missing      (OS disk full:          (Docker/containerd
cgroup memory exceeded) config, port conflict)   container logs bloat)   hung; Kubelet timeout)
      │                       │                       │                       │
      ▼                       ▼                       ▼                       ▼
Increase memory limit   Inspect stdout logs:     Prune /var/lib/docker   Restart containerd
& verify heap size      `kubectl logs --previous` via node shell        or re-image VMSS node
```

---

## 2. Container Exit Code Taxonomy & Immediate Actions

| Exit Code | Termination Reason | Underlying Kernel / K8s Mechanism | Immediate Remediation Action |
| :--- | :--- | :--- | :--- |
| **137** | **OOMKilled** | Linux kernel Out-Of-Memory killer triggered ($128 + 9 = \text{SIGKILL}$) | Increase `.resources.limits.memory`; fix application memory leak |
| **143** | **SIGTERM** | Graceful termination initiated by K8s ($128 + 15 = \text{SIGTERM}$) | Check if Cluster Autoscaler or Node Surge upgrade evicted the pod |
| **1** | **Application Crash** | General software exception, uncaught error, or syntax fault | Run `kubectl logs -n <ns> <pod> --previous` to inspect stack trace |
| **126** | **Permission Denied** | Container command binary is not executable (`chmod +x`) | Verify container entrypoint file permissions in Dockerfile |
| **127** | **Binary Not Found** | Entrypoint executable or shell missing from container image | Check if binary was compiled dynamically without libc |
| **139** | **Segmentation Fault**| Memory access violation in compiled code ($128 + 11 = \text{SIGSEGV}$) | Inspect C/C++ or Rust native extensions for null pointer deref |

---

## 3. Top AKS Production Failures & Incident Playbooks

### Playbook 1: Resolving `Node NotReady` and Kubelet PLEG Timeouts

#### Diagnostic Commands
```bash
# 1. Identify all NotReady worker nodes
kubectl get nodes --sort-by='.metadata.name' | grep NotReady

# 2. Inspect Node Conditions for DiskPressure, MemoryPressure, or NetworkUnavailable
kubectl describe node <node-name> | grep -A 8 "Conditions:"

# 3. Check Kubelet systemd journal logs via AKS Node Shell
az aks node-shell --resource-group rg-prod-aks --name aks-core-prod --node-name <node-name>
# Inside node shell:
journalctl -u kubelet -e --no-pager | grep -i "PLEG"
```

#### Root Cause & Resolution
- **PLEG (Pod Lifecycle Event Generator) Timeout:** Occurs when hundreds of pods on a single node concurrently churn, causing the container runtime (`containerd`) to block. Kubelet misses its heartbeat to the API server and marks the node `NotReady`.
- **Action:**
  ```bash
  # Inside node shell: restart containerd and kubelet
  systemctl restart containerd
  systemctl restart kubelet
  ```

---

### Playbook 2: Resolving Traditional Azure CNI IP Exhaustion

#### Diagnostic Commands
```bash
# Check if pods are stuck in Pending with Network Plugin IPAM errors
kubectl get pods -A | grep Pending
kubectl describe pod <pending-pod> | grep -i "FailedAllocateIPAddress"
```

#### Root Cause & Resolution
- **Symptom:** `Failed to allocate address: Failed to allocate IP address from subnet: No free IP addresses available`.
- **Root Cause:** Traditional Azure CNI reserved all available private IPs from the host VNet subnet.
- **Action:**
  1. Add a new secondary IP range to the VNet.
  2. Create a new Node Pool using **Azure CNI Overlay** (which uses private overlay IPs and requires only 1 VNet IP per node):
     ```bash
     az aks nodepool add \
         --resource-group rg-prod-aks \
         --cluster-name aks-core-prod \
         --name overlaypool \
         --node-vm-size Standard_D8ds_v5 \
         --network-plugin-mode overlay
     ```
  3. Cordon and drain the depleted node pool.

---

### Playbook 3: Resolving Azure Disk Detach Deadlocks (`VolumeAttachment` Stuck)

#### Diagnostic Commands
```bash
# Check for stuck VolumeAttachments preventing StatefulSet pod failover
kubectl get volumeattachments | grep false
kubectl describe volumeattachment <attachment-name>
```

#### Root Cause & Resolution
- **Symptom:** Pod fails to start on Node 2 with `Multi-Attach error for volume: Volume is already exclusively attached to Node 1`.
- **Root Cause:** Node 1 crashed abruptly without cleanly unmounting the LUN. Azure's `csi-attacher` controller will wait up to 6 minutes before issuing a force detach.
- **Action:**
  ```bash
  # 1. Force delete the stuck pod on Node 1
  kubectl delete pod <pod-name> -n <namespace> --grace-period=0 --force

  # 2. Delete the stuck VolumeAttachment to release the Azure Disk lock
  kubectl delete volumeattachment <attachment-name>
  ```

---

## 4. AKS Built-In Diagnostic Tooling (`az` CLI)

### 1. Run AKS Diagnostic Collector
Collect comprehensive logs across the control plane, CoreDNS, network dataplane, and node metrics:

```bash
# Run automated self-service diagnostic checks on the cluster
az aks check-acr \
    --resource-group rg-prod-aks \
    --name aks-core-prod \
    --acr myregistry.azurecr.io

# Capture cluster diagnostic bundle for Microsoft Support
az aks kollect \
    --resource-group rg-prod-aks \
    --name aks-core-prod \
    --storage-account-name stdiagnosticsprod
```

---

## 5. Quotas, Performance & Configuration Limits

| Failure Vector | Threshold / Limit | SRE Triage Rule |
| :--- | :--- | :--- |
| **Kubelet Node Heartbeat** | **40 Seconds** | Node marked `NotReady` if heartbeat is missed |
| **CSI Disk Attach Timeout** | **6 Minutes** | Hard Azure timeout before force-detaching LUN |
| **Subnet Reserve IPs** | **5 IPs reserved by Azure**| First 4 IPs and last IP cannot be allocated to nodes |
| **ARM API Throttling** | **1,200 reads/writes per hr**| Rapid nodepool script loops can trigger `429 Throttling`|

---

## 6. Official References

- [Troubleshoot AKS Cluster Issues](https://learn.microsoft.com/en-us/azure/aks/troubleshooting)
- [Troubleshoot Common Node NotReady Issues](https://learn.microsoft.com/en-us/troubleshoot/azure/azure-kubernetes/error-node-not-ready)
- [Debug Pod and Container Failures](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
- [Use AKS Node Shell for Host Debugging](https://learn.microsoft.com/en-us/azure/aks/node-access)

---

## 7. Realistic Pricing Scenarios (The Cost of Outages)

### Scenario A: Prevented SLA Breach via Rapid Runbook Execution

- **Environment:** Global FinTech API ($500,000 hourly revenue) running on a 30-node AKS cluster.
- **Incident:** Memory leak in payment service triggers cluster-wide OOMKilled cascade.
- **Unmitigated Outage (4 Hours):** $2,000,000 in lost revenue and SLA penalty refunds.
- **Runbook Triage (12 Minutes):** SRE runs KQL query, identifies Exit Code 137, scales limits via `kubectl set resources`, and restarts pods cleanly.
- **Net Outage Avoidance:** **~$1.9 Million in enterprise value preserved**.

### Scenario B: Diagnostic Storage & Telemetry Overhead

- **Configuration:** Dedicated diagnostic storage account holding historical crash dumps and `kollect` bundles.
- **Monthly Cost Breakdown:**
  - Standard Hot Blob Storage (500 GB crash logs): **$9.00 / month**.
  - Log Analytics Ingestion for Triage Alerts: **$45.00 / month**.
- **Total SRE Tooling Spend:** **$54.00 / month**

---

## 8. Battle-Tested Nuggets & Production Gotchas

1. **The CoreDNS CrashLoop DNS Black Hole:** If CoreDNS pods crash or run out of memory (`OOMKilled`), every single microservice across the cluster will fail with `NameResolutionFailure` or `EAI_AGAIN`. Applications will report that databases and external APIs are "down," when in reality only internal DNS lookup has failed. **Always check `kubectl get pods -n kube-system -l k8s-app=coredns` first during widespread connection failures.**
2. **Ephemeral OS Disk Disconnection on Hard Host Failure:** If an underlying physical Azure host server experiences a sudden hardware crash, nodes using Ephemeral OS Disks cannot be "rebooted" in place because the local NVMe drive lost power. AKS automatically re-provisions a fresh VMSS instance on a healthy host. Pods are evicted and rescheduled in **under 2 minutes**.
3. **Log Disk Saturation Freezing Worker Nodes:** When a container enters a rapid crash loop and writes gigabytes of stack traces to stdout/stderr, Docker/containerd stores these in `/var/log/pods`. If log rotation is disabled or lagging, the OS root disk hits **100% capacity (`DiskPressure`)**, causing the Kubelet to reject all container executions. Run `df -h` inside the node shell to verify root filesystem capacity.
4. **VNet NSG Outbound Blocking API Server Drops:** If an enterprise security engineer applies an aggressive Network Security Group (NSG) to the AKS node subnet that blocks outbound TCP port 443 or port 9000 (Konnectivity tunnel), worker nodes lose connectivity to the managed control plane. All nodes will abruptly transition to `NotReady`. Ensure NSGs whitelist the `AzureCloud` service tag.
5. **ImagePullBackOff Caused by ACR Managed Identity Desync:** When AKS pulls images from Azure Container Registry (ACR), it authenticates using the cluster's `kubeletidentity`. If someone accidentally removes the **"AcrPull"** role assignment on the ACR resource group, all rolling deployments will suddenly fail with `ImagePullBackOff: 401 Unauthorized`. Run `az aks check-acr` to immediately audit registry connectivity.
