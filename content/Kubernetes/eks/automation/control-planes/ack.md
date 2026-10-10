---
title: AWS Controllers for Kubernetes (ACK)
tags: [eks, ack, control-planes, infrastructure-as-code, operators]
date: 2026-05-17
description: Managing AWS resources as Kubernetes objects with ACK — one controller per service, installation and IAM, the resource lifecycle, adoption and deletion policies, passing values to workloads, cross-account use and how ACK compares with Crossplane and Terraform.
---

# AWS Controllers for Kubernetes (ACK)

ACK lets you create and manage AWS resources by applying Kubernetes manifests. An S3 bucket, an RDS instance or an SQS queue becomes a custom resource; an ACK controller calls the AWS API to create it and keeps reconciling it against the declared state.

It is AWS's own project, generated from the AWS API models, which makes its resources a close, predictable mapping of the underlying APIs.

## One controller per service

ACK is not a single installation. Each AWS service has its own controller, with its own CRDs, release cycle and IAM permissions: `s3-controller`, `rds-controller`, `iam-controller`, `sqs-controller`, `dynamodb-controller`, `ec2-controller`, `eks-controller` and many more.

Install only what you use. Each controller is a small Deployment, and each adds CRDs to the API server.

```bash
aws ecr-public get-login-password --region us-east-1 | \
  helm registry login --username AWS --password-stdin public.ecr.aws

helm install ack-s3-controller \
  oci://public.ecr.aws/aws-controllers-k8s/s3-chart \
  --namespace ack-system --create-namespace \
  --set aws.region=eu-west-1
```

On EKS, ACK is also available as a managed **EKS Capability**: AWS runs the controllers and you only create resources.

## IAM

Each controller needs an [[AWS/security/iam/README|IAM]] role allowing exactly the API calls for its service. Bind it to the controller's service account with [[Kubernetes/eks/security/pod-identity|Pod Identity]] or [[Kubernetes/eks/security/iam-roles-for-sa|IRSA]]:

```bash
aws eks create-pod-identity-association \
  --cluster-name my-cluster \
  --namespace ack-system \
  --service-account ack-s3-controller \
  --role-arn arn:aws:iam::111122223333:role/ack-s3-controller
```

The ACK documentation publishes a recommended policy per controller. Treat them as a starting point and narrow them: **anyone who can create an ACK resource in the cluster can make AWS create it.** The controller's role, plus Kubernetes [[Kubernetes/concepts/L07-security/01-api-access/03-rbac|RBAC]] on the ACK kinds, is your access control.

## A resource

```yaml
apiVersion: s3.services.k8s.aws/v1alpha1
kind: Bucket
metadata:
  name: payments-exports
  namespace: payments
  annotations:
    services.k8s.aws/deletion-policy: retain
spec:
  name: example-payments-exports-prod
  encryption:
    rules:
      - applyServerSideEncryptionByDefault:
          sseAlgorithm: aws:kms
  publicAccessBlock:
    blockPublicAcls: true
    blockPublicPolicy: true
    ignorePublicAcls: true
    restrictPublicBuckets: true
  tagging:
    tagSet:
      - { key: team, value: payments }
```

```bash
kubectl get bucket -n payments
kubectl describe bucket payments-exports -n payments   # conditions and the ARN in status
```

Every ACK resource reports the same conditions:

| Condition            | Meaning                                                             |
| :------------------- | :------------------------------------------------------------------ |
| `ACK.ResourceSynced` | The AWS resource matches the spec                                   |
| `ACK.Terminal`       | An error that retrying will not fix — invalid spec, immutable field |
| `ACK.Recoverable`    | A transient error; the controller will retry                        |

The AWS error message appears verbatim in the condition, which makes debugging direct.

## Lifecycle details that matter

**Deletion.** By default, deleting the Kubernetes object **deletes the AWS resource**. For anything holding data, set `services.k8s.aws/deletion-policy: retain` on the resource, or as the controller's default. A deleted namespace should not take a production database with it.

**Adoption.** To manage a resource that already exists, annotate a new object with `services.k8s.aws/adoption-policy: adopt` (or `adopt-or-create`) and the identifying fields. The controller takes over without recreating it.

**Read-only.** `services.k8s.aws/read-only: "true"` observes a resource and fills in status without ever modifying it — useful for referencing shared infrastructure.

**Drift.** Controllers re-check resources periodically and correct differences. The interval is long by default (hours) to stay within API rate limits, so a manual console change is not reverted immediately.

