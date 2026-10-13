---
title: AWS Secrets Manager
description: AWS Secrets Manager — secrets rotation and management. API keys, passwords, database credentials, Lambda rotation functions, multi-region secrets, and integration with RDS, Redshift, DocumentDB.
tags:
  - aws/security
date: 2026-10-12
---

# AWS Secrets Manager

Prerequisites: [[AWS/security/iam/README|IAM roles and least privilege]] and the [[AWS/security/README|security evidence/response model]].

Secrets Manager stores versioned secrets with access policies, encryption and rotation workflows. Retrieving a secret is not a reason to print it in a log, shell history or documentation.

## Access and version model

Use scoped secret ARNs and [[AWS/security/kms/README|KMS]] permission where required. Cross-account retrieval needs both caller/resource authorization and a compatible customer-managed KMS policy. Cache secrets appropriately to reduce API calls while handling rotation and invalidation.

Staging labels select versions: AWSCURRENT, AWSPENDING and AWSPREVIOUS are workflow markers. The twenty-label quota is across secret versions, not per version. Labeled versions are retained; unlabeled version cleanup above one hundred preserves very recent versions, so excessive updates can exhaust quotas.

Primary rotation propagates to regional replicas. A replica can be promoted to an independent secret, breaking replication and creating independent rotation/version responsibility.

## Rotation contract

Use an AWS-maintained rotation template for the backend; this is a conceptual lifecycle, not an incomplete deployable Lambda handler.

1. createSecret: use the supplied ClientRequestToken idempotently for the AWSPENDING version.
2. setSecret: update the backend with pending credentials after verifying the intended resource/user and current/pending relationship.
3. testSecret: authenticate using pending credentials and verify only the intended capabilities.
4. finishSecret: transfer AWSCURRENT using update_secret_version_stage; retain the previous version under AWSPREVIOUS.

RotationToken is required in documented assumed-role/cross-account invocation cases. Never log tokens or values. Choose the backend's supported rotation strategy and test retries/concurrent rotation. With single-user rotation, setSecret changes the backend password before finishSecret moves AWSCURRENT; new connections using the old current value can fail during that interval or after a pending-test failure. Alternating-user rotation preserves a second user's credential path under its documented assumptions. Reconcile backend state, version labels and application caches on retry/rollback rather than promising the old value stays usable. Managed database rotation and customer Lambda rotation are distinct workflows.

## Sandbox exercise

Use a disposable non-production secret and a role scoped to that ARN. Create a synthetic value through a secure console/editor workflow, retrieve it in a test application without logging it, and inspect metadata through describe-secret. Test a caller lacking access (expected denial). Update the value, inspect version labels and verify cache refresh.

For rotation, deploy the maintained backend-specific template with the documented IAM/network prerequisites and a disposable backend. Force a pending-test failure and inspect both backend authentication and version labels. Under single-user rotation, expect the possible old-AWSCURRENT authentication gap; under alternating-user rotation, test the documented alternate-credential behavior. Fix the cause and retry/reconcile idempotently, then verify application reconnect/cache recovery. Do not rotate a production database as a first exercise.

Cleanup the secret/backend/rotation function and lab-only policy after evidence collection. Schedule deletion with recovery where possible; remove regional replicas before deleting a primary when required. Treat backend credentials as still active until the backend is decommissioned or changed.

## Cost

Budget each regional secret's storage and API calls at its actual Region's rate; there is no undocumented universal replica discount. Lambda rotation, database, KMS and network resources add charges.

## Secret, version and rotation architecture

```text
application role → GetSecretValue → cache → backend connection
                         ↑                   ↑
                 AWSCURRENT version ← tested pending backend credentials
                         ↓
               encrypted secret/key policy → regional replicas
```

| Boundary          | Example                         | Required check                                       |
| ----------------- | ------------------------------- | ---------------------------------------------------- |
| Secret metadata   | ARN/tags/rotation/replication   | Correct Region/account and owner                     |
| Version           | Encrypted value plus version ID | Current/pending/previous label relationship          |
| Rotation backend  | Database/API credential update  | Test pending auth before current transfer            |
| Application cache | Bounded reuse                   | Refresh on expiry/auth failure without logging value |
| Replica           | Regional copy                   | Promotion breaks primary rotation ownership          |

## Complete SDK retrieval and safe failure handling

This example retrieves a pre-existing synthetic JSON secret through the verified SDK session and returns parsed data to its caller; it does not print credentials.

