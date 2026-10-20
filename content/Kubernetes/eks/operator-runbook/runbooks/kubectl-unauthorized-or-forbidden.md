---
title: "Runbook: kubectl Unauthorized or Forbidden"
description: "Operators or CI get 'You must be logged in to the server (Unauthorized)' or 'Forbidden' from an EKS cluster. Separate wrong identity, missing access entry, RBAC gaps and full lockout."
tags:
  [kubernetes/eks/operator-runbook, eks, runbook, access, iam, rbac, incident]
date: 2026-10-20
aliases:
  [
    EKS lockout runbook,
    EKS access denied kubectl,
    You must be logged in to the server,
  ]
---

# Runbook: kubectl Unauthorized or Forbidden

**Applies to:** human and CI access to the EKS API through IAM: access entries (`API` or `API_AND_CONFIG_MAP` mode) and the legacy `aws-auth` ConfigMap. For Pods calling AWS APIs, use [[Kubernetes/eks/operator-runbook/runbooks/workload-aws-access-denied|workload AccessDenied]] instead.
**Typical severity:** Sev 3 for one user. Sev 1 if nobody, or no pipeline, can administer the cluster.
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

| Message                                                                                                                                     | What it means                                                                           |
| ------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `error: You must be logged in to the server (Unauthorized)`, or `the server has asked for the client to provide credentials`                | **401: authentication failed.** EKS didn't map your IAM identity to any Kubernetes user |
| `Error from server (Forbidden): pods is forbidden: User "arn:aws:sts::111122223333:assumed-role/Dev/alice" cannot list resource "pods" ...` | **403: authenticated, not authorized.** RBAC or access policy gap                       |
| `dial tcp 10.0.x.x:443: i/o timeout`, or `Unable to connect to the server`                                                                  | **Not an auth problem.** Endpoint reachability; see Fix E                               |
| `getting credentials: exec: executable aws not found`                                                                                       | Local tooling; kubeconfig `exec` plugin can't run                                       |

## Impact

Only API access is affected; workloads keep running. The danger is a **full lockout** while something else needs fixing. Also, if an `aws-auth` edit broke the file, **nodes** lose their mapping too and go NotReady (see [[Kubernetes/eks/operator-runbook/runbooks/node-not-ready|Node NotReady]]).

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export CLUSTER=my-cluster REGION=us-east-1
```

## Triage

**1. Who are you, as AWS sees it?**

```bash
aws sts get-caller-identity
kubectl config view --minify -o jsonpath='{.users[0].user.exec.args}{"\n"}{.users[0].user.exec.env}{"\n"}'
```

- Check the **account** and the **role**. Kubeconfig can pin `--role-arn` or `--profile`, so the identity kubectl uses can differ from your shell. Run `aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" [--role-arn ...]` to regenerate it.

**2. Does the API server accept your token, and who does it think you are?**

```bash
kubectl auth whoami
```

- **Expect:** a username (often the assumed-role ARN with session name) and groups.
- **If** it returns `Unauthorized` → authentication failure (causes A–C).
- **If** it works but your command is `Forbidden` → authorization (cause D).

**3. Which authentication modes does the cluster use?**

```bash
aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
  --query 'cluster.accessConfig.authenticationMode' --output text
```

`CONFIG_MAP` reads only `aws-auth`; `API` reads only access entries; `API_AND_CONFIG_MAP` reads both, with access entries taking precedence.

**4. Is your IAM principal mapped?** Use the **IAM role ARN** (`arn:aws:iam::<acct>:role/<name>`), not the `sts ... assumed-role` session ARN:

```bash
export PRINCIPAL_ARN=arn:aws:iam::111122223333:role/Dev
aws eks describe-access-entry --cluster-name "$CLUSTER" --region "$REGION" --principal-arn "$PRINCIPAL_ARN"
aws eks list-associated-access-policies --cluster-name "$CLUSTER" --region "$REGION" --principal-arn "$PRINCIPAL_ARN"
kubectl get configmap aws-auth -n kube-system -o yaml   # only if someone else still has access
```

**5. What changed?** Check CloudTrail for EKS access changes in the last day:

```bash
aws cloudtrail lookup-events --region "$REGION" --start-time "$(date -u -d '-24 hours' +%FT%TZ)" \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=eks.amazonaws.com \
  --query 'Events[?contains(`["DeleteAccessEntry","CreateAccessEntry","DisassociateAccessPolicy","UpdateAccessEntry","UpdateClusterConfig"]`, EventName)].[EventTime,EventName,Username]' \
  --output table
```

`aws-auth` edits are Kubernetes API calls, not AWS calls. Find them in the EKS `audit` log in CloudWatch, if it's enabled.

## Diagnosis

| Signal                                                                                         | Cause                          | Fix   |
| ---------------------------------------------------------------------------------------------- | ------------------------------ | ----- |
| `get-caller-identity` shows an unexpected account or role                                      | A. Wrong local identity        | Fix A |
| Correct identity; no access entry and not in `aws-auth` (or the mode ignores the one you have) | B. Principal not mapped        | Fix B |
| Nobody can authenticate; `aws-auth` recently edited, or the admin entry deleted                | C. Lockout                     | Fix C |
| `whoami` works; command is `Forbidden`                                                         | D. RBAC or access-policy scope | Fix D |
| Timeout or `Unable to connect`                                                                 | E. Endpoint access, not auth   | Fix E |

## Fix

### A. Wrong local identity

