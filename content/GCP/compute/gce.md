---
title: GCP Compute Engine (GCE)
description: Compute Engine architecture — machine families, custom machine shapes, Managed Instance Groups (MIGs), Spot VMs, Live Migration, and OS Login.
tags:
  - gcp
  - compute
  - gce
  - vms
  - infrastructure
---

# GCP Compute Engine (GCE) 🖥️

Google Compute Engine provides secure, customizable virtual machines running on Google's global infrastructure. Compute Engine stands apart from AWS EC2 through two signature architectural capabilities: **Live Migration** (VMs seamlessly move to new physical hosts during hardware maintenance with zero guest OS downtime or reboots) and **Custom Machine Shapes** (independent vCPU and RAM provisioning).

---

## Architecture & Mental Model

### Machine Families Matrix

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Compute Engine Families                         │
├─────────────────┬─────────────────┬──────────────────┬─────────────────┤
│ General Purpose │Compute-Optimized│ Memory-Optimized │  Accelerator    │
│  (E2, N2, C3)   │    (C2, C2D)    │   (M1, M2, M3)   │    (A2, A3)     │
├─────────────────┼─────────────────┼──────────────────┼─────────────────┤
│ Web apps, micro-│ High-frequency  │ Large in-memory  │ LLM training,   │
│ services, dev/  │ trading, gaming │ DBs (SAP HANA),  │ deep learning,  │
│ test environments│ compute, media  │ massive Redis    │ NVIDIA H100/A100│
└─────────────────┴─────────────────┴──────────────────┴─────────────────┘
```

* **Custom Sizing:** If your application needs 6 vCPUs and 21 GB of RAM, you configure exactly `custom-6-21504`, paying only for what you allocate rather than jumping to a rigid 8 vCPU / 32 GB instance tier.

---

## Core Concepts

### 1. Managed Instance Groups (MIGs)

A Managed Instance Group pools identical VM instances created from an **Instance Template**:

* **Regional vs. Zonal MIGs:**
  * **Zonal MIG:** Deploys VMs inside a single availability zone.
  * **Regional MIG:** Distributes instances evenly across 3 zones in a region. **Mandatory for production HA.**
* **Auto-Healing:** Attaches a health check probe. If a VM fails the application health check, the MIG automatically destroys and recreates the instance.
* **Rolling Updates:** Zero-downtime canary and phased deployments:
  * `max-surge`: Number of extra instances created above target capacity during update.
  * `max-unavailable`: Number of instances permitted down simultaneously.

### 2. Spot VMs vs. Standard VMs

* **Spot VMs:** Offer 60% to 91% discounts compared to on-demand pricing by running on spare GCP capacity.
* **Preemption Mechanics:**
  * GCP can reclaim a Spot VM at any time when capacity is needed.
  * The VM receives an ACPI shutdown signal with a **30-second termination notice**.
  * Unlike legacy "Preemptible VMs" (which had a hard 24-hour lifetime limit), Spot VMs have **no 24-hour limit** and run indefinitely until reclaimed.

### 3. Live Migration

During hypervisor patching, physical hardware degradation, or network maintenance:
* GCP's hypervisor freezes the VM's execution for milliseconds, transfers memory pages across Google's private backbone to another physical host, and resumes execution seamlessly.
* The guest OS, active network sockets, and attached Persistent Disks remain completely uninterrupted without reboots.

### 4. OS Login & Shielded VMs

* **Legacy Metadata SSH Keys (Insecure):** Project-wide SSH public keys stored in metadata allow anyone with project-level access to SSH into any VM as root.
* **OS Login (Modern Standard):**
  * Replaces metadata keys with IAM permissions: `roles/compute.osLogin` (standard user) or `roles/compute.osAdminLogin` (sudoer).
  * Automatically provisions POSIX accounts from Google Workspace profiles and integrates with multi-factor authentication (MFA/2FA).
* **Shielded VMs:** Employs virtual Trusted Platform Module (vTPM) and Secure Boot to verify bootloader integrity against rootkits.

---

## Production `gcloud` CLI Commands

### 1. Creating a VM with Custom Shape and OS Login

```bash
gcloud compute instances create prod-worker-01 \
  --zone=us-central1-a \
  --custom-cpu=4 \
  --custom-memory=14GB \
  --network=prod-vpc \
  --subnet=prod-us-central1 \
  --no-address \
  --service-account=worker-sa@my-prod-project.iam.gserviceaccount.com \
  --no-scopes \
  --shielded-secure-boot \
  --shielded-vtpm \
  --metadata=enable-oslogin=TRUE \
  --boot-disk-size=50GB \
  --boot-disk-type=pd-balanced
