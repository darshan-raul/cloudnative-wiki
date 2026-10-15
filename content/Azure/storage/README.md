---
title: Azure Storage Architecture Hub
description: Master architectural guide to Microsoft Azure storage services — Blob Storage, Azure Data Lake Storage Gen2 (ADLS), Azure Files, Azure NetApp Files, Managed Disks, and Elastic SAN.
tags:
  - azure
  - storage
  - blob
  - adls
  - files
  - disks
date: 2026-10-15
---

# Azure Storage Architecture Hub 💽☁️

Microsoft Azure provides a comprehensive enterprise storage portfolio categorized into **Object & Data Lake Storage**, **Shared File Systems**, and **Hypervisor Block Storage**.

---

## Architectural Decision Matrix

```
                                  Storage Requirement
                                           │
            ┌──────────────────────────────┼──────────────────────────────┐
            ▼                              ▼                              ▼
    Object & Big Data             Shared Network File             Dedicated Block Storage
            │                              │                              │
    [[Azure/storage/blob|Azure Blob Storage]]          ┌───────┴───────┐              ┌───────┴───────┐
    - Standard Object Store         ▼               ▼              ▼               ▼
    - ADLS Gen2 (HNS)          [[Azure/storage/files-netapp|Azure Files]]   [[Azure/storage/files-netapp|Azure NetApp]] [[Azure/storage/disks-elastic-san|Managed Disks]]  [[Azure/storage/disks-elastic-san|Elastic SAN]]
    - Cold / Archive Tiers     - Cloud SMB/NFS - Sub-ms Bare Metal - VM Attached   - Multi-host iSCSI
                               - FSLogix       - SAP HANA / Oracle - Premium v2    - Shared Cluster
```

### Storage Capabilities Matrix

| Service                                                      | Protocol / Access                      | Redundancy Options                 | Max Capacity                       | Primary Fit                                                                                         |
| :----------------------------------------------------------- | :------------------------------------- | :--------------------------------- | :--------------------------------- | :-------------------------------------------------------------------------------------------------- |
| **[[Azure/storage/blob\|Azure Blob Storage & ADLS Gen2]]**   | REST, SDKs, HDFS (ABFS), SFTP          | LRS, ZRS, GRS, GZRS                | Exabytes (5 PiB per account)       | Unstructured object storage, static websites, big data analytics (Databricks/Synapse), archival.    |
| **[[Azure/storage/files-netapp\|Azure Files]]**              | SMB 2.1–3.1.1, NFSv4.1                 | LRS, ZRS, GRS, GZRS                | 100 TiB per share                  | Windows user profiles (FSLogix), legacy file server lift-and-shift, multi-pod container RWX shares. |
| **[[Azure/storage/files-netapp\|Azure NetApp Files (ANF)]]** | NFSv3, NFSv4.1, SMB 3.x, Dual-Protocol | LRS, ZRS, Cross-Region Replication | 100 TiB per volume (540 TiB pool)  | Sub-millisecond latency databases (SAP HANA, Oracle), high-performance computing (HPC), EDA.        |
| **[[Azure/storage/disks-elastic-san\|Azure Managed Disks]]** | Direct Hypervisor VHDX                 | LRS, ZRS                           | 64 TiB per disk                    | VM OS boot disks, transaction logs, databases needing dedicated IOPS (Premium SSD v2, Ultra Disk).  |
| **[[Azure/storage/disks-elastic-san\|Azure Elastic SAN]]**   | iSCSI Target                           | LRS, ZRS                           | Up to 2,000,000 IOPS / 80,000 MB/s | Storage consolidation for VM fleets, Azure VMware Solution (AVS) datastores, SCSI-3 clustering.     |

---

## Service Catalog

- [[Azure/storage/blob|Azure Blob Storage & Data Lake Storage Gen2 (ADLS)]] — Blob redundancy models (LRS, ZRS, GRS, GZRS), Access Tiers (Hot, Cool, Cold, Archive), ADLS Gen2 Hierarchical Namespace (HNS), User Delegation SAS, and Lifecycle Management.
- [[Azure/storage/files-netapp|Azure Files & Azure NetApp Files (ANF)]] — Cloud-native SMB 3.1.1 and NFSv4.1 shares vs bare-metal NetApp ONTAP infrastructure, sub-millisecond latencies, FSLogix user profiles, and SAP HANA storage.
- [[Azure/storage/disks-elastic-san|Azure Managed Disks & Elastic SAN Architecture]] — Standard HDD, Standard SSD, Premium SSD v1, Premium SSD v2 (independent IOPS/throughput), Ultra Disks, SCSI-3 Shared Disks, and cloud-native iSCSI SAN.

---

## Multi-Cloud Equivalents

| Capability               | Microsoft Azure                                          | Amazon Web Services (AWS)     | Google Cloud Platform (GCP)       |
| :----------------------- | :------------------------------------------------------- | :---------------------------- | :-------------------------------- |
| **Object Storage**       | [[Azure/storage/blob\|Azure Blob Storage]]               | Amazon S3                     | Cloud Storage (GCS)               |
| **Data Lake Engine**     | [[Azure/storage/blob\|ADLS Gen2 (Hierarchical)]]         | AWS Lake Formation / S3       | Cloud Storage (GCS with Dataplex) |
| **Managed File Shares**  | [[Azure/storage/files-netapp\|Azure Files]]              | Amazon EFS / FSx for Windows  | Cloud Filestore                   |
| **High-Performance NAS** | [[Azure/storage/files-netapp\|Azure NetApp Files]]       | Amazon FSx for NetApp ONTAP   | Google Cloud NetApp Volumes       |
| **Block Storage (VM)**   | [[Azure/storage/disks-elastic-san\|Azure Managed Disks]] | Amazon EBS                    | Persistent Disk / Hyperdisk       |
| **Clustered SAN**        | [[Azure/storage/disks-elastic-san\|Azure Elastic SAN]]   | Amazon FSx / EBS Multi-Attach | Hyperdisk Storage Pools           |
