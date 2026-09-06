---
title: Kubernetes Curriculum Improvement Plan
tags: [kubernetes, curriculum, planning, documentation]
date: 2026-09-06
draft: true
description: Editorial and implementation plan for turning the Kubernetes knowledge base into a structured beginner curriculum and deep reference.
---

# Kubernetes Curriculum Improvement Plan

## Purpose

This document defines the work required to turn the Kubernetes section into two complementary resources:

1. A structured, practical learning path for someone new to Kubernetes.
2. A fast revision and deep-reference system for engineers who already know Kubernetes.

The existing section contains substantial technical material. The goal is to organize, connect, validate, and teach that material more effectively rather than simply increase the number of notes.

This is an editorial plan. It is marked `draft: true` so Quartz does not publish it as part of the reader-facing wiki while the work is underway.

## Current-state assessment

### Inventory

The Kubernetes section currently contains 231 Markdown notes:

| Area            | Notes | Current role                                                          |
| --------------- | ----: | --------------------------------------------------------------------- |
| `concepts/`     |   104 | Numbered conceptual curriculum, L00 through L09                       |
| `guides/`       |    51 | Tools, troubleshooting, delivery, networking, and production concerns |
| `eks/`          |    73 | AWS-specific Kubernetes implementation guidance                       |
| Top-level notes |     3 | Client-go, troubleshooting, and version history                       |

The strongest areas by depth are workloads, networking, scheduling, security, Helm, troubleshooting, and Kubernetes extension mechanisms. Several individual notes are already detailed enough to serve as strong reference material.

### Strengths to preserve

- The L00–L09 numbering establishes a recognizable progression.
- The split between universal concepts, practical guides, and EKS-specific implementation is sound.
- Many notes explain internals, failure modes, operational commands, decision criteria, and gotchas.
- Workloads follow the useful Pod → ReplicaSet → Deployment controller model.
- Networking covers Services, DNS, EndpointSlices, NetworkPolicy, CNI, and packet flow.
- Scheduling covers placement primitives, resources, disruption, and several forms of autoscaling.
- Security spans identity, authorization, sandboxing, encryption, policy, auditing, and hardening.
- Guides include practical troubleshooting and production-oriented subjects.
- Advanced notes cover CRDs, controllers, finalizers, garbage collection, admission, etcd, and API aggregation.

### Main problems

#### 1. The curriculum is structured by subject, but not by learner experience

A beginner can see the order of topics but does not complete a coherent application journey. The path needs a cumulative lab in which every level changes, observes, secures, or repairs the same application.

#### 2. Core lessons are mixed with reference depth

Several pages are long encyclopedic treatments. The Pod note, for example, includes lifecycle, networking, init containers, sidecars, probes, resources, security, storage, scheduling, disruption, QoS, static Pods, recipes, and mistakes. Many of those topics also have dedicated notes.

Long-form depth should remain available, but beginners need a visible core path and clear permission to defer internals.

#### 3. Practice and retrieval are inconsistent

Only a small portion of the section has explicit prerequisites, labs, exercises, knowledge checks, summaries, or revision aids. Reading alone is insufficient for learning operational Kubernetes.

#### 4. Navigation contains gaps and stale promises

- Several links point to nonexistent certification, service-mesh, networking, storage, ReplicaSet, control-plane, and resource-management paths.
- Level hubs often link to folders while the curated introduction is `00-README.md`; readers may land on an automatically generated folder page instead of the intended lesson hub.
- Some status tables still label substantial notes as outlines or stubs.
- Several hub table rows begin with `||` and may render incorrectly.
- `concepts/L07-security.md` is empty.
- Reader-facing content and internal Gateway API research/planning files are mixed together.

#### 5. Version-sensitive guidance is stale

- The version-history note ends at Kubernetes 1.30.
- Kubernetes 1.37 is the current release as of this plan.
- The Ingress note recommends ingress-nginx as a safe default even though the project was retired in March 2026.
- The IPVS material does not lead with its deprecation in Kubernetes 1.35 and the migration path toward nftables.
- The swap note inaccurately implies that modern cgroup-v2 nodes generally accept enabled swap without explicit kubelet configuration.
- Legacy Endpoints and deprecated storage behavior need clearer labels.

Version-sensitive claims must state the relevant Kubernetes version, feature state, and verification date.

#### 6. Metadata is inconsistent

Many concept notes do not use the repository's normal frontmatter. Some guide hubs lack an H1. This reduces the quality of page titles, descriptions, tags, search results, and generated metadata.

## Learning design principles

All curriculum work should follow these principles.

### Learn through one continuous system

Use one small application throughout the beginner path. A suggested application has:

- A stateless web/API Deployment
- A worker or batch Job
- A ConfigMap and Secret
- A ClusterIP Service
- An optional stateful dependency
- Health endpoints
- Metrics and structured logs
- A deliberately configurable failure mode

The application should remain small enough to understand from its manifests. Each level adds one concern to the same system.

### Introduce an idea immediately before using it

Explain Pods before Deployments, labels before selectors, Services before Ingress, requests before scheduling, and identities before RBAC. Avoid requiring concepts that are only taught several levels later.

### Separate core, production, and internals depth

Every substantial note should label its content:

- **Core:** required for the sequential beginner path
- **Production:** operational practices and tradeoffs
- **Internals:** implementation details useful for debugging or extension

