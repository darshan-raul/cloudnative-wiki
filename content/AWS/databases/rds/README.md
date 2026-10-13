---
title: "Amazon RDS"
description: "RDS manages infrastructure for relational databases, but you still own schema design, indexes, query tuning, database users and recovery verification."
tags:
  - aws/databases
date: 2026-10-12
---

# Amazon RDS

RDS manages infrastructure for relational databases, but you still own schema design, indexes, query tuning, database users and recovery verification. Supported engine families include Db2, MariaDB, MySQL, Oracle, PostgreSQL and SQL Server, with engine/version-specific licensing and features.

Prerequisites: [[AWS/databases/README|database selection]], [[AWS/networking/README|networking]] and [[AWS/security/iam/README|IAM]]. Compare [[AWS/databases/aurora/README|Aurora]] where its engine compatibility and clustered design fit.

## Availability and scaling

Classic Multi-AZ DB instances use a synchronous standby that is not a read target. Their failover typically takes 60–120 seconds, depending on activity and conditions; application reconnect/DNS behavior matters. Multi-AZ DB clusters are a separate mode with readable standby instances. Do not apply either topology's rules to every RDS deployment.

Read replicas support engine-specific replication and promotion. MySQL/MariaDB/PostgreSQL support up to fifteen replicas per source in the current API; Db2 supports up to three, while other engines differ. Replica lag is not a guaranteed failover duration. Vertical scaling, storage scaling and replica addition have distinct restart/downtime implications.

## Networking, credentials and recovery

A publicly accessible RDS instance is possible with appropriate subnet routing and security groups, but private access is generally the safer application baseline. Security groups, TLS, database authentication and supported IAM authentication are separate layers. Never paste master passwords into shell history.

A DB subnet group should match the intended HA topology. Parameter groups tune engine configuration; option groups apply only to applicable engines/features. Backups and maintenance have separate windows. Automated backups/PITR and manual snapshots have different retention/lifecycle properties. Restores create new instances; rehearse credential, endpoint, KMS and application cutover.

## Observability and cost

CloudWatch Database Insights is the current console experience after Performance Insights' July 31, 2026 end-of-life. Standard and Advanced modes have different capabilities/retention/billing. Do not infer that every underlying API parameter was removed. Enhanced Monitoring provides OS-level telemetry and requires its role/configuration.

RDS gp3 baseline depends on engine and allocated size: SQL Server starts at 3,000 IOPS/125 MiB/s; other qualifying engines cross capacity thresholds into 12,000 IOPS/500 MiB/s. Do not apply EBS gp3 economics blindly. Bill instance hours, storage, excess IOPS/throughput, backups, replication/transfer, licenses and monitoring.

## Sandbox failover and restore exercise

Use a small disposable database with budget approval, private networking, a permitted client and a labelled test table. Observe connections, latency and replica lag. If testing Multi-AZ, record topology and actual failover time; the expected behavior is a reconnect requirement, not uninterrupted client sessions.

Restore a snapshot/PITR into an isolated instance and verify data plus application authentication. An unauthorized client must be denied without opening the database to the internet. Delete disposable instances/replicas and reviewed snapshots afterward; stopping an instance is not permanent removal or a promise of zero storage charges.

## Engine, compute and storage choices

| Engine family            | Typical compatibility decision                                                     |
| ------------------------ | ---------------------------------------------------------------------------------- |
| PostgreSQL/MySQL/MariaDB | Validate upstream version/features/extensions and driver behavior.                 |
| Oracle/SQL Server        | Validate licensing, edition, option groups and engine-specific HA/replica support. |
| Db2                      | Validate supported edition/license/deployment and migration capabilities.          |

General-purpose, memory-optimized and burstable instance classes are workload choices, not a permanent “small/medium/large” table. Burstable credits can add capacity/cost constraints. Measure peak connections, working-set memory, CPU and storage latency together.

Storage is allocated separately from compute. gp3 performance depends on engine/size threshold; provisioned IOPS and storage autoscaling have their own supported limits. A storage increase does not solve every query/index problem and may not be reversibly shrinkable.