Switch to the right profile or role (`export AWS_PROFILE=...`, or SSO `aws sso login --profile ...`). Regenerate the kubeconfig with `update-kubeconfig`. Check the system clock as well: a clock skewed by more than a few minutes makes the presigned token invalid.

### B. Principal not mapped

Someone with cluster-admin, or with the IAM permissions `eks:CreateAccessEntry` and `eks:AssociateAccessPolicy`, creates the mapping. Do it through IaC if that's where access is managed, or it'll be removed on the next apply.

```bash
aws eks create-access-entry --cluster-name "$CLUSTER" --region "$REGION" --principal-arn "$PRINCIPAL_ARN"
aws eks associate-access-policy --cluster-name "$CLUSTER" --region "$REGION" --principal-arn "$PRINCIPAL_ARN" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy \
  --access-scope type=namespace,namespaces=team-a
```

Choose the narrowest policy (`AmazonEKSViewPolicy`, `AmazonEKSEditPolicy`, `AmazonEKSAdminPolicy` or `AmazonEKSClusterAdminPolicy`) and scope. Alternatively, give the entry `--kubernetes-groups` and bind those groups with your own RBAC.

`aws-auth` gotcha: a role ARN with a **path** (`role/teams/dev/Dev`) must be written **without the path** in `mapRoles` (`role/Dev`), or it never matches.

### C. Lockout: nobody can authenticate

The way back in is through the EKS API, which only needs IAM permissions, not Kubernetes access.

1. Get an IAM principal with `eks:CreateAccessEntry` and `eks:AssociateAccessPolicy` on the cluster (your account admin or break-glass role).
2. If the mode is `CONFIG_MAP`, enable access entries first. **This is one-way**: you can't go back to `CONFIG_MAP`. It doesn't affect existing `aws-auth` mappings.

   ```bash
   aws eks update-cluster-config --name "$CLUSTER" --region "$REGION" \
     --access-config authenticationMode=API_AND_CONFIG_MAP
   aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query cluster.status   # wait for ACTIVE
   ```

3. Grant the break-glass role cluster admin:

   ```bash
   aws eks create-access-entry --cluster-name "$CLUSTER" --region "$REGION" --principal-arn "$BREAKGLASS_ROLE_ARN"
   aws eks associate-access-policy --cluster-name "$CLUSTER" --region "$REGION" --principal-arn "$BREAKGLASS_ROLE_ARN" \
     --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster
   ```

4. With access restored, repair `aws-auth` from IaC or its last good copy. If nodes went NotReady, restore the node role first: an `EC2_LINUX` access entry, or the `mapRoles` entry with groups `system:bootstrappers` and `system:nodes`.

**Undo:** once normal access works, remove the break-glass entry (`aws eks delete-access-entry --principal-arn "$BREAKGLASS_ROLE_ARN"`), unless policy keeps it as a standing break-glass path.

### D. Authenticated but Forbidden

```bash
kubectl auth whoami -o yaml                     # username and groups
kubectl auth can-i --list -n <namespace>        # what you can do
# from an admin:
kubectl auth can-i list pods -n <namespace> --as "<username>" --as-group "<group>"
kubectl get rolebindings,clusterrolebindings -A -o wide | grep -E "<username>|<group>"
```

- **Access policy:** the scope may be `namespace` while you're working in another namespace, or the policy may be View where you need Edit. Change it with `associate-access-policy`.
- **Groups and RBAC:** the entry maps you to a group, but no RoleBinding grants that group the verb. Add the binding through your RBAC repository.

### E. Endpoint not reachable

Run `aws eks describe-cluster --query cluster.resourcesVpcConfig`. If `endpointPublicAccess` is `false`, you must be on the VPC, a VPN or Direct Connect. If the endpoint is public, your egress IP must be in `publicAccessCidrs`. CI runners in another VPC need routing and DNS for the private endpoint. See [[Kubernetes/eks/security/access/endpoint-access|endpoint access]].

## Verify recovery

```bash
kubectl auth whoami
kubectl auth can-i '*' '*' --all-namespaces     # admins only; expect "yes"
kubectl get nodes                               # nodes Ready (if aws-auth was involved)
```

Also confirm your CI and GitOps identities can still deploy. They're mapped the same way and often break at the same time.

## Escalate

Access is fully customer-controlled. Open an AWS Support case only if a principal with correct access entries and policies still gets `Unauthorized` and `kubectl auth whoami` fails. Attach the cluster ARN, principal ARN, the UTC time and the CloudTrail event IDs.

## Prevent

- Migrate from `aws-auth` to access entries (mode `API`), managed in IaC. A typo in `aws-auth` can lock out everyone, nodes included.
- Keep at least two independent cluster-admin principals: a pipeline role and a break-glass role, used only through an audited process; see [[Kubernetes/eks/operator-runbook/procedures/break-glass-access-setup|Break-glass access setup]].
- Alert on CloudTrail `DeleteAccessEntry`, `DisassociateAccessPolicy` and `UpdateClusterConfig` with an `accessConfig` change, and on `aws-auth` edits in the audit log.
- Turn on the EKS `audit` and `authenticator` control-plane logs, so the next investigation has data.

## Background

- [[Kubernetes/eks/security/access/cluster-access-management|Cluster access management (access entries)]]
- [[Kubernetes/eks/security/access/aws-auth-legacy|aws-auth (legacy)]]
- [[Kubernetes/eks/security/access/authentication-patterns|Authentication patterns]]
- [[Kubernetes/concepts/L07-security/01-api-access/03-rbac|RBAC]]
- [Grant IAM users access to Kubernetes with EKS access entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)
