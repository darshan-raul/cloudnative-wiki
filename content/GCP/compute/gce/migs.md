---
title: GCP Managed Instance Groups (MIGs)
description: Compute Engine Managed Instance Groups (MIGs) — Regional vs Zonal MIGs, auto-healing health checks, rolling updates, stateful MIGs, and autoscaling policies.
tags:
  - gcp
  - compute
  - gce
  - migs
  - autoscaling
  - reliability
---

# GCP Managed Instance Groups (MIGs) 🖥️🔄

A Managed Instance Group (MIG) is a collection of identical Compute Engine virtual machines operated as a single, coordinated unit. Built on top of **Instance Templates**, MIGs provide automated provisioning, multi-zone high availability, application auto-healing, rolling zero-downtime deployments, and dynamic autoscaling.

---

## Architecture & Mental Model

### Regional MIG Topology with Auto-Healing & Autoscaling

```
                                  Google Cloud Load Balancer
                                              │
                                              ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                          Regional Managed Instance Group (us-central1)                 │
│                                                                                        │
│   Target Distribution Shape: EVEN                                                      │
│   Auto-Healing Health Check: HTTP /healthz (Port 8080, Interval 10s, Unhealthy 3)      │
│   Autoscaler: Scale Out when Avg CPU > 70% or LB Capacity > 80%                        │
│                                                                                        │
│         Zone: us-central1-a              Zone: us-central1-b        Zone: us-central1-c│
│       ┌──────────────────────┐         ┌──────────────────────┐   ┌──────────────────┐ │
│       │ VM Instance 1        │         │ VM Instance 2        │   │ VM Instance 3    │ │
│       │ (Running healthy)    │         │ (Running healthy)    │   │ (Fails /healthz) │ │
│       └──────────────────────┘         └──────────────────────┘   └────────┬─────────┘ │
│                                                                            │           │
│                                                                            ▼           │
│                                                            [Auto-Healer Recreates VM]  │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

* **Regional Distribution:** A Regional MIG automatically balances instances evenly across three availability zones in the region. If a single datacenter zone suffers a physical outage, the surviving instances continue serving traffic without human intervention.

---

## Core Concepts

### 1. Zonal vs. Regional MIGs

| Feature | Zonal MIG | Regional MIG |
| :--- | :--- | :--- |
| **Geographic Scope** | Confined to a single availability zone (e.g., `us-central1-a`) | Distributed across multiple zones in a region |
| **High Availability** | None (Single Point of Failure if zone degrades) | **High (Multi-Zone Resilience)** |
| **Target Distribution** | N/A | Balanced evenly or dynamically packed |
| **Max Capacity** | Up to 1,000 instances | Up to 2,000 instances |
| **Production Recommendation** | Dev/Test or strict single-zone cluster requirements | **Mandatory for all production application tiers** |

### 2. Auto-Healing Mechanics

Auto-healing uses application-level health checks to detect silent failures (e.g. frozen processes, memory exhaustion, deadlocked web servers) that the hypervisor cannot detect:
* **Health Check Probe:** Pings an HTTP, HTTPS, or TCP endpoint exposed by the application (e.g., `/healthz`).
* **Initial Delay (`--initial-delay`):** The grace period given to a newly launched VM to complete initialization (running startup scripts, pulling container images, starting application runtimes) before the auto-healer begins evaluating health check probes.
* **Auto-Recovery:** If an instance fails the configured number of consecutive checks (e.g. 3 failures), the MIG recreates the instance from the instance template while preserving its name if stateful.

### 3. Rolling Updates & Deployment Strategies

MIGs support progressive, zero-downtime rolling updates when updating instance templates:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Rolling Update Mechanics                        │
│                                                                        │
│   Template V1 (Active) ────────────────────────► Template V2 (Target)  │
│                                                                        │
│   • max-surge: Number of temporary instances created ABOVE target      │
│     capacity during the roll (e.g., max-surge = 3).                    │
│   • max-unavailable: Number of instances allowed to be offline         │
│     simultaneously (e.g., max-unavailable = 0 for 100% capacity).      │
│   • min-ready-sec: Time a new VM must report healthy before the        │
│     updater proceeds to tear down the next old instance.               │
└────────────────────────────────────────────────────────────────────────┘
```