```

### 2. Provisioning a Regional MIG with Auto-Healing & Autoscaling

```bash
# 1. Create an Instance Template
gcloud compute instance-templates create prod-api-template \
  --region=us-central1 \
  --machine-type=e2-standard-4 \
  --network=prod-vpc \
  --subnet=prod-us-central1 \
  --no-address \
  --tags=web-backend \
  --service-account=api-sa@my-prod-project.iam.gserviceaccount.com \
  --boot-disk-size=50GB \
  --boot-disk-type=pd-balanced

# 2. Create an Application Health Check
gcloud compute health-checks create http prod-api-hc \
  --port=8080 \
  --request-path=/healthz \
  --check-interval=10s \
  --unhealthy-threshold=3

# 3. Create the Regional MIG
gcloud compute instance-groups managed create prod-api-mig \
  --region=us-central1 \
  --template=prod-api-template \
  --size=3 \
  --health-check=prod-api-hc \
  --initial-delay=120

# 4. Enable Autoscaling (Scale out when CPU > 70%)
gcloud compute instance-groups managed set-autoscaling prod-api-mig \
  --region=us-central1 \
  --min-num-replicas=3 \
  --max-num-replicas=15 \
  --target-cpu-utilization=0.70
```

---

## Quotas & Limits

| Parameter | Default Limit | Notes |
| :--- | :--- | :--- |
| **CPUs per region** | 24–100 vCPUs (new projects) | Easily increased via Quota Request console |
| **Spot vCPUs per region** | Separate quota from standard | Request increase before launching large Spot fleets |
| **Instances per MIG** | 1,000 per zonal MIG | Up to 2,000 per regional MIG |
| **Preemption notice window** | 30 seconds | Handle via metadata shutdown scripts |
| **Max disk size per instance** | 64 TB total across all disks | Hyperdisk or Persistent Disk |

---

## References

* **Homepage:** https://cloud.google.com/compute
* **Documentation:** https://cloud.google.com/compute/docs
* **Machine Families Guide:** https://cloud.google.com/compute/docs/machine-types
* **OS Login Overview:** https://cloud.google.com/compute/docs/oslogin
* **Pricing:** https://cloud.google.com/compute/pricing

---

## Pricing Examples

### Scenario 1: Production Web Backend Cluster (On-Demand + CUD)
* 6 instances of `e2-standard-4` (4 vCPU, 16 GB RAM) running 24/7 across 3 zones.
* Base on-demand cost: 6 × ~$97.00 / month = $582.00 / month.
* With a **3-Year Committed Use Discount (CUD)** for General Purpose Compute:
  * 55% discount applied across all 24 vCPUs and 96 GB RAM.
* **Effective Monthly Cost:** **~$261.90 / month** (Saving $320.10/mo).

### Scenario 2: Batch Analytics Processing with Spot VMs
* 50 worker instances using `c2-standard-8` (Compute-optimized: 8 vCPU, 32 GB RAM).
* Workload runs for 8 hours every weekend (32 hours / month).
* On-Demand rate: $0.3376 / hr × 50 × 32 hrs = $540.16.
* Spot VM rate (~80% discount): $0.0675 / hr × 50 × 32 hrs = $108.00.
* **Monthly Savings:** **$432.16** per month.

---

## Nuggets & Gotchas

1. **Spot VMs Have a 30-Second Shutdown Window (vs. AWS 2 Minutes):** AWS EC2 Spot instances give a 2-minute warning via IMDS before termination. Compute Engine Spot VMs give only **30 seconds** via the metadata server ACPI signal. Checkpointing logic in shutdown scripts must be lightweight and fast; heavy state flushing will be abruptly terminated.
2. **The "External IP" Security Vulnerability:** By default, if you run `gcloud compute instances create` without passing `--no-address`, Compute Engine assigns an ephemeral public IPv4 address to the instance. If your firewall allows ingress, your VM is exposed directly to internet port scanners. Always pass `--no-address` and use Cloud NAT.
3. **OS Login Overrides Metadata SSH Keys:** Enabling OS Login (`enable-oslogin=TRUE`) at the project or instance level instantly disables all legacy SSH keys stored in instance or project metadata. If an automated script connects using a raw SSH key without Google Cloud IAM authorization, it will be locked out immediately.
4. **MIG Auto-Healing `initial-delay` Trap:** When configuring auto-healing on a MIG, the `--initial-delay` flag must exceed the time it takes your application container or JVM to start. If your application takes 90 seconds to boot but `initial-delay` is set to 30 seconds, the auto-healer will kill the VM before it ever finishes launching, entering an infinite reboot loop.
5. **E2 Machine CPU Steal on Overcommit:** The `e2` series uses dynamic resource sharing on host processors. During severe noisy-neighbor spikes or prolonged 100% CPU loads, E2 instances can experience CPU throttling and variable latency. For latency-sensitive databases, Kafka brokers, or high-throughput APIs, use dedicated-core **N2** or **C3** instances instead.
