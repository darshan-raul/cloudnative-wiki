---
title: GCP Vault Progress Tracker
description: Tracks progress of GCP section expansion — categories, in-depth notes written, and roadmap
tags:
  - gcp
  - tracking
---

# GCP Vault Progress 🟠

Tracks completion of the Google Cloud Platform knowledge base, adhering to the high-depth engineering standard: **Architecture & Mental Models + Production `gcloud` CLI + Quotas & Limits + References + 2 Realistic Pricing Scenarios + 5+ Battle-Tested Nuggets & Gotchas**.

---

## Section Progress

### 1. Compute & Containers 🖥️

- [x] **[[GCP/compute/README|GCP Compute Hub]]** — Master overview of VM, container, and serverless compute
- [x] **[[GCP/compute/gce|Compute Engine (GCE)]]** — Machine families, custom VM shapes, Regional MIGs, auto-healing, Spot VMs, Live Migration, and OS Login
- [x] **[[GCP/compute/gce/migs|Managed Instance Groups (MIGs)]]** — Regional vs Zonal MIGs, auto-healing health checks, rolling zero-downtime updates, stateful MIGs, and autoscaling policies
- [x] **[[GCP/compute/gce/spot-vms|Spot VMs & Preemption Engineering]]** — 30-second ACPI shutdown notice, metadata polling, shutdown scripts, and fault-tolerant batch architectures
- [x] **[[GCP/compute/gke|Google Kubernetes Engine (GKE)]]** — Master Hub: Autopilot vs Standard, VPC-native alias IPs, Datapath V2 (Cilium eBPF), private clusters, Gateway API
  - [x] **[[GCP/compute/gke/autopilot-deep-dive|GKE Autopilot Deep Dive]]** — SRE mechanics, mutating webhooks, pod-level billing, DaemonSet economics, compute classes
  - [x] **[[GCP/compute/gke/cluster-types|GKE Cluster Architectures & Control Plane]]** — Zonal vs Multi-Zonal vs Regional, master replication, etcd Raft quorum, 99.95% SLA, cross-zone egress
  - [x] **[[GCP/compute/gke/release-channels-upgrades|GKE Release Channels & Upgrades]]** — Rapid/Regular/Stable channels, Extended Support, Blue-Green vs Surge upgrades, maintenance windows, PDBs
  - [x] **[[GCP/compute/gke/autoscaling|GKE Autoscaling Architecture]]** — Cluster Autoscaler (CA), Node Auto-Provisioning (NAP), HPA v2 custom/external metrics, VPA recommendation mode
  - [x] **[[GCP/compute/gke/node-pools-heterogeneous|GKE Heterogeneous Node Pools]]** — Specialized machine families, taints/tolerations, node affinity, Local NVMe SSD RAID arrays, Tau Arm (T2A)
  - [x] **[[GCP/compute/gke/networking|GKE Networking Deep Dive]]** — VPC-native alias IPs, Datapath V2 (Cilium eBPF), Zonal NEGs, kube-proxy replacement, and Gateway API
  - [x] **[[GCP/compute/gke/gateway-api|GKE Gateway API & Advanced Traffic Routing]]** — Gateway controller, GatewayClasses, HTTPRoute, GCPBackendPolicy, HealthCheckPolicy, canary splits
  - [x] **[[GCP/compute/gke/multi-cluster-services|GKE Multi-Cluster Services & Ingress (MCS/MCI)]]** — ServiceExport/ServiceImport, `clusterset.local`, global Anycast proximity routing and failover
  - [x] **[[GCP/compute/gke/network-security|GKE Datapath V2 & Network Security]]** — Cilium eBPF datapath, Layer 7 FQDN egress network policies, dedicated Egress NAT per namespace
  - [x] **[[GCP/compute/gke/security|GKE Security & Hardening]]** — Workload Identity, Shielded Nodes, Binary Authorization deploy-time image validation, Network Policies, and Master Authorized Networks
  - [x] **[[GCP/compute/gke/binary-authorization|GKE Binary Authorization & Supply Chain Security]]** — Deploy-time admission control, Cloud KMS asymmetric signing, Grafeas attestations, Break-Glass
  - [x] **[[GCP/compute/gke/multi-tenancy-isolation|GKE Multi-Tenancy & Workload Isolation]]** — Hard vs Soft multi-tenancy, GKE Sandbox (gVisor user-space microkernel), Pod Security Standards, LimitRanges, ResourceQuotas
  - [x] **[[GCP/compute/gke/storage-csi|GKE Compute Engine Persistent Disk CSI Driver]]** — Dynamic provisioning, Hyperdisk Extreme/Balanced, online volume expansion, VolumeSnapshots
  - [x] **[[GCP/compute/gke/cloud-storage-fuse|GKE Cloud Storage FUSE CSI Driver]]** — POSIX object storage mounts for AI/ML dataset streaming, local NVMe caching, ReadWriteMany (RWX)
  - [x] **[[GCP/compute/gke/filestore-csi|GKE Filestore CSI Driver]]** — Managed NFS v3/v4.1, ReadWriteMany (RWX) multi-pod state, multi-share instance packing
  - [x] **[[GCP/compute/gke/gpu-tpu-orchestration|GKE GPU & TPU Orchestration for AI/ML]]** — NVIDIA L4/A100/H100 GPUs, Cloud TPU v5e/v5p slicing, GPUDirect RDMA, Ray on GKE (KubeRay), Kueue
  - [x] **[[GCP/compute/gke/batch-workloads-kueue|GKE Batch Workloads & Kueue Orchestration]]** — IndexedJob API, Kueue multi-tenant queueing, fair-share scheduling, preemption fault tolerance
  - [x] **[[GCP/compute/gke/observability-gmp|GKE Observability & Google Cloud Managed Service for Prometheus (GMP)]]** — Managed collector, PodMonitoring, ClusterPodMonitoring, ContainerLogV2, metric relabeling
  - [x] **[[GCP/compute/gke/backup-for-gke|Backup for GKE & Disaster Recovery]]** — Managed Backup for GKE, BackupPlans, RestorePlans, cross-region disaster recovery, VolumeSnapshot remapping
  - [x] **[[GCP/compute/gke/cost-optimization-finops|GKE Cost Optimization & FinOps]]** — GKE Cost Allocation in BigQuery, rightsizing, Spot VM pools, CUDs, overprovisioning pause pods
  - [x] **[[GCP/compute/gke/troubleshooting-runbook|GKE Troubleshooting & SRE Incident Runbook]]** — Exit code taxonomy, Node NotReady, OOMKilled (137), IP exhaustion, CSI deadlocks
  - [x] **[[GCP/compute/gke/fleets-and-anthos|GKE Fleets & Anthos Service Mesh]]** — GKE Fleets, Anthos Service Mesh (ASM / Managed Istio), Policy Controller (Gatekeeper OPA), Config Sync GitOps