```python
import json
import os
import boto3

client = boto3.client("secretsmanager")

def read_secret(secret_id):
    response = client.get_secret_value(
        SecretId=secret_id,
        VersionStage="AWSCURRENT",
    )
    if "SecretString" not in response:
        raise ValueError("this application expects a JSON string secret")
    value = json.loads(response["SecretString"])
    if not isinstance(value, dict) or not isinstance(value.get("username"), str):
        raise ValueError("unexpected secret schema")
    return value

secret = read_secret(os.environ["SECRETS_LAB_ARN"])
assert secret["username"] == "synthetic-user"
```

SecretBinary has a separate SDK binary representation; do not blindly JSON-decode it. Propagate/handle AccessDenied, key denial, not-found, throttling and malformed schema without including response values in logs. Use a maintained cache/library for production, not a permanent process-global credential copied once at startup.

## Version/stage and rotation walkthrough

```bash
aws secretsmanager describe-secret --secret-id SECRETS_LAB_ARN
aws secretsmanager list-secret-version-ids --secret-id SECRETS_LAB_ARN
```

Inspect labels/rotation/replica state before mutation. Each rotation invocation contains Step, SecretId and ClientRequestToken (plus RotationToken in applicable flows). The function checks whether the version is already current/pending and handles retries idempotently.

| Step         | Backend/secret action                | Failure safeguard                                                                                                           |
| ------------ | ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------- |
| createSecret | Create pending token/version         | Do not generate a second secret on retry                                                                                    |
| setSecret    | Update intended backend/user         | Verify resource/current/pending relationship                                                                                |
| testSecret   | Authenticate with pending value      | On failure reconcile backend/password and labels; old current credentials are not guaranteed usable in single-user rotation |
| finishSecret | Move current stage to tested version | Preserve previous/recovery and reconcile partial failure                                                                    |

A generic placeholder lambda that only creates a random string is not rotation. Deploy the maintained backend template, define VPC/SG/key permissions, schedule/window and recovery; database-managed rotation has a separate supported workflow.

## Cross-account resource policy and replication

A policy granting GetSecretValue to an external role is only one side of authorization. The caller identity and customer-managed KMS key policy must also allow the operation. Validate resource policies with the documented safeguards; do not include a broad account wildcard as a debugging shortcut.

```bash
aws secretsmanager replicate-secret-to-regions --secret-id SECRETS_LAB_ARN \
  --add-replica-regions '[{"Region":"us-west-2","KmsKeyId":"DESTINATION_KEY_ARN"}]'
```

Verify supported Region/partition/key setup and propagation status. Primary rotation propagates; promotion requires the supported stop-replication-to-replica workflow and independent ownership. Regional secrets/API/KMS/network charges apply.

## Application monitoring and cleanup

Log only request/result metadata, schema/version/stage and safe error class—not passwords, tokens or full secret responses. Correlate denied reads/rotation failures with CloudTrail and Lambda/backend evidence. Frequent writes can exhaust version quotas even with automatic cleanup.

Remove replica dependencies and lab rotation schedules/functions/backend credentials as required, then schedule lab secret deletion with recovery where possible. A deleted secret does not revoke a still-valid backend password or remove cached credentials; rotate/decommission the backend explicitly.

References: [GetSecretValue](https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html), [cache](https://docs.aws.amazon.com/secretsmanager/latest/userguide/retrieving-secrets_cache-python.html), [cross-account access](https://docs.aws.amazon.com/secretsmanager/latest/userguide/auth-and-access_examples_cross.html), [rotation templates](https://docs.aws.amazon.com/secretsmanager/latest/userguide/reference_available-rotation-templates.html).

Rotation strategy reference: [single-user versus alternating-user rotation](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotation-strategy.html).

## Cross-wiki comparisons

- [[Azure/compute/aks/security-key-vault-csi|AKS Secrets Management — Azure Key Vault Provider for Secrets Store CSI Driver]] — secrets management (Azure)
- [[DevOps/devsecops/stage4-runtime/16-secret-management|M16: Runtime Secret Management]] — secrets management (DevOps)

## References

- [Four-stage rotation and safeguards](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotate-secrets_lambda-functions.html)
- [Invocation contract](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotate-secrets_lambda.html)
- [Version model](https://docs.aws.amazon.com/secretsmanager/latest/userguide/whats-in-a-secret.html)
- [Replication/promotion](https://docs.aws.amazon.com/secretsmanager/latest/userguide/replicate-secrets.html)
- [Quotas](https://docs.aws.amazon.com/secretsmanager/latest/userguide/reference_limits.html)
- [Pricing](https://aws.amazon.com/secrets-manager/pricing/)

## Across the wiki

- [[Kubernetes/eks/security/secrets-management/README|Secrets Management on EKS]]
- [[Security/kubernetes-security/secrets/README|Kubernetes Secrets Management]]
