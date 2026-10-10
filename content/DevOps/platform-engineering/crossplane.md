---
title: Crossplane for Platform APIs
tags: [devops, platform-engineering, crossplane, control-planes, self-service]
date: 2026-10-10
description: Using Crossplane as the engine behind a platform's self-service API — designing the abstraction developers see, composition functions, a worked example, tenancy and guardrails, evolving an API safely, and when a simpler tool is the better choice.
---

# Crossplane for Platform APIs

Crossplane lets a platform team define its **own Kubernetes APIs** and implement them as compositions of real infrastructure. A developer creates a small `Database` or `WebService` object; Crossplane expands it into the cloud resources, IAM, networking and Kubernetes objects behind it and keeps them reconciled.

That makes it one of the main engines for the self-service layer of an [[DevOps/platform-engineering/internal-developer-platforms|internal developer platform]]. This note is about the platform-design side. Installation, providers and AWS authentication are covered in [[Kubernetes/eks/automation/control-planes/crossplane|Crossplane on EKS]].

## Two audiences, two layers

```
developer writes                     platform team writes                    Crossplane manages
┌──────────────────┐       ┌──────────────────────────────────┐     ┌──────────────────────────┐
│ kind: Database   │       │ XRD: the schema of "Database"    │     │ RDS instance             │
│ spec:            │ ───►  │ Composition: how to build one    │ ──► │ subnet group, SG         │
│   size: small    │       │   (a pipeline of functions)      │     │ KMS key, parameter group │
│   engine: 16     │       │                                  │     │ Secret with credentials  │
└──────────────────┘       └──────────────────────────────────┘     └──────────────────────────┘
   the platform API               the implementation                    managed resources
```

The **XRD** (CompositeResourceDefinition) is the contract with developers. The **Composition** is the implementation and can change without the contract changing — which is the property that solves the "day-two" problem described in [[DevOps/platform-engineering/golden-paths|golden paths]]: tighten a default in one Composition and every existing instance is reconciled to it.

## Designing the API

The hard part of Crossplane is not YAML. It is deciding what the developer-facing API should look like.

**Ask for intent, not implementation.**

| Leaky                                        | Intent-based                           |
| :------------------------------------------- | :------------------------------------- |
| `instanceClass: db.r7g.large`                | `size: medium`                         |
| `multiAZ: true`, `backupRetentionPeriod: 14` | `tier: production`                     |
| `subnetIds: […]`, `vpcSecurityGroupIds: […]` | Nothing — derived from the environment |
| `storageEncrypted: true`, `kmsKeyId: …`      | Nothing — always on, not negotiable    |

Guidelines:

- **Expose what legitimately varies** between uses: size, engine version, perhaps a tier. Decide everything else.
- **Never expose a security or compliance setting as optional.** If encryption is required, it is not a field.
- **Use enums with meaningful names.** `small | medium | large` can be remapped to new instance generations later; a raw instance type cannot.
- **Report useful status**: an endpoint, the name of the Secret holding credentials, a ready condition.
- **Keep it cloud-neutral only if you will really run on several clouds.** Otherwise the abstraction costs more than it returns.
- **Fewer fields is better.** Every field is a promise you must keep across versions.

## A worked example

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
              required: [size]
              properties:
                size: { type: string, enum: [small, medium, large] }
                engineVersion:
                  { type: string, enum: ["15", "16", "17"], default: "16" }
                tier:
                  {
                    type: string,
                    enum: [development, production],
                    default: development,
                  }
            status:
              type: object
              properties:
                endpoint: { type: string }
                secretName: { type: string }
```

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: database-aws
spec:
  compositeTypeRef:
    apiVersion: platform.example.com/v1alpha1
    kind: Database
  mode: Pipeline
  pipeline:
    - step: render
      functionRef: { name: function-go-templating }
      input:
        apiVersion: gotemplating.fn.crossplane.io/v1beta1
        kind: GoTemplate
        source: Inline
        inline:
          template: |
            {{ $xr := .observed.composite.resource }}
            {{ $sizes := dict "small" "db.t4g.medium" "medium" "db.r7g.large" "large" "db.r7g.2xlarge" }}
            {{ $prod := eq $xr.spec.tier "production" }}
            apiVersion: rds.aws.upbound.io/v1beta1
            kind: Instance
            metadata:
              annotations:
                gotemplating.fn.crossplane.io/composition-resource-name: instance
            spec:
              forProvider:
                region: eu-west-1
                engine: postgres
                engineVersion: {{ $xr.spec.engineVersion | quote }}
                instanceClass: {{ index $sizes $xr.spec.size }}
                allocatedStorage: {{ if $prod }}100{{ else }}20{{ end }}
                multiAz: {{ $prod }}
                backupRetentionPeriod: {{ if $prod }}14{{ else }}1{{ end }}
                storageEncrypted: true
                deletionProtection: {{ $prod }}
                manageMasterUserPassword: true
    - step: ready
      functionRef: { name: function-auto-ready }
```

