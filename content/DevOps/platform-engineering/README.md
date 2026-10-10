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

Avoid building a monolithic internal platform before understanding team needs:

1. Start with **Golden Paths** implemented as simple GitHub Actions templates and cookiecutters.
2. Introduce a central service catalog when microservice count exceeds ~20.
3. Decouple infrastructure through self-service control planes (Crossplane/GitOps) only when operations bottlenecks arise.

---

## Notes in this section

- [[DevOps/platform-engineering/internal-developer-platforms|Internal Developer Platforms]] — Capabilities, portal versus platform, platform as a product, metrics and failure modes
- [[DevOps/platform-engineering/golden-paths|Golden Paths]] — Designing paved roads, guardrails over gates, the day-two problem
- [[DevOps/platform-engineering/backstage|Backstage]] — Software catalog, templates, TechDocs, plugins and operating cost
- [[DevOps/platform-engineering/crossplane|Crossplane for Platform APIs]] — Designing and evolving self-service infrastructure APIs
- [[DevOps/platform-engineering/platform-vs-devops-vs-sre|Platform Engineering vs DevOps vs SRE]] — Principles and how the disciplines differ
- [[DevOps/infrastructure-as-code/README|Infrastructure as Code]] — The building blocks underneath
- [[DevOps/sre/README|Site Reliability Engineering]] — Running the platform itself

---

## Related Knowledge Bases

- ☸️ **[[Kubernetes/guides/delivery/gitops/argo-cd/README|Argo CD & GitOps]]** — Declarative continuous delivery
- 🚀 **[[DevOps/ci-cd/README|CI/CD Pipelines]]** — Integration and delivery pipelines
- 🔐 **[[DevOps/devsecops/README|DevSecOps Curriculum]]** — Embedding security into golden paths
- 📊 **[[Observability|Observability]]** — OpenTelemetry and monitoring for platform services
