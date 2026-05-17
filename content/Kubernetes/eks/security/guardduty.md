---
title: Amazon GuardDuty for EKS
tags: [eks, security, guardduty]
date: 2026-05-17
description: GuardDuty security findings for EKS clusters
---

# GuardDuty for EKS

## Overview

GuardDuty provides threat detection for EKS workloads by analyzing Kubernetes audit logs and cluster-level events.

## Enable EKS Protection

```bash
# Enable GuardDuty for EKS
aws guardduty enable-organization-configuration \
  --feature-names EKS_PROTECTION \
  --region us-west-2
```

## Finding Types

| Finding Type | Severity | Description |
|-------------|----------|-------------|
| EKSClusterAnonymousAccess | High | Cluster accessed anonymously |
| EKSClusterPrivilegedContainer | Critical | Privileged container detected |
| EKSPodSensitiveMountAccess | High | Sensitive mount access |
| EKSWorkloadsSensitiveContainer | Medium | Sensitive data access |

## View Findings

```bash
# List EKS findings
aws guardduty list-findings \
  --detector-id abc123 \
  --filter-criteria '{"severity":{"eq":["HIGH","CRITICAL"]}}'

# Get finding details
aws guardduty get-findings \
  --detector-id abc123 \
  --finding-ids f-xxxxx
```

## Response Automation

```yaml
# Example: EventBridge rule for high severity
{
  "source": ["aws.guardduty"],
  "detail": {
    "type": ["EKSClusterPrivilegedContainer"]
  },
  "target": ["sns-topic-arn"]
}
```

## References

- [GuardDuty for EKS](https://docs.aws.amazon.com/eks/latest/userguide/guardduty.html)
- [EKS Workshop - GuardDuty](https://www.eksworkshop.com/docs/security/guardduty/)