## Instance provisioning sequence

1. Select supported engine/version and compute/storage size.
2. Create the correct subnet group and restrict security groups to the application path.
3. Choose encryption/key, credential-management and supported authentication.
4. Configure backup retention/window separately from maintenance.
5. Create/wait for the instance; inspect actual endpoint and availability.
6. Connect with a verified TLS client and only the necessary database privileges.
7. Test backup/restore and failover for the selected topology.

A Describe call retrieves the real endpoint without exposing a password:

```bash
aws rds describe-db-instances --db-instance-identifier sandbox-db \
  --query 'DBInstances[0].{Endpoint:Endpoint,Status:DBInstanceStatus,Engine:Engine}'
aws rds describe-db-parameters \
  --db-parameter-group-name sandbox-params \
  --query 'Parameters[].{Name:ParameterName,Value:ParameterValue,ApplyType:ApplyType}'
```

These are read-only examples needing real identifiers and permissions. For client TLS, use the current regional/global RDS CA bundle and hostname verification; sslmode=require encrypts but does not provide the same server-identity verification as verify-full with an appropriate trust root.

## Parameter and option groups

Parameter groups resemble engine configuration files. Dynamic parameters may apply immediately; static ones require reboot. Choose the parameter-group family matching the engine/version and examine allowed values/apply type before changes. max_connections, shared_buffers, work_mem or innodb_buffer_pool_size are engine-specific; a fixed numeric example is not a universal tuning recommendation.

Option groups enable supported engine features where applicable; they are not available/identical for every engine. Attach changes deliberately and inspect reboot/maintenance requirements. Protect the database from a deployment that lowers connections/memory without testing the client workload.

## HA, replicas and backups compared

```text
Classic Multi-AZ: application → primary ↔ synchronous standby (not read target)
Read scaling: application → primary + supported async read replicas
Multi-AZ DB cluster: distinct cluster topology with readable standbys
```

A promoted read replica and a managed HA failover have different procedures/data-loss behavior. Restore creates a new database identity/endpoint; applications, secrets, KMS/network access and DNS require a cutover plan. Snapshot retention and automated PITR windows differ. Test counts, representative rows and application semantics, not only available status.

Enhanced Monitoring needs an authorized monitoring role and selected interval; CloudWatch metrics, OS telemetry and Database Insights database-load evidence serve different diagnostics. Distinguish queue/I/O latency, connection exhaustion and bad SQL before resizing. Include retained storage/backups and stopped-instance behavior in costs.

## Worked private PostgreSQL failover and snapshot restore

This lab deliberately uses a **classic Multi-AZ DB instance**, not a Multi-AZ DB cluster, and incurs two-instance HA plus restore/storage/secret costs. Obtain approval before creation. Have an existing DB subnet group spanning two private AZs, a dedicated DB security group allowing TCP 5432 only from the lab client's security group, a reachable Linux client with `psql`, and Python/Boto3 with temporary operator credentials in the chosen Region. Set RDS_LAB_SUBNET_GROUP and RDS_LAB_SECURITY_GROUP_ID to those verified resources. A second client must have no allowed DB path. The operator needs the create/describe/reboot/snapshot/restore/delete actions and required Secrets Manager/KMS/service-role permissions; the data client is a separate database identity.

Use these cells in one Python session. Discover the regional default PostgreSQL version and ensure the selected burstable class supports this configuration before spending money; abort rather than silently choosing a larger class.

