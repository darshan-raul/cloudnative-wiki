---
title: AWS Storage Gateway
description: AWS Storage Gateway — hybrid cloud storage connecting on-premises to S3. File Gateway (NFS/SMB), Volume Gateway (iSCSI), Tape Gateway (VTL) for backup.
tags:
  - aws
  - storage
  - hybrid
  - gateway
---

# AWS Storage Gateway

Storage Gateway connects on-premises storage to AWS cloud storage. It runs as a VM on-premises (VMware ESXi, Hyper-V, or as a hardware appliance) and provides file, block, and tape-based storage interfaces.

## Gateway Types

| Type | Protocol | Use Case | Backend |
|------|----------|---------|---------|
| File Gateway | NFS/SMB | File storage, backup | S3 |
| Volume Gateway (Cached) | iSCSI | Block storage, SAN replacement | S3 (with local cache) |
| Volume Gateway (Stored) | iSCSI | Full block backup, DR | S3 (all data in cloud) |
| Tape Gateway | iSCSI/VTL | Tape-based backup to cloud | S3/Glacier |

## File Gateway

### How It Works

```
On-Premises Application
  ├── NFS mount: storage-gateway.company.local:/sfshare
  └── SMB share: \\\\storage-gateway\\share
         │
         ▼
  Storage Gateway VM (on-prem)
         │
         │  (HTTPS, encrypted)
         ▼
  S3 Bucket (my-fsgateway-files)
       └── Objects (NFS filenames become S3 keys)
```

Files written to the NFS/SMB share are uploaded to S3 as objects. S3 is the backend — you can use S3 lifecycle rules, cross-region replication, and other S3 features.

### Creating a File Gateway

```bash
# Activate gateway (get activation code from the gateway VM console)
aws storagegateway activate-gateway \
  --gateway-type FILE_FGB \
  --gateway-name my-file-gateway \
  --gateway-region us-east-1 \
  --activation-key XXXX-XXXX

# Create file share (NFS)
aws storagegateway create-nfs-file-share \
  --gateway-arn arn:aws:storagegateway:us-east-1:123456789012:gateway/sgw-xxxxx \
  --nfs-file-share-defaults '{"FileShareType": "NFS", "Organization": "default"}' \
  --default-storage-class S3 \
  --location-arn arn:aws:s3:::my-fsgateway-bucket \
  --bucket-region us-east-1
```

### Mounting from Linux

```bash
sudo mount -t nfs -o rw,sync storage-gateway.company.local:/sfshare /mnt/on-prem-storage
```

### SMB Active Directory Integration

```bash
aws storagegateway create-smb-file-share \
  --gateway-arn arn:aws:storagegateway:us-east-1:123456789012:gateway/sgw-xxxxx \
  --storage-class S3 \
  --location-arn arn:aws:s3:::my-fsgateway-bucket \
  --domain "company.local" \
  --authentication ActiveDirectory
```

## Volume Gateway (Cached)

### How It Works

```
On-Premises Application (iSCSI)
  └── iSCSI target (e.g., /dev/sdb)
         │
         ▼
  Storage Gateway VM
         │
         │  Frequently accessed data cached locally
         │  All data stored in S3
         │
         ▼
  S3 Bucket (volume data)
```

Frequently accessed data is cached locally (SSD). All data is stored in S3. The local cache is the working set — it reduces S3 retrieval latency for active data.

### Creating a Volume

```bash
# Create cached volume
aws storagegateway create-cached-volume \
  --gateway-arn arn:aws:storagegateway:us-east-1:123456789012:gateway/sgw-xxxxx \
  --volume-size-in-bytes 1099511627776 \
  --snapshot-id "" \
  --target-name my-cached-volume
```

### Connecting via iSCSI

```bash
# On Linux
sudo iscsiadm --mode discovery --type sendtargets --portal 10.0.0.100:3260
sudo iscsiadm --mode node --targetname iqn.2010-11.company:storagegw-myvolume \
  --portal 10.0.0.100:3260 --login

# Mount
sudo mkfs.ext4 /dev/sdb1
sudo mount /dev/sdb1 /mnt/data
```

## Volume Gateway (Stored)

### How It Works

```
On-Premises Application (iSCSI)
  └── iSCSI target
         │
         ▼
  Storage Gateway VM
         │
         │  All data stored locally + async backup to S3
         │
         ▼
  S3 Bucket (point-in-time snapshots)
```

All data is stored locally. Async snapshots go to S3. This provides full local access (low latency) plus cloud backup (DR).

### Use Case

DR scenario: if the on-premises site fails, you can restore volumes to AWS (EC2 with the gateway) or recover from S3 snapshots.

## Tape Gateway (VTL)

### How It Works

```
Backup Application (Commvault, Veeam, etc.)
  └── iSCSI (shows as physical tape library)
         │
         ▼
  Tape Gateway VM
         │
         │  Virtual tapes → S3 → Glacier
         │
         ▼
  S3 / Glacier (tape archives)
```

Your existing backup software sees the Tape Gateway as a physical tape library (VTL). You write to virtual tapes, which are stored in S3 and archived to Glacier.

### Creating a Tape Gateway