The labels may be expressed with Quartz callouts, consistent headings, or page metadata.

### Make outcomes observable

Every practical lesson should state:

- What the learner will create or change
- What command they will run
- What successful output looks like
- What failure they may encounter
- How to clean up
- What Kubernetes behavior the exercise demonstrated

### Teach diagnosis alongside the happy path

After a learner successfully uses a concept, give them one controlled failure involving that concept. Examples include a selector mismatch, bad readiness probe, missing Secret key, Pending PVC, denied NetworkPolicy, insufficient resources, or forbidden RBAC request.

### Make reference use fast

Experienced readers should be able to reach a command, comparison, failure mode, feature status, or decision table without reading a full tutorial.

## Target information architecture

### Kubernetes landing page

Replace the current short landing page with an audience-oriented entry point:

| Reader intent                       | Destination                         |
| ----------------------------------- | ----------------------------------- |
| I am new to Kubernetes              | Beginner learning path              |
| I know the basics and want depth    | Concepts and internals map          |
| I need to fix a problem             | Symptom-based troubleshooting index |
| I am preparing a production cluster | Production readiness path           |
| I need AWS-specific Kubernetes      | EKS path                            |
| I want exam revision                | Certification and practice path     |

The landing page should also contain:

- A visual curriculum map
- Prerequisite expectations
- Estimated depth for each route
- A glossary link
- A current-version banner
- A clear explanation of concepts versus guides versus provider material

### Beginner curriculum

The target core path is:

| Level | Theme                                   | Learner outcome                                            |
| ----- | --------------------------------------- | ---------------------------------------------------------- |
| 00    | Orientation and environment             | Run a local cluster and deploy a first workload            |
| 01    | Cluster and API model                   | Explain the components and inspect Kubernetes objects      |
| 02    | Workloads                               | Deploy, update, scale, and roll back an application        |
| 03    | Configuration and identity              | Configure workloads and introduce ServiceAccounts          |
| 04    | Services and networking                 | Reach the application and trace traffic                    |
| 05    | Storage and state                       | Persist data and understand provisioning                   |
| 06    | Resources, scheduling, and availability | Place, protect, and scale workloads                        |
| 07    | Security                                | Reduce permissions and isolate the application             |
| 08    | Observability and operations            | Measure, diagnose, maintain, and recover the system        |
| 09    | Delivery and lifecycle                  | Package, deliver, upgrade, and manage change               |
| 10    | Extensibility and internals             | Understand CRDs, controllers, operators, and API machinery |

The existing L00–L09 content can be migrated incrementally. Renumbering should happen only after links are tested and redirects or aliases are planned.

### Experienced-reader paths

Create a `review/` or equivalent hub organized around common questions:

- How does `kubectl apply` become a running container?
- Why is a Pod Pending?
- Why is a Deployment rollout stuck?
- How does traffic reach a Pod through a Service?
- Why does a Service have no endpoints?
- How does DNS resolution work inside a Pod?
- Which controller owns this object?
- What happens during a node drain?
- How should HPA, VPA, KEDA, Cluster Autoscaler, and node provisioners be combined?
- How do I diagnose CNI, DNS, storage, admission, and certificate failures?
- Which APIs and features changed in recent Kubernetes versions?

Each question should provide:

1. A five-minute refresher
2. A diagram or decision table
3. Links to the full deep dives
4. A failure scenario
5. A small set of recall questions

### Production-readiness path

Create a cross-cutting path that draws from concepts and guides:

1. Availability and failure domains
2. Resource management and capacity
3. Security baseline
4. Network isolation and ingress
5. Storage resilience
6. Observability and alerting
7. Backup and restore validation
8. Upgrades and API deprecations
9. Cost controls
10. Incident response and runbooks

This path should end with a production-readiness checklist and a scenario-based review.

## Cumulative beginner lab

### Lab environment

Use `kind` as the default environment because it is reproducible and supports multi-node configurations. Mention minikube, k3d, and desktop distributions as alternatives without maintaining parallel instructions in every lesson.

Pin the following:

- Kubernetes version
- `kind` version
- `kubectl` version range
- Container image digests or immutable tags
- Optional add-on versions

Provide setup and cleanup scripts only where they reduce error-prone repetition. Every script must be understandable from the accompanying guide.

### Lab progression

#### Lab 00: Create and inspect a cluster

- Create a multi-node local cluster
- Inspect contexts, nodes, namespaces, and system Pods
- Identify control-plane and worker nodes
- Delete and recreate the cluster

#### Lab 01: Deploy the application

- Create a Deployment
- Inspect its ReplicaSet and Pods
- Use labels and selectors
- Read events and logs
- Explain desired versus observed state

#### Lab 02: Update and repair it

- Perform a rolling update
- Watch rollout status
- Introduce a bad image
- Diagnose `ImagePullBackOff`
- Roll back

#### Lab 03: Configure it

- Add a ConfigMap and Secret
- Consume values as environment variables and mounted files
- Observe update behavior
- Introduce a missing key and diagnose it

#### Lab 04: Expose it

- Create a ClusterIP Service
- Inspect EndpointSlices
- Test DNS from a debug Pod
- Introduce a selector mismatch
- Add Gateway API routing or a maintained ingress implementation

#### Lab 05: Persist data

- Create a PVC through a StorageClass
- Mount it into a Pod
- Recreate the Pod and verify persistence
- Observe binding and topology behavior
- Diagnose a deliberately Pending claim

