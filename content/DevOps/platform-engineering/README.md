---
title: Platform Engineering & Internal Developer Platforms (IDP)
tags: [devops, platform-engineering, idp, backstage, crossplane, self-service]
date: 2026-09-06
description: "Platform engineering architecture: Thinnest Viable Platform (TVP), Internal Developer Platforms (IDP), Backstage, Crossplane control planes, and cognitive load reduction."
---

# Platform Engineering & Internal Developer Platforms (IDP) 🏗️

Platform Engineering is the discipline of designing and building toolchains and workflows that enable self-service capabilities for software engineering organizations in the cloud-native era.

---

## 1. The Core Problem: Cognitive Load & "Shadow DevOps"

Before platform engineering, developers were burdened with sprawling operational complexity: writing raw Helm charts, provisioning IAM roles, configuring ingress controllers, and wrestling with CloudFormation/Terraform state files. This created friction, bottlenecks on operations teams, and widespread configuration drift.

Platform engineering solves this by treating the platform as a product, providing paved paths (Golden Paths) that allow developers to self-serve infrastructure and deployment without needing to become cloud architects.

```mermaid
flowchart TD
    subgraph Devs["Product Developers"]
        Dev1["Frontend Engineer"]
        Dev2["Backend Engineer"]
        Dev3["Data Scientist"]
    end

    subgraph PlatformProduct["Internal Developer Platform (IDP)"]
        Portal["Developer Portal\n(Backstage / Port / Internal CLI)"]
        Scaffold["Service Scaffolding\n(Golden Paths & Templates)"]
        ControlPlane["Declarative Control Plane\n(Crossplane / Argo CD / K8s CRDs)"]
    end

    subgraph CloudInfra["Cloud-Native Infrastructure"]
        EKS["Amazon EKS / AKS / GKE"]
        DB["Cloud Databases (RDS / Cloud SQL)"]
        Net["VPC & Ingress Networking"]
        Sec["IAM Roles & Vault Secrets"]
    end

    Devs -->|Self-Service Request (e.g. New Microservice)| Portal
    Portal --> Scaffold
    Scaffold --> ControlPlane
    ControlPlane -->|Provisions & Reconciles| CloudInfra
```

---

## 2. Platform Architecture Layers

An enterprise Internal Developer Platform typically comprises five operational planes:

| Plane                                 | Purpose                                                     | Key Technologies                                 |
| :------------------------------------ | :---------------------------------------------------------- | :----------------------------------------------- |
| **1. Developer Interface Plane**      | How developers interact with the platform (UI, CLI, API)    | Backstage, Port, Cortex, internal CLI (`devctl`) |
| **2. Integration & Delivery Plane**   | Automated build, test, and release orchestration            | GitHub Actions, GitLab CI, Argo Workflows        |
| **3. Resource Orchestration Plane**   | Translates high-level developer intents into infrastructure | Crossplane, Terraform Controller, Kratix         |
| **4. Runtime & Compute Plane**        | Where container workloads and functions run                 | Kubernetes (EKS/AKS/GKE), AWS ECS, Serverless    |
| **5. Observability & Security Plane** | Real-time health, security policies, and cost allocation    | OpenTelemetry, Prometheus, Kyverno, OpenCost     |

---

## 3. Core Technologies in Modern Platform Engineering

### 1. Spotify Backstage

An open-source developer portal framework that centralizes:

- **Software Catalog:** Single pane of glass tracking ownership, metadata, and dependencies of all services, APIs, and libraries.
- **Software Templates (Scaffolder):** One-click creation of new microservices with pre-baked CI/CD, linting, Dockerfile, and monitoring.
- **TechDocs:** Markdown documentation rendered next to code.

### 2. Crossplane: Kubernetes-Native Infrastructure Control Planes