**Secrets.** Fields such as a database master password reference a Kubernetes Secret (`masterUserPassword: {name: …, key: …}`) rather than appearing in the manifest. Better still, let the service manage the secret (`manageMasterUserPassword: true` for RDS).

**References.** Resources can point at each other by Kubernetes name instead of ARN — for example a `subnetRefs` field — and the controller resolves them once the referenced object is ready.

## Getting values to your workload

An application needs the queue URL or the database endpoint that only exists after creation. `FieldExport` copies a status field into a ConfigMap or Secret:

```yaml
apiVersion: services.k8s.aws/v1alpha1
kind: FieldExport
metadata:
  name: orders-db-endpoint
  namespace: payments
spec:
  from:
    path: ".status.endpoint.address"
    resource:
      group: rds.services.k8s.aws
      kind: DBInstance
      name: orders
  to:
    kind: configmap
    name: orders-db
```

The Deployment then reads the ConfigMap as environment variables. For wiring many resources together — a queue, a role, a pod identity association and a Deployment — [[Kubernetes/eks/automation/control-planes/kro|kro]] does this with a single definition.

## Multiple accounts and regions

- **Region**: a controller has a default region; override per resource with the `services.k8s.aws/region` annotation, or per namespace with `services.k8s.aws/default-region`.
- **Account**: with cross-account resource management, annotate a namespace with `services.k8s.aws/owner-account-id` and the controller assumes a role in that account for every resource in the namespace. One management cluster can then provision into many accounts.

## How it compares

|                     | ACK                                   | [[Kubernetes/eks/automation/control-planes/crossplane\|Crossplane]] | [[DevOps/infrastructure-as-code/terraform\|Terraform]] |
| :------------------ | :------------------------------------ | :------------------------------------------------------------------ | :----------------------------------------------------- |
| Scope               | AWS only                              | Many clouds and services                                            | Many clouds and services                               |
| Resource model      | A close mapping of the AWS API        | Generated from Terraform providers                                  | Provider resources                                     |
| Custom abstractions | None built in — pair with kro or Helm | XRDs and Compositions                                               | Modules                                                |
| Reconciliation      | Continuous                            | Continuous                                                          | On `apply`                                             |
| Change preview      | None                                  | Limited                                                             | `plan`                                                 |
| Maintained by       | AWS                                   | The Crossplane community and Upbound                                | HashiCorp and provider authors                         |
| Maturity            | Varies by controller: check GA status | High                                                                | Very high                                              |

ACK fits when you are on AWS, want application teams to request infrastructure with the same manifests and pipelines they already use, and want an AWS-supported mapping. Foundations that change rarely and benefit from a reviewed plan — VPCs, the cluster itself — usually stay in Terraform.

## Operating notes

- Check each controller's release status before depending on it; not all services are generally available.
- Deliver resources through [[Kubernetes/eks/automation/gitops/argocd|Argo CD]] or [[Kubernetes/eks/automation/gitops/flux|Flux]], with sync ordering so controllers and CRDs exist before the resources.
- Add admission policy for standards the API does not enforce: encryption, tags, allowed instance classes — [[Kubernetes/eks/security/policy-management|policy management]].
- Back up the cluster's ACK objects. With `retain`, a lost cluster does not delete anything, and re-applying the manifests with an adoption policy reconnects them.
- Watch for API throttling when many resources reconcile at once.

## Related

- [[Kubernetes/eks/automation/README|Automation on EKS]]
- [[Kubernetes/concepts/L09-advanced/01-operators|Operators]] and [[Kubernetes/concepts/L09-advanced/03-customresourcedefinitions|CustomResourceDefinitions]]
- [[DevOps/platform-engineering/internal-developer-platforms|Internal developer platforms]]
- [ACK documentation](https://aws-controllers-k8s.github.io/)
- [EKS Workshop: ACK](https://www.eksworkshop.com/docs/automation/controlplanes/ack/)

## Across the wiki

- [[DevOps/infrastructure-as-code/README|Infrastructure as Code]] — infrastructure as code (DevOps)
- [[AWS/management-governance/cloudformation/README|AWS CloudFormation]] — infrastructure as code (AWS)
- [[DevOps/devsecops/stage2-build/10-iac-security|M10: Infrastructure-as-Code Security]] — infrastructure as code (DevOps)
- [[AWS/management-governance/cdk/README|AWS CDK]] — infrastructure as code (AWS)
