---
title: Amazon FSx
description: Amazon FSx — managed Windows file servers (SMB) and Lustre parallel file systems. Integration with AD, high performance, and S3 data linking.
tags:
  - aws
  - storage
  - fsx
  - windows
  - lustre
---

# Amazon FSx

FSx provides fully managed file storage for two specialized workloads: **Windows File Server** (SMB, Active Directory) and **Lustre** (high-performance parallel file system for HPC and ML).

## FSx for Windows File Server

### Use Case

Enterprise Windows applications requiring SMB file shares: 
- Microsoft SQL Server (native file access)
- Microsoft SharePoint
- Custom .NET applications with file-based storage
- SAP with Windows back-end

### Features

- **SMB 3.x** support (up to SMB 3.1.1)
- **Active Directory** integration (Kerberos, NTLM, ACLs)
- **Multi-AZ** deployment for HA
- **On-premises access** via VPN or Direct Connect
- **Shadow copies** (backup/restore from previous versions)

### Creating a FSx for Windows File System

```bash
aws fsx create-file-system \
  --file-system-type WINDOWS \
  --storage-capacity 1000 \
  --subnet-ids subnet-xxxxx \
  --windows-configuration '{
    "ActiveDirectoryId": "d-xxxxx",
    "ThroughputCapacity": 256,
    "WeeklyMaintenanceStartTime": "1:00:00",
    "DailyAutomaticBackupStartTime": "03:00:00",
    "AutomaticBackupRetentionDays": 7,
    "CopyTagsToBackups": true
  }'
```

### Connecting from Windows EC2

```powershell
# Map network drive
net use Z: \\fs-xxxxx.example.com\share /persistent:yes

# From Linux
sudo mount -t cifs //fs-xxxxx.example.com/share /mnt/fsx \
  -o user=admin,password=secret,vers=3.0
```

### Performance

| Deployment | Throughput | IOPS | Use |
|-----------|-----------|------|-----|
| Single-AZ | 2-350 MB/s | Up to 350,000 | Dev/test |
| Multi-AZ | 2-350 MB/s | Up to 350,000 | Production HA |

## FSx for Lustre

### Use Case

High-performance computing and ML workloads:
- ML training (TensorFlow, PyTorch data loading)
- Scientific computing (genomics, climate modeling)
- Financial simulations
- Media rendering (video processing)

### How Lustre Works

```
Compute Cluster (EC2 instances)
       │
       ▼
  Lustre File System
  (Metadata Server + Object Storage)
       │
       ▼
  S3 Bucket (linked, optional)
  (data lives in S3, cached in Lustre)
```

Lustre is a parallel file system — multiple storage servers (OSS) serve data in parallel to multiple clients. It scales to petabytes and hundreds of GB/s throughput.

### S3 Data Repository

Link FSx Lustre to an S3 bucket for S3-backed file systems:

```bash
aws fsx create-file-system \
  --file-system-type LUSTRE \
  --storage-capacity 1200 \
  --subnet-ids subnet-xxxxx \
  --lustre-configuration '{
    "ImportPath": "s3://my-training-data/",
    "ImportedFileChunkSizeMiB": 32,
    "DataCompressionType": "LZ4",
    "WeeklyMaintenanceStartTime": "1:00:00"
  }'
```

Files in S3 appear in FSx (import). Writes to FSx can be exported back to S3 (export).

### Data Compression

Lustre supports transparent compression (LZ4):

```bash
aws fsx create-file-system \
  --file-system-type LUSTRE \
  --storage-capacity 1200 \
  --subnet-ids subnet-xxxxx \
  --lustre-configuration '{
    "ImportPath": "s3://my-data/",
    "DataCompressionType": "LZ4"
  }'
```

Compression is transparent to applications. LZ4: 2-3x compression ratio typical on text/binary data.

### Mounting Lustre

```bash
# Install Lustre client
sudo yum install lustre-client  # Amazon Linux
sudo apt install lustre-client   # Ubuntu

# Mount
sudo mount -t lustre fs-xxxxx@tcpfs.fs-xxxxx.fsx.us-east-1.amazonaws.com@tcp:/fsx /mnt/lustre
```