#### Lab 06: Schedule and scale it

- Add requests and limits
- Observe QoS
- Add topology spread or affinity
- Configure HPA with generated load
- Drain a node and observe a PDB
- Diagnose a Pending Pod caused by impossible constraints

#### Lab 07: Secure it

- Create a dedicated ServiceAccount
- Apply least-privilege RBAC

- Use `kubectl auth can-i`
- Apply a restricted security context
- Enforce Pod Security Admission
- Apply default-deny and explicit-allow NetworkPolicies
- Add one admission-policy exercise

#### Lab 08: Observe and troubleshoot it

- Inspect application and Kubernetes metrics
- Query current and previous logs
- Use events, `describe`, `exec`, and ephemeral containers
- Diagnose CPU, memory, probe, DNS, and Service failures
- Record a short incident timeline

#### Lab 09: Deliver and recover it

- Package the application with Helm or Kustomize
- Apply it through a simple GitOps workflow
- Perform an upgrade
- Detect a deprecated API
- Back up relevant state
- Restore into a clean namespace or cluster

#### Lab 10: Extend Kubernetes

- Install a small CRD
- Observe an existing controller reconcile it
- Add or inspect status conditions and finalizers
- Optionally build a minimal controller as an advanced exercise

## Page contract

Every core lesson should use this structure unless the subject clearly requires a different shape.

### Required frontmatter

```yaml
---
title: Example Topic
tags: [kubernetes, topic]
date: YYYY-MM-DD
description: One-sentence description of the page outcome
level: core
testedWith: "1.37"
lastVerified: YYYY-MM-DD
---
```

`level` and version fields may require confirmation that Quartz preserves unknown frontmatter fields. If they are not useful to the generated site, express them in a standard callout near the beginning instead.

### Required sections

1. **Why this matters**
2. **Prerequisites**
3. **What you will understand or do**
4. **Five-minute refresher**
5. **Mental model**
6. **Minimal working example**
7. **How it works**
8. **Production considerations**
9. **Failure modes and debugging**
10. **Hands-on exercise**
11. **Knowledge check**
12. **Key takeaways**
13. **Next lesson and related references**
14. **Official sources**

### Depth controls

- Keep core explanations short enough to complete in one sitting.
- Move exhaustive field references into dedicated reference notes.
- Use tables for comparisons and exact mappings.
- Use Mermaid only when component relationships or flows are materially clearer as a diagram.
- Place advanced material after the core explanation.
- Avoid repeating full explanations; summarize and link to the owning note.

### Exercise requirements

Every exercise must include:

- Goal
- Starting state
- Commands or manifests
- Expected result
- Verification commands
- One controlled failure when appropriate
- Explanation of the observed behavior
- Cleanup

### Knowledge-check requirements

Use questions that require explanation or diagnosis rather than recall alone. Each core note should contain three to five questions, such as:

- What would happen if this field were removed?
- Which component notices this change?
- Why is this object Pending?
- Which layer would you inspect next?
- What production tradeoff does this setting introduce?

Answers can be placed in a collapsed callout or a linked answer page.

## Revision system

### Five-minute refresher pages

Create compact review pages for:

- Cluster architecture
- Object anatomy
- Workload controllers
- Service and networking flow
- ConfigMap versus Secret
- PV, PVC, and StorageClass
- Requests, limits, and QoS
- Scheduling controls
- Autoscaler selection
- Authentication, authorization, and admission
- Observability data sources
- Controller and operator mechanics

Each refresher should fit on one page and include a diagram, comparison table, common failure, and links to deeper notes.

### Decision tables

Create or standardize tables for:

- Deployment versus StatefulSet versus DaemonSet versus Job
- ConfigMap versus Secret versus external secret store
- ClusterIP versus NodePort versus LoadBalancer versus Gateway routing
- Ingress versus Gateway API
- PV access modes and topology implications
- HPA versus VPA versus KEDA versus node autoscaling
- Taints versus node affinity versus pod affinity versus topology spread
- RBAC versus Pod Security Admission versus admission policy versus NetworkPolicy
- Helm versus Kustomize
- Operator versus controller versus admission webhook

### Troubleshooting index

Provide a symptom-first index:

| Symptom             | First checks                                     | Playbook             |
| ------------------- | ------------------------------------------------ | -------------------- |
| Pod Pending         | Events, requests, taints, affinity, PVC          | Pod Pending          |
| ContainerCreating   | Image, volume, CNI, sandbox events               | Container creation   |
| CrashLoopBackOff    | Previous logs, exit code, probes, OOM            | Crash loops          |
| ImagePullBackOff    | Image name, registry, credentials                | Image pull           |
| Service unreachable | Selector, EndpointSlice, port, readiness         | Service reachability |
| DNS failure         | Resolver config, CoreDNS, NetworkPolicy          | DNS resolution       |
| PVC Pending         | StorageClass, provisioner, topology, access mode | PVC stuck            |
| Node NotReady       | Conditions, kubelet, runtime, disk, network      | Node readiness       |
| Rollout stuck       | Conditions, availability, probes, PDB            | Deployment rollout   |
| Forbidden request   | Identity, RoleBinding, verb, scope               | RBAC diagnosis       |

### Scenario reviews

Add end-of-level scenarios that combine topics. Examples:

