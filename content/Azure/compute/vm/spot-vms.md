---
title: Azure Spot VMs & Scheduled Events Eviction Engineering
description: Exhaustive engineering guide to Azure Spot Virtual Machines — unallocated compute capacity, eviction policies, Azure Scheduled Events API polling (30-second notice), graceful draining, and resilient batch architectures.
tags:
  - azure
  - compute
  - spot-vms
  - finops
  - resilience
---

# Azure Spot VMs & Scheduled Events Eviction Engineering 📉⚡

Azure **Spot Virtual Machines** allow organizations to access unused Azure compute capacity at steep discounts (up to **90% off** standard pay-as-you-go rates). In exchange for deep cost savings, Azure reserves the right to evict (preempt) these instances whenever Azure requires the compute capacity back for full-price pay-as-you-go workloads, or when the market spot price exceeds the user's configured maximum bid. Engineering mission-critical or batch systems on Spot VMs requires handling the **Azure Scheduled Events API**, which delivers an automated **30-second preemption notice**.

---

## 1. Architecture & Eviction Mechanics

Unlike standard Azure Virtual Machines that operate with a 99.9% to 99.99% availability SLA, Spot VMs carry **no availability SLA**. They are provisioned from dynamic hardware pools across Azure data centers.

```
                           AZURE INFRASTRUCTURE CONTROLLER
                                          │
            ┌─────────────────────────────┴─────────────────────────────┐
            │ Capacity Shortage OR Market Price > Max Price             │
            ▼                                                           │
    ┌────────────────────────────────────────────────────────────────┐  │
    │              AZURE SCHEDULED EVENTS METADATA SERVICE           │  │
    │                   (http://169.254.169.254)                     │  │
    │                                                                │  │
    │  - Continuously polls: /metadata/scheduledevents?api-version   │  │
    │  - Emits: EventType="Preempt"                                  │  │
    │  - Countdown Timer: Exactly 30 Seconds                         │  │
    └──────────────────────────────┬─────────────────────────────────┘  │
                                   │ Notification Payload               │
                                   ▼                                    │
    ┌────────────────────────────────────────────────────────────────┐  │
    │                   SPOT VM GUEST OPERATING SYSTEM               │  │
    │                                                                │  │
    │  ┌──────────────────────────────────────────────────────────┐  │  │
    │  │               DAEMON / AGENT WATCHER PROCESS             │  │  │
    │  │  1. Receives Preempt event via metadata socket            │  │  │
    │  │  2. Triggers Kubernetes `kubectl drain --grace-period=25`│  │  │
    │  │  3. Flushes dirty application buffers to Blob / Redis    │  │  │
    │  │  4. Acknowledges event back to Scheduled Events API      │  │  │
    │  └──────────────────────────────────────────────────────────┘  │  │
    └──────────────────────────────┬─────────────────────────────────┘  │
                                   │ 30 Seconds Elapsed                 │
                                   ▼                                    │
    ┌────────────────────────────────────────────────────────────────┐  │
    │                 AZURE FABRIC HARD TERMINATION                  │  │
    │  - Deallocate (disk/IP retained) OR Delete (everything purged) ◄──┘
    └────────────────────────────────────────────────────────────────┘
```

### Eviction Triggers & Policies

1. **Eviction Triggers:**
   - **Capacity-Only:** Eviction occurs *only* when Azure needs the physical CPU/RAM capacity back for pay-as-you-go customers. The customer pays the current dynamic spot price up to the regular on-demand cap.
   - **Price or Capacity:** The customer sets a strict `max-price` cap (e.g., $0.05/hr). Eviction occurs if either Azure requires capacity *or* the market spot price rises above the configured cap.
2. **Eviction Policy Options:**
   - **Deallocate (Default):** The VM is shut down and its compute cores are released. The attached OS managed disk and data disks persist, retaining all data and IP assignments (storage costs continue to accrue). The VM can be manually or programmatically restarted later when spot capacity returns.
   - **Delete:** The VM and its ephemeral or attached managed disks are permanently destroyed upon eviction. This eliminates lingering storage charges and is optimal for stateless batch workers and Kubernetes nodes.

