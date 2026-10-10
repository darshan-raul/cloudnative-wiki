---
title: EFS Cost Optimization
description: Optimizing Amazon EFS storage costs — Standard vs One Zone storage classes, Lifecycle Management, and throughput modes
tags:
  - aws
  - cost-management
  - efs
  - storage
date: 2026-10-04
---

# Amazon EFS Cost Optimization

Amazon Elastic File System (Amazon EFS) provides serverless, elastic shared POSIX storage. Without proper configuration, high baseline storage costs and unoptimized throughput modes can inflate expenses.

---

## 1. Storage Class Optimization

EFS provides four storage classes with dramatic cost differences:

| Storage Class                  | Availability      | Storage Cost / GB-mo  | Use Case                                  |
| :----------------------------- | :---------------- | :-------------------- | :---------------------------------------- |
| **EFS Standard**               | Multi-AZ (99.99%) | ~$0.30                | Active shared production workloads        |
| **EFS Infrequent Access (IA)** | Multi-AZ          | ~$0.025 (92% savings) | Files unaccessed for > 7 to 90 days       |
| **EFS Archive**                | Multi-AZ          | ~$0.008 (97% savings) | Long-term archival and compliance data    |
| **EFS One Zone**               | Single AZ         | ~$0.16 (47% savings)  | Dev/test, build caches, reproducible data |

---

## 2. EFS Lifecycle Management

Always enable **Lifecycle Management** on all EFS file systems:

- Set **Transition into IA:** 14 or 30 days since last access.
- Set **Transition into Archive:** 90 days since last access.
- Set **Transition out of IA (Intelligent-Tiering):** `On first access` to avoid continuous read charges on repeatedly touched files.

---

## 3. Throughput Mode Cost Trade-offs

- **Elastic Throughput (Recommended for Spiky Workloads):** Pay only for data read/written ($0.03/GB read, $0.06/GB write). Zero hourly provisioning fee.
- **Provisioned Throughput:** Fixed hourly fee per MB/s. Only cost-effective if baseline throughput exceeds 50% utilization continuously.