- [x] **[[GCP/compute/cloud-run|Cloud Run Services]]** — Stateless containers, request concurrency (up to 1,000/inst), Direct VPC Egress, and CPU allocation models
- [x] **[[GCP/compute/cloud-run/jobs|Cloud Run Jobs & Batch Processing]]** — Run-to-completion batch processing, task arrays, concurrency parallelism, Cloud Scheduler integration, and 24-hour execution limits
- [x] **[[GCP/compute/cloud-functions/README|Cloud Functions (2nd Gen) & Eventarc]]** — Cloud Run infrastructure, Eventarc CloudEvents triggers, concurrency, cold-start mitigation, and 60-minute execution limits

### 2. Networking & Global Transit 🌐

- [x] **[[GCP/networking/README|GCP Networking Hub]]** — Master overview of global software-defined networking
- [x] **[[GCP/networking/vpc|Virtual Private Cloud (VPC)]]** — Global VPC vs Regional Subnets, Primary/Secondary IP ranges, Shared VPC, Cloud NAT, and Hierarchical Firewalls
- [x] **[[GCP/networking/vpc/shared-vpc|Shared VPC Architecture]]** — Host projects vs Service projects, subnet-level IAM delegation, cross-project service accounts, centralized hybrid connectivity, and enterprise governance
- [x] **[[GCP/networking/vpc/firewalls|Firewalls & Hierarchical Policies]]** — Stateful inspection, rule priority (0-65535), Hierarchical Policies (Org/Folder), target tags vs Service Accounts, and rule logging
- [x] **[[GCP/networking/vpc/cloud-nat|Cloud NAT Deep Dive]]** — Software-defined distributed NAT, Cloud Router integration, dynamic port allocation, SNAT port exhaustion prevention, and outbound logging
- [x] **[[GCP/networking/load-balancing|Cloud Load Balancing & Cloud Armor]]** — Global Anycast IPs, Envoy ALBs, Maglev NLBs, Zonal NEGs, Cloud Armor WAF/DDoS, and Private Service Connect
- [x] **[[GCP/networking/cloud-router|Cloud Router & Dynamic BGP]]** — Managed BGP control plane, custom route advertisements (MED), dynamic routing modes (Regional vs Global), BFD failover
- [x] **[[GCP/networking/network-connectivity-center|Network Connectivity Center (NCC)]]** — Transit hub, VPC spokes, Cloud VPN spokes, Cloud Interconnect spokes, SD-WAN Router Appliance
- [x] **[[GCP/networking/cloud-dns/README|Cloud DNS Architecture]]** — 100% uptime SLA, Anycast nameservers, split-horizon DNS, private forwarding zones, DNS peering, Response Policies (RPZ), and DNSSEC
- [x] **[[GCP/networking/cloud-cdn/README|Cloud CDN Architecture & Edge Caching]]** — Google edge Points of Presence (PoPs), cache modes, cache key customization, negative caching, signed URLs/cookies, and cache invalidation
- [x] **[[GCP/networking/hybrid/README|Cloud Interconnect & HA VPN]]** — Cloud HA VPN (99.99% SLA), Dedicated vs Partner Interconnect, BGP routing with Cloud Router, and 99.99% enterprise topologies
- [x] **[[GCP/networking/private-service-connect/README|Private Service Connect (PSC)]]** — Private consumption of Google APIs and multi-tenant SaaS services, Service Attachments, PSC Endpoints, and eliminating VPC peering IP overlap

