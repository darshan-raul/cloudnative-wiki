---
title: "AWS backup and recovery"
description: "Design plans, vault governance and copies, test application restoration, and distinguish backup from continuous server disaster recovery."
tags:
  - cloud/aws/reliability
date: 2026-10-12
---

# AWS backup and recovery

Prerequisites: [[AWS/storage/README|storage models]], [[AWS/security/kms/README|KMS]] and [[AWS/reliability/README|recovery objectives]]. A successful backup job proves capture, not successful application restoration.

## AWS Backup design

Select supported resources, plans/schedules, lifecycle and vaults. Resource support differs for continuous backup, copies, encryption and restore options; consult the feature matrix instead of assuming identical behavior.

Use tagging or explicit selections with reviewed backup/restore roles. Plan destination-account/Region access and KMS permissions. Vault Lock governance/compliance choices have different removal consequences; test configuration with disposable data and obtain approval before an irreversible compliance lock.

Retention and replication are separate: a locally retained recovery point does not survive an account-wide failure merely because the source is Multi-AZ.

## Restore drill

Prerequisites: one tagged sandbox resource, dedicated vault/plan, scoped role, disposable data and an agreed spending limit.

1. Record a known marker and checksum in the source; create a backup using the supported resource workflow.
2. Verify recovery-point state, resource identity, retention and encryption key.
3. Restore into an isolated sandbox target. Never overwrite production during a practice drill.
4. Verify file/data integrity, application startup, credentials, networking and dependency access.
5. Measure elapsed detection-to-validated-service time and actual data-loss window. Compare with RTO/RPO.
6. Test with the intended recovery identity, not an administrator shortcut.
7. Remove restored resources and dedicated plans after acceptance; delete recovery points only when approved and permitted by retention/lock. Confirm copies and storage are accounted for.

An expected restore failure caused by missing destination-key permissions is useful evidence: repair the least-privilege key/role policy and retest. Preserve required backups.

### Worked EBS backup-to-new-volume drill

Choose **one encrypted, disposable EBS data volume**, not an EC2 root disk or a database with live writes. Follow [[AWS/storage/ebs/README|the EBS lab]] to create/mount it on a sandbox Linux instance. Record its volume ID, Region, AZ, filesystem type and mount path. Use a second isolated Linux recovery instance in the same target AZ, or the original lab instance with a different mount point. Never format the restored volume.

