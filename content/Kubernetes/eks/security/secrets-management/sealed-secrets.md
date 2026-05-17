---
title: Sealed Secrets
tags: [eks, security, secrets, sealed-secrets]
date: 2026-05-17
description: GitOps-friendly encrypted secrets with Sealed Secrets
---

# Sealed Secrets

## Overview

Sealed Secrets lets you commit encrypted secrets to Git. Only the Sealed Secrets controller can decrypt them.

## Install Sealed Secrets Controller

```bash
# Add Helm repo
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update

# Install controller
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system
```

## Get Public Key

```bash
# Download public key for encrypting secrets
kubeseal --fetch-cert \
  --controller-name=sealed-secrets \
  --controller-namespace=kube-system \
  > pub-cert.pem
```

## Create Encrypted Secret

```bash
# Create a sealed secret
kubeseal --cert=pub-cert.pem < my-secret.yaml > my-sealed-secret.yaml
```

### Original secret.yaml

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-app-secret
  namespace: default
type: Opaque
stringData:
  database-password: supersecretpassword
  api-key: my-api-key
```

### Sealed secret (git-safe)

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: my-app-secret
  namespace: default
spec:
  encryptedData:
    database-password: AgA2M8GZHGqLdU4f...
    api-key: AgB23M8HZJqmLhR5...
```

## Deploy Sealed Secret

```bash
# Apply to cluster (controller decrypts)
kubectl apply -f my-sealed-secret.yaml

# Verify decrypted secret exists
kubectl get secret my-app-secret -o yaml
```

## Secret Update Workflow

1. Update original secret
2. Re-seal with kubeseal
3. Commit updated sealed secret to Git
4. Sealed Secrets controller auto-updates

## Benefits

- Commit secrets to Git safely
- RBAC controls who can decrypt
- Controller-only decryption
- No external dependencies

## Limitations

- Need to re-seal when cluster changes
- Controller must be bootstrapped first
- Key rotation requires special handling

## References

- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [EKS Workshop - Sealed Secrets](https://www.eksworkshop.com/docs/security/secrets-management/sealed-secrets/)