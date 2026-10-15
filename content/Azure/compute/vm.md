---
title: Azure Virtual Machines & Scale Sets (VMSS)
description: Exhaustive engineering guide to Azure Virtual Machines (VMs) and VMSS — decoupled ARM resource models, VM lifecycle and deallocation billing mechanics, Ephemeral OS disks, IMDS, VM series, Availability Zones, and Flexible Scale Sets.
tags:
  - azure
  - compute
  - vms
  - vmss
  - infrastructure
  - linux
date: 2026-10-16
---

# Azure Virtual Machines & Scale Sets (VMSS) 🖥️⚡

Azure Virtual Machines (VMs) provide on-demand, high-performance compute capacity across hundreds of hardware configurations powered by the **Azure Hyper-V / Cloud Hypervisor** virtualization stack.

Unlike traditional bare-metal or monolithic VPS providers, an Azure VM is an **orchestration of decoupled ARM resources** (Compute, Storage, Network, and Identity). Understanding this decoupled resource model and the VM lifecycle state machine is foundational to preventing cloud billing leaks and architecting resilient compute tiers with **Virtual Machine Scale Sets (VMSS)**.

---

## 1. Single-VM Architecture & Decoupled Resource Model

In Azure Resource Manager (ARM), a "virtual machine" is not a single atomic object. Creating a VM provisions and binds multiple independent resources that maintain separate lifecycles:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              Azure Resource Group Boundary                             │
│                                                                                        │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │                      Microsoft.Compute/virtualMachines                         │   │
│   │                              (Compute Shell)                                   │   │
│   │  - CPU / RAM allocation (e.g., Standard_D4s_v5)                                │   │
│   │  - Hypervisor scheduling & hardware host assignment                            │   │
│   │  - System-Assigned Managed Identity (OAuth2 Token Authority)                  │   │
│   │  - VM Extensions (AzureMonitorLinuxAgent, AADLoginForLinux)                    │   │
│   └──────────────┬────────────────────────┬────────────────────────┬───────────────┘   │
│                  │                        │                        │                   │
│         Binds vNIC                       Binds OS Disk            Binds Data Disks     │
│                  ▼                        ▼                        ▼                   │
│   ┌────────────────────────┐┌────────────────────────┐┌────────────────────────┐       │
│   │Microsoft.Network/      ││Microsoft.Compute/      ││Microsoft.Compute/      │       │
│   │networkInterfaces       ││disks (OS Disk)         ││disks (Data LUNs)       │       │
│   │(vNIC)                  ││- Premium SSD v1/v2     ││- Ultra Disk / SSD      │       │
│   │- Private IP (10.10.1.5)││- Ephemeral NVMe Cache  ││- Up to 64 LUNs         │       │
│   │- Accelerated Net (SRIOV││- Host Caching: ReadOnly││- Host Caching: None/RO │       │
│   └──────────┬─────────────┘└────────────────────────┘└────────────────────────┘       │
│              │                                                                         │
│     Attached to Subnet                                                                 │
│              ▼                                                                         │
│   ┌────────────────────────┐┌────────────────────────┐                                 │
│   │Microsoft.Network/      ││Microsoft.Network/      │                                 │
│   │virtualNetworks/subnets ││publicIPAddresses       │                                 │
│   │(snet-workloads)        ││(Optional Standard PIP) │                                 │
│   └────────────────────────┘└────────────────────────┘                                 │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

### Decoupled Lifecycle Implications

1. **Independent Deletion:** Deleting an Azure VM through the Azure Portal or API leaves the **OS Disk, Data Disks, and Network Interface (vNIC) active** by default. Orphaned managed disks will continue accruing storage charges indefinitely unless `deleteOption: Delete` is explicitly configured on the VM's disk and network attachments.
2. **Dynamic Resizing:** Modifying a VM's size (`Standard_D4s_v5` to `Standard_E8s_v5`) unbinds the compute shell from its current physical hypervisor blade, pauses execution, and schedules the existing vNICs and Disks onto a new host blade with the desired CPU/RAM capacity.
3. **VM Extensions:** Lightweight in-guest daemons managed by the Azure Linux Guest Agent (`waagent`). Extensions handle post-deployment bootstrap (`CustomScriptExtension`), domain joining, and telemetry forwarding without opening SSH ports.

---

## 2. VM Lifecycle States & The "Stopped" Billing Trap

Azure VMs transition through strict lifecycle states. The most critical operational distinction is between **Stopped (Allocated)** and **Stopped (Deallocated)**:

```
                            Azure VM Lifecycle State Machine
                                           │
                                    [ Provisioning ]
                                           │
                                           ▼
                                      [ Starting ]
                                           │
                                           ▼
                                      ┌──────────┐
                                      │ Running  │ ◄─── (Billed: Compute + Storage)
                                      └────┬─────┘
                     Guest OS Shutdown     │      az vm deallocate / Portal Stop
                  (sudo shutdown -h now)   │
                                           ▼
        ┌──────────────────────────────────────────────────────────────────────┐
        │                        STOPPED (ALLOCATED)                           │
        │  - Guest OS is halted; CPU/RAM remains pinned on physical host blade.│
        │  - Private IP is preserved; hypervisor reservations remain active.   │
        │  - ⚠️ 100% OF COMPUTE (CPU/RAM) AND STORAGE BILLING CONTINUES!        │
        └──────────────────────────────────┬───────────────────────────────────┘
                                           │
                                           ▼ az vm deallocate
        ┌──────────────────────────────────────────────────────────────────────┐
        │                       STOPPED (DEALLOCATED)                          │
        │  - Hardware blade is released back to the Azure regional pool.       │
        │  - Compute billing drops to EXACTLY $0.00/hour.                      │
        │  - Attached Managed Disks and Static Public IPs continue billing.    │
        └──────────────────────────────────────────────────────────────────────┘
```

> [!CAUTION]
> If a script or sysadmin executes `sudo poweroff`, `sudo shutdown -h now`, or `Stop-Computer` from inside the operating system, the VM enters the **Stopped (Allocated)** state. **Azure will continue to bill full hourly compute rates for the VM.** To stop compute charges, you must execute `az vm deallocate` or stop the VM from the Azure Portal/CLI.

---

## 3. OS Storage: Persistent Managed Disks vs. Ephemeral OS Disks

Every Azure VM requires an operating system disk. Azure provides two distinct architectures:

| Architectural Metric | Persistent Managed OS Disk                             | Ephemeral OS Disk                                            |
| :------------------- | :----------------------------------------------------- | :----------------------------------------------------------- |
| **Storage Location** | Remote Azure Storage cluster over network fabric       | **Local NVMe SSD or Hypervisor OS Cache** on host blade      |
| **Latency**          | 1–3 ms (Network round-trip)                            | **< 0.1 ms (Sub-millisecond native bus speed)**              |
| **Storage Cost**     | Standard Managed Disk billing (e.g. $19.71/mo for P10) | **$0.00 / month (Completely Free)**                          |
| **Persistence**      | Data persists across VM deallocation & reboots         | Data is wiped whenever the VM is deallocated or moved        |
| **Re-image Time**    | Minutes (Remote disk copy)                             | **Seconds (Instant local wipe & re-clone)**                  |
| **Best For**         | Stateful servers, databases, domain controllers        | **Stateless workloads, AKS node pools, CI/CD runners, VMSS** |

---

## 4. Azure Instance Metadata Service (IMDS)

Every Azure VM can communicate with the non-routable link-local endpoint **`http://169.254.169.254/metadata/`** directly from the guest OS without internet access. All requests strictly require the header `Metadata: true`.

```bash
# 1. Query VM Compute Metadata (Zone, Region, VM ID, Fault Domain)
curl -s -H Metadata:true "http://169.254.169.254/metadata/instance?api-version=2021-02-01" | jq .compute

# 2. Acquire Microsoft Entra ID Access Token via System-Assigned Managed Identity
curl -s -H Metadata:true "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/" | jq .access_token

# 3. Poll Scheduled Events (Maintenance, Reboot, and Spot Eviction Alerts)
curl -s -H Metadata:true "http://169.254.169.254/metadata/scheduledevents?api-version=2020-07-01" | jq .
```

---

## 5. VM Hardware Specialization & Series Matrix

Azure organizes instance types into purpose-built families identified by prefix letters:

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

### Series Naming Convention Taxonomy (e.g. `Standard_D8ads_v5`)

- **`Standard_`**: Standard production tier (vs Basic).
- **`D`**: Family series (General Purpose).
- **`8`**: Number of virtual CPUs (vCPUs).
- **`a`**: AMD processor (no letter = Intel Xeon; `p` = Ampere Altra ARM64).
- **`d`**: Direct local temporary disk attached (temp NVMe/SSD present).
- **`s`**: Premium SSD compatible (supports managed disk bursting and encryption).
- **`v5`**: Hardware generation / architecture version.

---

## 6. High Availability & Resilience Topologies

| HA Topology                              | SLA        | Resilience Scope & Failure Domain                                                                                                                        |
| :--------------------------------------- | :--------- | :------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Single VM with Premium SSD**           | **99.9%**  | Protects against individual drive failure; zero hardware host failure resilience.                                                                        |
| **Availability Set (Legacy)**            | **99.95%** | Distributes VMs across separate **Fault Domains (FDs)** (independent rack power/switches) and **Update Domains (UDs)** inside a single datacenter.       |
| **Availability Zones (Modern Standard)** | **99.99%** | Distributes VMs across physically isolated datacenter facilities (Zones 1, 2, 3) with independent power, cooling, and low-latency optical interconnects. |

---

## 7. Virtual Machine Scale Sets (VMSS): Flexible vs. Uniform

VMSS enables deploying and managing identical or heterogeneous fleets of auto-scaling instances:

- **Uniform Orchestration (Legacy):** Identical VMs deployed from a single golden OS image. Lacks individual VM management and cannot mix Spot with On-Demand instances.
- **Flexible Orchestration (Modern Standard):**
  - Mixes multiple VM series, sizes, and generations in the same pool.
  - Mixes **Spot VMs** and **On-Demand VMs** within the same autoscaling set.
  - Native integration with Azure Load Balancer backend pools and AKS Node Auto-Provisioning.

---

## 8. Spot VMs, Eviction Notices & PPGs

### Spot VMs & 30-Second Eviction Notice

- **Cost Savings:** Unallocated Azure datacenter capacity offered at up to **90% discount**.
- **Eviction Triggers:** Capacity reclaiming or current Spot market price exceeding your defined maximum bid.
- **Eviction Notice:** Delivered via the **Scheduled Events API** (`/metadata/scheduledevents`). Applications have **exactly 30 seconds** to flush write buffers, checkpoint state, and deregister from load balancers.

### Proximity Placement Groups (PPGs)

For ultra-low latency compute clusters (e.g., SAP application-to-database tiers or high-frequency trading):

- A **Proximity Placement Group (PPG)** physically pins VMs within the same server rack or row in a datacenter hall, reducing inter-VM latency to **< 0.5 milliseconds**.

---

## 9. Production `az` CLI Workflows

### 1. Creating a Production Linux VM with Ephemeral OS & Accelerated Networking

```bash
# 1. Create Resource Group
az group create --name rg-compute-prod --location eastus

# 2. Deploy hardened VM with Ephemeral OS disk, Accelerated Networking, and Managed Identity
az vm create \
  --resource-group rg-compute-prod \
  --name vm-api-prod-01 \
  --location eastus \
  --zone 1 \
  --image Ubuntu2204 \
  --size Standard_D4ds_v5 \
  --vnet-name vnet-workloads-eastus \
  --subnet snet-apps \
  --public-ip-address "" \
  --accelerated-networking true \
  --ephemeral-os-disk true \
  --os-disk-placement ResourceDisk \
  --assign-identity \
  --generate-ssh-keys
```

### 2. Deploying a Flexible VMSS with Autoscaling

```bash
# 1. Create Flexible VMSS across 3 Availability Zones
az vmss create \
  --resource-group rg-compute-prod \
  --name vmss-workloads-fleet \
  --orchestration-mode Flexible \
  --location eastus \
  --zones 1 2 3 \
  --image Ubuntu2204 \
  --vm-sku Standard_D2s_v5 \
  --instance-count 3 \
  --vnet-name vnet-workloads-eastus \
  --subnet snet-apps \
  --public-ip-per-vm false \
  --load-balancer alb-internal-services

# 2. Configure Metric-Based Autoscaling Rule (Scale out when CPU > 75% for 5m)
az monitor autoscale create \
  --resource-group rg-compute-prod \
  --resource vmss-workloads-fleet \
  --resource-type Microsoft.Compute/virtualMachineScaleSets \
  --name autoscale-workload-rules \
  --min-count 3 \
  --max-count 20 \
  --count 3

az monitor autoscale rule create \
  --resource-group rg-compute-prod \
  --autoscale-name autoscale-workload-rules \
  --condition "Percentage CPU > 75 avg 5m" \
  --scale out 2
```

---

## 10. Quotas & Limits

| Parameter                       | Limit                  | Production Notes                                         |
| :------------------------------ | :--------------------- | :------------------------------------------------------- |
| **Total Regional vCPUs**        | 20–100 vCPUs (default) | Increase via Azure Portal Quotas blade                   |
| **Spot vCPUs per Region**       | Separate quota tier    | Must be requested prior to launching large Spot clusters |
| **Instances per Flexible VMSS** | Up to 1,000 instances  | Scalable across availability zones and fault domains     |
| **Data Disks per VM**           | Up to 64 disks         | Dependent on VM size (typically 2 disks per vCPU)        |
| **Network Interfaces per VM**   | Up to 8 vNICs          | Scales with instance size                                |

---

## 11. Pricing Examples

### Scenario 1: Multi-Zone Production Web Tier (Reserved Instances)

- **Topology:** 6 instances of `Standard_D4s_v5` (4 vCPU, 16 GB RAM) running 24/7 across Zones 1, 2, 3.
- **On-Demand Cost:** 6 × $0.192 / hr × 730 hrs = **$840.96 / month**.
- **With 3-Year Reserved VM Instance (RI):** 62% discount applied ($0.073 / hr).
- **Total Compute Cost:** **~$320.00 / month** (Saving $520.96 / month).

### Scenario 2: Batch Processing with Flexible VMSS Spot Instances

- **Topology:** 50 worker VMs using `Standard_F8s_v2` (Compute-optimized: 8 vCPU, 16 GB RAM).
- **Usage:** 80 hours of batch processing per month.
- **On-Demand Rate:** 50 × $0.338 / hr × 80 hrs = $1,352.00.
- **Spot Discount (~85% savings):** 50 × $0.0507 / hr × 80 hrs = **$202.80 / month**.
- **Net Monthly Savings:** **$1,149.20 / month**.

---

## 12. Battle-Tested Nuggets & Gotchas

1. **The Burstable B-Series Credit Cliff:** `B-series` instances accumulate CPU credits during low activity. When sustained workloads exhaust credits, the CPU is hard-throttled to its baseline performance (as low as 10%–20% of 1 core), causing web apps and SSH logins to lock up completely. Never run production databases or latency-sensitive APIs on B-series VMs.
2. **Deallocated vs. Stopped Billing State:** Stopping a VM from inside the guest OS (e.g. `sudo shutdown -h now`) places the VM in a **"Stopped"** state; Azure still reserves the physical hardware host and **continues charging full compute prices**. You must stop the VM via `az vm deallocate` or the portal to reach **"Stopped (Deallocated)"** and halt compute billing.
3. **Availability Zones vs. Regional Disk Locks:** If a VM in Zone 1 crashes, its attached Zonal Managed Disk cannot be attached to a VM in Zone 2. Availability Zones are physically isolated hardware boundaries. For cross-zone disk failover, stateful applications must replicate data at the software layer or use Azure NetApp Files / shared filesystems.
4. **Scheduled Events Polling Requirement:** Azure notifies VMs of Spot preemption, host maintenance, and reboots via the Scheduled Events API at `http://169.254.169.254/metadata/scheduledevents`. However, unlike push webhooks, your application or monitoring daemon **must continuously poll this endpoint every 1–5 seconds** to catch the 30-second shutdown notice.
5. **Orphaned Managed Disks and Public IPs on VM Deletion:** Deleting an Azure VM via ARM or script leaves the OS disk, data disks, and network interfaces active in the Resource Group by default. Always configure the `deleteOption: Delete` parameter on the VM resource so that associated disks and NICs are automatically purged with the compute instance.
6. **Accelerated Networking Cannot Be Toggled While Running:** Accelerated Networking (SR-IOV) cannot be enabled or disabled on an active VM's vNIC. You must completely deallocate the VM (`az vm deallocate`), update the network interface setting, and restart the VM.

---

## Across the Wiki

- [[Azure/compute/README|Azure Compute Hub]] — Compute decision matrix and modern architectures
- [[Azure/compute/aks|Azure Kubernetes Service (AKS)]] — Container orchestration on Azure
- [[Azure/compute/vm/spot-vms|Azure Spot VMs & Scheduled Events]] — In-depth guide to Spot architecture and eviction handling
- [[Azure/compute/container-apps/README|Azure Container Apps (ACA)]] — Serverless microservices runtime
- [[AWS/compute/ec2/README|Amazon EC2]] — Virtual compute instances in AWS
- [[GCP/compute/gce|GCP Compute Engine (GCE)]] — Virtual machines in Google Cloud