### 3. Storage & Data Systems 💽

- [x] **[[GCP/storage/README|GCP Storage Hub]]** — Master overview of object, block, and shared file architectures
- [x] **[[GCP/storage/gcs|Google Cloud Storage (GCS)]]** — Storage classes, sub-second archive retrieval, Object Lifecycle Management, Bucket Lock WORM, and Soft Delete
- [x] **[[GCP/storage/persistent-disk|Persistent Disk & Hyperdisk]]** — Zonal vs Regional synchronous mirroring, Hyperdisk ML, online volume expansion, and GKE CSI driver
- [x] **[[GCP/storage/filestore|Cloud Filestore (Managed NFS)]]** — POSIX NFSv3/NFSv4.1, ReadWriteMany (RWX), Basic/Zonal/Regional/Enterprise tiers, multi-share instance packing
- [x] **[[GCP/storage/storage-transfer-service|Storage Transfer Service & Transfer Appliance]]** — Serverless migration from AWS S3, Azure Blob, on-prem NAS, and physical Transfer Appliances

### 4. Identity, Security & Zero Trust 🔐

- [x] **[[GCP/security/README|GCP Security Hub]]** — Master overview of Google Cloud security operations and defense-in-depth
- [x] **[[GCP/identity/README|Identity & Access Management (IAM)]]** — Resource Hierarchy (Org > Folder > Project), Roles, Service Accounts, Impersonation, Org Policies, and CEL Conditions
- [x] **[[GCP/identity/workload-identity|Workload Identity & Federation]]** — GKE Workload Identity, GitHub Actions OIDC federation, STS token exchange
- [x] **[[GCP/security/scc|Security Command Center & Secret Manager]]** — SCC tiers, agentless VM Threat Detection (VMTD), Secret Manager, and Cloud KMS envelope encryption
- [x] **[[GCP/security/kms/README|Cloud KMS, Cloud HSM & CMEK Envelope Encryption]]** — FIPS 140-2 Level 3 HSM, automated rotation, asymmetric keys, and Cloud EKM
- [x] **[[GCP/security/cloud-armor|Cloud Armor WAF & DDoS Defense]]** — Global Anycast edge DDoS defense, OWASP ModSecurity CRS, ML-based Adaptive Protection, and rate-based throttling
- [x] **[[GCP/security/iap-beyondcorp|Identity-Aware Proxy (IAP) & BeyondCorp]]** — Context-aware zero-trust HTTPS/TCP proxying, eliminating VPNs for SSH/RDP and internal web apps
- [x] **[[GCP/security/cloud-dlp|Sensitive Data Protection (Cloud DLP)]]** — Automated discovery, classification, and cryptographic tokenization/masking of PII/PHI
- [x] **[[GCP/security/cas|Certificate Authority Service (CAS) & Certificate Manager]]** — Managed private CA hierarchy (Root/Subordinate CAs), Cloud HSM keys, automated TLS rotation, and client mTLS