---

## 2. Core Concepts: Scheduled Events API

The **Azure Scheduled Events API** is an internal metadata service endpoint exposed inside the VM at non-routable link-local IP `http://169.254.169.254/metadata/scheduledevents`.

### Polling Mechanics

The guest OS must execute a daemon that queries this endpoint at regular intervals (recommended: **every 1 second** for Spot VMs):

```bash
curl -H "Metadata: true" -s \
  "http://169.254.169.254/metadata/scheduledevents?api-version=2020-07-01"
```

When an eviction is scheduled, the response contains:
```json
{
  "DocumentIncarnation": 1,
  "Events": [
    {
      "EventId": "80CF2D9C-42F7-40DF-9E2A-1456D380AB9B",
      "EventStatus": "Scheduled",
      "EventType": "Preempt",
      "ResourceType": "VirtualMachine",
      "Resources": ["spot-worker-vm-01"],
      "NotBefore": "Sun, 06 Sep 2026 12:55:30 GMT"
    }
  ]
}
```

The `NotBefore` field indicates the exact timestamp when Azure will forcefully power off the hypervisor slot—guaranteeing a minimum **30-second window** for the guest to checkpoint state.

---

## 3. Production Deployment & Management CLI (`az`)

### 1. Deploy a Standalone Spot VM with Capacity Eviction Policy

```bash
# Deploy Spot VM that deallocates on preemption
az vm create \
    --resource-group rg-compute-prod \
    --name vm-spot-batch-01 \
    --image Ubuntu2204 \
    --size Standard_D4s_v5 \
    --priority Spot \
    --eviction-policy Deallocate \
    --max-price -1 \
    --admin-username azureuser \
    --generate-ssh-keys
```
*(Note: `--max-price -1` specifies that the VM will not be evicted due to price fluctuations; it will only be evicted if Azure runs out of physical hardware capacity).*

### 2. Deploy a Spot Virtual Machine Scale Set (VMSS) with Delete Policy

Deploy a horizontally autoscaling scale set for stateless render workers:

```bash
az vmss create \
    --resource-group rg-compute-prod \
    --name vmss-spot-workers \
    --image Ubuntu2204 \
    --vm-sku Standard_E8s_v5 \
    --priority Spot \
    --eviction-policy Delete \
    --max-price -1 \
    --instance-count 5 \
    --single-placement-group false \
    --upgrade-policy-mode Automatic \
    --admin-username azureuser \
    --generate-ssh-keys
```

### 3. Deploy AKS Spot Node Pool with Automated Taints

For Kubernetes workloads, deploy dedicated Spot node pools with Kubernetes taints so only tolerant pods are scheduled:

```bash
az aks nodepool add \
    --resource-group rg-aks-prod \
    --cluster-name aks-core-prod \
    --name spotpool01 \
    --priority Spot \
    --eviction-policy Delete \
    --spot-max-price -1 \
    --node-vm-size Standard_D8s_v5 \
    --node-count 3 \
    --enable-cluster-autoscaler \
    --min-count 1 \
    --max-count 20 \
    --node-taints "kubernetes.azure.com/scalesetpriority=spot:NoSchedule" \
    --labels "environment=batch" "cost-center=analytics"
```

### 4. Deploy Production Graceful Eviction Daemon (`spot-drainer.py`)

Run this Python 3 script as a `systemd` service inside the Spot VM to intercept eviction events and gracefully drain processes:

