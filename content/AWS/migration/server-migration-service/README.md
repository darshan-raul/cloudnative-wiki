---
title: Server Migration Service (SMS)
description: AWS Server Migration Service (SMS) — older lift-and-shift service superseded by MGN. Comparison, migration path from SMS to MGN, and when to use MGN instead
tags:
  - aws
  - migration
---

# Server Migration Service (SMS)

SMS is the older AWS lift-and-shift service for replicating VMware VMs to AWS. **It has been superseded by Application Migration Service (MGN)** and is in maintenance mode — no new features, limited support.

## SMS vs MGN

| Feature | SMS | MGN |
|---------|-----|-----|
| Status | Deprecated, maintenance mode | Active development |
| Continuous replication | Yes | Yes |
| Test launch | No | Yes |
| Wave management | No | Yes |
| VMware support | Yes | Yes |
| Hyper-V support | No | Yes |
| Physical servers | No | Yes |
| Agent-based | Yes | Yes |
| Cutover modes | Direct only | Test + Final |

## Why Use MGN Instead

MGN is the modern replacement and has significant advantages:
- **Test launch:** Validate before cutover without affecting production
- **Wave management:** Coordinate multi-server cutovers
- **Better replication performance:** Optimized agent communication
- **Broader platform support:** Hyper-V, physical servers, Azure, GCP
- **Active development:** New features and improvements

## Migration Path: SMS → MGN

If you have existing SMS migrations in progress, you can migrate them to MGN:

```bash
# 1. Note the source server IDs from SMS console
aws sms list-servers

# 2. Install MGN agent on the same VMs (it will create new source servers in MGN)
# The existing SMS replication can continue while you set up MGN

# 3. Once MGN source servers are replicating and validated, complete MGN cutover

# 4. After MGN cutover, delete the source servers from SMS
aws sms delete-servers --server-ids sms-1234567890abcdef0
```

**Important:** Don't run both SMS and MGN agents simultaneously on the same VM. Install MGN, wait for initial sync, then uninstall SMS agent.

## SMS CLI Reference (Maintenance)

```bash
# List servers (read-only)
aws sms list-servers

# Get server details
aws sms get-server-details --server-id sms-1234567890abcdef0

# Describe replication jobs
aws sms describe-replication-jobs

# Start a replication job
aws sms start-replication-job --server-id sms-1234567890abcdef0

# Delete (cleanup only, after migration complete)
aws sms delete-servers --server-ids sms-1234567890abcdef0
```

## When SMS Was Appropriate

SMS was used for VMware environments before MGN existed. The typical workflow was:

```
VMware VM → SMS Agent → SMS Replication Job → S3 Staging → EBS Snapshot → AMI → EC2
```

SMS supported only VMware and required creating an SMS connector (a VM appliance) that managed replication.

## If You're Starting New

**Use MGN.** It handles VMware VMs just as well as SMS did, plus Hyper-V, physical servers, and cloud VMs. There's no reason to start a new migration with SMS.

## If You're Mid-Migration with SMS

You have two options:

**Option A: Continue with SMS** (not recommended)
- SMS still works, but no new features or fixes
- If you hit issues, AWS support may suggest migrating to MGN anyway

**Option B: Migrate to MGN** (recommended)
1. Keep SMS running (don't interrupt replication)
2. Install MGN agent on the same VMs
3. MGN will register as new source servers and start replicating
4. Once MGN shows healthy replication, complete MGN cutover
5. Clean up SMS after MGN cutover is done

This approach has a brief period where both agents run, but the overhead is minimal (both use similar bandwidth). The gain in reliability and test-launch capability is worth it.

## Connector-Based Architecture (SMS)

SMS used a connector VM deployed in your VMware environment:

```
VMware vCenter
    ↓
SMS Connector (deployed in VMware)
    ↓
SMS Service (AWS-managed)
    ↓
S3 Staging Bucket
```

MGN's agent-based approach is simpler — no connector VM to manage, direct agent-to-service communication over HTTPS.

## Deprecation Timeline

- **SMS announced deprecated:** 2021
- **No new features since:** 2021
- **Migration to MGN recommended:** Immediately for new migrations, planned migration for existing

## Key Takeaway

> **Use Application Migration Service (MGN) for all new lift-and-shift migrations. SMS is in maintenance mode and will eventually be retired.**

If you're working with SMS today, plan to migrate to MGN. The MGN agent handles VMware VMs equivalently to SMS, with a better feature set and active development.