### 5. Governance & Policy Guardrails 🏛️

- [x] **[[GCP/governance/README|GCP Governance Hub]]** — Master overview of resource management and compliance guardrails
- [x] **[[GCP/governance/org-policies|Organization Policies & Resource Governance]]** — Admission-control guardrails across Org/Folder/Project hierarchies, boolean/list constraints, custom CEL constraints, dry-run mode

### 6. Databases & Storage Engines 🗄️

- [x] **[[GCP/databases/README|GCP Databases Hub]]** — Master overview of relational, NoSQL, and in-memory database engines
- [x] **[[GCP/databases/cloud-sql|Cloud SQL]]** — PostgreSQL/MySQL/SQL Server, regional synchronous HA failover, Cloud SQL Auth Proxy, and IAM database authentication
- [x] **[[GCP/databases/spanner|Cloud Spanner]]** — TrueTime atomic clock synchronization, external consistency, Processing Units (PUs), interleaved tables, and 5-nines multi-region SLA
- [x] **[[GCP/databases/bigquery|Google BigQuery]]** — Dremel, Colossus, Capacitor columnar storage, partitioned/clustered tables, on-demand vs slot editions
- [x] **[[GCP/databases/alloydb/README|AlloyDB for PostgreSQL]]** — Disaggregated storage engine, log processing service, columnar engine, and cross-region replication
- [x] **[[GCP/databases/bigtable/README|Cloud Bigtable]]** — Petabyte-scale distributed NoSQL wide-column store, SSTables on Colossus, and row key schema design
- [x] **[[GCP/databases/firestore/README|Cloud Firestore]]** — Serverless document store, Native vs Datastore mode, real-time listeners, and distributed multi-document ACID transactions
- [x] **[[GCP/databases/memorystore/README|Cloud Memorystore]]** — Fully managed Redis & Memcached, standard HA vs Cluster sharding (up to 250 shards), and eviction policies

### 7. Analytics & Big Data 📊

- [x] **[[GCP/analytics/README|GCP Analytics Hub]]** — Master overview of data lakes, streaming engines, and analytics platforms
- [x] **[[GCP/analytics/pubsub/README|Cloud Pub/Sub]]** — Global Anycast messaging, serverless log storage, ordering keys, exactly-once delivery, and dead-letter queues
- [x] **[[GCP/analytics/dataflow/README|Cloud Dataflow]]** — Serverless Apache Beam runner, dynamic work rebalancing, watermarks, windowing, and Streaming Engine
- [x] **[[GCP/analytics/dataproc|Cloud Dataproc]]** — Managed Spark, Hadoop, Flink, and Presto clusters, ephemeral cluster lifecycle, and Dataproc Serverless
- [x] **[[GCP/analytics/dataplex|Cloud Dataplex]]** — Intelligent data mesh, universal metadata catalog, automated schema discovery, data quality (AutoDQ), and data lineage
- [x] **[[GCP/analytics/looker|Looker & Looker Studio]]** — LookML code-based semantic modeling, in-database SQL pushdown, Persistent Derived Tables (PDTs), and enterprise BI
- [x] **[[GCP/analytics/composer|Cloud Composer]]** — Managed Apache Airflow workflow orchestration on GKE with serverless DCU scaling

### 8. AI & Machine Learning 🤖

- [x] **[[GCP/ai/README|GCP AI Hub]]** — Master overview of Google Cloud artificial intelligence and machine learning platforms
- [x] **[[GCP/ai/vertex-ai|Vertex AI Architecture & MLOps]]** — Model Garden, Gemini 1.5/2.0 multimodal APIs, Vector Search (ScaNN), Feature Store, custom training, and managed endpoints
- [x] **[[GCP/ai/cloud-tpu|Cloud TPU Supercomputing]]** — Matrix Multiply Units (MXUs), 2D/3D Torus Inter-Chip Interconnect (ICI), TPU v4/v5e/v5p hardware, and Queued Resources

### 9. Developer Tools & Software Delivery 🛠️

- [x] **[[GCP/developer-tools/README|GCP Developer Tools Hub]]** — Master overview of CI/CD and software supply chain security
- [x] **[[GCP/developer-tools/cloud-build|Cloud Build]]** — Serverless CI build runner, parallel container steps, private worker pools in VPC, and SLSA Level 3 provenance
- [x] **[[GCP/developer-tools/artifact-registry|Artifact Registry]]** — Universal OCI container and package repository (Docker, Helm, Maven, npm, PyPI), and Container Analysis vulnerability scanning
- [x] **[[GCP/developer-tools/cloud-deploy|Cloud Deploy]]** — Continuous delivery orchestration for GKE, Cloud Run, and Anthos with automated canary traffic shifting and rollback

