---
title: "AWS reliability"
description: "Move from availability claims to tested recovery objectives, dependency failure handling and restore procedures."
tags:
  - cloud/aws/reliability
date: 2026-10-12
---

# AWS reliability

Reliability is a property of a workload and its dependencies, not a product label. State the business objectives before selecting a topology.

- **Availability:** define the service-level indicator, measurement window and allowed failure budget.
- **RPO:** maximum acceptable data loss, measured against a specific failure.
- **RTO:** maximum acceptable restoration time, including detection, decisions and validation.

Start with [[AWS/reliability/backup-and-recovery|backup and recovery drills]], [[AWS/architecture/well-architected|architecture review]], [[AWS/monitoring/tracing-and-observability|observability]] and [[AWS/operations/quotas-health-and-support|capacity/incident operations]].

A read replica, snapshot, Multi-AZ deployment and cross-Region backup address different risks. A snapshot may protect data but not restore DNS, secrets, network rules or compatible application code.

Exercise: enumerate the dependencies of a three-tier application. For each, choose one failure, detection method, recovery owner and validation test. Measure the complete recovery path; do not quote a database failover time as the entire application's RTO.

## References

- [Reliability pillar](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/welcome.html).
- [Disaster recovery strategies](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-workloads-on-aws.html).
