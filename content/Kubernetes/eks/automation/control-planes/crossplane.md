---
title: Crossplane on EKS
tags:
  [
    eks,
    crossplane,
    control-planes,
    platform-engineering,
    infrastructure-as-code,
  ]
date: 2026-05-17
description: Using Crossplane on EKS to provision AWS infrastructure through the Kubernetes API — providers and their IAM, managed resources, compositions as platform APIs, and how it compares with ACK, kro and Terraform.
---

# Crossplane on EKS

Crossplane turns a Kubernetes cluster into a control plane for infrastructure. You declare an S3 bucket or an RDS instance as a Kubernetes object, and a controller creates it in AWS and keeps it matching the declaration — the same reconcile loop that keeps a Deployment at three replicas, applied to cloud resources.

Its real purpose is one level higher: letting a platform team publish its **own APIs** ("a `PostgresDatabase` with a size and a version") that hide dozens of underlying resources. That makes it a building block for [[DevOps/platform-engineering/README|platform engineering]].

## The pieces

| Concept                               | What it is                                                                           |
| :------------------------------------ | :----------------------------------------------------------------------------------- |
| **Provider**                          | A controller package for one API family, e.g. `provider-aws-s3`, `provider-aws-rds`  |
| **Managed resource (MR)**             | One Kubernetes object per cloud resource — `Bucket`, `Instance`, `Role`              |
| **ProviderConfig**                    | How a provider authenticates: which credentials, which account                       |
| **XRD** (CompositeResourceDefinition) | The schema of an API you define                                                      |
| **Composition**                       | The implementation of that API: a pipeline of functions that emits managed resources |
| **XR** (composite resource)           | An instance of your API, created by a platform user                                  |

## Install and authenticate

```bash
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm upgrade --install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system --create-namespace
```

Install only the provider families you need. The AWS provider is split per service precisely because the monolithic one installed nearly a thousand CRDs and strained the API server.

```yaml
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-aws-s3
spec:
  package: xpkg.upbound.io/upbound/provider-aws-s3:v1
  runtimeConfigRef:
    name: aws-irsa
---
apiVersion: aws.upbound.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: IRSA
```

The provider pod's service account gets an [[AWS/security/iam/README|IAM]] role through [[Kubernetes/eks/security/iam-roles-for-sa|IRSA]] or [[Kubernetes/eks/security/pod-identity|Pod Identity]]. No access keys are stored. For multi-account setups, that role assumes a role in each target account, selected by a per-account `ProviderConfig`.

**The provider's role is as powerful as the infrastructure it manages.** Anyone who can create a managed resource in the cluster can make AWS create it. Scope the role, set a permissions boundary, and control who can create which resource kinds with [[Kubernetes/concepts/L07-security/01-api-access/03-rbac|RBAC]] and [[Kubernetes/eks/security/policy-management|admission policy]].

## A managed resource

```yaml
apiVersion: s3.aws.upbound.io/v1beta2
kind: Bucket
metadata:
  name: payments-exports
spec:
  forProvider:
    region: eu-west-1
    tags: { team: payments }
  deletionPolicy: Orphan
  providerConfigRef:
    name: default
```

`kubectl get bucket` shows `READY` and `SYNCED`. If someone changes the bucket in the console, Crossplane changes it back at the next reconcile. `deletionPolicy: Orphan` leaves the cloud resource in place when the object is deleted — the safe setting for anything holding data.

## Building a platform API

Developers should not write raw managed resources. Define what they may ask for:

```yaml
apiVersion: apiextensions.crossplane.io/v2
kind: CompositeResourceDefinition
metadata:
  name: databases.platform.example.com
spec:
  scope: Namespaced
  group: platform.example.com
  names: { kind: Database, plural: databases }
  versions:
    - name: v1alpha1
      served: true
      referenceable: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                size: { type: string, enum: [small, medium, large] }
                engineVersion: { type: string, default: "16" }
              required: [size]
```

A **Composition** then maps `size: small` to an instance class, a subnet group, a security group, a parameter group, a KMS key and a Secrets Manager entry, using a pipeline of composition functions (patch-and-transform, Go templates, KCL or Python). A developer's entire request becomes:

```yaml
apiVersion: platform.example.com/v1alpha1
kind: Database
metadata:
  name: orders
  namespace: payments
spec:
  size: small
```

The platform team owns the Composition and can change defaults — encryption, backups, instance generation — for every database at once.

## How it compares

|                     | Crossplane                 | [[Kubernetes/eks/automation/control-planes/ack\|ACK]] | [[Kubernetes/eks/automation/control-planes/kro\|kro]] | Terraform / OpenTofu           |
| :------------------ | :------------------------- | :---------------------------------------------------- | :---------------------------------------------------- | :----------------------------- |
| Model               | Continuous reconcile       | Continuous reconcile                                  | Continuous reconcile                                  | Plan and apply on demand       |
| Clouds              | Many                       | AWS only                                              | Any CRDs present in the cluster                       | Many                           |
| Custom abstractions | XRDs and Compositions      | None                                                  | ResourceGraphDefinitions                              | Modules                        |
| State               | The Kubernetes API (etcd)  | The Kubernetes API                                    | The Kubernetes API                                    | A state file                   |
| Preview of changes  | Limited                    | None                                                  | None                                                  | `plan` — its biggest advantage |
| Maturity            | High, steep learning curve | Per-service, AWS-maintained                           | Young                                                 | Very high                      |

A pragmatic split: [[DevOps/infrastructure-as-code/terraform|Terraform]] for foundations that change rarely and need a reviewed plan (accounts, VPCs, the cluster itself), and a control plane for resources that belong to an application's lifecycle and are requested self-service.

## Operating notes

- **The cluster becomes critical infrastructure.** Deleting an XR can delete a database. Back up the cluster's API objects, use `Orphan` for stateful resources, and protect namespaces from accidental deletion.
- **CRD count** affects API server memory and client discovery time; install the minimum set of providers.
- **Rate limits.** Many resources reconciling against the same AWS API get throttled. Tune poll intervals and provider concurrency.
- **Debugging** is `kubectl describe` on the managed resource: the `Synced` condition carries the AWS error message verbatim. `crossplane beta trace <kind> <name>` shows the whole tree under an XR.
- **Importing** existing resources is done by setting the `crossplane.io/external-name` annotation, optionally with `managementPolicies: ["Observe"]` to adopt without changing anything.
- Deliver XRs and Compositions with [[Kubernetes/eks/automation/gitops/argocd|Argo CD]] or [[Kubernetes/eks/automation/gitops/flux|Flux]], so infrastructure requests are pull requests.

## Related

- [[Kubernetes/eks/automation/README|Automation on EKS]]
- [[DevOps/platform-engineering/crossplane|Crossplane in platform engineering]]
- [[Kubernetes/concepts/L09-advanced/03-customresourcedefinitions|CustomResourceDefinitions]] and [[Kubernetes/concepts/L09-advanced/01-operators|operators]]
- [[DevOps/infrastructure-as-code/README|Infrastructure as code]]
- [Crossplane documentation](https://docs.crossplane.io/)
