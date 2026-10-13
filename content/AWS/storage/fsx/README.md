---
title: "Amazon FSx"
description: "FSx is a family of four managed filesystem products, not a single filesystem with interchangeable settings."
tags:
  - aws/storage
date: 2026-10-12
---

# Amazon FSx

FSx is a family of four managed filesystem products, not a single filesystem with interchangeable settings. Learn [[AWS/storage/README|storage selection]], [[AWS/networking/README|VPC networking]] and [[AWS/security/iam/README|IAM]] first.

## Product selection

| Product             | Workload and integration                                                             |
| ------------------- | ------------------------------------------------------------------------------------ |
| Windows File Server | SMB and Active Directory; Windows applications requiring NTFS-style access controls. |
| Lustre              | Parallel HPC/analytics filesystem, with supported S3 data-repository integrations.   |
| NetApp ONTAP        | NFS/SMB/iSCSI, enterprise storage features and compatible migration workflows.       |
| OpenZFS             | NFS with ZFS snapshots/clones and application-appropriate deployment choices.        |

Deployment type, availability, protocol, backup, scaling and encryption differ by product. A generic FSx create command cannot configure all four. Windows throughput is provisioned in MB/s and has its own price dimension; it is not a GB storage rate. Lustre storage can grow for eligible persistent and scratch-2 deployments, subject to restrictions/cooldowns; it is not universally fixed at creation.

## Architecture and security

For Windows, establish AD prerequisites, DNS and service-account/network requirements before creation; choose single/Multi-AZ from availability needs. For Lustre, choose scratch versus persistent, client compatibility and repository import/export semantics. S3 integration does not mean every filesystem write is instantaneously a durable S3 backup.

For ONTAP, plan storage virtual machines, volumes and multiprotocol identity mappings. For OpenZFS, distinguish filesystem/volume deployment characteristics, snapshots and backup. Across products, validate routing/security groups, encryption keys, identity permissions and recovery paths. Follow the selected filesystem's protocol ports; do not expose them publicly.

## Selection and restore exercise

Prerequisites: supported clients, isolated networking, an authorized role and a budget. Choose one product and write down why the others do not meet the protocol/application requirements. Deploy the smallest suitable sandbox through the product's owning guide, mount it with the correct client and write a checksum-labelled dataset.

Expected observations: authorized clients can read/write; an unauthorized security-group path or principal cannot. Create a backup/snapshot supported by that product, restore separately and verify data plus permissions. Test a documented scaling action only if the selected deployment supports it; record the wait/cooldown rather than claiming instant scaling.

Unmount clients and remove sandbox filesystems, backups, repository associations and any directory infrastructure you created. Retained backups continue to cost money.

## Comparable cost model

Use storage GB-months, provisioned throughput units, IOPS where applicable, backups and transfer/request costs. For a three-days-per-week schedule, monthly runtime is approximately 3 × (weeks in month) × 24 hours, not three days total. Compare the same 2-TB dataset and recovery design against EBS/EFS; do not replace it with a 200-GB baseline.

## Product-specific architecture and workflows

| Product             | Protocol/application fit          | Integration to plan                                                                             |
| ------------------- | --------------------------------- | ----------------------------------------------------------------------------------------------- |
| Windows File Server | SMB/Windows application semantics | Active Directory, DNS, security groups and Windows permissions.                                 |
| Lustre              | Parallel filesystem clients/HPC   | Compatible Lustre client, networking, scratch/persistent choice and S3 repository associations. |
| OpenZFS             | Supported NFS/ZFS workloads       | Export permissions, snapshots/clones and deployment topology.                                   |
| ONTAP               | Supported NFS/SMB/iSCSI workloads | Storage virtual machines, volumes, identity mapping and tiering.                                |

```text
Windows client → SMB → FSx Windows + AD identity
HPC clients → Lustre → FSx Lustre ↔ supported S3 repository association
NFS clients → OpenZFS / ONTAP → managed filesystem volumes
```

FSx for Lustre import/export is a configured workflow, not proof that every write instantly exists as an independently recoverable S3 object. Scratch and persistent deployments have different durability/recovery characteristics; storage growth depends on supported deployment type and documented limits/cooldowns.

## Windows and Lustre walkthrough comparison

For Windows, validate domain service accounts, DNS/ports and subnet/HA requirements first. After creation, retrieve the actual DNS/share path and mount using an authorized identity. Verify both Windows filesystem permissions and share-level access. A successful SMB connection does not establish correct application permissions.

For Lustre, select supported capacity/performance/deployment, install the compatible client and use the filesystem's real DNS/mount name from DescribeFileSystems. Load a small S3-linked dataset if a repository association is in scope, verify import/export status and checksum the filesystem and object views. Do not install an obsolete hard-coded client package merely because an old note showed it.