Crossplane extends the Kubernetes API to manage external cloud resources (RDS databases, S3 buckets, IAM roles) using standard Kubernetes manifests. By defining **Composite Resource Definitions (XRDs)**, platform teams publish simplified abstractions (e.g., `kind: DatabaseInstance`) while hiding complex multi-cloud Terraform underneath.

---

## 4. The "Thinnest Viable Platform" (TVP) Approach

Avoid building a monolithic internal platform before understanding team needs. The [CNCF Platform Engineering Maturity Model](https://tag-app-delivery.cncf.io/whitepapers/platform-eng-maturity-model/) frames platform evolution around observable pain and developer feedback:

1. **Provisional Stage (Paved Roads):** Start with **Golden Paths** implemented as simple, versioned GitHub Actions templates and cookiecutters that solve immediate onboarding and build friction.
2. **Operational Stage (Service Discovery & Ownership):** Introduce a central software catalog when discovery pain, unclear service ownership, or untracked cross-service dependencies measurably slow down incident triage and security audits.
3. **Scalable Stage (Declarative Self-Service Control Planes):** Decouple infrastructure provisioning through self-service control planes (Crossplane, GitOps, Kubernetes CRDs) when manual operations tickets and configuration drift become quantifiable delivery bottlenecks.
4. **Optimizing Stage (Continuous Product Feedback):** Continuously evaluate platform capabilities using developer satisfaction surveys (DevEx), adoption telemetry, and DORA metrics, deprecating unused tooling and refining golden paths.

---

## Notes in this section

### Foundations & Strategy

- [[DevOps/platform-engineering/internal-developer-platforms|Internal Developer Platforms]] — Capabilities, portal versus platform, platform as a product, metrics and failure modes
- [[DevOps/platform-engineering/platform-vs-devops-vs-sre|Platform Engineering vs DevOps vs SRE]] — Team Topologies operating models, RACI matrix, evolution paths
- [[DevOps/platform-engineering/golden-paths|Golden Paths]] — Paved roads, guardrails over gates, and a complete worked end-to-end developer journey
- [[DevOps/platform-engineering/devex-and-inner-loop|Developer Experience (DevEx) & Inner Loop]] — Bridging local IDE to remote clusters (mirrord/Telepresence), SPACE & DevEx metrics

### Developer Interfaces & Abstractions

- [[DevOps/platform-engineering/backstage|Backstage Developer Portal]] — Software catalog entity model, Scaffolder templates, partial failure handling
- [[DevOps/platform-engineering/workload-specifications|Workload Specifications & Score]] — Separating application intent from environmental context (`score.yaml`, OAM)

### Orchestration, Control Planes & Environments

- [[DevOps/platform-engineering/platform-orchestrators|Platform Orchestrators & Dynamic Configuration]] — Resolving intent into infrastructure with Kratix Promises and Humanitec
- [[DevOps/platform-engineering/crossplane|Crossplane for Platform APIs]] — Declarative namespaced control planes, compositions, and renderable manifests
- [[DevOps/platform-engineering/ephemeral-environments|Ephemeral Environments & EaaS]] — On-demand PR preview environments, vCluster architecture, database branching

### Operations & Governance

- [[DevOps/platform-engineering/finops-and-cost-allocation|FinOps & Cost Allocation for Platforms]] — OpenCost, automated label inheritance, showback vs chargeback, and hygiene
- [[DevOps/infrastructure-as-code/README|Infrastructure as Code]] — The foundational building blocks underneath
- [[DevOps/sre/README|Site Reliability Engineering]] — Running the platform control plane as a production service

---

## Related Knowledge Bases

- ☸️ **[[Kubernetes/guides/delivery/gitops/argo-cd/README|Argo CD & GitOps]]** — Declarative continuous delivery
- 🚀 **[[DevOps/ci-cd/README|CI/CD Pipelines]]** — Integration and delivery pipelines
- 🔐 **[[DevOps/devsecops/README|DevSecOps Curriculum]]** — Embedding security into golden paths
- 📊 **[[Observability|Observability]]** — OpenTelemetry and monitoring for platform services
