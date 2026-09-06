---
title: Azure Virtual Machines & Scale Sets (VMSS)
description: Azure Compute architecture — VM series, Virtual Machine Scale Sets (VMSS), Availability Zones vs Fault Domains, Spot VMs, Proximity Placement Groups, and Azure Bastion.
tags:
  - azure
  - compute
  - vms
  - vmss
  - infrastructure
---

# Azure Virtual Machines & Scale Sets (VMSS) 🖥️⚡

Azure Virtual Machines (VMs) provide on-demand, high-performance compute capacity across hundreds of hardware configurations. To manage fleets of identical or heterogeneous instances at scale, Azure provides **Virtual Machine Scale Sets (VMSS)** with automated load balancing, health probing, and auto-scaling.

---

## Architecture & Mental Model

### VM Series Decision Matrix

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Azure VM Series Guide                           │
├─────────────────┬─────────────────┬──────────────────┬─────────────────┤
│ B-Series        │ D-Series        │ E-Series         │ F-Series        │
│ (Burstable CPU) │ (General Core)  │ (Memory-Heavy)   │ (Compute-Heavy) │
├─────────────────┼─────────────────┼──────────────────┼─────────────────┤
│ Dev/test, low   │ Balanced CPU/RAM│ Databases, SAP,  │ Batch compute,  │
│ traffic web apps│ web & API apps  │ Redis, analytics │ video encoding  │
├─────────────────┴─────────────────┴──────────────────┴─────────────────┤
│ Specialized High-Performance Compute:                                  │
│ • M-Series: Extreme memory (up to 12 TB RAM for SAP HANA)              │
│ • ND / NC-Series: AI/ML training & inference (NVIDIA H100/A100 Tensor) │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Core Concepts

### 1. High Availability: Availability Zones vs. Availability Sets

| High Availability Topology | SLA | Resilience Scope |
| :--- | :--- | :--- |
| **Single VM with Premium SSD** | **99.9%** | Protects against individual drive failure; no hardware host resilience |
| **Availability Set (Legacy)** | **99.95%** | Distributes VMs across isolated **Fault Domains (FDs)** (separate power/racks) and **Update Domains (UDs)** inside a single datacenter |
| **Availability Zones (Modern Standard)**| **99.99%** | Distributes VMs across physically separate datacenter facilities (Zones 1, 2, 3) with independent power, cooling, and network |

### 2. Virtual Machine Scale Sets (VMSS): Flexible vs. Uniform

* **Uniform Orchestration (Legacy):** Identical VMs deployed from a single golden image. Limited flexibility.
* **Flexible Orchestration (Modern Standard):**
  * Allows mixing multiple VM sizes and architectures within the same scale set.
  * Dynamically mixes **Spot VMs** and **On-Demand VMs** to optimize cloud spend.
  * Provides granular control over individual VM instances within the scale set.

### 3. Spot VMs & Scheduled Events

* **Spot VMs:** Up to 90% discount on unused Azure capacity.
* **Eviction Notice:** Azure can evict a Spot VM when capacity is reclaimed. The instance is provided a **30-second eviction notice** via Azure Scheduled Events metadata.
* **Scheduled Events Query:**
```bash
curl -H Metadata:true http://169.254.169.254/metadata/scheduledevents?api-version=2020-07-01
```

### 4. Proximity Placement Groups (PPGs)

For workloads requiring microsecond network latency between nodes (e.g., high-frequency trading or multi-node MPI clustering):
* A **Proximity Placement Group (PPG)** physically co-locates compute hardware within the exact same server rack or datacenter hall, reducing inter-VM latency to under **0.5 milliseconds**.

### 5. Azure Bastion (Zero-Exposure Remote Access)

Azure Bastion provides fully managed RDP and SSH connectivity directly through the Azure Portal or browser over SSL (Port 443):
* VMs require **no public IP addresses**.
* Eliminates the need for exposing port 22 or 3389 to internet port scanners.

---

## Production `az` CLI Commands

### 1. Creating a Hardened Production Linux VM in an Availability Zone

```bash
az vm create \
  --resource-group prod-compute-rg \
  --name prod-api-vm-01 \
  --location eastus \
  --zone 1 \
  --image Ubuntu2204 \
  --size Standard_D4s_v5 \
  --vnet-name prod-vnet-eastus \
  --subnet snet-workloads \
  --public-ip-address "" \
  --assign-identity \
  --generate-ssh-keys \
  --os-disk-size-gb 64 \
  --storage-sku Premium_LRS
```

### 2. Deploying a Flexible Virtual Machine Scale Set with Autoscaling