A developer's entire request:

```yaml
apiVersion: platform.example.com/v1alpha1
kind: Database
metadata:
  name: orders
  namespace: payments
spec:
  size: small
  tier: production
```

`tier: production` silently brings multi-AZ, fourteen days of backups, more storage and deletion protection. Those are platform decisions, made once.

## Composition functions

A Composition is a **pipeline of functions**, each a small program that receives the desired state and returns a modified one.

| Function                      | Write logic in             | Use for                                        |
| :---------------------------- | :------------------------- | :--------------------------------------------- |
| Patch and transform           | Declarative patches        | Simple field mapping                           |
| Go templating                 | Go templates               | Conditionals and loops, familiar to Helm users |
| KCL, CUE, Pkl                 | A configuration language   | Typed, testable configuration logic            |
| Python, Go, TypeScript SDKs   | A general-purpose language | Complex logic, external lookups                |
| Auto-ready, status, sequencer | —                          | Readiness, status propagation, ordering        |

Start with templating or patch-and-transform. Reach for a real language only when the logic demands it — and when it does, unit-test it.

## Tenancy and guardrails

Crossplane's providers hold powerful cloud credentials. Anyone who can create an object that Crossplane acts on can make it create infrastructure.

- **Developers get RBAC on your XR kinds only**, in their own namespaces — never on raw managed resources such as `Instance` or `Role`. See [[Kubernetes/concepts/L07-security/01-api-access/03-rbac|RBAC]].
- **Namespaced XRs** give natural per-team isolation and work with ordinary Kubernetes tooling.
- **One `ProviderConfig` per environment or account**, selected by the Composition, not by the developer.
- **Admission policy** for what the schema cannot express: quotas, naming, which tiers a namespace may request — [[Kubernetes/eks/security/policy-management|policy management]].
- **`deletionPolicy: Orphan` and deletion protection** on anything stateful. Deleting a namespace must not delete a production database.
- **Scope and bound the provider's IAM role** — [[AWS/security/iam/README|IAM]].

## Evolving an API

Your XRD is an API with consumers, and deserves the same care as any other — [[DevOps/ci-cd/release-and-versioning|release and versioning]].

- **Additive changes are safe**: a new optional field with a default.
- **Breaking changes need a new version** (`v1alpha1` → `v1beta1`), both served for a migration period.
- **Changing a Composition changes every instance.** Roll out with composition revisions: pin existing resources to the current revision, try the new one on a few, then promote. A careless edit can trigger replacement of live databases across the organisation.
- **Test compositions in CI**: `crossplane render` produces the output for a given input offline, so you can diff it and assert on it before anything reaches a cluster.
- **Package and version** XRDs, Compositions and functions as a Configuration, and deliver them through GitOps like any other artifact.

## When to choose something simpler

Crossplane is powerful and has a real learning curve and operational weight.

| Situation                                                   | Consider instead                                                                                                 |
| :---------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------- |
| A few infrastructure types that rarely change               | [[DevOps/infrastructure-as-code/terraform\|Terraform]] modules in a pipeline                                     |
| AWS only, and resources already have Kubernetes controllers | [[Kubernetes/eks/automation/control-planes/ack\|ACK]] with [[Kubernetes/eks/automation/control-planes/kro\|kro]] |
| The abstraction is only Kubernetes objects                  | A Helm chart with a small values schema, or kro                                                                  |
| You need a reviewed plan before every infrastructure change | Terraform or OpenTofu                                                                                            |
| A small team with no one to own a control plane             | A managed PaaS                                                                                                   |

It earns its place when many teams need self-service infrastructure with centrally enforced standards, across accounts or clouds, with continuous reconciliation. The comparison table is in [[Kubernetes/eks/automation/control-planes/crossplane|Crossplane on EKS]].

## Operating it

- The control-plane cluster is now critical infrastructure. Back it up, monitor provider health, and alert on resources that stay unsynced.
- Install only the provider families you use; CRD count affects API server memory.
- Debug top-down: `crossplane beta trace database orders -n payments` shows the whole tree and where it is stuck.
- Surface failures to developers in the XR's status and events — they cannot and should not read provider logs.

## Related

- [[DevOps/platform-engineering/README|Platform engineering overview]]
- [[DevOps/platform-engineering/golden-paths|Golden paths]]
- [[DevOps/infrastructure-as-code/README|Infrastructure as code]]
- [[Kubernetes/concepts/L09-advanced/03-customresourcedefinitions|CustomResourceDefinitions]] and [[Kubernetes/concepts/L09-advanced/01-operators|operators]]
- [[Kubernetes/eks/automation/gitops/argocd|Argo CD]] — delivering XRs and Compositions

## Further reading

- [Crossplane: crossplane pipeline functions (video)](https://youtu.be/jjtpEhvwgMw)