```bash
# Create tape
aws storagegateway create-tapes \
  --gateway-arn arn:aws:storagegateway:us-east-1:123456789012:gateway/sgw-xxxxx \
  --tape-barcode-prefix AWS- \
  --num-tapes 5 \
  --tape-size-in-bytes 1073741824000
```

### Managing Tapes

```bash
# List tapes
aws storagegateway list-tapes --gateway-arn arn:aws:storagegateway:us-east-1:123456789012:gateway/sgw-xxxxx

# Archive tape (move to Glacier)
aws storagegateway/archive-tape \
  --gateway-arn arn:aws:storagegateway:us-east-1:123456789012:gateway/sgw-xxxxx \
  --tape-arn arn:aws:storagegateway:us-east-1:123456789012:gateway/sgw-xxxxx/tape/VTL-123456 \
  --vault-access-key xxx
```

## Architecture Patterns

### Hybrid Backup

```
On-Premises Data Center
  └── Tape Gateway (VTL)
        ├── Archive Tapes → S3 → Glacier (long-term)
        └── Recent Tapes → S3 Standard-IA (30-90 days)

AWS Cloud
  └── S3 (primary backup)
       └── S3 Glacier (archive)
```

### Cloud-Native File Storage

```
On-Premises Application
  └── File Gateway (NFS)
        └── S3 Bucket (shared across offices via CloudFront)
```

## Performance Tuning

```bash
# Upload buffer (local cache for File Gateway)
aws storagegateway update-gateway-information \
  --gateway-arn arn:aws:storagegateway:us-east-1:123456789012:gateway/sgw-xxxxx \
  --upload-buffer-size 2048  # MB

# CloudWatch metrics for Storage Gateway
aws cloudwatch get-metric-statistics \
  --namespace AWS/StorageGateway \
  --metric-name ReadBytes \
  --dimensions Name=GatewayId,Value=sgw-xxxxx
```

Key metrics:
- `ReadBytes` / `WriteBytes` — throughput
- `CloudBytesUploaded` / `CloudBytesDownloaded` — data transfer
- `CacheHitPercent` — cache hit ratio (Cached Volume Gateway)
- `UploadBufferPercentUsed` — upload buffer utilization

## Bandwidth Costs

Data transfer from on-premises to S3 via Storage Gateway:

| Direction | Cost |
|-----------|------|
| Upload (on-prem → S3) | $0.02-0.09/GB |
| Download (S3 → on-prem) | $0.02-0.09/GB |

For 10TB/month upload: 10TB × 1024GB × $0.02 = $205/month.

## Hardware Appliance

For high-throughput requirements (10+ Gbps), AWS offers a hardware appliance:

```
Storage Gateway Hardware Appliance
  ├── 8 TB usable storage (cache)
  ├── 10 Gbps network
  └── For remote offices with limited VM infrastructure
```

## References

- **Homepage:** https://aws.amazon.com/storage-gateway/
- **Documentation:** https://docs.aws.amazon.com/storage-gateway/
- **Pricing:** https://aws.amazon.com/storage-gateway/pricing/

## Pricing Examples

**Scenario 1:** A remote office with 50 users sharing 500GB of files via File Gateway. 500GB uploaded/month × $0.02/GB = $10/month for data transfer + S3 storage (500GB × $0.023 = $11.50/month). Total: ~$21.50/month. Without File Gateway, you'd need a 500GB EFS volume replicated somehow or a site-to-site VPN to a central EFS (cross-AZ costs). File Gateway is cost-effective for remote offices.

**Scenario 2:** An enterprise migrating from physical tape to Tape Gateway. 100 virtual tapes × 1TB each = 100TB of backups. S3 storage: 100TB × $0.023/GB = $2,300/month. Plus Glacier for old tapes: 80TB archived × $0.004/GB = $320/month. Total: ~$2,620/month. Physical tapes (10,000 cartridges × $25/month rental = $250/month) + offsite storage ($500/month) + manual retrieval ($200/month average) = $950/month. Tape Gateway is 2.7x more expensive but fully managed, infinite capacity, no manual tape handling.

## Nuggets & Gotchas

- **Storage Gateway VM must be activated before use — the activation key expires in 30 minutes:** If you deploy the VM and don't activate within 30 minutes, you'll need to redeploy. Plan activation as part of the VM deployment process.
- **File Gateway's upload buffer is separate from the local cache — both consume local disk:** If you have a 2TB SSD and allocate 1TB for upload buffer and 1TB for local cache, both are used for different purposes. Monitor `/opt/aws/storagegateway/cache` to ensure you don't run out of local storage.
- **Storage Gateway uploads to S3 asynchronously — there is a lag before data appears in S3:** For File Gateway, files appear in S3 within minutes to hours depending on upload buffer and network bandwidth. For critical data, don't rely on immediate S3 visibility.
- **Tape Gateway virtual tapes are immutable once written — you can't overwrite them:** A tape with corrupted data must be discarded and a new one created. Your backup software manages tape lifecycle — set retention policies there, not in the gateway.
- **Cross-AZ data transfer costs apply when Storage Gateway and S3 bucket are in different AZs:** If your gateway is in us-east-1a and your S3 bucket is in us-east-1b, cross-AZ upload costs $0.02/GB. Deploy the gateway in the same AZ as the S3 bucket to avoid this.