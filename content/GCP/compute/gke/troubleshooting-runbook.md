---
title: GKE SRE Incident Response & Production Troubleshooting Runbook
description: Exhaustive engineering runbook for troubleshooting mission-critical failures on GKE — CrashLoopBackOff, Node NotReady, OOMKilled (Exit Code 137), IP exhaustion, control plane latency, etcd contention, and CSI volume mount deadlocks.
tags:
  - gcp
  - gke
  - troubleshooting
  - runbook
  - sre
  - incident-response
---

# GKE SRE Incident Response & Production Troubleshooting Runbook 🚨🛠️

When high-severity incidents strike a production Google Kubernetes Engine cluster, SRE and Platform Engineering teams need immediate, deterministic root-cause workflows. This runbook documents the failure signatures, diagnostic commands, underlying Linux/Kubernetes kernel mechanics, and production remediation steps for the most common and catastrophic GKE failure modes: **CrashLoopBackOff**, **Node NotReady**, **OOMKilled (Exit Code 137)**, **Subnet IP Exhaustion (`PXC_K8S_POD_IP_RANGE_EXHAUSTED`)**, **CSI Volume Attachment Deadlocks**, and **Control Plane Latency**.

---

## 1. Diagnostic Decision Tree

```
                           KUBERNETES ALERT / INCIDENT FIRED
                                           │
             ┌─────────────────────────────┼─────────────────────────────┐
             ▼                             ▼                             ▼
       POD FAILURES                  NODE FAILURES                 STORAGE & NETWORK
     ┌──────────────┐              ┌──────────────┐              ┌──────────────┐
     │CrashLoopBack │              │ NodeNotReady │              │VolumeAttach  │
     │ OOMKilled    │              │ Kernel Panic │              │ Deadlock     │
     │ ImagePullErr │              │ DiskPressure │              │ IP Exhaustion│
     └──────┬───────┘              └──────┬───────┘              └──────┬───────┘
            │                             │                             │
            ▼                             ▼                             ▼
     Check Exit Code              Check Node Events             Check Secondary CIDR
     - 137: OOM Killed            - Kubelet status              - Subnet IP utilization
     - 1: App Exception           - GCE Serial Console          - GCE CSI Driver logs
     - 143: SIGTERM               - Node Auto-Repair            - Cloud Logging filter
```

---

## 2. Failure Signature 1: `CrashLoopBackOff` & Exit Code Taxonomy

When a container repeatedly starts, crashes, and restarts with exponential backoff delay (from 10s up to 300s):

```bash
# 1. Inspect Pod Status & Exit Code
kubectl get pod <POD_NAME> -n <NAMESPACE> -o jsonpath='{.status.containerStatuses[0].lastState.terminated}'

# 2. View logs from the PREVIOUS crashed instance
kubectl logs <POD_NAME> -n <NAMESPACE> --previous --tail=100

# 3. Check Kubernetes Event Stream
kubectl describe pod <POD_NAME> -n <NAMESPACE> | grep -A 10 Events:
```

### Exit Code Decision Table

| Exit Code | Root Cause | Engineering Remediation |
| :--- | :--- | :--- |
| **`137`** | **OOMKilled (Out Of Memory)** | Process exceeded cgroup memory limit (`limits.memory`); kernel sent `SIGKILL`. Increase memory limit or tune JVM heap (`-XX:MaxRAMPercentage=75.0`). |
| **`139`** | **Segmentation Fault (`SIGSEGV`)** | Application attempted to read/write unallocated memory. Debug C/C++/Go/Rust binary or native library bindings. |
| **`143`** | **Graceful Shutdown (`SIGTERM`)** | Container was asked to stop (e.g., node drain or preemption) but exceeded `terminationGracePeriodSeconds` and was killed. |
| **`1`** | **Application Exception** | Uncaught Python, Java, or Node runtime error (missing environment variable, bad config, database connection refusal). |
| **`126`** | **Command Cannot Be Executed** | File permissions issue (`chmod +x entrypoint.sh` missing) or bad binary format. |
| **`127`** | **File / Command Not Found** | Entrypoint script does not exist, or shebang line points to missing shell (`#!/bin/bash` in Alpine container). |

---

## 3. Failure Signature 2: Node `NotReady` & Kubelet Disconnections

A node transitions to `NotReady` when the master control plane fails to receive a node lease heartbeat from the Kubelet for more than 40 seconds.

### Root Cause Triaging

```bash
# 1. Identify the unready node
kubectl get nodes -o wide | grep NotReady

# 2. Inspect node conditions (DiskPressure, MemoryPressure, NetworkUnavailable)
kubectl describe node <NODE_NAME> | grep -A 10 Conditions:

# 3. View GCE Serial Port Output via gcloud
gcloud compute instances get-serial-port-output <NODE_NAME> \
    --zone=<ZONE> \
    --project=core-infrastructure-prod | tail -n 100

# 4. SSH into Node via OS Login (if SSH accessible)
gcloud compute ssh <NODE_NAME> --zone=<ZONE> --project=core-infrastructure-prod

# Inside the node: inspect Kubelet and containerd systemd service logs
sudo systemctl status kubelet
sudo journalctl -u kubelet -n 100 --no-pager
sudo journalctl -u containerd -n 100 --no-pager
```

