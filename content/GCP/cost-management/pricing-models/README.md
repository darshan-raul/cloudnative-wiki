---
title: GCP Cost Optimization, Committed Use Discounts (CUDs), and FinOps
description: Exhaustive engineering guide to Google Cloud cost management — Resource-based vs Flexible Spend-based Committed Use Discounts (CUDs), Sustained Use Discounts (SUDs), Active Assist Recommender API, BigQuery billing export, and FinOps governance.
tags:
  - gcp
  - finops
  - cost-optimization
  - cuds
  - suds
---

# GCP Cost Optimization, Committed Use Discounts (CUDs), and FinOps 💰📊

Cost optimization in Google Cloud Platform requires deep engineering alignment between infrastructure architecture and financial mechanics. Unlike traditional static infrastructure, GCP provides automated, non-contractual discounts (**Sustained Use Discounts - SUDs**), contractual reservations (**Committed Use Discounts - CUDs** across Resource-Based and Flexible Spend-Based vectors), AI-driven rightsizing recommendations via the **Active Assist Recommender API**, and real-time granular cost attribution through **BigQuery Detailed Billing Exports**.

---

## 1. Architectural Cost Mechanics & Discount Taxonomy

Understanding how Google Cloud discounts stack and apply across projects, folders, and organizations is critical for preventing financial waste.

```
                           TOTAL RAW ON-DEMAND CONSUMPTION
                                          │
                                          ▼
     ┌────────────────────────────────────────────────────────────────────────┐
     │ 1. SUSTAINED USE DISCOUNTS (SUDs)                                      │
     │    - Automatically applied to N1, N2, N2D, C2, M1 Compute Engine VMs   │
     │    - Progressive tier discount as usage crosses 25%, 50%, 75% of month │
     │    - Up to 30% automatic savings without contractual commitment        │
     └────────────────────────────────────┬───────────────────────────────────┘
                                          │ Uncovered Baseline Workloads
                                          ▼
     ┌────────────────────────────────────────────────────────────────────────┐
     │ 2. COMMITTED USE DISCOUNTS (CUDs)                                      │
     │                                                                        │
     │  ┌─────────────────────────────────┐ ┌──────────────────────────────┐  │
     │  │   RESOURCE-BASED CUDs           │ │   FLEXIBLE SPEND-BASED CUDs  │  │
     │  │   - Pinned to Region & Machine  │ │   - Hourly spend commitment  │  │
     │  │     Family (e.g., N2 in us-cen1)│ │     (e.g., $100/hr on compute│  │
     │  │   - Up to 57% savings (vCPU/RAM)│ │   - Applies across C3, N2,   │  │
     │  │   - Up to 70% for Memory-Optim. │ │     Cloud Run, GKE Autopilot │  │
     │  └─────────────────────────────────┘ └──────────────────────────────┘  │
     └────────────────────────────────────┬───────────────────────────────────┘
                                          │
                                          ▼
     ┌────────────────────────────────────────────────────────────────────────┐
     │ 3. ACTIVE ASSIST & RECOMMENDER ENGINE                                  │
     │    - Machine learning models analyze 8-30 day CPU/RAM/Disk percentiles │
     │    - Recommends machine shape resizing, idle VM purge, and CUD buys    │
     └────────────────────────────────────┬───────────────────────────────────┘
                                          │ Real-Time Streaming Export
                                          ▼
     ┌────────────────────────────────────────────────────────────────────────┐
     │ 4. FINOPS ATTRIBUTION & BIGQUERY DETAILED BILLING                      │
     │    - Line-item cost breakdown with labels and tags                     │
     │    - Amortized cost attribution across departments & cost centers      │
     └────────────────────────────────────────────────────────────────────────┘
```

### Sustained Use Discounts (SUDs)

