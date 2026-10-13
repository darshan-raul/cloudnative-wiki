---
title: EBS Cost Optimization
description: Billing models, trade-offs, safe workflows and scoped examples for ebs cost optimization.
tags:
  - aws/cost-management
date: 2026-10-12
---

# EBS Cost Optimization

Price exercises use hypothetical us-east-1 (US East, N. Virginia) rates for study on 2026-10-12, not current tariffs, unless explicitly identified as a dated published fee.

EBS is billed for provisioned volumes and applicable provisioned performance, not filesystem utilization. Stopping EC2 or detaching a volume does not stop volume charges.

## Volume choice

gp3 includes baseline 3,000 IOPS and 125 MiB/s throughput. Performance above the baseline is charged separately under current regional rates and supported limits. Its limits differ from RDS gp3. io2 serves workloads requiring its performance/durability characteristics; there is no EBS `io3` volume type.

Use SSD versus HDD options according to workload and boot/support constraints. c5 is a Nitro-based family; do not classify it as non-Nitro. Check instance EBS bandwidth as well as volume limits before purchasing extra IOPS.

## Worked storage calculation

At an assumed \$0.10/GB-month, four 100-GB and four 50-GB volumes total 600 GB and cost \$60/month. Do not add an IOPS fee for gp3's included baseline. Actual gp3 rates and additional IOPS/throughput must come from the selected Region's price sheet.

A 1,000-GB provisioned volume with 100 GB of files still bills for 1,000 GB. Filesystem usage requires guest metrics/inventory, not `VolumeReadBytes`. EBS cannot shrink a volume in place; plan a smaller replacement, copy data and validate before cutting over.

## Retention and encryption

EBS snapshots have their own pricing and incremental storage semantics, not direct S3 Standard billing. Archive and restore have separate retention/retrieval rules. Deleting a volume does not delete its snapshots; deleting EC2 depends on each volume's `DeleteOnTermination` setting.

EBS encryption uses AWS KMS, not SSE-S3. AWS-managed versus customer-managed keys have different control and pricing; KMS requests and customer-managed key charges are separate from per-volume storage, not one monthly key fee per volume. A snapshot's reference to a KMS key does not itself prevent deletion.

## Safe cleanup

Inventory unattached volumes, owner tags, snapshot/AMI dependencies and retention obligations. An unattached or old resource is a candidate, not proof it is disposable. Require owner approval and a recoverability plan. Use DLM/AWS Backup policies where appropriate and verify restore tests.

## Volume and performance trade-offs

| Type    | Workload fit                         | Cost/performance consideration                                       |
| ------- | ------------------------------------ | -------------------------------------------------------------------- |
| gp3     | General-purpose SSD                  | Included baseline plus separately provisioned additional performance |
| gp2     | Existing general-purpose SSD         | Size-linked performance and burst credits                            |
| io1/io2 | Supported provisioned-IOPS workloads | IOPS fees and durability/latency requirements                        |
| st1     | Large sequential throughput          | HDD; not a boot-volume replacement                                   |
| sc1     | Infrequent sequential access         | HDD performance/access constraints                                   |

Maximum IOPS/throughput and size ratios depend on current volume type and instance support. Do not revive stale limit tables; consult the linked owning table when planning. Multi-Attach is limited to supported provisioned-IOPS configurations/AZ/instances and requires application/cluster coordination. It is not a generic shared filesystem; compare EFS/FSx if that is the actual requirement.

## Corrected gp2-to-gp3 calculation

Use hypothetical us-east-1 exercise prices on 2026-10-12: gp2=\$0.10/GB-month, gp3=\$0.08/GB-month and extra gp3 IOPS=\$0.005/IOPS-month.

```text
500 GB gp2                         = $50/month
500 GB gp3, included 3,000 IOPS     = $40/month
500 GB gp3, 10,000 provisioned IOPS = $40 + (10,000 − 3,000) × $0.005
                                   = $75/month before extra throughput
```

Ten thousand IOPS are not fully included. A cheaper storage rate alone does not prove a cheaper configured volume. Compare io2 using its actual tiered performance pricing and required durability/latency, not a universal io2-versus-gp3 crossover.

## Metrics and snapshot worksheet

I/O operations per second derive from VolumeReadOps/VolumeWriteOps over the measurement period; bytes per second derive from byte counters. Queue length and latency help diagnose saturation. BurstBalance is relevant to supported burst-credit volume types, not evidence of filesystem free space.

Suppose a volume provisions 500 GB but its first snapshot contains 100 GB of billable changed blocks. Later snapshots add 10 GB of new retained blocks. Standard snapshot cost follows retained billable blocks, not 500 GB multiplied by snapshot count. Deleting an earlier snapshot may preserve blocks referenced by later snapshots, so apparent logical size is not guaranteed reclaimable storage.

DLM or AWS Backup can automate protected schedules; confirm which resources the policy manages and test restores. A manually created snapshot is not automatically governed by an unrelated DLM policy. Keep AMI references, legal holds, cross-account copies and encryption-key recoverability in the review.

- [EBS Multi-Attach requirements](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-volumes-multi.html)
- [Snapshot incremental behavior](https://docs.aws.amazon.com/ebs/latest/userguide/how_snapshots_work.html)

## References

- [Volume types and performance limits](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-volume-types.html)
- [EBS pricing](https://aws.amazon.com/ebs/pricing/)
- [Volume modification restrictions](https://docs.aws.amazon.com/ebs/latest/userguide/modify-volume-requirements.html)
- [EBS encryption](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-encryption.html)