```bash
# 1. Create the Flexible VMSS across 3 availability zones
az vmss create \
  --resource-group prod-compute-rg \
  --name vmss-web-fleet \
  --orchestration-mode Flexible \
  --location eastus \
  --zones 1 2 3 \
  --image Ubuntu2204 \
  --vm-sku Standard_D2s_v5 \
  --instance-count 3 \
  --vnet-name prod-vnet-eastus \
  --subnet snet-workloads \
  --public-ip-per-vm false \
  --load-balancer alb-internal-services

# 2. Add autoscale rule (Scale out when average CPU > 75% for 5 mins)
az monitor autoscale create \
  --resource-group prod-compute-rg \
  --resource vmss-web-fleet \
  --resource-type Microsoft.Compute/virtualMachineScaleSets \
  --name autoscale-web \
  --min-count 3 \
  --max-count 15 \
  --count 3

az monitor autoscale rule create \
  --resource-group prod-compute-rg \
  --autoscale-name autoscale-web \
  --condition "Percentage CPU > 75 avg 5m" \
  --scale out 2
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Total Regional vCPUs** | 20–100 vCPUs (default) | Increase via Azure Portal Quotas blade |
| **Spot vCPUs per region** | Separate quota tier | Request increase before launching large Spot clusters |
| **Instances per Flexible VMSS** | Up to 1,000 instances | Scalable for massive compute tiers |
| **Data disks per VM** | Up to 64 disks | Dependent on VM size (e.g. 2 disks per vCPU) |

---

## References

* **Homepage:** https://azure.microsoft.com/en-us/products/virtual-machines
* **VM Series Guide:** https://learn.microsoft.com/en-us/azure/virtual-machines/sizes
* **VMSS Overview:** https://learn.microsoft.com/en-us/azure/virtual-machine-scale-sets/overview
* **Azure Bastion Overview:** https://learn.microsoft.com/en-us/azure/bastion/bastion-overview
* **Pricing:** https://azure.microsoft.com/en-us/pricing/details/virtual-machines/

---

## Pricing Examples

### Scenario 1: Multi-Zone Production Web Tier (Reserved Instances)
* 6 instances of `Standard_D4s_v5` (4 vCPU, 16 GB RAM) running 24/7 across Zones 1, 2, 3.
* On-Demand rate: 6 × $0.192 / hr × 730 hrs = **$840.96 / month**.
* With a **3-Year Azure Reserved VM Instance (RI)**:
  * 62% discount applied ($0.073 / hr).
* **Effective Monthly Compute Bill:** **~$320.00 / month** (Saving $520/month).

### Scenario 2: Batch Processing with VMSS Spot Instances
* 50 worker VMs using `Standard_F8s_v2` (Compute-optimized: 8 vCPU, 16 GB RAM).
* Job runs for 20 hours per week (80 hours / month).
* Standard On-Demand cost: 50 × $0.338 / hr × 80 hrs = $1,352.00.
* Spot discount (~85% savings): 50 × $0.0507 / hr × 80 hrs = **$202.80 / month**.
* **Monthly Savings:** **$1,149.20** per month.

---

## Nuggets & Gotchas

1. **The Burstable B-Series Credit Cliff:** `B-series` instances accumulate credits during low CPU utilization. When credits are exhausted during sustained traffic surges, the CPU is hard-throttled to its baseline performance (as low as 10%–20% of 1 core), causing web apps to become completely unresponsive. Never run production databases or latency-sensitive APIs on B-series VMs.
2. **Deallocated vs. Stopped Billing State:** Stopping a VM from inside the guest OS (e.g. `sudo shutdown -h now`) places the VM in a **"Stopped"** state; Azure still reserves the physical hardware host and **continues charging you full compute prices**! You must stop the VM via the Azure Portal or CLI (`az vm deallocate`) so the state changes to **"Stopped (Deallocated)"** to stop compute billing.
3. **Availability Zones vs. Regional Disk Locks:** If a VM in Zone 1 crashes, its attached Zonal Managed Disk cannot be attached to a VM in Zone 2. Availability Zones are physically isolated hardware boundaries. For cross-zone disk failover, stateful applications must replicate data at the software layer or use Azure NetApp Files / shared filesystems.
4. **Scheduled Events Polling Requirement:** Azure notifies VMs of Spot preemption, host maintenance, and reboots via the Scheduled Events API at `http://169.254.169.254/metadata/scheduledevents`. However, unlike push notifications, your application or monitoring daemon **must continuously poll this endpoint every 1–5 seconds** to catch the 30-second shutdown notice.
5. **Azure Bastion Subnet Sizing:** Azure Bastion requires a dedicated subnet named strictly `AzureBastionSubnet`. The subnet must be at least `/26` to support scaling. If created as a `/27` or smaller, Bastion will fail to provision or scale during multi-user sessions.
