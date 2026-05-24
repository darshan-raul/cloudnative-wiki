---
title: Kubernetes Secrets Management
tags: [kubernetes, security, secrets, vault, eso, sealed-secrets]
date: 2025-05-24
description: Kubernetes secrets management - Sealed Secrets, External Secrets Operator (ESO), HashiCorp Vault integration for EKS
---

# Kubernetes Secrets Management 🔐

Kubernetes secrets store sensitive data (passwords, tokens, keys) securely, but base64 encoding is not encryption. Production workloads need proper secret encryption.

## Options

| Tool | How It Works | Best For |
|------|-------------|----------|
| **Sealed Secrets** | Encrypt secrets with a cluster-specific RSA key | GitOps workflows |
| **ESO (External Secrets Operator)** | Sync from AWS Secrets Manager / Vault | AWS-native |
| **HashiCorp Vault** | Direct integration via Vault CSI provider | Enterprise |
| **AWS Secrets Manager** | Native EKS integration via IRSA | AWS-first |

## Sealed Secrets (Bitnami)

```bash
# Install Sealed Secrets controller
helm install sealed-secrets bitnami-labs/sealed-secrets

# Create a sealed secret from a regular secret
kubectl create secret generic my-secret --from-literal=password=supersecret --dry-run=json -o json | \
kubeseal --cert pub-cert.pem -o json > sealed-secret.json
```

```yaml
# sealed-secret.json — safe to commit to git
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: my-secret
spec:
  encryptedData:
    password: AgA...encrypted...
```

## External Secrets Operator (ESO)

```bash
# Install ESO
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace
```

```yaml
# Sync from AWS Secrets Manager
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: db-credentials
    creationPolicy: Owner
  data:
  - secretKey: password
    remoteRef:
      key: prod/database/password
```

## Vault via CSI Provider

```yaml
# Mount secrets as files (no env var exposure)
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: app
    volumeMounts:
    - name: vault-secrets
      mountPath: /mnt/secrets
      readOnly: true
  volumes:
  - name: vault-secrets
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: vault-gpi
```

## Related

- [[Security/kubernetes-security/README|K8s Security Hub]]
- [[Security/siem/wazuh/integrations/README|n8n Integrations]]