### 4. Stateful MIGs

While MIGs are typically used for stateless web servers, **Stateful MIGs** allow running workloads that require persistent state across updates and auto-healing:
* **Stateful Persistent Disks:** Disks are preserved and re-attached to the same instance upon recreation.
* **Stateful Static IP Addresses:** Preserves internal or external IP addresses assigned to specific instances across reboots.
* **Stateful Metadata:** Key-value metadata specific to individual instances (e.g. node IDs in a Kafka or ZooKeeper cluster).

### 5. Autoscaling Signals

A MIG autoscaler can dynamically scale the group based on multiple metrics:
1. **Average CPU Utilization:** Target threshold (e.g., 70% CPU).
2. **Cloud Load Balancing Serving Capacity:** Based on backend utilization (QPS or connections per instance).
3. **Cloud Monitoring Metrics:** Custom metrics (e.g., Pub/Sub queue depth, RabbitMQ backlog).
4. **Predictive Autoscaling:** Machine learning forecasts future load based on historical trends and pre-allocates instances before the traffic spike arrives.

---

## Production `gcloud` CLI Commands

### 1. Creating a Production Instance Template

```bash
gcloud compute instance-templates create prod-api-v1 \
  --region=us-central1 \
  --machine-type=e2-standard-4 \
  --network=prod-vpc \
  --subnet=prod-us-central1 \
  --no-address \
  --maintenance-policy=MIGRATE \
  --service-account=api-worker@my-prod-project.iam.gserviceaccount.com \
  --no-scopes \
  --tags=web-backend,http-server \
  --metadata=enable-oslogin=TRUE \
  --boot-disk-size=50GB \
  --boot-disk-type=pd-balanced \
  --boot-disk-device-name=boot-disk
```

### 2. Creating an Auto-Healing Health Check

```bash
gcloud compute health-checks create http prod-api-health-check \
  --region=us-central1 \
  --port=8080 \
  --request-path=/healthz \
  --check-interval=10s \
  --timeout=5s \
  --unhealthy-threshold=3 \
  --healthy-threshold=2
```

### 3. Provisioning a Regional MIG with Auto-Healing

```bash
gcloud compute instance-groups managed create prod-api-mig \
  --region=us-central1 \
  --template=prod-api-v1 \
  --size=6 \
  --health-check=prod-api-health-check \
  --initial-delay=180 \
  --target-distribution-shape=EVEN
```

### 4. Configuring Autoscaling with Predictive Scaling

```bash
gcloud compute instance-groups managed set-autoscaling prod-api-mig \
  --region=us-central1 \
  --min-num-replicas=6 \
  --max-num-replicas=30 \
  --target-cpu-utilization=0.70 \
  --cool-down-period=90 \
  --mode=on
```

### 5. Executing a Zero-Downtime Rolling Update to a New Template

```bash
gcloud compute instance-groups managed rolling-action start-update prod-api-mig \
  --region=us-central1 \
  --version=template=prod-api-v2 \
  --max-surge=3 \
  --max-unavailable=0 \
  --min-ready=60s \
  --replacement-method=substitute
```

---

## Quotas & Limits

| Metric / Parameter | Default Limit | Production Guidance |
| :--- | :--- | :--- |
| **Max instances per Zonal MIG** | 1,000 instances | Single zone boundary |
| **Max instances per Regional MIG** | 2,000 instances | Distributed across up to 3 zones |
| **Autoscaling cooldown period** | Default 60 seconds (min 15s) | Set longer than application boot time |
| **Max target capacity change** | Scales up by max 100% or 10 VMs at a time | Prevents sudden runaway quota exhaustion |
| **Health Check initial delay** | Up to 3,600 seconds | Typical: 120s – 300s for heavy JVM apps |