- A Deployment has three replicas but no available Pods.
- A Service resolves in DNS but connections time out.
- HPA requests more replicas but no new Pods become Ready.
- A node drain blocks indefinitely.
- A workload can read Secrets from another namespace.
- A StatefulSet cannot reattach its volume after rescheduling.
- A validating webhook outage blocks all deployments.

## Section plans

### L00 — Start Here

#### Objective

Give a new learner enough context and tooling to complete their first observable Kubernetes workflow.

#### Work

- Add a prerequisite self-assessment for containers, YAML, command line, HTTP, DNS, and basic Linux concepts.
- Link to concise prerequisite material where a learner has gaps.
- Pick `kind` as the canonical lab environment.
- Add cluster creation, verification, and cleanup.
- Deploy a first application within the first lesson.
- Explain what the learner caused the API server, scheduler, kubelet, and runtime to do.
- Add setup troubleshooting for Docker/runtime access, ports, contexts, and architecture differences.
- Replace the nonexistent certification link or create the destination.

#### Completion criteria

- A learner can create a cluster, deploy an application, inspect it, and clean up.
- All commands have tested expected output.
- No later curriculum concept is required to finish the first exercise.

### L01 — Architecture

#### Objective

Establish the component and request-flow mental model used by all later lessons.

#### Work

- Add a dedicated cluster-architecture note.
- Add a control-plane-components note.
- Add a node-components and CRI note.
- Teach reconciliation before deep HA design.
- Make the `kubectl apply` → API server → etcd → controller → scheduler → kubelet → runtime trace the level capstone.
- Move high availability into an optional production branch from the core architecture lesson.
- Correct and re-test the swap guidance against current kubelet behavior.
- Explain cgroup v2 and containerd 2.x implications for current releases.
- Fix the missing control-plane link from the certificates note.

#### Completion criteria

- A learner can identify each core component and explain when it acts.
- A learner can trace object creation without treating Kubernetes as a single opaque service.
- Swap guidance distinguishes default behavior from explicitly configured NodeSwap behavior.

### L02 — Objects and API

#### Objective

Teach the Kubernetes API as the foundation for manifests, automation, controllers, and troubleshooting.

#### Work

- Split labels, selectors, and annotations into a focused core lesson or clearly bounded subsection.
- Add namespaced versus cluster-scoped resources.
- Add API groups, versions, discovery, and preferred/storage versions.
- Teach `kubectl api-resources`, `api-versions`, and `explain`.
- Add server-side apply, field ownership, and conflict handling.
- Add status conditions, generation, observed generation, UID, resourceVersion, and deletion timestamps.
- Introduce owner references without duplicating the advanced garbage-collection treatment.
- Move Downward API to configuration and identity.
- Add an exercise that creates, reads, patches, watches, and deletes an object.

#### Completion criteria

- A learner can read an unfamiliar manifest and discover its schema.
- A learner can distinguish desired state, observed state, and ownership.
- The section prepares readers for Deployments and controllers.

### L03 — Workloads

#### Objective

Teach workload selection and lifecycle through the controller hierarchy.

#### Work

- Reduce the Pod core lesson to purpose, anatomy, lifecycle, shared namespaces, and why bare Pods are rarely deployed.
- Convert repeated material on probes, resources, security, storage, and scheduling into short previews with links.
- Keep the detailed Pod material in a separate deep-dive or reference page.
- Put Deployment before the deep ReplicaSet treatment in the beginner sequence while still explaining the ownership chain.
- Add rollout, rollback, pause, and progress-failure exercises.
- Add graceful termination and readiness transition exercises.
- Add a workload-selection decision table.
- Add version notes for native sidecars, Job behavior, and other evolving features.
- Fix the broken ReplicaSet link in the restart-policy note.

#### Completion criteria

- A beginner can choose a controller for a workload.
- A beginner can deploy, update, inspect, break, and restore the sample application.
- Deep workload notes remain useful as standalone references.

### L04 — Services and Networking

#### Objective

Teach the path from process socket to Pod, Service, Gateway, and external client, followed by policy and data-plane internals.

#### Work

- Establish a simple traffic-flow diagram reused across networking lessons.
- Teach Pod IP, Service VIP, EndpointSlice, DNS, and external routing in that order.
- Add a learner-facing Gateway API hub.
- Move Gateway API research and planning documents outside the public curriculum or mark them draft.
- Retain the 16 Gateway API scenarios as an advanced lab track with an index and prerequisites.
- Replace ingress-nginx recommendations with migration guidance and maintained options.
- Explain that the Ingress API remains stable while the ingress-nginx implementation is retired.
- Add nftables and eBPF data planes.
- Mark IPVS deprecated and provide an nftables migration path.
- Mark legacy Endpoints deprecated and use EndpointSlice in examples.
- Add dual-stack networking.
- Add a packet-tracing and network-policy failure lab.
- Fix links to old service-mesh, DNS, CNI, and IPVS paths.

#### Completion criteria

- A learner can trace traffic through every relevant object and component.
- No page recommends retired ingress-nginx for a new deployment.
- Current examples use EndpointSlice-aware tooling and supported proxy guidance.
- Gateway API has a clear core path and a separate advanced scenario track.

### L05 — Configuration and Storage

#### Objective

Teach application configuration and the complete storage provisioning and attachment lifecycle.

#### Work