## Performance and recovery measurements

Separate storage capacity, provisioned throughput, IOPS where applicable and client/network limits. Measure concurrent readers/writers, small-file metadata operations and sequential transfer independently. Do not promise one throughput ratio across all products.

Create the selected product's supported backup/snapshot and restore to an isolated target. Review whether application state/ACLs and externally configured AD/repository dependencies are included. Filesystem backup success does not restore every directory service or cross-account permission.

Compute cost from identical data size and elapsed time: storage capacity and provisioned throughput have different units. If using three days per week, multiply by the number of weeks—not three total days for the month. Remove test filesystems/associations and approved recovery copies, but do not delete shared AD resources.

## Worked Windows SMB and backup lab

This recipe chooses **FSx for Windows, SINGLE_AZ_2, 32-GiB SSD, 8-MB/s throughput**, not an HA recommendation. Obtain budget approval for the filesystem, backup/restore copy, Windows client and any directory resources. Before running it:

- Have an existing authorized AWS Managed Microsoft AD directory in the same VPC, an available private subnet, DNS/AD connectivity and a domain-joined Windows test client. Complete the [Windows getting-started prerequisites](https://docs.aws.amazon.com/fsx/latest/WindowsGuide/getting-started.html); do not create or delete a shared directory as implicit cleanup.
- Create a dedicated filesystem security group with SMB TCP 445 from the authorized client security group and the [required directory-service connectivity](https://docs.aws.amazon.com/fsx/latest/WindowsGuide/limit-access-security-groups.html). A second test client has no permitted SMB path. Do not use a public client allowlist.
- Configure Python/Boto3, temporary operator credentials and the intended Region. Authorize the FSx create/describe/backup/restore/delete actions and required service-linked-role/KMS setup. Set FSX_LAB_SUBNET_ID, FSX_LAB_SECURITY_GROUP_ID and FSX_LAB_DIRECTORY_ID to the verified existing identifiers. Confirm the selected deployment/throughput is supported in that Region before creation.

Run these Python cells in the same session, preserving returned identifiers:

```python
import os
import time
import uuid
import boto3

fsx = boto3.client("fsx")
subnet = os.environ["FSX_LAB_SUBNET_ID"]
security_group = os.environ["FSX_LAB_SECURITY_GROUP_ID"]
directory = os.environ["FSX_LAB_DIRECTORY_ID"]
windows = {"ActiveDirectoryId": directory, "DeploymentType": "SINGLE_AZ_2",
           "ThroughputCapacity": 8, "AutomaticBackupRetentionDays": 0}

def wait_filesystem(identifier):
    deadline = time.monotonic() + 1800
    while time.monotonic() < deadline:
        filesystem = fsx.describe_file_systems(FileSystemIds=[identifier])["FileSystems"][0]
        if filesystem["Lifecycle"] == "AVAILABLE":
            return filesystem
        if filesystem["Lifecycle"] == "FAILED":
            raise RuntimeError(filesystem.get("FailureDetails", filesystem))
        time.sleep(15)
    raise TimeoutError(f"Inspect {identifier}; do not create another filesystem blindly")

created = fsx.create_file_system(
    ClientRequestToken=str(uuid.uuid4()), FileSystemType="WINDOWS",
    StorageType="SSD", StorageCapacity=32, SubnetIds=[subnet],
    SecurityGroupIds=[security_group], WindowsConfiguration=windows,
    Tags=[{"Key": "Purpose", "Value": "cloudnative-wiki-fsx-lab"}],
)["FileSystem"]
source_id = created["FileSystemId"]
source = wait_filesystem(source_id)
print(source_id, source["DNSName"])
```

Record the creation token before submission if implementing automatic retries; reuse it with identical parameters, not a fresh token on an uncertain failure. The example makes a single submission. A timeout leaves a billable resource to inspect.

On the authorized Windows client, replace the DNS value with the returned source DNS. Use a permitted domain identity via the credential prompt; do not paste a password into a mount command:

```powershell
$FsxLabDns = "REPLACE_WITH_RETURNED_SOURCE_DNS"
$FsxLabCredential = Get-Credential
New-PSDrive -Name FsxLab -PSProvider FileSystem -Root "\\$FsxLabDns\share" -Credential $FsxLabCredential
New-Item -ItemType Directory -Path "FsxLab:\cloudnative-wiki-fsx-lab" -Force
Set-Content -Path "FsxLab:\cloudnative-wiki-fsx-lab\orders.csv" -Encoding ASCII -Value "order_id,total`nlab-001,25`nlab-002,40"
$FsxLabExpectedHash = (Get-FileHash "FsxLab:\cloudnative-wiki-fsx-lab\orders.csv" -Algorithm SHA256).Hash
$FsxLabExpectedHash
```

Expect two order rows totaling 65 and record the hash outside the filesystem. Test the denied client with `Test-NetConnection $FsxLabDns -Port 445`; the excluded network path should fail. Distinguish this network denial from a reachable client's NTFS/share authorization denial; inspect ACLs with `Get-Acl` and test any ACL change only inside this lab directory.

Close writers before backup. In the same Python session:

```python
backup_id = fsx.create_backup(
    FileSystemId=source_id, ClientRequestToken=str(uuid.uuid4()),
    Tags=[{"Key": "Purpose", "Value": "cloudnative-wiki-fsx-lab"}],
)["Backup"]["BackupId"]
deadline = time.monotonic() + 1800
while time.monotonic() < deadline:
    backup = fsx.describe_backups(BackupIds=[backup_id])["Backups"][0]
    if backup["Lifecycle"] == "AVAILABLE":
        break
    if backup["Lifecycle"] == "FAILED":
        raise RuntimeError(backup.get("FailureDetails", backup))
    time.sleep(15)
else:
    raise TimeoutError(f"Inspect backup {backup_id}")

restored_id = fsx.create_file_system_from_backup(
    BackupId=backup_id, ClientRequestToken=str(uuid.uuid4()),
    SubnetIds=[subnet], SecurityGroupIds=[security_group],
    WindowsConfiguration=windows,
    Tags=[{"Key": "Purpose", "Value": "cloudnative-wiki-fsx-lab-restore"}],
)["FileSystem"]["FileSystemId"]
restored = wait_filesystem(restored_id)
print(restored_id, restored["DNSName"])
```

Map the restored DNS as another drive, not over the original. Verify its bytes and ACLs:

```powershell
$FsxLabRestoreDns = "REPLACE_WITH_RETURNED_RESTORE_DNS"
New-PSDrive -Name FsxRestore -PSProvider FileSystem -Root "\\$FsxLabRestoreDns\share" -Credential $FsxLabCredential
$FsxLabActualHash = (Get-FileHash "FsxRestore:\cloudnative-wiki-fsx-lab\orders.csv" -Algorithm SHA256).Hash
if ($FsxLabActualHash -ne $FsxLabExpectedHash) { throw "Restored content differs" }
Import-Csv "FsxRestore:\cloudnative-wiki-fsx-lab\orders.csv"
Get-Acl "FsxRestore:\cloudnative-wiki-fsx-lab\orders.csv"
Remove-PSDrive FsxRestore
Remove-PSDrive FsxLab
```

Expected rows remain lab-001/25 and lab-002/40; verify the intended domain user's access separately. Backup does not recreate the external AD environment. After recording evidence, review both IDs and invoke `fsx.delete_file_system(FileSystemId=restored_id, WindowsConfiguration={"SkipFinalBackup": True})` and the equivalent for source_id only for these disposable filesystems. Inspect deletion completion and delete backup_id with `fsx.delete_backup(BackupId=backup_id)` after retention approval; remove only the dedicated security group/client if unused. Do not delete the shared directory. A failed create/restore can still leave resources requiring inspection.

For a parallel Linux/HPC exercise, use the separate [FSx for Lustre getting-started tutorial](https://docs.aws.amazon.com/fsx/latest/LustreGuide/getting-started.html), including its release-compatible client and real mount name. Windows SMB commands are not a Lustre client recipe. [Create filesystem contract](https://docs.aws.amazon.com/cli/latest/reference/fsx/create-file-system.html), [backup creation](https://docs.aws.amazon.com/cli/latest/reference/fsx/create-backup.html), [restore configuration](https://docs.aws.amazon.com/cli/latest/reference/fsx/create-file-system-from-backup.html).

## References

- [FSx product documentation](https://docs.aws.amazon.com/fsx/)
- [Lustre storage scaling](https://docs.aws.amazon.com/fsx/latest/LustreGuide/managing-storage-capacity.html)
- [FSx pricing dimensions](https://aws.amazon.com/fsx/pricing/)

## Across the wiki

- [[Kubernetes/eks/storage/efs-csi|EFS CSI Driver]] — shared file storage (Kubernetes)
- [[Azure/compute/aks/storage-csi-files-blob|AKS Shared Storage CSI — Azure Files (NFS/SMB) and Azure Blob CSI Architecture]] — shared file storage (Azure)
- [[GCP/compute/gke/filestore-csi|GKE Filestore CSI Driver — Managed NFS and ReadWriteMany (RWX) Architecture]] — shared file storage (GCP)
