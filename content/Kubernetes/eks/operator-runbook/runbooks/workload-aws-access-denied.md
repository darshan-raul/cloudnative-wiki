---
title: "Runbook: Workload Gets AWS AccessDenied (Pod Identity or IRSA)"
description: "A Pod's calls to S3, DynamoDB, SQS or another AWS API fail with AccessDenied. Find whether the Pod got the wrong identity, couldn't assume its role, or has the right role with too little permission."
tags:
  [
    kubernetes/eks/operator-runbook,
    eks,
    runbook,
    iam,
    pod-identity,
    irsa,
    incident,
  ]
date: 2026-10-20
aliases: [EKS Pod Identity AccessDenied, IRSA AccessDenied runbook]
---

# Runbook: Workload Gets AWS AccessDenied (Pod Identity or IRSA)

**Applies to:** Pods on EC2 nodes using EKS Pod Identity or IAM Roles for Service Accounts (IRSA). Fargate supports IRSA only.
**Typical severity:** depends on the workload. Often Sev 2 right after a deploy, a role change or an account migration.
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

The application logs an AWS SDK error. **Read which identity it names**; that decides the path:

| Error                                                                                                                      | Meaning                                                                     |
| -------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `User: arn:aws:sts::111122223333:assumed-role/<NODE-ROLE>/i-0abc... is not authorized to perform: s3:GetObject`            | **Wrong identity.** The Pod fell back to the node's instance role (cause A) |
| `User: arn:aws:sts::111122223333:assumed-role/<APP-ROLE>/... is not authorized to perform: ...`                            | **Right identity, missing permission** (cause D)                            |
| `WebIdentityErr: failed to retrieve credentials ... AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity` | **IRSA trust failure** (cause C)                                            |
| `failed to refresh cached credentials` with `169.254.170.23`, or `connection refused`                                      | **Pod Identity agent unreachable** (cause B)                                |
| `no EC2 IMDS role found`, or `NoCredentialProviders`                                                                       | No credentials were injected, and IMDS is blocked (cause A)                 |

## Impact

Limited to the Pods using that service account. A bad role change, though, can hit every replica at once, and Pods that cache credentials fail later, when they refresh, which makes the cause look unrelated.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=my-cluster REGION=us-east-1 NS=<namespace> POD=<pod>
export SA=$(kubectl get pod "$POD" -n "$NS" -o jsonpath='{.spec.serviceAccountName}')
```

## Triage

**1. Which credential mechanism did the Pod get?**

```bash
kubectl get pod "$POD" -n "$NS" -o json | jq -r '.spec.containers[] | .name as $c | .env[]? |
  select(.name|test("^AWS_(ROLE_ARN|WEB_IDENTITY_TOKEN_FILE|CONTAINER_CREDENTIALS_FULL_URI|CONTAINER_AUTHORIZATION_TOKEN_FILE)$")) |
  "\($c)\t\(.name)=\(.value)"'
```

- `AWS_CONTAINER_CREDENTIALS_FULL_URI=http://169.254.170.23/v1/credentials` → **Pod Identity**.
- `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` → **IRSA**.
- **Neither** → nothing was injected. The SDK falls back to IMDS, which means the node role or nothing (cause A).

Both mechanisms inject at **Pod creation**. A Pod created before the association or annotation existed never gets credentials until it's recreated.

**2. If the image has the AWS CLI, ask it directly:**

```bash
kubectl exec "$POD" -n "$NS" -- aws sts get-caller-identity
```

**3. Is the service account wired up?**

```bash
# Pod Identity
aws eks list-pod-identity-associations --cluster-name "$CLUSTER" --region "$REGION" \
  --namespace "$NS" --service-account "$SA"
kubectl get ds eks-pod-identity-agent -n kube-system

# IRSA
kubectl get sa "$SA" -n "$NS" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}'
aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query 'cluster.identity.oidc.issuer' --output text
aws iam list-open-id-connect-providers
```

**4. Read the role's trust policy:**

```bash
export ROLE_NAME=<role name>
aws iam get-role --role-name "$ROLE_NAME" --query 'Role.AssumeRolePolicyDocument' | jq
```

- **Pod Identity** needs principal `{"Service": "pods.eks.amazonaws.com"}` with actions `sts:AssumeRole` **and** `sts:TagSession`.
- **IRSA** needs principal `{"Federated": "arn:aws:iam::<acct>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/<ID>"}`, action `sts:AssumeRoleWithWebIdentity`, and conditions `<issuer>:sub = system:serviceaccount:<ns>:<sa>` and `<issuer>:aud = sts.amazonaws.com`. The issuer ID must be **this** cluster's. A copied trust policy from another cluster is the classic mistake.

