---
title: AWS Secrets Manager with EKS
tags: [eks, security, secrets, secrets-manager, csi]
date: 2026-05-17
description: Delivering AWS Secrets Manager and Parameter Store secrets to EKS pods — the Secrets Store CSI Driver with the AWS provider versus External Secrets Operator, identity, rotation and the trade-offs of syncing to Kubernetes Secrets.
---

# AWS Secrets Manager with EKS

Kubernetes Secrets are base64-encoded objects in etcd. They are fine as a delivery mechanism and poor as a system of record: no rotation, no versioning, coarse access control. The usual EKS pattern keeps the source of truth in [[AWS/security/secrets-manager/README|AWS Secrets Manager]] (or SSM Parameter Store) and delivers values to pods at runtime.

There are two mainstream ways to do that, and they differ in _where the secret ends up_.

## Two delivery models

|                            | Secrets Store CSI Driver + AWS provider (ASCP)   | External Secrets Operator (ESO)                         |
| :------------------------- | :----------------------------------------------- | :------------------------------------------------------ |
| Secret reaches the pod as  | Files on a tmpfs volume                          | A normal Kubernetes Secret (env vars or volume)         |
| Stored in etcd             | No, unless you opt into sync                     | Yes                                                     |
| Who calls AWS              | The node DaemonSet, using **the pod's** identity | A central controller, using its own or a per-store role |
| Works when AWS API is down | Running pods keep files; new pods cannot start   | Yes, pods start from the cached Secret                  |
| Application change needed  | Read from a file                                 | None                                                    |
| Fargate                    | No (needs a DaemonSet)                           | Yes                                                     |

Choose the CSI driver when the requirement is "secrets never rest in etcd" and per-pod access control. Choose ESO when applications expect environment variables or ordinary Secrets and you want one place to manage many secret stores.

## Secrets Store CSI Driver with ASCP

Install the driver and the AWS provider (AWS publishes the provider as an EKS add-on):

```bash
helm repo add secrets-store-csi-driver \
  https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm upgrade --install csi-secrets-store \
  secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --set enableSecretRotation=true \
  --set rotationPollInterval=120s

aws eks create-addon --cluster-name my-cluster \
  --addon-name aws-secrets-store-csi-driver-provider
```

Give the **application's** service account a role that can read exactly its own secrets:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:eu-west-1:111122223333:secret:payments/*"
    }
  ]
}
```

Bind it with [[Kubernetes/eks/security/pod-identity|Pod Identity]] or [[Kubernetes/eks/security/iam-roles-for-sa|IRSA]]. If the secret is encrypted with a customer managed [[AWS/security/kms/README|KMS]] key, add `kms:Decrypt` on that key.

A `SecretProviderClass` declares what to fetch:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: payments-db
  namespace: payments
spec:
  provider: aws
  parameters:
    usePodIdentity: "true"
    objects: |
      - objectName: "payments/db"
        objectType: "secretsmanager"
        jmesPath:
          - path: username
            objectAlias: db-username
          - path: password
            objectAlias: db-password
```

```yaml
# pod spec
volumes:
  - name: secrets
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: payments-db
containers:
  - name: app
    volumeMounts:
      - name: secrets
        mountPath: /mnt/secrets
        readOnly: true
```

The pod now sees `/mnt/secrets/db-username` and `/mnt/secrets/db-password`. If the pod's role cannot read the secret, the pod stays in `ContainerCreating` with a `FailedMount` event that names the denied call.

## Rotation

Secrets Manager can rotate a secret on a schedule with a Lambda function. Getting the new value into a running pod is a separate problem:

- **Mounted files** are refreshed by the driver every `rotationPollInterval`. The application must re-read the file — watch it, or reopen it on authentication failure.
- **Environment variables** never change in a running process. A rotation requires a restart; tools such as Reloader trigger a rolling restart when a synced Secret changes.
- Use the **alternating-users** rotation strategy for databases so the previous credential stays valid while pods catch up.

Polling has a cost: every poll is a `GetSecretValue` call per mounted secret per pod. With thousands of pods, lengthen the interval.

## Syncing to a Kubernetes Secret

Both tools can materialise a Kubernetes Secret. With the CSI driver that is the `secretObjects` field, and the Secret exists only while some pod mounts the volume. Be clear about what this gives up: the value is now in etcd, readable by anyone with `get secrets` in the namespace. If you sync, also:

- turn on [[Kubernetes/concepts/L07-security/03-encryption-identity/14-secret-encryption|envelope encryption]] of Secrets with KMS (new EKS clusters encrypt all API data by default),
- restrict `get`/`list` on Secrets with [[Kubernetes/concepts/L07-security/01-api-access/03-rbac|RBAC]].

## External Secrets Operator in brief

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: payments-db
  namespace: payments
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: aws-secrets-manager
  target:
    name: payments-db
  dataFrom:
    - extract:
        key: payments/db
```

The controller's role is the security boundary here. A single `ClusterSecretStore` with broad read access lets any namespace request any secret; scope stores per namespace or restrict them with conditions on the store.

## Secrets Manager or Parameter Store

Secrets Manager adds built-in rotation, cross-region replication and resource policies, and charges per secret per month. Parameter Store `SecureString` parameters are free at the standard tier and adequate for configuration that rarely changes. Both work with both tools.

## Related

- [[Kubernetes/eks/security/secrets-management/README|Secrets management on EKS]]
- [[Kubernetes/eks/security/secrets-management/sealed-secrets|Sealed Secrets]] — the Git-native alternative
- [[Kubernetes/concepts/L05-config-storage/02-secrets|Secrets (concepts)]]
- [[Security/kubernetes-security/secrets/README|Secrets in the Security section]]
- [Use Secrets Manager secrets in EKS](https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_csi_driver.html)
