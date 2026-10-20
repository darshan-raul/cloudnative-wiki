---
title: "Procedure: Set Up and Test Break-Glass Cluster Access"
description: "Prepare an audited emergency admin path to every EKS cluster that works when normal access, GitOps or the identity provider fails, and test it on a schedule."
tags:
  [kubernetes/eks/operator-runbook, eks, procedure, access, iam, break-glass]
date: 2026-10-20
aliases: [EKS break-glass access, EKS emergency admin access]
---

# Procedure: Set Up and Test Break-Glass Cluster Access

**Applies to:** every production EKS cluster. Set this up **before** you need it; [[Kubernetes/eks/operator-runbook/runbooks/kubectl-unauthorized-or-forbidden|kubectl Unauthorized]] relies on it.
**Duration:** a few hours to set up across accounts, 15 minutes per test.
**Risk:** low to set up. The role is powerful, so the controls around it matter.
**Tested:** not run on a live cluster; commands checked for syntax.

## What you're building

| Piece                           | Purpose                                                                                                                                      |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| IAM role `eks-break-glass`      | Assumable only by a small named group, with MFA, for short sessions                                                                          |
| Access entry on each cluster    | `AmazonEKSClusterAdminPolicy`, cluster scope, so the role works even if every other mapping is broken                                        |
| EKS API permissions on the role | `eks:CreateAccessEntry`, `AssociateAccessPolicy`, `UpdateClusterConfig`, `Describe*`, so it can repair access entries if its own was deleted |
| A network path                  | For private-only endpoints: a bastion, SSM-managed host or VPN that doesn't depend on the cluster                                            |
| An alert                        | Every use pages the security on-call                                                                                                         |
| A test schedule                 | Proves it still works                                                                                                                        |

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=my-cluster REGION=us-east-1 ACCOUNT=<account id>
export BREAKGLASS_ROLE_ARN=arn:aws:iam::$ACCOUNT:role/eks-break-glass
```

## Steps

**1. Create the role** (in IaC). The trust policy allows only named principals, and only with MFA:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::<security-account>:role/<incident-commanders>"
      },
      "Action": "sts:AssumeRole",
      "Condition": { "Bool": { "aws:MultiFactorAuthPresent": "true" } }
    }
  ]
}
```

Set `MaxSessionDuration` to one hour. Attach a permissions policy limited to EKS read and repair actions (the table above), plus the read-only permissions you need to investigate (`ReadOnlyAccess` or a scoped equivalent).

Decide whether break-glass must survive an **identity-provider outage**. If it must, the principals in the trust policy can't depend on SSO alone; follow your organisation's emergency-credential policy (for example, a hardware-MFA IAM user in a security account, with sealed credentials).

**2. Map it on every cluster** (in the same IaC that creates clusters, so new clusters get it automatically):

```bash
aws eks create-access-entry --cluster-name "$CLUSTER" --region "$REGION" --principal-arn "$BREAKGLASS_ROLE_ARN"
aws eks associate-access-policy --cluster-name "$CLUSTER" --region "$REGION" --principal-arn "$BREAKGLASS_ROLE_ARN" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster
```

Clusters still in `CONFIG_MAP` mode can't use access entries. Migrate them first ([[Kubernetes/eks/operator-runbook/procedures/migrate-aws-auth-to-access-entries|aws-auth migration]]).

**3. Make sure there's a network path.** For clusters with `endpointPublicAccess=false`, document how a responder reaches the private endpoint without the cluster's help: an SSM-managed admin host in the VPC with `kubectl` installed, or a VPN.

**4. Alert on every use.** Page when the role is assumed. For example, an EventBridge rule on CloudTrail `AssumeRole` events for the role ARN, in each region where it can be assumed, sending to SNS or your paging tool. Or a SIEM query over CloudTrail:

```json
{
  "source": ["aws.sts"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "eventName": ["AssumeRole"],
    "requestParameters": {
      "roleArn": ["arn:aws:iam::<account>:role/eks-break-glass"]
    }
  }
}
```

**5. Write the runbook entry:** who may use it, how to get MFA credentials, the kubeconfig command, and the duty to report every use.

```bash
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" --role-arn "$BREAKGLASS_ROLE_ARN" --alias "$CLUSTER-breakglass"
```

## Test (quarterly, and after access or network changes)

1. Assume the role with MFA, as a person on the authorised list.
2. Run:

   ```bash
   kubectl --context "$CLUSTER-breakglass" auth whoami
   kubectl --context "$CLUSTER-breakglass" auth can-i '*' '*' --all-namespaces    # yes
   aws eks list-access-entries --cluster-name "$CLUSTER" --region "$REGION" >/dev/null && echo EKS_API_OK
   ```

3. Confirm the alert fired and reached the security on-call.
4. Record the date, the clusters tested, and the result.

A failed test is a Sev 3 to fix within days. You don't want to find out during a lockout.

## Abort criteria and rollback

Nothing to roll back. If the alert doesn't fire during a test, fix the alerting before you call the test passed.

## Clean-up after a real use

Rotate any credentials exposed during the incident, review CloudTrail and the audit log for everything done with the role, and file the usage report.

## Background

- [[Kubernetes/eks/security/access/cluster-access-management|Cluster access management]]
- [[Kubernetes/eks/security/access/endpoint-access|Endpoint access]]
- [[Kubernetes/eks/operator-runbook/runbooks/kubectl-unauthorized-or-forbidden|kubectl Unauthorized or Forbidden]]
