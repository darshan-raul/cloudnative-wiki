---
title: PostgreSQL Replication and High Availability
tags:
  [architecture, databases, postgres, replication, high-availability, backup]
date: 2026-10-10
description: Keeping PostgreSQL available and its data safe — physical and logical replication, synchronous versus asynchronous commit, replication slots, automated failover and split-brain, backups with point-in-time recovery, and upgrades.
---

# PostgreSQL Replication and High Availability

A single PostgreSQL server is a single point of failure, and a replica is not a backup. This note covers the three separate things a production database needs: **replication** (a current copy elsewhere), **failover** (promoting that copy automatically and safely), and **backup** (the ability to go back in time). All three are built on the write-ahead log described in [[Architecture/solution-architecture-concepts/data-architecture/databases/postgres/README|PostgreSQL]].

## Two kinds of replication

|                | Physical (streaming)                               | Logical                                                   |
| :------------- | :------------------------------------------------- | :-------------------------------------------------------- |
| What is sent   | WAL records: byte-level changes to pages           | Decoded row changes: insert, update, delete               |
| The replica is | An exact copy of the whole cluster, read-only      | An independent, writable database                         |
| Granularity    | Everything                                         | Chosen tables (publications and subscriptions)            |
| Versions       | Must match (same major version)                    | Can differ                                                |
| Schema changes | Replicated automatically                           | Not replicated — apply them on both sides                 |
| Use for        | High availability, read scaling, disaster recovery | Major-version upgrades, migrations, feeding other systems |

**Physical replication** is what high availability is built on. A standby connects to the primary, receives WAL continuously and replays it. It can serve read-only queries while doing so.

**Logical replication** is the mechanism behind zero-downtime upgrades and [[Architecture/solution-architecture-concepts/migration-patterns/change-data-capture|change data capture]] tools such as Debezium, which turn committed changes into events.

## Synchronous or asynchronous

| Mode                       | A commit returns when                                   | If the primary is lost                | Cost                                                                                             |
| :------------------------- | :------------------------------------------------------ | :------------------------------------ | :----------------------------------------------------------------------------------------------- |
| **Asynchronous** (default) | WAL is flushed on the primary                           | The last few transactions may be lost | None                                                                                             |
| **Synchronous**            | A standby has also confirmed receiving (or applying) it | Nothing committed is lost             | Each commit waits a network round trip; if no synchronous standby is available, **writes block** |

Use quorum commit with more than one candidate so that one standby failing does not stop writes:

```ini
synchronous_standby_names = 'ANY 1 (standby_a, standby_b)'
synchronous_commit = on        # can be relaxed per transaction for unimportant writes
```

These settings are the concrete form of the recovery point objective in [[Architecture/solution-architecture-concepts/foundations/non-functional-requirements/disaster-recovery|disaster recovery]]: asynchronous means an RPO of seconds, synchronous an RPO of zero.

## Replication lag and reading from replicas

A replica is always slightly behind. Monitor lag in bytes and in time:

```sql
-- On the primary
SELECT application_name, state, sync_state,
       pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_lag_bytes,
       replay_lag
FROM pg_stat_replication;
```

Sending reads to replicas introduces **read-your-writes** anomalies: a user saves a change, the next page load hits a replica that has not replayed it yet, and the change appears to be lost. Mitigations: route reads that follow a write to the primary, or accept staleness only for queries where it does not matter (reports, search, feeds).

Long queries on a replica also conflict with replay, and are cancelled after `max_standby_streaming_delay`. Setting `hot_standby_feedback = on` avoids that at the cost of holding back vacuum on the primary.

## Replication slots: useful and dangerous

A **replication slot** makes the primary retain WAL until a consumer has received it, so a replica or CDC tool can disconnect and catch up later without missing changes.

The danger: if the consumer never comes back, WAL accumulates **until the disk is full and the primary stops**. An abandoned slot is one of the most common causes of PostgreSQL outages.

```sql
SELECT slot_name, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained
FROM pg_replication_slots;
```

Alert on retained WAL per slot, set `max_slot_wal_keep_size` as a safety limit, and drop slots that are no longer used.

## Failover

Replication gives you a standby. **Failover** is deciding the primary is dead, promoting a standby, and redirecting clients — and doing it without ever having two primaries.

**Split-brain** is that failure: a network partition makes the old primary unreachable but still alive, a standby is promoted, and both accept writes. The data diverges and cannot be merged automatically. Preventing it requires two things:

1. **A consensus store** (etcd, Consul or the Kubernetes API) that grants a leader lease to exactly one node. Background: [[Architecture/solution-architecture-concepts/cluster-management/raft|Raft]].
2. **Fencing**: the old primary must stop itself when it cannot renew its lease, before anyone else is promoted.

| Tool                                          | Where                                                                                       |
| :-------------------------------------------- | :------------------------------------------------------------------------------------------ |
| **Patroni**                                   | VMs or Kubernetes; the de facto standard, using etcd/Consul/Kubernetes for the leader lease |
| **CloudNativePG**, Zalando, Crunchy operators | Kubernetes operators that manage clusters, failover and backups as custom resources         |
| **Managed services**                          | RDS Multi-AZ, Aurora, Cloud SQL HA, Azure Flexible Server — failover is the provider's job  |