---

## References

* **Managed Instance Groups Documentation:** https://cloud.google.com/compute/docs/instance-groups
* **Auto-Healing Guide:** https://cloud.google.com/compute/docs/instance-groups/autohealing-instances-in-migs
* **Rolling Updates Overview:** https://cloud.google.com/compute/docs/instance-groups/rolling-out-updates-to-managed-instance-groups
* **Stateful MIGs Guide:** https://cloud.google.com/compute/docs/instance-groups/stateful-migs
* **Pricing:** https://cloud.google.com/compute/pricing (MIG orchestrator is free; pay for provisioned VMs and disks)

---

## Pricing Examples

### Scenario 1: Multi-Zone Production Web API Fleet
* Regional MIG running across 3 zones in `us-central1`.
* Baseline footprint: 6 instances of `e2-standard-4` (4 vCPU, 16 GB RAM).
* Autoscaling range: 6 to 18 instances. Average usage: 9 instances sustained.
* Compute cost: 9 × ~$97.00 / month = **$873.00 / month**.
* Boot storage: 9 × 50 GB `pd-balanced` ($0.10/GB) = **$45.00 / month**.
* MIG Orchestrator & Auto-Healer: **$0.00**.
* **Total Monthly Cost:** **~$918.00 / month**.

### Scenario 2: High-Volume E-Commerce Flash Sale Scaling
* Autoscaling triggers scale-out from 6 to 30 instances for 12 hours during a promotional campaign.
* Surge instances: 24 additional `e2-standard-4` instances for 12 hours.
* Surge compute: 24 × $0.134 / hr × 12 hrs = **$38.59**.
* Additional temporary disk usage: negligible (< $1.00).
* **Incremental Surge Cost:** **~$39.50** to absorb millions of promotional requests without degradation.

---

## Nuggets & Gotchas

1. **The Infinite Reboot Loop (`initial-delay` Under-sizing):** If an application container or JVM takes 90 seconds to bootstrap, compile JIT, and open its listening port, setting `--initial-delay=30s` causes the auto-healer to test `/healthz` at second 31. Because the app has not finished booting, the health check fails, and the MIG destroys and recreates the instance. The VM will loop in an infinite restart cycle forever without ever receiving a single user request.
2. **`max-unavailable=0` Requires Available Quota for Surge:** When configuring a zero-downtime rolling update with `--max-unavailable=0`, the MIG creates new instances before destroying old ones (`max-surge`). If your project has a regional CPU quota of 24 vCPUs and your MIG already uses 24 vCPUs, the rolling update will immediately stall with `QUOTA_EXCEEDED` because the MIG cannot create the surge instances.
3. **Health Check Probes Must Hit Internal Firewall IP Ranges:** Health checks for auto-healing do not originate from within your subnet; they originate from Google's centralized health-checking probes: `35.191.0.0/16` and `130.211.0.0/22`. If you fail to add an explicit ingress firewall rule allowing traffic from these CIDRs to your health check port, every VM in the MIG will be declared unhealthy and auto-healing will destroy all instances.
4. **Stateful MIG Instance Deletion Mechanics:** When deleting a specific instance from a stateful MIG via `gcloud compute instance-groups managed delete-instances`, the stateful disks and static IPs are **deleted by default** unless you explicitly specify `--preserve-state` or configure the per-instance configs to retain attached disks.
5. **Autoscaler Scale-Down Throttling (Flapping Prevention):** The MIG autoscaler is designed with built-in stabilization windows to prevent rapid instance creation and destruction (flapping). When traffic drops, the autoscaler waits for the **stabilization window** (default 10 minutes) before terminating instances to ensure the drop is not a momentary dip.
