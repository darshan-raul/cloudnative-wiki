---
title: GCP Spot VMs & Preemption Engineering
description: Compute Engine Spot VMs — preemption mechanics, 30-second ACPI shutdown notice, metadata polling, graceful draining, and fault-tolerant batch architectures.
tags:
  - gcp
  - compute
  - gce
  - spot-vms
  - finops
  - cost-optimization
---

# GCP Spot VMs & Preemption Engineering 💰⚡

Google Cloud Spot VMs provide dynamic access to unused Compute Engine capacity at **60% to 91% discounts** compared to standard on-demand pricing. In exchange for massive cost savings, Spot VMs are ephemeral: Google Cloud reserves the right to reclaim (preempt) the capacity at any moment when needed for on-demand workloads.

Mastering Spot VMs requires **Preemption Engineering**: designing stateful and stateless architectures that anticipate, detect, and gracefully respond to sudden terminations within Google's **30-second shutdown notice window**.

---

## Architecture & Mental Model

### The 30-Second Preemption Lifecycle

Unlike standard VMs that shut down on user demand, Spot VM termination is initiated externally by Google's global cluster scheduler (Borg):

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Google Borg Scheduler                           │
│        (Detects capacity deficit in zone: us-central1-a)               │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
       T = 0s: Preemption Signal Sent
       ├── 1. Hypervisor sends ACPI Power Off signal to Guest OS
       └── 2. Metadata Server sets:
              /computeMetadata/v1/instance/preempted = "TRUE"
                                    │
                                    ▼
       T = 0s to 30s: Graceful Shutdown Window
       ├── 1. Shutdown script executes (/var/run/google-shutdown-scripts)
       ├── 2. Monitoring daemon polls metadata server
       ├── 3. Application flushes dirty in-memory buffers to GCS / DB
       └── 4. Instance deregisters from Load Balancer / Kubernetes CNI
                                    │
                                    ▼
       T = 30s: Hard Termination
       └── Hypervisor forcefully cuts power (SIGKILL) & terminates VM
```

---

## Core Concepts

### 1. Spot VMs vs. Legacy Preemptible VMs

| Dimension | Legacy Preemptible VMs (Deprecated) | Modern Spot VMs (Current Standard) |
| :--- | :--- | :--- |
| **Max Runtime** | **Hard 24-Hour Limit:** Terminated automatically after 24 hours even if capacity is abundant | **No 24-Hour Limit:** Runs indefinitely for days, weeks, or months until reclaimed |
| **Pricing Discount** | Fixed 60% – 80% discount | Dynamic 60% – 91% discount reflecting real-time spare capacity |
| **Preemption Notice** | 30-second ACPI signal | 30-second ACPI signal |
| **CLI Flag** | `--preemptible` | `--provisioning-model=SPOT` |

### 2. The 30-Second Shutdown Window vs. AWS & Azure

* **AWS EC2 Spot:** Delivers a **2-minute** (120-second) warning via CloudWatch Events and IMDS.
* **Azure Spot VMs:** Delivers a **30-second** warning via Scheduled Events metadata.
* **GCP Spot VMs:** Delivers a strict **30-second** warning. Applications migrating from AWS to GCP must accelerate their draining and checkpointing logic by **4x**.

### 3. Detecting Preemption via Metadata Server

Applications or background sidecars can actively poll the link-local metadata server:

```bash
# Query the preemption status
curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/preempted"
```
* **Return Value:** Returns `FALSE` under normal operation. Changes immediately to `TRUE` the microsecond Google marks the instance for preemption.

### 4. High-Availability Spot Architectural Patterns

#### Pattern A: Mixed Spot & On-Demand MIGs
Never run 100% of a customer-facing production service on Spot VMs. Configure a Managed Instance Group with mixed provisioning models:
* **Base Capacity (e.g. 30%):** On-demand standard instances to guarantee minimum service uptime during widespread capacity crunches.
* **Surge Capacity (e.g. 70%):** Spot VMs that absorb traffic spikes at 80% discount.

#### Pattern B: Checkpointed Batch Processing (Cloud Batch / Dataproc)
For batch pipelines (transcoding, ETL, ML training):
* Break large tasks into discrete chunks taking <= 5 minutes.
* Store intermediate state in Cloud Storage or Cloud Spanner.
* When an instance is preempted, the task is re-queued and resumes from the last 5-minute checkpoint on a new node.

---

## Production `gcloud` CLI Commands

### 1. Creating a Standalone Spot VM with a Shutdown Script

```bash
gcloud compute instances create spot-batch-worker-01 \
  --zone=us-central1-a \
  --machine-type=c2-standard-8 \
  --provisioning-model=SPOT \
  --instance-termination-action=STOP \
  --network=prod-vpc \
  --subnet=prod-us-central1 \
  --no-address \
  --metadata=shutdown-script='#!/bin/bash
    echo "Preemption received! Uploading checkpoint to GCS..." >> /var/log/preemption.log
    gsutil cp /data/checkpoint.tar.gz gs://my-prod-checkpoints/$(hostname).tar.gz
    echo "Checkpoint flush complete." >> /var/log/preemption.log' \
  --boot-disk-size=100GB \
  --boot-disk-type=pd-balanced