```python
import os
import time
import uuid
import boto3

rds = boto3.client("rds")
versions = rds.describe_db_engine_versions(Engine="postgres", DefaultOnly=True)["DBEngineVersions"]
assert len(versions) == 1, "Select one supported regional PostgreSQL version explicitly"
engine_version = versions[0]["EngineVersion"]
instance_class = "db.t4g.micro"
options = rds.describe_orderable_db_instance_options(
    Engine="postgres", EngineVersion=engine_version,
    DBInstanceClass=instance_class,
)["OrderableDBInstanceOptions"]
assert any(o["StorageType"] == "gp3" and o["MultiAZCapable"]
           and o["SupportsStorageEncryption"] for o in options), "Configuration unavailable; review alternatives"
source_id = "wiki-rds-lab-" + uuid.uuid4().hex[:8]
subnet_group = os.environ["RDS_LAB_SUBNET_GROUP"]
database_sg = os.environ["RDS_LAB_SECURITY_GROUP_ID"]
rds.create_db_instance(
    DBInstanceIdentifier=source_id, Engine="postgres", EngineVersion=engine_version,
    DBInstanceClass=instance_class, AllocatedStorage=20, StorageType="gp3",
    DBName="wikilab", MasterUsername="labadmin", ManageMasterUserPassword=True,
    DBSubnetGroupName=subnet_group, VpcSecurityGroupIds=[database_sg],
    PubliclyAccessible=False, StorageEncrypted=True, MultiAZ=True,
    BackupRetentionPeriod=1, DeletionProtection=False,
    Tags=[{"Key": "Purpose", "Value": "cloudnative-wiki-rds-lab"}],
)
rds.get_waiter("db_instance_available").wait(
    DBInstanceIdentifier=source_id, WaiterConfig={"Delay": 30, "MaxAttempts": 60},
)
source = rds.describe_db_instances(DBInstanceIdentifier=source_id)["DBInstances"][0]
print(source_id, source["Endpoint"]["Address"], source["MasterUserSecret"]["SecretArn"])
```

If a waiter times out/fails, inspect that exact identifier and events; it may still be billable. No password is passed to CreateDBInstance or printed. Retrieve the managed secret only through an authorized private operator workflow, then enter the password at `psql`'s prompt; never paste it into the command, shared output or history.

Download the current RDS CA bundle from its [official certificate guide](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html). Set RDS_LAB_HOST to the returned source hostname and RDS_LAB_CA_FILE to the downloaded bundle path:

```bash
psql "host=${RDS_LAB_HOST:?} port=5432 dbname=wikilab user=labadmin sslmode=verify-full sslrootcert=${RDS_LAB_CA_FILE:?} connect_timeout=5" -W
```

Paste this SQL in that session. The schema is reserved solely for the disposable lab:

```sql
CREATE SCHEMA wiki_rds_lab;
CREATE TABLE wiki_rds_lab.orders (
  order_id text PRIMARY KEY,
  total numeric(10,2) NOT NULL CHECK (total >= 0)
);
INSERT INTO wiki_rds_lab.orders VALUES ('lab-001',25), ('lab-002',40);
SELECT count(*) AS rows, sum(total) AS total FROM wiki_rds_lab.orders;
```

Expect rows=2 and total=65.00. Attempt the same connection from the excluded client's network with the same short connection timeout: connection should fail before authentication. On the permitted client, an incorrect password should fail authentication instead; do not open public access to make either test pass.

Close the writer, then capture a named manual snapshot and wait for it:

```python
snapshot_id = source_id + "-fixture"
rds.create_db_snapshot(DBInstanceIdentifier=source_id, DBSnapshotIdentifier=snapshot_id)
rds.get_waiter("db_snapshot_available").wait(
    DBSnapshotIdentifier=snapshot_id, WaiterConfig={"Delay": 30, "MaxAttempts": 60},
)
```

After the snapshot is AVAILABLE, insert `('lab-003',30)` into the source. Its total is now 95.00; that row must not appear in the earlier snapshot restore.

Run a controlled failover only on this Multi-AZ lab instance. Observe a fresh connection/query alongside the API state; existing connections can be interrupted. Do not treat the initial successful reboot response or an immediately available status as completed failover:

