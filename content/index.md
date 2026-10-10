---
title: Home
tags: [index, wiki, cloud-native]
date: 2025-05-24
description: Darshan's CloudNative Wiki - knowledge graph covering AWS, Kubernetes, Linux, AI, DevOps, and Security
---

# Darshan's CloudNative Wiki

Welcome to my knowledge graph! This wiki covers cloud-native engineering, from infrastructure to AI.

## Core Topics

- ☁️ **[[AWS]]** - Amazon Web Services (EC2, ECS, EKS, Lambda, VPC, IAM)
- ☸️ **[[Kubernetes]]** - Container orchestration, EKS, GitOps
- 🐧 **[[Linux]]** - System administration, networking, tools
- 🤖 **[[AI]]** - LLMs, agents, RAG, evals, prompt engineering
- 📦 **[[Containers]]** - Namespaces and cgroups, images, registries, runtimes

## Supporting Topics

- 🚀 **[[DevOps]]** - CI/CD, infrastructure as code, SRE, DevSecOps, platform engineering
- 🔐 **[[Security]]** - Zero Trust, Supply Chain, IAM
- 📊 **[[Observability]]** - Metrics, logs, traces, alerting, OpenTelemetry, eBPF
- 🏛️ **[[Architecture]]** - System design, databases, event-driven systems, authentication

## Cloud Providers

- ☁️ **[[AWS]]** - Amazon Web Services
- 🔷 **[[Azure]]** - Microsoft Azure
- 🟠 **[[GCP]]** - Google Cloud Platform

## How the topics connect

- **Bottom up:** [[Linux]] → [[Containers]] → [[Kubernetes]] → a managed cluster on [[Kubernetes/eks/README|EKS]], [[Azure/compute/aks|AKS]] or [[GCP/compute/gke|GKE]].
- **Shipping software:** [[DevOps/ci-cd/pipeline-design|pipelines]] → [[DevOps/ci-cd/deployment-strategies|deployment strategies]] → [[Kubernetes/guides/delivery/gitops/basics|GitOps]] → [[DevOps/platform-engineering/golden-paths|golden paths]].
- **Running it:** [[Observability/fundamentals|observability]] → [[Observability/alerting|alerting]] → [[DevOps/sre/slos-and-error-budgets|SLOs]] → [[DevOps/sre/incident-management|incident management]].
- **Designing it:** [[Architecture/solution-architecture-concepts/foundations/non-functional-requirements/README|non-functional requirements]] → [[Architecture/solution-architecture-concepts/data-architecture/databases/README|databases]] → [[Architecture/solution-architecture-concepts/event-driven-architecture/README|event-driven architecture]].
- **Securing it:** [[Security/zero-trust|zero trust]] → [[Architecture/solution-architecture-concepts/authentication/README|authentication]] → [[DevOps/devsecops/README|DevSecOps]] → [[Kubernetes/concepts/L07-security/index|Kubernetes security]].

_The knowledge graph is interconnected — navigate between topics using bidirectional links!_