- **Mechanics:** SUDs are automatic discounts applied to eligible Compute Engine instances and Cloud SQL databases that run for more than 25% of a billing month.
- **Incremental Curve:**
  - 0% to 25% of the month: 100% of base on-demand rate.
  - 25% to 50% of the month: 20% discount on the incremental usage.
  - 50% to 75% of the month: 40% discount on the incremental usage.
  - 75% to 100% of the month: 60% discount on the incremental usage.
  - An instance running 24/7 for a full month receives an effective **30% net discount** compared to hourly on-demand rates.
- **Machine Family Support:** Appears automatically on N1, N2, N2D, C2, and M1/M2 families. **Note:** Newer machine series like C3, C3D, N4, and GKE Autopilot do not receive SUDs; they rely solely on CUDs.

### Committed Use Discounts (CUDs): Resource-Based vs Flexible Spend

| Dimension | Resource-Based CUDs | Flexible Spend-Based CUDs |
| :--- | :--- | :--- |
| **Commitment Unit** | Specific amount of vCPU, RAM, GPU, or Local SSD | Dollar spend commitment per hour (e.g., $50.00/hr) |
| **Term Length** | 1 Year or 3 Years | 1 Year or 3 Years |
| **Region Portability** | **Regionally locked** (e.g., must run in `us-central1`) | **Globally portable** across all GCP regions |
| **Family Portability** | Pinned to machine family (e.g., N2 only) | **Cross-family** (N1, N2, N2D, C2, C3, E2) |
| **Service Scope** | Compute Engine, Cloud SQL, AlloyDB, Spanner | Compute Engine, GKE Autopilot, Cloud Run |
| **Maximum Savings** | Up to **57%** (1-yr ~37%, 3-yr ~57%) | Up to **46%** (1-yr ~28%, 3-yr ~46%) |
| **Best Used For** | Predictable, static database and core compute tiers | Rapidly evolving microservice clusters & global apps |

---

## 2. Granular FinOps Governance & Cost Attribution

### Billing Sharing & Scope Hierarchy

By default, a CUD purchased within a billing account can be shared across all projects linked to that billing account (**Discount Sharing Enabled**). 
- If Project A under-utilizes its committed vCPUs, Project B in the same region running N2 machines automatically consumes the unused commitment, preventing financial slippage.
- Organizations can disable discount sharing or isolate commitments to specific projects using Billing Subaccounts for strict departmental cost boundaries.

### BigQuery Detailed Billing Export

To calculate true cost of ownership (TCO) and unit economics:
- **Standard Usage Cost:** Hourly line-item usage.
- **Detailed Usage Cost:** Includes resource-level metadata, instance IDs, GKE pod labels, and disk serial numbers.
- **Pricing Export:** Historical catalog pricing adjustments.

```sql
-- Query Top 10 Cost Drivers with Amortized CUD Discounts
SELECT
  project.name AS project_name,
  service.description AS service_description,
  sku.description AS sku_description,
  ROUND(SUM(cost), 2) AS unblended_cost,
  ROUND(SUM(cost + IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 2) AS net_cost
FROM
  `billing_export.gcp_billing_export_resource_v1_01AB23_CD45EF_678901`
WHERE
  _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY
  1, 2, 3
ORDER BY
  net_cost DESC
LIMIT 10;
```

---

## 3. Production CLI Operations & Active Assist (`gcloud`)

### 1. Query Active Assist Recommendations for Rightsizing & Idle VMs

```bash
# List all VM rightsizing recommendations across a production project
gcloud recommender recommendations list \
    --recommender=google.compute.instance.MachineTypeRecommender \
    --location=us-central1-a \
    --project=core-infrastructure-prod \
    --format="table(name.basename(),content.overview.title,content.operationGroups[0].operations[0].resource,primaryImpact.costProjection.cost.units)"

# List idle VM instances (candidates for deletion)
gcloud recommender recommendations list \
    --recommender=google.compute.instance.IdleResourceRecommender \
    --location=us-central1-a \
    --project=core-infrastructure-prod \
    --format="yaml"
```

### 2. Inspect Committed Use Discount Recommendations