```python
#!/usr/bin/env python3
import json
import time
import urllib.request
import os
import subprocess

METADATA_URL = "http://169.254.169.254/metadata/scheduledevents?api-version=2020-07-01"
HEADERS = {"Metadata": "true"}

def poll_scheduled_events():
    req = urllib.request.Request(METADATA_URL, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=2) as response:
            data = json.loads(response.read().decode("utf-8"))
            for event in data.get("Events", []):
                if event.get("EventType") == "Preempt":
                    handle_eviction(event["EventId"])
    except Exception as e:
        print(f"Error polling metadata: {e}")

def handle_eviction(event_id):
    print("ALERT: Eviction notice received! 30 seconds remaining.")
    # 1. Kubernetes Node Drain (if AKS node)
    subprocess.run(["kubectl", "drain", os.uname().nodename, "--ignore-daemonsets", "--delete-emptydir-data", "--force", "--grace-period=20"])
    
    # 2. Stop application gracefully
    subprocess.run(["systemctl", "stop", "batch-worker-service"])
    
    # 3. Acknowledge the event to Azure
    ack_url = "http://169.254.169.254/metadata/scheduledevents?api-version=2020-07-01"
    ack_data = json.dumps({"StartRequests": [{"EventId": event_id}]}).encode("utf-8")
    ack_req = urllib.request.Request(ack_url, data=ack_data, headers=HEADERS, method="POST")
    urllib.request.urlopen(ack_req, timeout=2)
    print("Preempt event acknowledged. Ready for poweroff.")

if __name__ == "__main__":
    while True:
        poll_scheduled_events()
        time.sleep(1)
```

---

## 4. Quotas, Eviction Rates, and VM Family Matrix

| VM Family | General Workload Fit | Historical Eviction Rate | Typical Spot Discount |
| :--- | :--- | :--- | :--- |
| **Standard D-Series (D4s, D8s v5)** | General compute, web apps, microservices | Low (5% - 10%) | 60% - 80% |
| **Standard E-Series (E8s, E16s v5)**| In-memory caching, Spark, big data | Moderate (10% - 15%) | 70% - 85% |
| **Standard F-Series (F8s, F16s v2)**| Batch transcoding, CI/CD runners | Low (5% - 10%) | 75% - 90% |
| **Standard NC / ND-Series (GPU)**   | AI model training, LLM inference | **High (20% - 40%+)** | 50% - 70% |
| **Notice Duration** | **30 seconds** | Fixed platform constraint via Scheduled Events API |
| **SLA Guarantee** | **0.0% (None)** | Cannot be used for single-instance stateful production DBs |

---

## 5. Official References & Documentation