- Teach ConfigMap, Secret, and Downward API together.
- Compare environment variables, projected files, CSI-mounted secrets, and external secret controllers.
- Add a CSI architecture note.
- Visualize PVC → StorageClass → provisioner → PV → VolumeAttachment → node mount → container mount.
- Add volume topology and `WaitForFirstConsumer`.
- Add snapshots, restore, clone, and expansion.
- Add StatefulSet storage lifecycle exercises.
- Mark `Recycle` reclaim policy deprecated wherever mentioned.
- Separate generic ephemeral volumes from node-local ephemeral storage.
- Move general ResourceQuota teaching into resource governance while retaining storage quota links.
- Fix EKS storage and pluralized PV/StorageClass links.

#### Completion criteria

- A learner can explain both provisioning and attachment.
- A learner can diagnose a Pending PVC using events and relevant controller state.
- Deprecated storage behavior is visually and textually unambiguous.

### L06 — Resources, Scheduling, Scaling, and Availability

#### Objective

Teach how Kubernetes decides whether, where, and how many workload instances run.

#### Work

- Use the sequence: requests/limits → basic scheduling → placement controls → disruption → Pod autoscaling → node autoscaling → scheduler internals.
- Add a single scheduling decision diagram.
- Make QoS, eviction, priority, and preemption relationships explicit.
- Clarify which constraints are hard filters and which are scoring preferences.
- Add HPA prerequisites and metrics-pipeline diagnosis.
- Teach generic node autoscaling in the universal path.
- Move Karpenter implementation detail into EKS and link it as an example.
- Cover current in-place Pod resize behavior.
- Update DRA and extended-resource coverage for Kubernetes 1.37.
- Add current Metrics API version information.
- Add a combined Pending Pod, HPA, node capacity, and PDB scenario.
- Fix the outdated resource-request link from ResourceQuota.

#### Completion criteria

- A reader can select the correct placement or scaling mechanism.
- A reader can distinguish application scaling from node provisioning.
- Version-sensitive resource and device features state their current maturity.

### L07 — Security

#### Objective

Teach Kubernetes security as layered control over identity, permissions, workload behavior, traffic, software supply, and detection.

#### Work

- Organize the section around a progressive threat model.
- Begin with authentication, authorization, and admission as separate stages.
- Follow with ServiceAccounts and RBAC.
- Teach workload security context and Pod Security Standards.
- Add network isolation and secret protection.
- Teach admission policy, image verification, and SBOM use.
- End with auditing, detection, node hardening, and compliance.
- Decide which admission-controller note is canonical and replace duplication with cross-links.
- Decide the boundary between this section and the top-level Security knowledge base.
- Add an intentionally insecure workload hardening lab.
- Remove, redirect, or populate the empty `L07-security.md` file.
- Add a security-control comparison table.

#### Completion criteria

- A learner can explain which stage blocks a request and which control enforces it.
- The hardening lab demonstrates identity, RBAC, workload, network, and admission layers.
- Duplicate security explanations have clear canonical owners.

### L08 — Observability and Operations

#### Objective

Give readers a systematic model for keeping clusters healthy and diagnosing failures.

#### Work

- Connect the concept-level troubleshooting flow to every symptom-based guide.
- Add observability architecture for application and platform signals.
- Cover logs, events, resource metrics, state metrics, traces, and audit logs.
- Add SLI/SLO and alert-design guidance.
- Add node lifecycle: cordon, drain, eviction, shutdown, and replacement.
- Add capacity planning and saturation.
- Add cluster upgrade planning and API-deprecation discovery.
- Add certificate expiration and rotation.
- Add backup and restore validation.
- Add control-plane and etcd health checks.
- Add incident timeline and evidence-collection practices.
- Replace legacy `componentstatuses` guidance with supported health checks.
- Consolidate or redirect the top-level legacy troubleshooting note.

#### Completion criteria

- A learner can move from symptom to responsible layer using a repeatable process.
- The operations path covers routine maintenance as well as incident diagnosis.
- Troubleshooting commands use supported APIs and tools.

### L09 — Delivery and Lifecycle

#### Objective

Teach repeatable application delivery and safe change management before platform extensibility.

#### Work

- Promote Helm and Kustomize into a clear delivery sequence.
- Add artifact, image, and manifest promotion concepts.
- Teach GitOps reconciliation and ownership.
- Add progressive delivery and rollback signals.
- Cover image signing, policy gates, and deployment evidence.
- Connect upgrades, API deprecations, and delivery pipelines.
- Update the guides hub statuses to match actual content.
- Create missing sub-section landing pages.
- Repair incorrect Helm-relative links if Quartz shortest-path resolution does not resolve them reliably.

#### Completion criteria

- A learner can package and deliver the sample application reproducibly.
- A learner can explain the ownership boundary between CI, GitOps, and Kubernetes controllers.
- Delivery guidance includes verification and rollback.

### L10 — Extensibility and Internals

#### Objective

Explain how Kubernetes is extended and how its internal control loops work.

#### Work

- Move existing advanced material under this level when renumbering is practical.
- Organize content as API machinery → watches/informers → work queues → reconciliation → CRDs → controllers/operators → ownership/finalizers → admission → API aggregation.
- Update stale status labels for custom controllers, operators, garbage collection, and pause container notes.
- Add CRD version conversion and storage-version migration.
- Add controller idempotency, retry, rate limiting, caching, and leader election.
- Retain etcd operations as a cluster-operator branch.
- Move IPVS into networking legacy/migration content.
- Add an optional minimal-controller lab.
- Decide where the standalone `client-go.md` belongs and integrate or redirect it.