```bash
# Query automated recommendations for CUD purchases based on 30-day historical baseline
gcloud recommender recommendations list \
    --recommender=google.compute.commitment.UsageCommitmentRecommender \
    --location=us-central1 \
    --project=billing-admin-prod \
    --format="yaml"
```

### 3. Purchase a Resource-Based CUD for Production Infrastructure

```bash
# Purchase a 1-year commitment for 64 vCPUs and 256 GB RAM of N2 in us-central1
gcloud compute commitments create prod-n2-us-central1-1yr \
    --region=us-central1 \
    --plan=TWELVE_MONTH \
    --resources=vcpu=64,memory=262144MB \
    --type=COMPUTE_OPTIMIZED \
    --project=core-infrastructure-prod
```

### 4. Enforce Budget Alerts with Cloud Pub/Sub Webhooks

Automate notifications and shutdown triggers when project spend approaches monthly budgets:

```bash
# Create a budget with programmatic Pub/Sub notification at 50%, 90%, and 100% thresholds
gcloud billing budgets create \
    --billing-account=01AB23-CD45EF-678901 \
    --display-name="Production Infrastructure Monthly Budget" \
    --budget-amount=25000USD \
    --threshold-rule=percent=0.5 \
    --threshold-rule=percent=0.9 \
    --threshold-rule=percent=1.0,basis=forecasted-spend \
    --notifications-topic=projects/secops-kms-prod/topics/billing-budget-alerts
```

---

## 4. Quotas, Performance, and Configuration Limits

| Parameter / Dimension | Default Limit | Operational Best Practice |
| :--- | :--- | :--- |
| **Max CUD Purchases per Day** | 20 commitments | Consolidate commitments into quarterly or monthly reviews |
| **CUD Term Modification** | Irrevocable contract | Cannot cancel or decrease commitment once finalized |
| **CUD Expiration Notice** | Active Assist alert at 30d | Set up calendar reminders to prevent sudden cliff drop to on-demand |
| **Budgets per Billing Account** | 5,000 budgets | Create granular budgets per environment / department |
| **Recommender API Lookback** | 8 to 30 days default | Configurable lookback prevents rightsizing based on anomalous dips |
| **Billing Export Latency** | 2 to 6 hours | BigQuery billing export streams micro-batches; not instantaneous |

---

## 5. Official References & Documentation