- [Azure Spot Virtual Machines Overview](https://learn.microsoft.com/en-us/azure/virtual-machines/spot-vms)
- [Azure Scheduled Events Metadata API](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/scheduled-events)
- [Use Azure Spot Virtual Machines in Azure Kubernetes Service (AKS)](https://learn.microsoft.com/en-us/azure/aks/spot-node-pool)
- [Spot VM Eviction Rate & Historical Pricing Advisor](https://learn.microsoft.com/en-us/azure/virtual-machines/spot-vms#pricing-and-eviction-history)
- [Azure Spot Pricing Portal](https://azure.microsoft.com/en-us/pricing/spot/)

---

## 6. Realistic Pricing Scenarios

Azure Spot VM pricing fluctuates dynamically based on demand in each specific Azure region and data center zone.

### Scenario A: High-Throughput Video Transcoding Fleet (F-Series Compute)

- **Architecture:**
  - Fleet of 20 `Standard_F8s_v2` instances (8 vCPU, 16 GiB RAM).
  - Workload: Runs batch transcoding queues from Azure Service Bus 12 hours/day (360 hours/month).
  - Standard Pay-As-You-Go Rate: $0.338 per hour.
  - Current Azure Spot Rate in `East US`: ~$0.068 per hour (**~80% discount**).
- **Monthly Cost Comparison:**
  - Standard Pay-As-You-Go: $20 \times \$0.338/\text{hr} \times 360 \text{ hrs} = \mathbf{\$2{,}433.60}$
  - Azure Spot Fleet: $20 \times \$0.068/\text{hr} \times 360 \text{ hrs} = \mathbf{\$489.60}$
- **Net Monthly Savings:** **$1,944.00 / month** ($23,328/year).

### Scenario B: Distributed Apache Spark & Big Data Analytics (E-Series Memory)

- **Architecture:**
  - 50 worker nodes running `Standard_E16s_v5` (16 vCPU, 128 GiB RAM).
  - Runs continuous nightly ETL workloads (8 hours/night = 240 hours/month).
  - Standard Pay-As-You-Go Rate: $1.008 per hour.
  - Azure Spot Rate: $0.181 per hour (**82% discount**).
  - Attached OS Disks: 50 × 128 GB Standard SSD ($9.60/disk-month = $480.00).
- **Monthly Cost Comparison:**
  - Standard Pay-As-You-Go Compute: $50 \times \$1.008/\text{hr} \times 240 \text{ hrs} = \mathbf{\$12{,}096.00}$
  - Spot Compute: $50 \times \$0.181/\text{hr} \times 240 \text{ hrs} = \mathbf{\$2{,}172.00}$
  - Storage Disks: $480.00
- **Net Total Spot Spend:** **$2,652.00 / month** (versus $12,576.00 on-demand).

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **The 30-Second Eviction Window is Non-Negotiable:** AWS EC2 Spot instances provide a 2-minute (120-second) warning via CloudWatch/Metadata; Google Cloud Spot VMs provide 30 seconds; **Azure Spot VMs provide exactly 30 seconds**. If your application takes 45 seconds to gracefully flush memory buffers to disk, it will be forcefully terminated mid-write, resulting in corrupted local files. Architecture rule: any write buffer on a Spot VM must be flushed in $\le 15$ seconds, or state must be written synchronously to remote storage (Blob/Cosmos DB).
2. **Deallocate vs Delete Policy Storage Leaks:** If you deploy a Spot VM or VMSS with `--eviction-policy Deallocate`, when Azure evicts 50 VMs during a peak load event, the compute cores are deallocated, but **the attached 128 GB Premium SSD OS disks remain provisioned in your subscription**. You will continue paying standard monthly disk storage fees for dozens of stopped VMs unless your automation cleans them up. For stateless batch workloads, always specify `--eviction-policy Delete`.
3. **Never Mix Spot and System Pools in AKS:** System node pools in AKS run critical cluster services including CoreDNS, metrics-server, and the CSI storage drivers. If you run system pods on Spot node pools and an Azure eviction storm strikes, CoreDNS pods are terminated, immediately breaking DNS resolution for the entire Kubernetes cluster. Always dedicate a small, stable, pay-as-you-go node pool for system pods (`CriticalAddonsOnly=true:NoSchedule`) and restrict Spot nodes to user workloads.
4. **Use Spot Allocation Strategy `Capacity-Optimized` in VMSS:** When deploying Virtual Machine Scale Sets with Spot VMs, set the orchestration mode to Flexible and configure the Spot allocation strategy to `Capacity-Optimized`. Azure will automatically analyze regional hardware availability across multiple VM sizes and provision instances in the specific fault domains and sizes that have the lowest risk of eviction.
5. **Spot Max Price Set to `-1` Avoids Market Bidding Flips:** Early Spot VM adopters frequently tried to set explicit max price caps (e.g., $0.08/hr). If the spot market price temporarily spikes to $0.081 for 10 minutes, Azure evicts all your instances even though hardware capacity was abundant. Setting `--max-price -1` caps your maximum price at the standard on-demand rate, ensuring you are never evicted due to pricing spikes—only due to genuine physical hardware shortages.
6. **Deploy Node Termination Handler for AKS:** Instead of writing custom Python metadata polling daemons for Kubernetes, deploy the open-source **Azure Scheduled Events Proxy** or **Node Termination Handler**. It automatically listens to `http://169.254.169.254`, marks the Kubernetes node as `Unschedulable` (cordoned), and initiates pod eviction with `kubectl drain` the microsecond Azure issues a `Preempt` notification.