#### Completion criteria

- A reader can explain a controller from watch to reconciliation and status update.
- The section distinguishes API extension, admission, scheduling extension, and aggregated API servers.
- Stale status labels and legacy networking placement are resolved.

## Guides plan

### Hub repairs

- Create reader-facing landing pages for `tools/`, `troubleshooting/`, `non-functional/`, `delivery/`, and `networking/`.
- Recalculate status from editorial review rather than file length alone.
- Replace planned file names with links only when the destination exists.
- Add an H1 and standard frontmatter to the guides hub.

### Tools

- Organize kubectl around common workflows rather than a flat command inventory.
- Add `kubectl explain`, server-side apply, diff, wait, events, debug, auth checks, and raw API access.
- Separate essential commands from advanced JSONPath and plugin material.
- Ensure shell examples do not accidentally parse Obsidian link syntax.

### Troubleshooting

- Preserve the symptom-first format.
- Standardize every playbook as symptom → scope → evidence → diagnosis → correction → verification → prevention.
- Add missing rollout, Helm, GitOps, admission-webhook, certificate, and control-plane playbooks.
- Cross-link each playbook to the concept that explains the failure.

### Nonfunctional requirements

- Connect each guide into the production-readiness path.
- State assumptions for managed versus self-managed control planes.
- Add measurable acceptance criteria to HA, DR, performance, cost, and security guidance.
- Clearly separate availability, disaster recovery, and backup.

### Delivery

- Keep the Helm series as a deep reference.
- Build a shorter beginner route through Helm or Kustomize before exposing the full series.
- Complete GitOps, progressive delivery, and pipeline paths using the sample application.
- Explain which tool owns rendering, promotion, reconciliation, and rollout.

### Networking guides

- Create a current controller comparison based on maintained projects.
- Add a Gateway API migration path.
- Remove reader-facing reliance on retired ingress-nginx.
- Fix the nonexistent `service-mesh/` hierarchy or change links to the current Istio and Linkerd pages.

## EKS plan

### Positioning

EKS should be an elective implementation track that assumes the reader understands universal Kubernetes concepts through networking, storage, scheduling, and security.

### Structure

For every EKS area, begin with the universal concept and then explain the AWS implementation:

| Universal concept                 | EKS implementation                                 |
| --------------------------------- | -------------------------------------------------- |
| Authentication and cluster access | Access entries and IAM authentication              |
| Workload identity                 | IRSA and EKS Pod Identity                          |
| Pod networking                    | Amazon VPC CNI                                     |
| Node provisioning                 | Managed node groups, Karpenter, Auto Mode, Fargate |
| Block and file storage            | EBS CSI, EFS CSI, FSx                              |
| Load balancing and ingress        | AWS Load Balancer Controller and VPC Lattice       |
| Metrics, logs, and traces         | CloudWatch, ADOT, managed Prometheus               |
| Secrets                           | Secrets Manager and external-secrets integrations  |

### Work

- Add explicit prerequisites to the EKS hub.
- Add architecture and responsibility-boundary diagrams.
- Deepen short overview pages where they currently list features without operational tradeoffs.
- Add cost, quota, IAM, subnet, IP-exhaustion, upgrade, and add-on lifecycle failure scenarios.
- Separate current EKS guidance from legacy `aws-auth` behavior.
- Add tested version and region assumptions.
- Link every EKS note back to its universal concept.
- Avoid duplicating generic Kubernetes explanations.

### Completion criteria

- Readers know what AWS manages and what they still operate.
- EKS pages explain AWS-specific mechanisms and failure modes.
- Generic concepts have one canonical owner.

## Version and source policy

### Current baseline

At the time this plan was written:

- Kubernetes 1.37 is current.
- The actively maintained upstream branches are 1.35, 1.36, and 1.37.
- ingress-nginx is retired and should not be recommended for new deployments.
- kube-proxy IPVS mode is deprecated; nftables is the recommended migration direction on compatible Linux systems.
- Legacy Endpoints is deprecated in favor of EndpointSlice.

### Source hierarchy

Use sources in this order:

1. Kubernetes documentation and release notes
2. Kubernetes Enhancement Proposals for feature lifecycle details
3. SIG or official project documentation
4. Maintainer documentation for ecosystem tools
5. Cloud-provider documentation for managed-service behavior

Blog posts and third-party articles may add operational perspective but should not be the sole source for API or feature-state claims.

### Required handling of changing features

For alpha, beta, deprecated, or recently stable behavior, record:

- Introduced version
- Current feature state
- Default feature-gate behavior
- Platform or runtime requirements
- Known removal or migration target
- Date last verified

Avoid phrases such as “new,” “currently,” or “the default” without a version anchor.

### Core verification sources