- [Google Cloud Cost Management Documentation](https://cloud.google.com/cost-management/docs)
- [Committed Use Discounts Overview](https://cloud.google.com/docs/cuds)
- [Sustained Use Discounts Guide](https://cloud.google.com/compute/docs/sustained-use-discounts)
- [Active Assist Recommender Documentation](https://cloud.google.com/recommender/docs)
- [BigQuery Detailed Billing Export Schema](https://cloud.google.com/billing/docs/how-to/export-data-bigquery)

---

## 6. Realistic Pricing Scenarios

### Scenario A: Compute Engine Cluster (On-Demand vs 3-Year Resource CUD)

- **Workload:**
  - 50 nodes running `n2-standard-8` (400 vCPUs, 1,600 GiB RAM) 24/7 in `us-central1`.
  - Base On-Demand Price:
    - vCPU: $0.031611 / vCPU-hr.
    - RAM: $0.004237 / GB-hr.
    - Hourly cluster cost: $(400 \times 0.031611) + (1{,}600 \times 0.004237) = \$12.644 + \$6.779 = \$19.423/\text{hr}$.
    - Unmitigated Monthly Cost: $\$19.423 \times 730 \text{ hrs} = \mathbf{\$14{,}178.79 / month}$.
- **Applying 3-Year Resource CUD (~57% Discount):**
  - Net Hourly cluster cost: $\$19.423 \times (1 - 0.57) = \$8.352/\text{hr}$.
  - Discounted Monthly Cost: $\$8.352 \times 730 \text{ hrs} = \mathbf{\$6{,}096.96 / month}$.
- **Net Annual Savings:** $(\$14{,}178.79 - \$6{,}096.96) \times 12 = \mathbf{\$96{,}981.96 / year}$ saved.

### Scenario B: Dynamic Serverless & Microservice Fleet (Flexible Spend CUD)

- **Workload:**
  - Dynamic fleet of Cloud Run microservices, GKE Autopilot workloads, and experimental C3 VMs fluctuating between $80/hr and $200/hr total compute spend across worldwide regions.
  - Safe Baseline Spend: $75.00 / hour continuous baseline.
  - Organization purchases a **3-Year Flexible Spend CUD** committing to **$75.00 / hour**.
- **Savings Analysis:**
  - 3-Year Flexible Spend discount delivers ~46% savings on committed eligible compute.
  - Effective hourly cost for $75.00 of compute: $\$75.00 \times (1 - 0.46) = \$40.50/\text{hr}$.
  - Hourly savings on commitment: $\$75.00 - \$40.50 = \$34.50/\text{hr}$.
  - Any compute above $75.00/hr bills at standard on-demand / SUD rates.
- **Monthly Savings:** $\$34.50/\text{hr} \times 730 \text{ hrs} = \mathbf{\$25{,}185.00 / month}$ ($302,220/year).

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **The CUD Commitment Trap (Commit to the Valley, Not the Peak):** A Committed Use Discount is a legally binding contract to pay for the committed resources for every single hour of the 1-year or 3-year term, whether you use them or not. If traffic drops or architecture migrates to another architecture (e.g., migrating from N2 VMs to Cloud Run), unused resource-based CUDs continue to bill every month. FinOps golden rule: **commit only to 70-80% of your historic minimum baseline trough**, leaving fluctuating peaks to on-demand or Spot VMs.
2. **Resource CUDs Do Not Cover Cross-Family Migrations:** If you purchase 500 vCPUs of a 3-year N2 Resource CUD in `us-central1`, and next year your team upgrades all workloads to C3 or ARM-based T2A instances, your N2 commitment **will not apply to C3 or T2A**. You will pay for the empty N2 CUD *plus* the new C3 instances. If your infrastructure roadmap anticipates machine family modernization, purchase **Flexible Spend CUDs** instead of Resource CUDs.
3. **SUDs Disappear on Modern Machine Series:** Many engineering teams budget assuming Compute Engine provides automatic ~30% Sustained Use Discounts. However, Google intentionally deprecated SUDs on third-generation and newer machine types (C3, C3D, N4, Z3) and GKE Autopilot. If you migrate from N1/N2 to C3 without purchasing CUDs, your monthly bill may jump significantly because the automatic 30% SUD is absent.
4. **Billing Export Labels Are Not Retroactive:** BigQuery detailed billing export only records labels and tags that existed on the resources *at the moment the usage occurred*. If you add an `environment: production` or `cost-center: 4010` label to a fleet of 200 persistent disks today, you cannot back-query or attribute last month's costs by that label. Enforce resource labeling at birth via Terraform or Google Cloud Policy (`require-labels`).
5. **Over-Rightsizing Memory Can Trigger OOM Failures:** Active Assist Recommender analyzes historical P95 and P99 memory utilization. If an application utilizes JVM or Python memory pools that occasionally spike during end-of-month financial reconciliation runs, an 8-day recommender window will suggest downsizing RAM. Blindly applying rightsizing recommendations via automated scripts can cause fatal Out-Of-Memory (`OOMKilled`) pod evictions during unexpected traffic bursts.
6. **Cross-Project Discount Sharing Must Be Actively Verified:** In large enterprise organizations with multiple billing subaccounts, verify that **Commitment Discount Sharing** is explicitly turned on in the Cloud Billing Console. If discount sharing is disabled, a project running at 200% capacity in `us-central1` cannot consume surplus CUDs purchased by a sister project in the exact same region, resulting in wasted commitments on one project and full on-demand surcharges on the other.