```python
old_az = rds.describe_db_instances(DBInstanceIdentifier=source_id)["DBInstances"][0]["AvailabilityZone"]
started = time.monotonic()
rds.reboot_db_instance(DBInstanceIdentifier=source_id, ForceFailover=True)
deadline = started + 900
while time.monotonic() < deadline:
    current = rds.describe_db_instances(DBInstanceIdentifier=source_id)["DBInstances"][0]
    if current["DBInstanceStatus"] == "available" and current["AvailabilityZone"] != old_az:
        print("Observed AZ change", old_az, current["AvailabilityZone"],
              "seconds", round(time.monotonic() - started))
        break
    time.sleep(10)
else:
    raise TimeoutError("Inspect lab failover events and connection recovery")
```

Reconnect through the source endpoint using fresh DNS resolution and verify three rows/95.00. The polling time is a coarse control-plane observation, not a promised failover SLA or exact application outage time.

Restore the snapshot to a **new** private instance; explicitly select its subnet group/security group rather than inheriting a default network policy. The restore is Single-AZ here to reduce additional lab cost; it is not the source's HA topology.

```python
restored_id = source_id + "-restore"
rds.restore_db_instance_from_db_snapshot(
    DBInstanceIdentifier=restored_id, DBSnapshotIdentifier=snapshot_id,
    DBInstanceClass=instance_class, DBSubnetGroupName=subnet_group,
    VpcSecurityGroupIds=[database_sg], PubliclyAccessible=False, MultiAZ=False,
    ManageMasterUserPassword=True,
    Tags=[{"Key": "Purpose", "Value": "cloudnative-wiki-rds-lab-restore"}],
)
rds.get_waiter("db_instance_available").wait(
    DBInstanceIdentifier=restored_id, WaiterConfig={"Delay": 30, "MaxAttempts": 60},
)
restored = rds.describe_db_instances(DBInstanceIdentifier=restored_id)["DBInstances"][0]
print(restored_id, restored["Endpoint"]["Address"], restored["MasterUserSecret"]["SecretArn"])
```

Connect to the new hostname with its newly managed secret and the same TLS settings. `SELECT * FROM wiki_rds_lab.orders ORDER BY order_id;` must return only lab-001/25 and lab-002/40; the aggregate is 2/65.00. A restore's available status alone does not establish recovered application permissions/data. Encrypted snapshot restoration preserves encryption, but required key access must still exist.

After closing clients and recording evidence, review source_id/restored_id and delete **only these disposable instances** with `rds.delete_db_instance(DBInstanceIdentifier=..., SkipFinalSnapshot=True, DeleteAutomatedBackups=True)` for each. Skipping final backups is appropriate only for this synthetic lab. Wait with `db_instance_deleted` using bounded WaiterConfig, inspect retained backups/secrets, then delete snapshot_id with `delete_db_snapshot`. Managed-secret lifecycle and manually retained secrets/backups differ; do not delete unrelated secrets or shared subnet groups/security groups. [Create instance](https://docs.aws.amazon.com/AmazonRDS/latest/APIReference/API_CreateDBInstance.html), [snapshot restore](https://docs.aws.amazon.com/AmazonRDS/latest/APIReference/API_RestoreDBInstanceFromDBSnapshot.html), [managed credentials](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html).

## References

- [Multi-AZ DB instance failover](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.Failover.html)
- [Read-replica creation and quotas](https://docs.aws.amazon.com/AmazonRDS/latest/APIReference/API_CreateDBInstanceReadReplica.html)
- [RDS storage performance](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Storage.html)
- [Database Insights migration](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Database-Insights.html)
- [RDS pricing](https://aws.amazon.com/rds/pricing/)

## Across the wiki

- [[Azure/databases/azure-sql|Azure SQL Database & Managed Instance]] — relational databases (Azure)
- [[GCP/databases/cloud-sql|GCP Cloud SQL]] — relational databases (GCP)
- [[Architecture/solution-architecture-concepts/data-architecture/databases/postgres/README|PostgreSQL]] — relational databases (Architecture)
- [[Azure/databases/postgres-flexible/README|Azure Database for PostgreSQL Flexible Server Architecture & Operations]] — relational databases (Azure)