- [Kubernetes releases](https://kubernetes.io/releases/)
- [Kubernetes 1.37 release announcement](https://kubernetes.io/blog/2026/08/26/kubernetes-v1-37-release/)
- [Kubernetes Basics](https://kubernetes.io/docs/tutorials/kubernetes-basics/)
- [Kubernetes deprecation policy](https://kubernetes.io/docs/reference/using-api/deprecation-policy/)
- [Ingress NGINX retirement](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)
- [Service and EndpointSlice documentation](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Virtual IPs and service proxies](https://kubernetes.io/docs/reference/networking/virtual-ips/)
- [Swap memory management](https://kubernetes.io/docs/concepts/cluster-administration/swap-memory-management/)
- [PersistentVolumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)

## Navigation and metadata cleanup

### Naming convention

- Use `README.md` for every curated folder landing page, or configure explicit aliases if `00-README.md` must remain.
- Use numbered file names only when order matters within a level.
- Avoid having both a folder page and a similarly named standalone page unless one redirects to the other.
- Keep internal plans and research under a draft-only location.

### Frontmatter

Add at minimum:

- `title`
- `tags`
- `date`
- `description`
- `draft` when appropriate

Use lower-case hierarchical tags consistently, for example:

```yaml
tags:
  - platform-engineering/kubernetes
  - platform-engineering/kubernetes/networking
```

Agree on the tag hierarchy before bulk-changing existing tags.

### Known navigation repairs

- Create or remove links to `Kubernetes/certifications/README`.
- Create the intended service-mesh hierarchy or point links to existing Istio and Linkerd pages.
- Fix old `concepts/networking/*` links.
- Fix `concepts/eks/storage/README` to the actual EKS path.
- Fix `L08-ipvs` to the actual IPVS page or its new migration page.
- Fix the missing architecture/control-plane target.
- Fix pluralized ReplicaSet, PersistentVolume, and StorageClass paths.
- Fix the outdated requests-and-limits path.
- Review relative Helm links under Quartz's shortest-link resolution.
- Review links containing escaped pipes after any automated rewrite.

### Status system

Replace file-length-based status with editorial criteria:

- **Draft:** direction exists, but the explanation is incomplete or unverified.
- **Core complete:** teaches the stated outcome, includes a verified example, and links prerequisites.
- **Reference complete:** covers operational and internals depth with sources.
- **Lab verified:** commands and manifests pass in the documented environment.
- **Version verified:** feature states and defaults are checked against the current baseline.

A page may carry more than one status, such as “core complete, lab pending.”

## Automated quality checks

Add a content validation script and run it in `npm run check` or a separate content-check command.

### Required checks

- Broken Obsidian wiki links
- Missing frontmatter
- Missing title, description, or tags
- Missing H1
- Duplicate slugs
- Empty Markdown files
- Links to ignored or draft-only targets from published pages
- Invalid internal anchors where practical
- Malformed Markdown tables
- Unpinned remote manifests in labs
- References to known retired or deprecated APIs and projects
- Notes whose `lastVerified` exceeds an agreed age

### Optional checks

- Duplicate large sections
- Code fences without language identifiers
- Commands without cleanup in lab pages
- Curriculum pages without prerequisites, takeaways, or next links
- Pages marked complete without official sources

### Validation gates

For each implementation phase:

1. Run the link and metadata checker.
2. Run Prettier on changed Markdown files.
3. Run the Quartz production build.
4. Test changed labs in the documented environment.
5. Review rendered navigation on desktop and mobile.
6. Confirm that draft planning files are excluded from output.

## Delivery phases

### Phase 0 — Restore trust and navigation

#### Tasks

- Fix confirmed broken internal links.
- Standardize level landing-page links.
- Fix malformed hub tables.
- Add missing H1 headings.
- Add frontmatter to reader-facing Kubernetes notes.
- Remove or redirect empty and legacy files.
- Update stale hub statuses.
- Separate internal Gateway API plans from published guidance.
- Add the automated link and metadata checker.

#### Exit criteria

- No known broken internal Kubernetes links.
- Every published note has standard metadata and one H1.
- Every folder has a deliberate entry point.
- Status labels reflect actual editorial state.

### Phase 1 — Correct time-sensitive guidance

#### Tasks

- Update the baseline to Kubernetes 1.37.
- Extend version history through 1.37 or replace it with a maintainable release matrix.
- Correct ingress-nginx guidance and add migration information.
- Mark and reposition IPVS as deprecated.
- Add nftables coverage.
- Correct swap behavior and configuration.
- Mark legacy Endpoints and Recycle behavior deprecated.
- Audit API versions and feature-state claims across Kubernetes notes.

#### Exit criteria

- No known recommendation directs readers toward a retired component.
- Version-sensitive pages include version and verification metadata.
- Deprecations include a replacement or migration path.

### Phase 2 — Build the beginner spine

#### Tasks

- Rewrite the Kubernetes landing page by reader intent.
- Finalize the core level sequence.
- Create the canonical local lab environment.
- Add the cumulative sample application.
- Implement Labs 00–06.
- Add prerequisites, objectives, takeaways, knowledge checks, and next links to core lessons.
- Split oversized core notes where needed.

#### Exit criteria

- A newcomer can progress from no cluster to a networked, configured, persistent, scheduled application.
- Every core level produces an observable result.
- The beginner path does not require unexplained future concepts.

### Phase 3 — Security and operations journey

#### Tasks

- Reorganize L07 around the layered threat model.
- Implement the insecure-to-hardened workload lab.
- Expand L08 into observability, maintenance, troubleshooting, and recovery.
- Connect all symptom playbooks.
- Implement Labs 07–09.
- Add the production-readiness path and checklist.

#### Exit criteria

- The sample application is secured, observed, diagnosed, upgraded, and restored.
- Readers can follow a consistent troubleshooting method.
- Production guidance has measurable verification steps.

### Phase 4 — Revision and depth

#### Tasks

- Create five-minute refreshers.
- Create decision tables and concept maps.
- Add scenario reviews and answer explanations.
- Add a glossary.
- Add role-based paths for application engineers, SREs, platform engineers, security engineers, and controller authors.
- Refactor repeated material into canonical reference notes.

#### Exit criteria

- Experienced readers can retrieve common answers within a few clicks.
- Each major subject has a refresher, deep dive, and troubleshooting route.
- Repetition is intentional and summarized rather than copied.

### Phase 5 — Extensibility, provider tracks, and certification

#### Tasks

- Complete the extensibility and internals sequence.
- Integrate client-go.
- Implement the optional controller lab.
- Reframe EKS as an implementation track with universal-concept prerequisites.
- Add deeper EKS failure scenarios.
- Create the certification section or remove its links until it exists.
- Map certification objectives to existing core lessons and exercises.

#### Exit criteria

- Advanced readers have a coherent controller and API-machinery path.
- EKS pages extend rather than duplicate universal material.
- Certification links point to a maintained and useful destination.

### Phase 6 — Ongoing maintenance

#### Tasks

- Review upstream releases three times per year.
- Review supported version branches monthly or before publishing major updates.
- Re-run labs after Kubernetes, `kind`, ingress/Gateway, CNI, CSI, or policy-engine changes.
- Rotate stale-page ownership or create an editorial review queue.
- Track link, build, and lab health in CI.

#### Exit criteria

- Version updates follow a repeatable checklist.
- Stale content is visible before it becomes misleading.
- Core labs remain reproducible.

## Prioritized backlog

### P0 — Correctness and trust

- [ ] Repair broken wiki links.
- [ ] Fix landing-page routing to curated README pages.
- [ ] Correct ingress-nginx recommendations.
- [ ] Correct NodeSwap guidance.
- [ ] Mark IPVS deprecated and add nftables.
- [ ] Update the version baseline through Kubernetes 1.37.
- [ ] Mark Endpoints and Recycle deprecations.
- [ ] Remove or redirect the empty L07 page.
- [ ] Fix malformed hub tables.
- [ ] Add automated content validation.

### P1 — Beginner usability

- [ ] Rewrite the main Kubernetes landing page.
- [ ] Create the canonical `kind` environment.
- [ ] Create the cumulative application.
- [ ] Add a dedicated architecture lesson.
- [ ] Expand the object/API level.
- [ ] Reduce and split the Pod core lesson.
- [ ] Implement the first six cumulative labs.
- [ ] Add prerequisites, objectives, takeaways, and knowledge checks to core lessons.

### P2 — Operational completeness

- [ ] Expand operations and observability.
- [ ] Connect symptom-based troubleshooting.
- [ ] Implement security hardening and failure labs.
- [ ] Add backup, restore, upgrades, and incident workflow.
- [ ] Create the production-readiness path.

### P3 — Reference quality

- [ ] Add five-minute refresher pages.
- [ ] Add standardized decision tables.
- [ ] Add scenario reviews.
- [ ] Add glossary and role-based paths.
- [ ] Consolidate duplicate explanations.
- [ ] Normalize metadata and tags.

### P4 — Advanced and provider paths

- [ ] Reorganize advanced material as L10.
- [ ] Integrate client-go.
- [ ] Add controller lab.
- [ ] Reframe and deepen EKS.
- [ ] Build or remove the promised certification path.

## Definition of done

The Kubernetes curriculum is complete when all of the following are true.

### Beginner experience

- A learner with container and command-line basics can start without choosing among many tools.
- The learner completes a continuous application journey.
- Every level has an observable outcome and controlled failure.
- Prerequisites and next steps are explicit.
- Core content can be completed without reading optional internals.

### Experienced-reader experience

- Common concepts are available as five-minute refreshers.
- Deep notes retain technical and operational detail.
- Symptom-based navigation reaches relevant playbooks quickly.
- Decision tables help readers choose between similar mechanisms.
- Version and feature-state information is easy to find.

### Correctness

- Examples have been tested against the documented Kubernetes version.
- Alpha, beta, stable, deprecated, and removed features are identified.
- Retired projects are not recommended for new deployments.
- Official sources support changing technical claims.

### Navigation and publishing

- Internal links pass automated validation.
- Every folder has a deliberate landing page.
- Published pages have standard frontmatter and headings.
- Internal plans and research do not leak into the public learning path.
- Quartz builds successfully.

### Maintainability

- Each concept has one canonical owning note.
- Release-review and lab-retest procedures are documented.
- Status metadata reflects editorial quality and verification state.
- New pages follow the page contract.

## First implementation slice

The first implementation slice should be small enough to review as one coherent change while fixing the most visible trust problems:

1. Repair the Kubernetes landing page and concepts hub navigation.
2. Standardize all L00–L09 hub table syntax and links.
3. Fix the known broken links referenced in this plan.
4. Correct ingress-nginx, NodeSwap, IPVS, Endpoints, and Recycle guidance.
5. Add a minimal content-validation script for links, frontmatter, H1 headings, and empty files.
6. Add the new beginner-path outline to the landing page without moving the existing deep notes yet.

After that foundation is stable, build L00, the sample application, and the first cumulative lab. This creates a reviewable pattern that can be applied to the rest of the curriculum.
