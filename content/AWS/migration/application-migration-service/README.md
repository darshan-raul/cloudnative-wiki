---
title: Application Migration Service (MGN)
description: AWS MGN — lift-and-shift service for Windows and Linux servers, continuous replication, wave management, cutover workflow, and post-launch validation
tags:
  - aws/migration
date: 2026-10-12
---

# Application Migration Service (MGN)

Prerequisites: [[AWS/security/iam/README|temporary-credential IAM roles]], [[AWS/networking/vpc/README|VPC routing]] and the [[AWS/migration/README|migration acceptance/rollback plan]].

AWS Transform MGN (formerly Application Migration Service) replicates supported source servers for rehosting. The API/CLI namespace remains mgn. Replication is not automatic application validation or source decommissioning.

## Architecture and networking

A source-installed replication agent sends block replication to replication servers and storage in a target staging subnet. This is not a primary S3-bucket staging architecture. Source-initiated TCP 1500 carries replication; TCP 443 is used for documented control-plane/service connectivity. Do not open speculative inbound-to-source or UDP heartbeat paths.

Plan routes, DNS, endpoints/proxy requirements and staging security groups from the owning network guide. Validate supported OS/boot/storage configuration and target launch settings. Sources may be in another AWS Region; initialize/control MGN in the target Region rather than claiming cross-Region migration is prohibited.

## Rehearsed server lab

This lab requires a disposable source VM and paid staging/target infrastructure. Use the current console-generated installer for the supported OS, not copied fictional installer flags. Scope the operator role and agent credentials using the official prerequisites.

1. Initialize the target Region and replication/launch settings. Install the agent following the current workflow, then inspect source-server replication health and lag.
2. Create an isolated test network so cloned schedulers/webhooks/email cannot affect production. Choose target IAM instance profile, security groups and storage.
3. Start a test using the real batch contract:

```bash
aws mgn start-test --source-server-ids SOURCE_SERVER_ID
aws mgn describe-source-servers
```

4. Inspect the returned job and documented lifecycle/replication states. Test boot, identity, connectivity, services, data and performance; terminate test instances through the owning test-cleanup workflow.
5. Freeze source writes after business approval, wait for the agreed lag threshold, then start-cutover with source-server-ids. Validate transactions before finalizing.
6. If acceptance fails, execute the agreed rollback before irreversible changes; reconcile writes made after target activation.
7. Finalize only after approval. Finalization stops replication; it does not prove the source OS was shut down or all billable resources were removed. Decommission source and staging/test leftovers explicitly.

Do not invent start-test-launch, terminate_target_instance, singular launch IDs or automatic source-shutdown flags. Lifecycle enums come from the API contract, not operational prose.

## Cost and cleanup

The MGN service free period is 2,160 hours (ninety continuous days) per migrated server; staging/test/cutover EC2/EBS and network charges still apply. Plan overlap and cleanup evidence. Remove lab agent/credentials and unused infrastructure only after backup/rollback acceptance; do not terminate the only valid source copy.

## Server lifecycle and replication architecture

```text
source disks → installed replication agent → source-initiated TCP 1500
                                              ↓
                                      target staging subnet
                                       replication EC2/EBS
                                              ↓
                                  test/cutover target instances
                                              ↓
                                validate → finalize → decommission
```

| Object/phase         | Evidence                                            | Customer responsibility                          |
| -------------------- | --------------------------------------------------- | ------------------------------------------------ |
| Source server        | Inventory, OS/storage support and replication state | Source access/agent/identity and write ownership |
| Replication settings | Target subnet, disk/server/network choices          | Correct paths/capacity/encryption and budget     |
| Launch configuration | Target template/storage/profile/SGs                 | Boot/application/network correctness             |
| Test                 | Isolated launched target and validation record      | Prevent duplicate external effects               |
| Cutover              | Accepted target plus lag/write-freeze evidence      | Traffic switching and rollback boundary          |
| Finalize/archive     | Actual supported lifecycle action/state             | Source/staging cleanup, retention and approvals  |

Human labels such as Live/Testing are not a substitute for the API's actual DataReplicationInfo/LifeCycle enums. Inspect the exact response/state and owning lifecycle contract.

## Installation and configuration runbook

Use the console-generated/current supported installer for the actual OS with reviewed agent credentials. Verify source-admin authority, supported disks/boot/OS, outbound DNS/control-plane TCP 443 and staging replication TCP 1500. Never download an arbitrary script or assume the old fictional source-server-id installer flag is required.

Source-side firewall/NAT/proxy, target subnet routes/SGs and endpoint access must be independently verified. Throttling uses supported replication settings and documented units, not an invented generic bandwidth flag. A replication pause/resume or source state change requires the real API and an approved maintenance plan.