### 10. Application Integration & Eventing 🔌

- [x] **[[GCP/application-integration/README|GCP Application Integration Hub]]** — Master overview of asynchronous messaging, eventing, and workflow state machines
- [x] **[[GCP/application-integration/cloud-tasks|Cloud Tasks]]** — Asynchronous HTTP push queue, token-bucket rate limiting, dispatch concurrency, and task deduplication
- [x] **[[GCP/application-integration/workflows|Cloud Workflows]]** — Low-latency serverless state machine orchestration, YAML DAGs, built-in connectors, and the Saga pattern
- [x] **[[GCP/application-integration/eventarc|Eventarc]]** — Standardized CloudEvents v1.0 routing from 130+ GCP sources and direct Cloud Storage mutations
- [x] **[[GCP/application-integration/apigee|Apigee X API Management]]** — Enterprise API gateway, traffic shaping (SpikeArrest/Quota), developer portal, and Cloud Armor security

### 11. Monitoring & Observability 📈

- [x] **[[GCP/monitoring/README|GCP Monitoring Hub]]** — Master overview of full-stack metrics, logs, traces, and continuous profiling
- [x] **[[GCP/monitoring/cloud-monitoring/README|Cloud Monitoring & MQL]]** — Cross-project metric scopes, MQL, Managed Service for Prometheus (GMP), and SRE SLO error budgets
- [x] **[[GCP/monitoring/cloud-logging/README|Cloud Logging & Log Analytics]]** — Log Router, exclusion filters, BigQuery SQL log analytics, log-based metrics, and enterprise sinks
- [x] **[[GCP/monitoring/cloud-trace|Cloud Trace]]** — Distributed latency tracing, OpenTelemetry (OTel) standard, W3C context propagation, and span waterfall root cause analysis
- [x] **[[GCP/monitoring/cloud-profiler|Cloud Profiler]]** — Zero-cost continuous production CPU, wall time, heap, and mutex profiling with flame graphs

### 12. Cost Optimization & FinOps 💰

- [x] **[[GCP/cost-management/README|GCP Cost Management Hub]]** — Master overview of cloud financial management and discount mechanisms
- [x] **[[GCP/cost-management/pricing-models/README|Cost Optimization, CUDs & FinOps]]** — Sustained Use Discounts (SUDs), Resource vs Flexible Committed Use Discounts (CUDs), and BigQuery billing exports

### 13. Migration & Enterprise Modernization 🚀

- [x] **[[GCP/migration/README|GCP Migration Hub]]** — Master overview of infrastructure discovery, assessment, and cutover
- [x] **[[GCP/migration/migration-center|Migration Center]]** — Automated infrastructure discovery, VMware vCenter integration, TCO rightsizing models, and migration wave planning

---

## Roadmap & Next Phases

- [x] **GCP Databases Expansion** — Cloud Bigtable, Firestore, Memorystore (Redis), AlloyDB
- [x] **GCP Big Data & Streaming** — Cloud Pub/Sub, Cloud Dataflow (Beam)
- [x] **GCP Operations Suite** — Cloud Monitoring (MQL), Cloud Logging (Log Router), Cloud Trace, Cloud Profiler
- [x] **GCP Cost & Security** — Cloud KMS & HSM, CUDs / SUDs FinOps, Cloud Armor, IAP BeyondCorp, Cloud DLP, CAS
- [x] **GKE Mega Expansion (20x Content Depth)** — 23 exhaustive engineering modules covering Autopilot, Networking, Storage CSI, GPU/TPU AI/ML, Security, Multi-Cluster, Fleets, FinOps, SRE Runbooks
- [x] **GCP Enterprise Gaps Remediation** — 13 Category Landing Hubs + 20 core service deep dives (Vertex AI, Cloud TPU, Cloud Build, Artifact Registry, Cloud Deploy, Cloud Tasks, Workflows, Eventarc, Apigee X, Dataproc, Dataplex, Looker, Composer, Cloud Router, NCC, Filestore, Storage Transfer Service, Migration Center, Org Policies)
- [ ] **Azure Section Full Breadth Deepening** — Expanding Azure to mirror the identical 50+ module standard
