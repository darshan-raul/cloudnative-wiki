---
title: Crossplane
tags: [eks, automation, crossplane, infrastructure]
date: 2026-05-17
description: Cloud-native infrastructure management with Crossplane
---

# Crossplane

## Overview

Crossplane is an open source multicloud control plane that extends Kubernetes to manage infrastructure.

## Install Crossplane

```bash
# Add Helm repo
helm repo add crossplane https://charts.crossplane.io/stable
helm repo update

# Install Crossplane
helm install crossplane crossplane/crossplane \
  --namespace crossplane-system \
  --create-namespace
```

## Install AWS Provider

```yaml
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-aws
spec:
  package: xpkg.upbound.io/crossplane/provider-aws:v0.42.0
---
apiVersion: aws.crossplane.io/v1alpha1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: InjectedIdentity
```

## Create Managed Resources

### S3 Bucket

```yaml
apiVersion: s3.aws.crossplane.io/v1beta1
kind: Bucket
metadata:
  name: my-bucket
spec:
  forProvider:
    locationConstraint: us-west-2
    versioningConfiguration:
      status: Enabled
  providerConfigRef:
    name: default
```

### RDS Instance

```yaml
apiVersion: rds.aws.crossplane.io/v1alpha1
kind: DBInstance
metadata:
  name: my-database
spec:
  forProvider:
    dbInstanceClass: db.t3.medium
    engine: postgres
    engineVersion: "15.3"
    allocatedStorage: 20
    masterUsername: admin
    publiclyAccessible: false
    dbSubnetGroupNameRef:
      name: my-db-subnet-group
    vpcSecurityGroupIDs:
      - sg-1234567890abcdef0
  providerConfigRef:
    name: default
```

## Composite Resources (XR)

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: database
spec:
  resources:
    - base:
        apiVersion: rds.aws.crossplane.io/v1alpha1
        kind: DBInstance
      patches:
        - fromFieldPath: spec.parameters.engine
          toFieldPath: spec.forProvider.engine
        - fromFieldPath: spec.parameters.instanceClass
          toFieldPath: spec.forProvider.dbInstanceClass
      connectionDetails:
        - fromConnectionSecretKeyRef:
            name: db-creds
            key: username
        - fromConnectionSecretKeyRef:
            name: db-creds
            key: password
---
apiVersion: database.example.com/v1alpha1
kind: PostgreSQLInstance
metadata:
  name: my-postgres
spec:
  parameters:
    engine: postgres
    instanceClass: db.t3.medium
  compositionRef:
    name: database
  publishConnectionDetailsTo:
    name: db-creds
```

## Usage

```bash
# Create database instance
kubectl apply -f postgres-instance.yaml

# View managed resources
kubectl get managed

# View connection secret
kubectl get secret db-creds -o yaml
```

## References

- [Crossplane Documentation](https://crossplane.io/)
- [EKS Workshop - Crossplane](https://www.eksworkshop.com/docs/automation/controlplanes/crossplane/)