Read and update the actual server settings with the returned ID:

```bash
aws mgn describe-source-servers --filters '{"sourceServerIDs":["SOURCE_SERVER_ID"]}'
aws mgn get-replication-configuration --source-server-id SOURCE_SERVER_ID
aws mgn get-launch-configuration --source-server-id SOURCE_SERVER_ID
```

Match supported response settings to the launch template and target application requirements; get-launch-configuration does not return every EC2 template detail. Do not confuse setting configuration with starting a job.

## Concrete test and cutover API walkthrough

```bash
aws mgn start-test --source-server-ids SOURCE_SERVER_ID
aws mgn describe-jobs
aws mgn describe-source-servers --filters '{"sourceServerIDs":["SOURCE_SERVER_ID"]}'
```

Record JobId/target instance IDs, inspect job/server results and actual lifecycle state. Verify instance boot/status, volumes, application service, dependencies, licensing and business transaction. Poll with a timeout; a failed job/boot does not become success merely because replication was healthy.

After recorded validation, use the documented terminate-target-instances/mark-ready-for-cutover workflow for the intended server/targets. These are mutations; do not copy the old terminate_target_instance Python name or arbitrary target-instance flag.

```bash
aws mgn start-cutover --source-server-ids SOURCE_SERVER_ID
aws mgn describe-source-servers --filters '{"sourceServerIDs":["SOURCE_SERVER_ID"]}'
```

Only run after the approved write freeze/lag boundary and rollback plan. Finalize-cutover is a separate lifecycle action after business acceptance; it stops replication but does not promise source shutdown.

## Wave, post-launch and monitoring depth

Group dependency-related sources into approved waves and record test/cutover owners, sequence and rollback. Use the currently supported MGN/Transform wave APIs/console for your account, not fabricated migration-hub wave commands. A wave can include failed and successful servers; validate each one and cross-server consistency.

Post-launch actions use supported SSM/service integrations and roles. A custom validation function/document must actually exist with required network/permissions, bounded execution and result reporting; do not infer a Lambda trigger from a prose comment.

Inspect per-source replication progress/backlog, errors, lag, last snapshot/sync data and launched-job outcomes in the real response/console. Guest disk/CPU/network telemetry needs its own supported collection; inspect documented metric/field names rather than inferring them from generic progress labels.

## Troubleshooting and cleanup matrix

| Symptom             | Investigate                                             | Do not do                                               |
| ------------------- | ------------------------------------------------------- | ------------------------------------------------------- |
| Agent missing       | Installer/OS support, credentials, service connectivity | Invent an inbound source heartbeat/UDP exception        |
| Replication stalled | TCP 1500 path, staging server/disk and throttling       | Treat a staging S3 bucket as the disk path              |
| Target fails boot   | Supported OS/boot/disk/launch template                  | Finalize an unvalidated target                          |
| Application fails   | Identity/DNS/ports/dependencies/license/test isolation  | Conclude replication success proves application success |
| Rollback needed     | Source authority and target writes accepted             | Flip DNS without reconciliation                         |

Terminate test targets and decommission only approved source/staging leftovers after acceptance. Remove the source agent/temporary credentials by the owning uninstall workflow. Archive records only when required evidence is preserved; the free service period does not remove infrastructure charges.

References: [replication contract](https://docs.aws.amazon.com/cli/latest/reference/mgn/get-replication-configuration.html), [launch contract](https://docs.aws.amazon.com/cli/latest/reference/mgn/get-launch-configuration.html), [source-server contract](https://docs.aws.amazon.com/cli/latest/reference/mgn/describe-source-servers.html), [migration workflow](https://docs.aws.amazon.com/mgn/latest/ug/migration-workflow-gs.html), [post-launch settings](https://docs.aws.amazon.com/mgn/latest/ug/post-launch-settings.html).

## References

- [Current workflow](https://docs.aws.amazon.com/mgn/latest/ug/migration-workflow-gs.html)
- [Network preparation](https://docs.aws.amazon.com/mgn/latest/ug/preparing-environments.html)
- [Replication settings](https://docs.aws.amazon.com/mgn/latest/ug/replication-server-settings.html)
- [StartTest CLI](https://docs.aws.amazon.com/cli/latest/reference/mgn/start-test.html)
- [Lifecycle contract](https://docs.aws.amazon.com/mgn/latest/APIReference/API_LifeCycle.html)
- [Finalization](https://docs.aws.amazon.com/mgn/latest/ug/finalizing-cutover-2.html)
- [Pricing](https://aws.amazon.com/application-migration-service/pricing/)