### Common Triggers
- **Kernel OOM Starvation:** Pods without memory limits exhausted all physical RAM, forcing the Linux kernel OOM killer to terminate system daemons like `systemd-resolved` or `kubelet`.
- **Node Disk Pressure:** Root filesystem (`/dev/sda1`) reached 100% capacity due to massive unrotated Docker logs in `/var/log/pods`. Kubelet begins aggressive pod eviction.

---

## 4. Failure Signature 3: Subnet IP Exhaustion (`PXC_K8S_POD_IP_RANGE_EXHAUSTED`)

In GKE VPC-native clusters, each node receives an entire `/24` CIDR block (256 Pod IPs) from the subnet's secondary IP range by default.

### Symptom
When the cluster attempts to scale up, new nodes fail to initialize, and `gcloud container clusters describe` outputs:
`PXC_K8S_POD_IP_RANGE_EXHAUSTED: Pod CIDR range does not have enough available addresses.`

### Remediation Workflow

```bash
# 1. Calculate IP consumption on the Pod secondary range
gcloud compute networks subnets describe <SUBNET_NAME> \
    --region=us-central1 \
    --project=core-infrastructure-prod \
    --format="yaml(secondaryIpRanges)"

# 2. Check current node count vs maximum theoretical nodes:
# Formula: Max Nodes = 2^(32 - Subnet_Mask) / 256
# E.g., /20 Pod Range = 4,096 IPs / 256 = 16 Max Nodes!

# 3. Add an Additional Pod Secondary IP Range (Zero-Downtime)
gcloud compute networks subnets update <SUBNET_NAME> \
    --region=us-central1 \
    --add-secondary-ranges="gke-pods-expansion=10.200.0.0/16" \
    --project=core-infrastructure-prod

# 4. Bind the new range to the GKE Cluster
gcloud container clusters update prod-regional-cluster \
    --region=us-central1 \
    --add-pod-ipv4-ranges="gke-pods-expansion" \
    --project=core-infrastructure-prod
```

---

## 5. Failure Signature 4: Volume Attachment Deadlocks (CSI Storage)

When a stateful pod (e.g., Kafka or PostgreSQL) fails over to another node, the pod sits in `ContainerCreating` indefinitely.

### Diagnostic Command
```bash
kubectl describe pod <POD_NAME> -n <NAMESPACE> | grep -A 10 Events:
# Output:
# Warning FailedAttachVolume AttachVolume.Attach failed for volume "pvc-1234":
# Volume is already exclusively attached to node gke-prod-worker-abc
```

### Remediation Procedure
1. **Root Cause:** The old node crashed or lost network connectivity. The GCE Compute API still records the disk as attached to the dead VM. The Kubernetes `attach-detach-controller` will not attach a disk to a new VM while GCE reports it as attached elsewhere.
2. **Step 1: Verify the dead node status:**
   ```bash
   kubectl get node <DEAD_NODE>
   ```
3. **Step 2: Force detach disk via GCE CLI:**
   ```bash
   # Identify disk name
   DISK_NAME=$(kubectl get pv <PV_NAME> -o jsonpath='{.spec.csi.volumeHandle}')

   # Force detach from old VM
   gcloud compute instances detach-disk <DEAD_NODE_VM> \
       --disk="${DISK_NAME}" \
       --zone=<ZONE> \
       --project=core-infrastructure-prod
   ```
4. **Step 3:** The GKE CSI attacher will immediately detect the disk as free and attach it to the new node within 15 seconds.

---

## 6. Failure Signature 5: Control Plane Latency & etcd Contention

### Symptoms
- `kubectl get pods` takes 5 to 20 seconds to respond.
- Deployments fail to scale; HPA reports `unable to fetch metrics`.
- In-cluster admission webhooks time out.

### Root Cause Analysis in Cloud Logging
Execute this query in Google Cloud Logging:

```sql
resource.type="k8s_control_plane_component"
resource.labels.component_name="kube-apiserver"
jsonPayload.message=~"slow request" OR jsonPayload.message=~"etcd server call took too long"
```

### Common Triggers & Remediation
1. **High-Frequency CRD Watchers:** A broken controller or rogue deployment is querying `kube-apiserver` with full-cluster polling (`ResourceVersion=0`) without pagination. Inspect top API consumers in Cloud Monitoring (`apiserver_request_total`).
2. **Overloaded Secrets / ConfigMaps:** Hundreds of microservices mounting 50 MB ConfigMaps. Transition heavy configuration to GCS FUSE or external storage.
3. **Regional Master Failover:** In a regional cluster, if Zone A's master VM encounters maintenance, API traffic temporarily concentrates on the remaining two master replicas. GKE will automatically balance load within minutes.

---

## 7. Emergency Incident Response Checklist

During a P1 Outage on GKE, follow this structured runbook:

- [ ] **Step 1: Check Master API Health**
  `kubectl get --raw='/readyz?verbose'`
- [ ] **Step 2: Check Node Status**
  `kubectl get nodes -o wide | grep -v Ready`
- [ ] **Step 3: Check Cluster Autoscaler Logs**
  `kubectl get configmap cluster-autoscaler-status -n kube-system -o yaml`
- [ ] **Step 4: Check Pods Across All Namespaces in Non-Running State**
  `kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded`
- [ ] **Step 5: Check GKE Datapath V2 (Cilium) Pod Status**
  `kubectl get pods -n kube-system -l k8s-app=cilium`
- [ ] **Step 6: Check Quota Availability in GCP Console**
  Verify `CPUS_ALL_REGIONS` and `IN_USE_ADDRESSES` are below 90% utilization.