### Performance Tiers

| Tier | Storage | Use |
|------|---------|-----|
| Scratch | Temporary (no replication) | Short-term, bursty workloads |
| Persistent | Replicated in single AZ | Long-term, consistent performance |

## FSx for OpenZFS

Managed OpenZFS file system (file storage, not block). Simpler than Windows or Lustre, for general-purpose Linux workloads.

## FSx for NetApp ONTAP

Fully managed ONTAP file system with advanced features:
- SnapMirror (replication)
- FlexCache (caching)
- Data tiering to S3
- Cloning (instant, zero-copy)

## Performance Comparison

| FSx Type | Max Throughput | Max IOPS | Latency |
|----------|---------------|----------|---------|
| Windows | 350 MB/s | 350,000 | 0.5-1ms |
| Lustre (Scratch) | 2,000 MB/s | 1,000,000+ | 0.1ms |
| Lustre (Persistent) | 2,500 MB/s | 1,000,000+ | 0.1ms |
| ONTAP | 2,200 MB/s | 400,000 | 0.5-1ms |

## Costs

| Type | Cost |
|------|------|
| Windows | $0.138/GB/mo (storage) + $0.013/GB/mo (backup) |
| Lustre Scratch | $0.136/GB/mo |
| Lustre Persistent | $0.22/GB/mo |
| ONTAP | $0.23/GB/mo |

## Limits

| Resource | Limit |
|----------|-------|
| Max storage (Windows) | 65,536 GB (64 TB) |
| Max storage (Lustre) | 1,000,000 GB (1 PB) |
| Max throughput (Lustre) | 2,500 MB/s |
| Max file size (Lustre) | 16 TiB |

## References

- **Homepage:** https://aws.amazon.com/fsx/
- **Documentation:** https://docs.aws.amazon.com/fsx/
- **Pricing:** https://aws.amazon.com/fsx/pricing/

## Pricing Examples

**Scenario 1:** A Windows file server for 50 users with 2TB of shared files. FSx for Windows: 2,000GB × $0.138 = $276/month. Plus throughput (256 MB/s = $0.013/GB/mo × 256 GB = $3.33/month). Total: ~$280/month. Compare to an EC2 instance with 2TB EBS (200GB × $0.08 = $16/month) + EC2 cost (m5.xlarge = $140/month) = $156/month. FSx is 80% more expensive but fully managed with AD integration — no EC2 maintenance.

**Scenario 2:** An ML training job processing 50TB of data from S3 using FSx Lustre. 50TB × $0.136/GB = $6,800/month. A better approach: link FSx Lustre to S3 (import on mount), process, then delete the FSx. 50TB Lustre for 3 days/week = 150TB-days/month × (50TB × $0.136/30) = ~$340/month. Total: $340/month vs $6,800/month.

## Nuggets & Gotchas

- **FSx for Windows is single-AZ by default — enable Multi-AZ for production:** Multi-AZ adds 2x cost but provides failover. For databases (SQL Server) and critical file shares, always use Multi-AZ.
- **FSx Lustre Scratch has no replication — if a storage server fails, data is lost:** Scratch is for temporary workloads (ML training, video rendering). For persistent data, use Persistent Lustre (replicated within single AZ).
- **Lustre imports from S3 are lazy (on-demand) — first access is slow:** When you first read a file from S3 via Lustre, it fetches from S3 and caches. This first-read latency can be 10-30 seconds for large files. For ML training, use `hdf5` or preload data before training starts.
- **FSx for Windows charges for throughput capacity (MB/s) even when idle:** A 256 MB/s file system costs ~$3.33/month even if unused. Right-size throughput capacity — a small team doesn't need 256 MB/s.
- **Lustre file system size is fixed at creation — you can't expand without creating a new one:** Plan capacity ahead. For ML workloads with growing datasets, create the file system with enough headroom or plan migration to a larger one.