Clients find the current primary through a virtual IP, a DNS name with a short TTL, a proxy (HAProxy, PgBouncer) or a Kubernetes Service that follows the leader. Applications must **reconnect and retry**: a failover drops every connection, and in-flight transactions are rolled back. After a failover the old primary must be rebuilt or rewound with `pg_rewind` before it can rejoin as a standby.

Aim for a failover of under a minute, and **test it regularly** — a failover that has never been exercised is a hope, not a capability. See [[Kubernetes/guides/non-functional/chaos-engineering|chaos engineering]].

## Backups and point-in-time recovery

Replication faithfully copies mistakes. `DROP TABLE` reaches the standby in milliseconds. Only a backup lets you go back.

| Type                          | What it is                                   | Restores                                                                              |
| :---------------------------- | :------------------------------------------- | :------------------------------------------------------------------------------------ |
| **Logical dump**              | `pg_dump`: SQL or an archive of one database | That database, at the time of the dump; slow for large data; portable across versions |
| **Physical base backup**      | A file-level copy of the whole cluster       | The cluster at the time of the backup                                                 |
| **Base backup + WAL archive** | A base backup plus every WAL segment since   | **Any point in time** in the retained window                                          |

Point-in-time recovery (PITR) is the goal: restore the base backup, then replay archived WAL up to a chosen moment — one second before the bad migration ran.

```
base backup (Sunday 02:00)  +  WAL archive (continuous)  ─►  restore to Wednesday 14:31:59
```

Use a dedicated tool — **pgBackRest**, Barman or WAL-G — rather than scripts. They provide parallel and incremental backups, compression, encryption, retention policies, and storage in object stores such as [[AWS/storage/s3/README|S3]].

Rules:

- **Test restores on a schedule.** An untested backup is not a backup. Automate a weekly restore into a scratch environment and run a query against it.
- **Store backups elsewhere**: another account and another region, with object lock or immutability so ransomware or a compromised credential cannot delete them.
- **Know the numbers.** How long does a restore of the full data set take? That is your recovery time for the worst case.
- **Monitor WAL archiving.** If archiving fails silently, PITR stops at the last archived segment and WAL piles up on the primary.

## Upgrades

| Kind                      | Example     | Method                                                                                                                                                                                       |
| :------------------------ | :---------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Minor                     | 17.2 → 17.5 | Replace binaries and restart. Do standbys first, then switch over. Always safe to apply.                                                                                                     |
| Major, in place           | 16 → 17     | `pg_upgrade --link`: minutes of downtime, largely independent of data size                                                                                                                   |
| Major, near-zero downtime | 16 → 17     | Logical replication to a new cluster, then a brief cutover — the [[Architecture/solution-architecture-concepts/migration-patterns/blue-green-deployments\|blue-green]] pattern for databases |

After a major upgrade, run `ANALYZE` — planner statistics are not carried over, and queries will be slow until they are rebuilt.

## Scaling beyond one primary

In order of increasing cost:

1. **A bigger machine**, and fix the slow queries.
2. **Read replicas** for read-heavy load.
3. **Partitioning** large tables by time or tenant, to keep indexes small and make deleting old data cheap.
4. **Sharding** across independent primaries — with Citus, or in the application.
5. **A distributed SQL database** when multi-region writes are a hard requirement.

## A production checklist

- [ ] At least one standby in another availability zone
- [ ] Automated failover with a consensus store and fencing, tested
- [ ] Synchronous commit decision made deliberately, per data class
- [ ] Continuous WAL archiving and PITR, with restores tested on a schedule
- [ ] Backups in a separate account and region, immutable
- [ ] Alerts on replication lag, slot WAL retention, archive failures, disk space and transaction ID age
- [ ] Connection pooler in front; applications retry on connection loss
- [ ] A rehearsed major-version upgrade procedure

## Related

- [[Architecture/solution-architecture-concepts/data-architecture/databases/postgres/README|PostgreSQL]]
- [[Architecture/solution-architecture-concepts/foundations/non-functional-requirements/availability|Availability]] and [[Architecture/solution-architecture-concepts/foundations/non-functional-requirements/reliability|reliability]]
- [[Architecture/solution-architecture-concepts/migration-patterns/data-migration|Data migration]]
- [[AWS/databases/rds/README|Amazon RDS]] and [[AWS/databases/aurora/README|Aurora]]
- [[Kubernetes/concepts/L03-workloads/04-statefulsets|StatefulSets]] and [[Kubernetes/guides/non-functional/backup-restore|backup and restore on Kubernetes]]

## Across the wiki

- [[Azure/compute/aks/backup-disaster-recovery|AKS Backup, Disaster Recovery, and Cross-Region Business Continuity]] — backup and disaster recovery (Azure)
- [[GCP/compute/gke/backup-for-gke|Backup for GKE Architecture, Stateful Disaster Recovery, and Cross-Region Restoration]] — backup and disaster recovery (GCP)
- [[AWS/solutions-architect-professional/domain-2/2.2-business-continuity|2.2 Business Continuity]] — backup and disaster recovery (AWS)