This exercise needs Python 3/Boto3, AWS CLI v2, a verified sandbox caller with Backup start/describe/metadata/delete permissions and restricted PassRole. Have an administrator provide two approved roles in `BACKUP_LAB_BACKUP_ROLE_ARN` and `BACKUP_LAB_RESTORE_ROLE_ARN`: both trust `backup.amazonaws.com`; the former can snapshot this source volume, the latter can create the restored EBS volume and use the required KMS keys. [Backup role guidance](https://docs.aws.amazon.com/aws-backup/latest/devguide/iam-service-roles.html) describes the backup/restore policy split. Also supply `BACKUP_LAB_RESOURCE_ARN` (`arn:aws:ec2:REGION:ACCOUNT:volume/vol-...`) and `BACKUP_LAB_AZ` matching the recovery instance. These roles are prerequisites, not permission to use an arbitrary administrator role.

Save `marker.txt` with the exact text `backup-fixture-v1` in the mounted source filesystem; record `sha256sum` of that file and `date -u`. Quiesce writes and `sync` before backup. Record a source-volume inventory using `aws ec2 describe-volumes --volume-ids "$BACKUP_LAB_SOURCE_VOLUME_ID"`; reconcile its actual ARN with the script input. Create an otherwise empty dedicated vault:

```bash
aws sts get-caller-identity
aws backup create-backup-vault --backup-vault-name wiki-ebs-restore-lab
```

Stop on a name collision. Do not add Vault Lock to this disposable lab. Save `backup_restore_ebs.py`:

```python
import json
import os
import time
import boto3

backup = boto3.client("backup")
VAULT = "wiki-ebs-restore-lab"

def wait_job(describe, job_id, id_field, state_field, success, failures):
    deadline = time.monotonic() + 1800
    while time.monotonic() < deadline:
        result = describe(**{id_field: job_id})
        state = result[state_field]
        if state == success:
            return result
        if state in failures:
            raise RuntimeError(f"{job_id}: {state}: {result.get('StatusMessage', '')}")
        time.sleep(15)
    raise TimeoutError(f"Still active: {job_id}; inspect before cleanup, do not resubmit")

capture = backup.start_backup_job(
    BackupVaultName=VAULT,
    ResourceArn=os.environ["BACKUP_LAB_RESOURCE_ARN"],
    IamRoleArn=os.environ["BACKUP_LAB_BACKUP_ROLE_ARN"],
    Lifecycle={"DeleteAfterDays": 1},
)
print("BackupJobId", capture["BackupJobId"], flush=True)
point = wait_job(backup.describe_backup_job, capture["BackupJobId"],
                 "BackupJobId", "State", "COMPLETED",
                 {"FAILED", "ABORTED", "EXPIRED", "PARTIAL"})
recovery_arn = point["RecoveryPointArn"]
print("RecoveryPointArn", recovery_arn, flush=True)
details = backup.describe_recovery_point(BackupVaultName=VAULT,
                                        RecoveryPointArn=recovery_arn)
assert details["ResourceArn"] == os.environ["BACKUP_LAB_RESOURCE_ARN"]
assert details["Status"] == "COMPLETED"
print("Encryption", details.get("IsEncrypted"), details.get("EncryptionKeyArn"))
metadata = backup.get_recovery_point_restore_metadata(
    BackupVaultName=VAULT, RecoveryPointArn=recovery_arn)["RestoreMetadata"]
# This is an EBS periodic snapshot restore, not an EC2/EFS resource recipe.
metadata.update({"availabilityZone": os.environ["BACKUP_LAB_AZ"],
                 "volumeType": "gp3"})
with open("ebs-restore-metadata.json", "w", encoding="utf-8") as out:
    json.dump(metadata, out, indent=2)
restore = backup.start_restore_job(
    RecoveryPointArn=recovery_arn, Metadata=metadata, ResourceType="EBS",
    IamRoleArn=os.environ["BACKUP_LAB_RESTORE_ROLE_ARN"],
)
print("RestoreJobId", restore["RestoreJobId"], flush=True)
finished = wait_job(backup.describe_restore_job, restore["RestoreJobId"],
                    "RestoreJobId", "Status", "COMPLETED", {"FAILED", "ABORTED"})
print("CreatedResourceArn", finished["CreatedResourceArn"], flush=True)
```

Run `python3 backup_restore_ebs.py` only after verifying the role/resource/AZ inputs. Keep the printed IDs if the process stops; inspect those jobs rather than starting another paid copy. Review the saved metadata before using the pattern elsewhere: volume size, encryption and key requirements come from this recovery point; no production volume ID is overwritten. [EBS-specific restoration options](https://docs.aws.amazon.com/aws-backup/latest/devguide/restoring-ebs.html), [backup job contract](https://docs.aws.amazon.com/aws-backup/latest/APIReference/API_StartBackupJob.html), [restore job contract](https://docs.aws.amazon.com/aws-backup/latest/APIReference/API_StartRestoreJob.html).

Set `BACKUP_LAB_RESTORED_VOLUME_ID` from CreatedResourceArn and inspect its AZ, gp3 type, encryption and `available` state. Compare it with the source ID; they must be different. Attach only this new volume to the recorded recovery instance:

```bash
aws ec2 describe-volumes --volume-ids "$BACKUP_LAB_RESTORED_VOLUME_ID"
aws ec2 attach-volume --volume-id "$BACKUP_LAB_RESTORED_VOLUME_ID" \
  --instance-id "$BACKUP_LAB_RECOVERY_INSTANCE_ID" --device /dev/sdf
```

On Nitro, `/dev/sdf` is an API attachment name, not proof of the guest device path. Use `lsblk -o NAME,SERIAL,FSTYPE,MOUNTPOINTS` and the EBS serial/by-id mapping to identify the exact restored volume/partition, then mount that filesystem read-only at a new empty directory. Follow the EBS lesson's device safeguards; use filesystem-specific read-only/no-replay options where required (for XFS, duplicate filesystem UUIDs need `nouuid`). Do not run `mkfs`, copy onto the source mount or attach an unknown device. `sha256sum` on the restored marker must equal the recorded source checksum. Record creation-to-integrity-validation elapsed time; this proves an EBS file restore, not a whole application's RTO.

Failure case: with an administrator-approved disposable-key setup, remove only the restore role's access to that key, attempt a restore and record its failure; restore the original grant and rerun once. Never disable a shared key. Metadata validation, role authorization and guest mounting are distinct checkpoints.

Cleanup: unmount/detach the new volume and wait until `available` before deleting its exact ID. Remove the source lab volume only after its owner approves. Delete the recorded recovery point using `delete-recovery-point --backup-vault-name wiki-ebs-restore-lab --recovery-point-arn ...` only if approved and retention permits, and verify the vault is empty before `delete-backup-vault`. If the point is retained for its one-day lifecycle, keep the vault and record the remaining storage charge rather than claiming immediate complete cleanup. Keep shared roles/keys, and record any copies separately.

## DRS versus backup

Elastic Disaster Recovery replicates supported servers into an AWS staging environment and supports drills/recovery/failback. It needs source agents, network capacity, staging resources and a failback procedure. It is not a database transaction-aware backup substitute.

Define test-network isolation, write quiescence, dependency order, DNS/client switching and failback data reconciliation. “Recovery in minutes” is a capability statement, not a guaranteed complete workload RTO. Staging, recovery instances, storage and replication services can incur charges.

## References

- [AWS Backup documentation](https://docs.aws.amazon.com/aws-backup/latest/devguide/whatisbackup.html).
- [Supported resource features](https://docs.aws.amazon.com/aws-backup/latest/devguide/backup-feature-availability.html).
- [Vault Lock](https://docs.aws.amazon.com/aws-backup/latest/devguide/vault-lock.html).
- [Elastic Disaster Recovery](https://docs.aws.amazon.com/drs/latest/userguide/what-is-drs.html).
- Related: [[AWS/storage/ebs/amazon-data-lifecycle-manager|DLM]] and [[AWS/migration/README|migration/cutover]].