**5. If the identity is right, what denied it?** Find the failing call in CloudTrail (`errorCode: AccessDenied`). The `errorMessage` usually says which policy type denied it: identity-based, resource-based, SCP, or permissions boundary.

## Diagnosis

| Signal                                                                                        | Cause                                                  | Fix   |
| --------------------------------------------------------------------------------------------- | ------------------------------------------------------ | ----- |
| Error names the node role; no injected env vars                                               | A. Credentials never injected                          | Fix A |
| Pod Identity env present; agent errors or `169.254.170.23` unreachable                        | B. Pod Identity agent problem                          | Fix B |
| `AssumeRoleWithWebIdentity` denied, or Pod Identity association exists but `AssumeRole` fails | C. Trust policy wrong                                  | Fix C |
| Error names the app role                                                                      | D. Permission policy, resource policy, SCP or boundary | Fix D |

## Fix

### A. Credentials never injected

- **Pod predates the association or annotation:** `kubectl rollout restart deploy/<name> -n "$NS"`.
- **Wrong service account:** the Deployment uses `default` or another SA. Fix `spec.template.spec.serviceAccountName`.
- **Association points at the wrong place:** a Pod Identity association is per cluster, namespace and service account. A typo or the wrong cluster means no injection.
- **Old SDK:** the SDK must support the container credential provider (Pod Identity) or web identity (IRSA). Older SDKs skip it and fall through to IMDS. Check the minimum SDK versions in the EKS documentation.
- **IMDS should not be the fallback.** If the error names the node role, the Pod can reach IMDS. Set the node launch template metadata hop limit to 1 (`HttpPutResponseHopLimit=1`), so non-host-network Pods can't use the node role silently.

### B. Pod Identity agent problem

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent -o wide
kubectl logs -n kube-system <agent-pod-on-the-same-node> --tail=100
aws eks describe-addon --cluster-name "$CLUSTER" --region "$REGION" --addon-name eks-pod-identity-agent \
  --query 'addon.{status:status,version:addonVersion,issues:health.issues}'
```

The agent must run on the Pod's node. It's a host-network DaemonSet, so check the tolerations if the node has custom taints. The node role needs `eks-auth:AssumeRoleForPodIdentity` (included in `AmazonEKSWorkerNodePolicy`).

### C. Trust policy wrong

Fix the trust policy in IaC to match the template in Triage step 4, for **this** cluster's OIDC issuer (IRSA) or with `sts:TagSession` (Pod Identity). For IRSA, the IAM OIDC provider for the issuer must exist in the account. Create it with `eksctl utils associate-iam-oidc-provider --cluster "$CLUSTER" --approve`, or through IaC.

**Verify:** new Pods (or a restart) succeed; SDKs re-read credentials on their own refresh cycle.

### D. Right role, insufficient permission

Look at four layers, in this order:

1. **Identity policy** on the role: action and resource ARN, including the `/*` object path for S3.
2. **Resource policy:** S3 bucket policy, KMS key policy (a common one for SSE-KMS objects and encrypted queues), SQS or SNS policies, or ECR repository policy for cross-account access.
3. **Session tags (Pod Identity):** a policy using ABAC conditions on `aws:PrincipalTag/kubernetes-namespace`, `eks-cluster-name` and similar must match the tags EKS sets.
4. **SCPs and permission boundaries:** an explicit deny at the organisation level beats everything. The CloudTrail message says when this happened.

Change the policy through its owner, then retry. Credentials don't need refreshing for a permission change. Allow a short delay for IAM to propagate.

## Verify recovery

```bash
kubectl exec "$POD" -n "$NS" -- aws sts get-caller-identity   # shows the app role
kubectl logs "$POD" -n "$NS" --since=5m | grep -c AccessDenied   # 0
```

Exercise the operation that failed (read from the bucket, send the message), and check every replica, not just one.

## Escalate

IAM decisions are explainable from CloudTrail; open a case only if CloudTrail shows `AssumeRoleForPodIdentity` failing with internal errors, or if the agent add-on is `DEGRADED` with no customer-side cause. Attach the cluster ARN, association ID, role ARN and CloudTrail event IDs.

## Prevent

- Prefer Pod Identity for new workloads on EC2. A single trust policy works across clusters, and there's no OIDC provider to manage.
- Block IMDS from Pods (hop limit 1) so a wiring mistake fails loudly instead of using node permissions.
- Define the role, the association and the service account in the same IaC module as the workload.
- Alert on `AccessDenied` in application logs, and on CloudTrail `AssumeRoleWithWebIdentity` failures.

## Background

- [[Kubernetes/eks/security/pod-identity|EKS Pod Identity]]
- [[Kubernetes/eks/security/iam-roles-for-sa|IAM roles for service accounts]]
- [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [IAM policy evaluation logic](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html)
