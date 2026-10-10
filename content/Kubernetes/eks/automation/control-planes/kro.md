---
title: kro (Kube Resource Orchestrator)
tags: [eks, kro, control-planes, platform-engineering]
date: 2026-05-17
description: kro lets a platform team define a new Kubernetes API as a graph of existing resources — how ResourceGraphDefinitions work, CEL expressions and dependency ordering, pairing with ACK, and where kro fits next to Helm and Crossplane.
---

# kro (Kube Resource Orchestrator)

kro is a Kubernetes controller for building custom APIs out of resources that already exist in the cluster. You describe a group of resources and how they depend on each other; kro generates a CRD for it and runs a controller that creates and maintains every instance. It was started by AWS and is developed in the open together with Google and Microsoft, so it is not tied to one cloud.

Think of it as the missing piece between a Helm chart and a hand-written operator: more than templating, far less than writing Go.

## The one resource you write

A **ResourceGraphDefinition** (RGD) has two parts:

- a **schema** — the fields users of the new API may set, with types and defaults, and the status fields it reports back;
- **resources** — the objects to create, with values filled in by [CEL](https://kubernetes.io/docs/reference/using-api/cel/) expressions.

```yaml
apiVersion: kro.run/v1alpha1
kind: ResourceGraphDefinition
metadata:
  name: webapp
spec:
  schema:
    apiVersion: v1alpha1
    kind: WebApp
    spec:
      image: string
      replicas: integer | default=2
      port: integer | default=8080
      public: boolean | default=false
    status:
      availableReplicas: ${deployment.status.availableReplicas}
      url: ${ingress.status.loadBalancer.ingress[0].hostname}
  resources:
    - id: deployment
      template:
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: ${schema.metadata.name}
        spec:
          replicas: ${schema.spec.replicas}
          selector:
            matchLabels: { app: "${schema.metadata.name}" }
          template:
            metadata:
              labels: { app: "${schema.metadata.name}" }
            spec:
              containers:
                - name: app
                  image: ${schema.spec.image}
                  ports:
                    - containerPort: ${schema.spec.port}
    - id: service
      template:
        apiVersion: v1
        kind: Service
        metadata:
          name: ${schema.metadata.name}
        spec:
          selector: ${deployment.spec.selector.matchLabels}
          ports:
            - port: 80
              targetPort: ${schema.spec.port}
    - id: ingress
      includeWhen:
        - ${schema.spec.public}
      template:
        apiVersion: networking.k8s.io/v1
        kind: Ingress
        metadata:
          name: ${schema.metadata.name}
          annotations:
            alb.ingress.kubernetes.io/scheme: internet-facing
            alb.ingress.kubernetes.io/target-type: ip
        spec:
          ingressClassName: alb
          rules:
            - http:
                paths:
                  - path: /
                    pathType: Prefix
                    backend:
                      service:
                        name: ${service.metadata.name}
                        port: { number: 80 }
```

Applying this creates a `WebApp` CRD. A developer then writes six lines:

```yaml
apiVersion: kro.run/v1alpha1
kind: WebApp
metadata:
  name: checkout
spec:
  image: 111122223333.dkr.ecr.eu-west-1.amazonaws.com/checkout:1.4.2
  public: true
```

## What kro does with it

1. **Builds a dependency graph.** Because `service` refers to `${deployment…}`, kro knows the Deployment comes first. Order is inferred from references, never declared, and a cycle is rejected when the RGD is applied.
2. **Validates statically.** Expressions are type-checked against the OpenAPI schemas of the referenced resources, so a typo in a field name fails at definition time rather than at 3 a.m.
3. **Creates resources in order**, waiting for each to be ready. `readyWhen` lets you define readiness per resource (for example, an RDS instance whose status is `available`).
4. **Passes values downstream.** A later resource can use an earlier one's status — an ARN, an endpoint, a generated name.
5. **Reconciles continuously** and deletes in reverse order.

`includeWhen` adds conditional resources, and collections let one template expand into several objects.

## kro with ACK

kro only orchestrates; something else must know how to create AWS resources. [[Kubernetes/eks/automation/control-planes/ack|ACK]] supplies that: each ACK controller adds CRDs such as `Bucket`, `DBInstance` or `Role`. An RGD can mix them with ordinary Kubernetes objects:

```
WebAppWithQueue (your API)
├── ACK  Queue (SQS)               ──► status.queueARN
├── ACK  Policy + Role (IAM)       ◄── uses the queue ARN
├── ACK  PodIdentityAssociation    ◄── uses the role ARN
├── ServiceAccount
└── Deployment                     ◄── env QUEUE_URL from the queue status
```

One object from the developer yields a queue, a least-privilege [[AWS/security/iam/README|IAM]] role bound through [[Kubernetes/eks/security/pod-identity|Pod Identity]], and a workload already wired to both. That end-to-end wiring is the reason to use kro rather than a chart.

On EKS, kro, ACK and Argo CD are also offered as managed **EKS Capabilities**: AWS runs the controllers and you only supply the definitions. Self-install with Helm when you want to pin versions or run elsewhere.

## Where it fits

|                                    | Helm chart                         | kro                                        | [[Kubernetes/eks/automation/control-planes/crossplane\|Crossplane]] |
| :--------------------------------- | :--------------------------------- | :----------------------------------------- | :------------------------------------------------------------------ |
| Runs                               | Client-side, at install or upgrade | In-cluster controller, continuously        | In-cluster controllers, continuously                                |
| User-facing API                    | A values file                      | A real CRD with validation and status      | A real CRD with validation and status                               |
| Uses values from created resources | No                                 | Yes, through CEL references                | Yes, through composition functions                                  |
| Talks to cloud APIs                | No                                 | No — delegates to ACK or other controllers | Yes, through its own providers                                      |
| Logic                              | Go templates                       | CEL expressions                            | Function pipelines in several languages                             |
| Complexity                         | Low                                | Low to medium                              | High                                                                |

Choose kro when the abstraction is "a known set of resources wired together", your cloud resources already have Kubernetes controllers, and you want something a platform team can learn in an afternoon. Choose Crossplane when you need multi-cloud providers or complex logic in the composition.

## Operating notes

- The API group is still `v1alpha1`. Expect field changes between releases and pin the version.
- RBAC: kro's controller needs permission for every resource kind your RGDs create. Grant them deliberately rather than giving it cluster-admin.
- Updating an RGD's schema updates the generated CRD; removing a field that instances use breaks them. Treat RGDs as versioned APIs.
- `kubectl get rgd` shows whether a definition is `Active`; `kubectl describe` on an instance shows which resource in the graph is blocking.
- Deliver RGDs and instances through [[Kubernetes/eks/automation/gitops/argocd|GitOps]] like any other manifest.

## Related

- [[Kubernetes/eks/automation/README|Automation on EKS]]
- [[DevOps/platform-engineering/golden-paths|Golden paths]] — what these APIs are for
- [[Kubernetes/concepts/L09-advanced/03-customresourcedefinitions|CustomResourceDefinitions]] and [[Kubernetes/concepts/L09-advanced/02-custom-controllers|custom controllers]]
- [kro documentation](https://kro.run/docs/overview)
