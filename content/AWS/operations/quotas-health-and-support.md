---
title: "Quotas, AWS Health and support operations"
description: "Preflight account/Region capacity, separate service events from workload health and prepare escalation evidence."
tags:
  - cloud/aws/operations
date: 2026-10-12
---

# Quotas, AWS Health and support operations

A documented default is not necessarily your account allocation, and an allocation is not a capacity reservation. Start with [[AWS/foundations/README|account boundaries]] and [[AWS/monitoring/tracing-and-observability|workload monitoring]].

## Capacity preflight

Identify whether a limit is account/Region/resource scoped, adjustable or hard. Check applied values, current utilization, dependencies and request lead time. Different purchasing modes/families can have separate quotas; a request count cannot always be compared with a vCPU limit.

```bash
aws service-quotas list-service-quotas \
  --service-code ec2 --region us-east-1 \
  --query 'Quotas[].{Name:QuotaName,Value:Value,Adjustable:Adjustable}' \
  --output table
```

This is read-only and paginated by the CLI. Not every service limit appears in Service Quotas; consult the owning service guide. Perform representative load tests and distinguish throttling, exhausted quota and unavailable launch capacity.

## Health and escalation

AWS Health events describe service/account impacts and planned changes. They are not proof your application works; combine them with synthetic checks, SLIs and dependency telemetry. API/dashboard capabilities depend on access and current support/product entitlement.

Prepare an incident record: account/Region, affected resource, request IDs, UTC timestamps, error rates, recent changes and safe reproduction. Remove credentials and customer data from attachments. Select severity based on actual impact and your current support contract; do not invent a guaranteed response time.

## Read-only operational drill

1. Inventory one workload's five most important quota dependencies and their owners.
2. Inspect current Health events and decide which actually affect the workload.
3. Simulate a dependency-throttling alert in the sandbox, not by exhausting production limits.
4. Follow a runbook: protect users, reduce demand/backoff, inspect quotas and collect evidence.
5. Draft an escalation without submitting it; identify the role allowed to contact support.

Checkpoint: another operator can determine impact and next action from your evidence. No support case or quota-change request is needed for this drill. Delete only dedicated test alarms and restore any sandbox fault.

## References

- [Service Quotas](https://docs.aws.amazon.com/servicequotas/latest/userguide/intro.html).
- [AWS Health](https://docs.aws.amazon.com/health/latest/ug/what-is-aws-health.html).
- [Support case management](https://docs.aws.amazon.com/awssupport/latest/user/case-management.html).
- [Support plans](https://aws.amazon.com/premiumsupport/plans/).