```

* `--instance-termination-action=STOP`: Instead of permanently deleting the VM on preemption, GCP changes the state to `TERMINATED` (preserving attached disks for rapid restart when capacity reopens).

### 2. Configuring a Mixed Spot & On-Demand MIG

```bash
# Create an instance template specifically configured for Spot compute
gcloud compute instance-templates create spot-worker-template \
  --region=us-central1 \
  --machine-type=e2-standard-4 \
  --network=prod-vpc \
  --subnet=prod-us-central1 \
  --no-address \
  --provisioning-model=SPOT \
  --instance-termination-action=DELETE \
  --boot-disk-size=50GB \
  --boot-disk-type=pd-balanced
```

### 3. Graceful Drain Daemon Script (Python)

```python
#!/usr/bin/env python3
import time
import requests
import subprocess

METADATA_URL = "http://metadata.google.internal/computeMetadata/v1/instance/preempted"
HEADERS = {"Metadata-Flavor": "Google"}

def check_preemption():
    try:
        r = requests.get(METADATA_URL, headers=HEADERS, timeout=1)
        return r.text.strip().upper() == "TRUE"
    except Exception:
        return False

def drain_and_exit():
    print("Preemption signal detected! Draining worker...")
    # 1. Stop accepting new tasks from message queue
    subprocess.run(["systemctl", "stop", "celery-worker"], timeout=10)
    # 2. Flush write buffers to remote store
    subprocess.run(["sync"], timeout=5)
    print("Draining completed within 15 seconds.")

if __name__ == "__main__":
    while True:
        if check_preemption():
            drain_and_exit()
            break
        time.sleep(2)
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Spot vCPU Quota** | Separate regional quota from standard vCPUs | Must request `Preemptible/Spot CPUs` in Quotas console |
| **Preemption Notice Duration** | Exactly 30 seconds | Hard cutoff; hypervisor drops power at 30s |
| **Shutdown script timeout** | Default 30s for Spot | Fits precisely inside the 30-second ACPI window |
| **Daily Preemption Probability** | Typically 5% – 15% per day | Highly variable depending on zone, time, and instance shape |

---

## References

* **Spot VMs Overview:** https://cloud.google.com/compute/docs/instances/spot
* **Preemption Process & Notice:** https://cloud.google.com/compute/docs/instances/spot#preemption-process
* **Shutdown Scripts Guide:** https://cloud.google.com/compute/docs/instances/startup-scripts/linux#shutdown-scripts
* **Pricing:** https://cloud.google.com/compute/vm-instance-pricing#spot_pricing

---

## Pricing Examples

### Scenario 1: Machine Learning Batch Inference Pipeline
* 100 worker instances running `c2-standard-16` (Compute-optimized: 16 vCPU, 64 GB RAM).
* Pipeline runs for 10 hours every night (300 hours / month).
* Standard On-Demand cost: 100 × $0.675 / hr × 300 hrs = **$20,250.00 / month**.
* Spot VM rate (~80% discount): 100 × $0.135 / hr × 300 hrs = **$4,050.00 / month**.
* **Monthly Savings:** **$16,200.00 / month** (80% net reduction in cloud spend).

### Scenario 2: Continuous CI/CD Container Build Fleet
* 20 builder VMs using `e2-standard-8` (8 vCPU, 32 GB RAM) operating 24/7.
* On-Demand cost: 20 × $0.268 / hr × 730 hrs = $3,912.80 / month.
* Spot VM cost (~70% discount): 20 × $0.080 / hr × 730 hrs = **$1,168.00 / month**.
* **Total Monthly Savings:** **$2,744.80 / month**. Occasional build retries on preemption represent negligible engineering overhead.

---

## Nuggets & Gotchas

1. **The 30-Second Shutdown Hard Kill:** At exactly 30.0 seconds after the ACPI shutdown signal is sent, Google cuts power to the VM. If your application or shutdown script takes 31 seconds to compress a checkpoint archive, the file will be corrupted mid-write and the VM terminates. Ensure all shutdown tasks complete in under **20 seconds**.
2. **Preemptible Quota vs. Standard Quota Confusion:** Requesting a quota increase for standard Compute Engine CPUs in a region does **not** increase your Spot VM quota! Spot VMs are governed by a distinct quota called `Preemptible CPUs`. If you spin up a large Spot batch fleet without requesting this specific quota, all instance creations fail with `QUOTA_EXCEEDED`.
3. **Spot VMs Do Not Support In-Place Live Migration:** Standard Compute Engine VMs seamlessly live-migrate to new hardware hosts during hypervisor maintenance without downtime. Spot VMs **do not support Live Migration**; during host maintenance, a Spot VM is simply preempted and stopped.
4. **Persistent Disk Costs Continue While Stopped:** If you configure `--instance-termination-action=STOP`, the VM stops compute billing when preempted. However, its attached boot and data Persistent Disks remain provisioned and continue to incur standard monthly storage charges ($0.10/GB/month) until the instance is explicitly deleted.
5. **Zone-Specific Spot Availability Crises:** Spot availability fluctuates dynamically per availability zone based on real-time on-demand consumption. If `us-central1-a` experiences high demand, Spot VM creation in that zone will fail repeatedly with `ZONE_RESOURCE_POOL_EXHAUSTED`. Always design multi-zone or multi-region failover scripts that automatically target alternative zones (e.g. fallback to `us-central1-b` or `us-central1-f`).
