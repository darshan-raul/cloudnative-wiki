---
title: GCP
tags: [gcp, google-cloud, cloud]
date: 2026-10-15
description: "Google Cloud Platform — comprehensive architectural deep dives across compute, networking, storage, security, databases, analytics, AI/ML, and developer tools."
---

# GCP 🟠

Google Cloud Platform — comprehensive architectural deep dives covering Google's global private network, container platforms, distributed storage, big data engines, generative AI supercomputing, and enterprise zero-trust security. Built to match the depth of the AWS knowledge base with **Architecture & Mental Models + Production `gcloud` CLI + Quotas & Limits + References + 2 Realistic Pricing Scenarios + 5+ Battle-Tested Nuggets & Gotchas**.

---

## Service Catalog

### 1. [[GCP/compute/README|Compute & Containers Hub]]

- [[GCP/compute/gce|Compute Engine (GCE)]] — Machine families, custom CPU/RAM shapes, Regional MIGs, auto-healing, Spot VMs, Live Migration, and OS Login.
- [[GCP/compute/gce/migs|Managed Instance Groups (MIGs)]] — Regional vs Zonal MIGs, auto-healing health checks, rolling zero-downtime updates, stateful MIGs, and autoscaling policies.
- [[GCP/compute/gce/spot-vms|Spot VMs & Preemption Engineering]] — 30-second ACPI shutdown notice, metadata polling, shutdown scripts, and fault-tolerant batch architectures.
- [[GCP/compute/gke|Google Kubernetes Engine (GKE) Master Hub]] — Autopilot vs Standard, VPC-native alias IPs, Datapath V2 (Cilium eBPF), private clusters, and Gateway API.
  - [[GCP/compute/gke/autopilot-deep-dive|GKE Autopilot Architecture & SRE Mechanics]] — Pod-level billing, mutating webhooks, DaemonSet economics, and compute classes.
  - [[GCP/compute/gke/cluster-types|Cluster Topologies (Zonal vs Regional)]] — Master replication, etcd Raft quorum, 99.95% SLA, and cross-zone networking costs.
  - [[GCP/compute/gke/release-channels-upgrades|Release Channels & Upgrades]] — Rapid, Regular, Stable, Surge vs Blue-Green node upgrades, and PodDisruptionBudgets.
  - [[GCP/compute/gke/autoscaling|GKE Autoscaling Architecture]] — Cluster Autoscaler (CA), Node Auto-Provisioning (NAP), HPA v2, and VPA.
  - [[GCP/compute/gke/node-pools-heterogeneous|Heterogeneous Node Pools & Accelerators]] — Taints, Tolerations, Node Affinity, Local NVMe SSDs, and Tau Arm64.
  - [[GCP/compute/gke/networking|GKE Networking Deep Dive]] — VPC-native alias IPs, Datapath V2 (Cilium eBPF), Zonal NEGs, and Cloud Armor WAF.
  - [[GCP/compute/gke/gateway-api|GKE Gateway API Architecture]] — HTTPRoute, GatewayClasses, GCPBackendPolicy, and canary traffic splitting.
  - [[GCP/compute/gke/multi-cluster-services|Multi-Cluster Services (MCS) & Ingress (MCI)]] — ServiceExport, ServiceImport, `clusterset.local`, and global Anycast failover.
  - [[GCP/compute/gke/network-security|Advanced Network Security & FQDN Policies]] — Datapath V2 eBPF, Layer 7 FQDN egress filtering, and dedicated Egress NAT.
  - [[GCP/compute/gke/storage-csi|Storage CSI, Hyperdisk & Volume Snapshots]] — Persistent Disk CSI driver, Hyperdisk Extreme/Balanced, and online expansion.
  - [[GCP/compute/gke/cloud-storage-fuse|Cloud Storage FUSE CSI Driver]] — POSIX object storage mounts, AI/ML dataset streaming, and local NVMe caching.
  - [[GCP/compute/gke/filestore-csi|Filestore CSI Driver (Managed NFS)]] — ReadWriteMany (RWX) multi-pod state, multi-share instance packing, and automated snapshots.
  - [[GCP/compute/gke/gpu-tpu-orchestration|GPU & TPU Orchestration]] — NVIDIA L4/A100/H100, Cloud TPU v5e/v5p slices, GPUDirect RDMA, Ray on GKE, and Kueue.
  - [[GCP/compute/gke/batch-workloads-kueue|Batch Workloads & Kueue Queueing]] — IndexedJob API, fair-share scheduling, preemption handling, and Spot VM fault tolerance.
  - [[GCP/compute/gke/security|GKE Security & Hardening]] — Workload Identity, Shielded nodes, Binary Authorization, and CIS benchmark enforcement.
  - [[GCP/compute/gke/binary-authorization|Binary Authorization & Supply Chain Security]] — Cryptographic attestations, Cloud KMS image signing, and Break-Glass procedures.
  - [[GCP/compute/gke/multi-tenancy-isolation|Multi-Tenancy Isolation & GKE Sandbox (gVisor)]] — Hard vs soft multi-tenancy, gVisor microkernel, and Pod Security Standards.
  - [[GCP/compute/gke/observability-gmp|GKE Observability & Managed Prometheus (GMP)]] — PodMonitoring, ClusterPodMonitoring, ContainerLogV2 logging, and PromQL.
  - [[GCP/compute/gke/backup-for-gke|Backup for GKE & Disaster Recovery]] — Native Kubernetes resource and Persistent Volume backups, and cross-region recovery.
  - [[GCP/compute/gke/troubleshooting-runbook|GKE SRE Production Troubleshooting Runbook]] — CrashLoopBackOff, Node NotReady, OOMKilled (Exit Code 137), and IP exhaustion.
  - [[GCP/compute/gke/cost-optimization-finops|GKE Cost Optimization & FinOps]] — GKE Cost Allocation in BigQuery, rightsizing, Spot node pools, and CUDs.
  - [[GCP/compute/gke/fleets-and-anthos|GKE Fleets, Anthos Service Mesh & Policy Controller]] — Multi-cluster Fleet federation, managed Istio mTLS, and OPA Gatekeeper guardrails.
- [[GCP/compute/cloud-run|Cloud Run Services]] — Stateless serverless containers, request concurrency (up to 1,000 req/inst), Direct VPC Egress, and CPU allocation models.
- [[GCP/compute/cloud-run/jobs|Cloud Run Jobs & Batch Processing]] — Run-to-completion batch processing, task arrays, concurrency parallelism, Cloud Scheduler integration, and 24-hour execution limits.
- [[GCP/compute/cloud-functions/README|Cloud Functions (2nd Gen) & Eventarc]] — Cloud Run infrastructure, Eventarc CloudEvents triggers, concurrency, cold-start mitigation, and 60-minute execution limits.

### 2. [[GCP/networking/README|Networking & Global Transit Hub]]

- [[GCP/networking/vpc|Virtual Private Cloud (VPC)]] — Global VPC routing domain, regional subnets, primary and secondary ranges for GKE, Shared VPC, Cloud NAT, and hierarchical firewalls.
- [[GCP/networking/vpc/shared-vpc|Shared VPC Architecture]] — Host projects vs Service projects, subnet-level IAM delegation, cross-project service accounts, centralized hybrid connectivity, and enterprise governance.
- [[GCP/networking/vpc/firewalls|Firewalls & Hierarchical Policies]] — Stateful inspection, rule priority (0-65535), Hierarchical Policies (Org/Folder), target tags vs Service Accounts, and rule logging.
- [[GCP/networking/vpc/cloud-nat|Cloud NAT Deep Dive]] — Software-defined distributed NAT, Cloud Router integration, dynamic port allocation, SNAT port exhaustion prevention, and outbound logging.
- [[GCP/networking/load-balancing|Cloud Load Balancing & Cloud Armor]] — Single Anycast IP architecture, Envoy-based ALBs, Maglev NLBs, Zonal NEGs, Cloud Armor WAF/DDoS, and Private Service Connect.
- [[GCP/networking/cloud-router|Cloud Router & Dynamic BGP]] — Fully managed BGP control plane, custom route advertisements (MED), dynamic routing modes (Regional vs Global), and BFD failover.
- [[GCP/networking/network-connectivity-center|Network Connectivity Center (NCC)]] — Centralized transit hub connecting VPCs, Cloud VPNs, Interconnects, and third-party SD-WAN router appliances.
- [[GCP/networking/cloud-dns/README|Cloud DNS Architecture]] — 100% uptime SLA, Anycast nameservers, split-horizon DNS, private forwarding zones, DNS peering, Response Policies (RPZ), and DNSSEC.
- [[GCP/networking/cloud-cdn/README|Cloud CDN Architecture & Edge Caching]] — Google edge Points of Presence (PoPs), cache modes, cache key customization, negative caching, signed URLs/cookies, and cache invalidation.
- [[GCP/networking/hybrid/README|Cloud Interconnect & HA VPN]] — Cloud HA VPN (99.99% SLA), Dedicated vs Partner Interconnect, BGP routing with Cloud Router, and 99.99% enterprise topologies.
- [[GCP/networking/private-service-connect/README|Private Service Connect (PSC)]] — Private consumption of Google APIs and multi-tenant SaaS services, Service Attachments, PSC Endpoints, and eliminating VPC peering IP overlap.

### 3. [[GCP/storage/README|Storage & Data Systems Hub]]

- [[GCP/storage/gcs|Google Cloud Storage (GCS)]] — Standard, Nearline, Coldline, and sub-second instant Archive retrieval, Object Lifecycle Management, Bucket Lock WORM, and Soft Delete.
- [[GCP/storage/persistent-disk|Persistent Disk & Hyperdisk]] — Zonal vs Regional synchronous mirroring (RPO = 0), next-gen Hyperdisk ML/Extreme, online volume resizing, and GKE CSI driver.
- [[GCP/storage/filestore|Cloud Filestore (Managed NFS)]] — POSIX-compliant NFSv3/NFSv4.1 shared storage, ReadWriteMany (RWX) multi-VM packing, and sub-millisecond file access.
- [[GCP/storage/storage-transfer-service|Storage Transfer Service & Transfer Appliance]] — Serverless cloud-to-cloud data migration (AWS S3, Azure Blob to GCS), on-premises agent pools, and physical migration appliances.

### 4. [[GCP/security/README|Security & Zero Trust Hub]]

- [[GCP/identity/README|Identity & Access Management (IAM)]] — Resource hierarchy (Organization > Folders > Projects), IAM roles, service accounts, token impersonation, CEL conditions, and organization policies.
- [[GCP/identity/workload-identity|Workload Identity & Federation]] — Eliminating static JSON keys. GKE Workload Identity, GitHub Actions OIDC federation, and STS token exchange.
- [[GCP/security/scc|Security Command Center (SCC)]] — Centralized CSPM/CWPP, hypervisor-level VM Threat Detection (VMTD), Secret Manager versioning, and Cloud KMS envelope encryption.
- [[GCP/security/kms/README|Cloud KMS, Cloud HSM & CMEK Envelope Encryption]] — FIPS 140-2 Level 3 hardware HSM, envelope encryption, automated key rotation, and External Key Manager (Cloud EKM).
- [[GCP/security/cloud-armor|Cloud Armor WAF & DDoS Defense]] — Global Anycast edge DDoS defense, OWASP ModSecurity CRS, ML-based Adaptive Protection, and rate-based throttling.
- [[GCP/security/iap-beyondcorp|Identity-Aware Proxy (IAP) & BeyondCorp]] — Context-aware zero-trust HTTPS/TCP proxying, eliminating VPNs for SSH/RDP and internal web apps.
- [[GCP/security/cloud-dlp|Sensitive Data Protection (Cloud DLP)]] — Automated discovery, classification, and cryptographic tokenization/masking of PII/PHI in BigQuery, GCS, and streams.
- [[GCP/security/cas|Certificate Authority Service (CAS) & Certificate Manager]] — Managed private CA hierarchy (Root/Subordinate CAs), Cloud HSM keys, automated TLS rotation, and client mTLS.

### 5. [[GCP/governance/README|Governance & Organization Policies Hub]]

- [[GCP/governance/org-policies|Organization Policies & Resource Governance]] — Preventive admission-control guardrails across Org/Folder/Project hierarchies, boolean/list constraints, custom CEL constraints, and dry-run mode.

### 6. [[GCP/databases/README|Databases & Distributed Storage Hub]]

- [[GCP/databases/cloud-sql|Cloud SQL]] — PostgreSQL, MySQL, and SQL Server with Regional synchronous HA failover, Cloud SQL Auth Proxy, and IAM database authentication.
- [[GCP/databases/spanner|Cloud Spanner]] — TrueTime atomic clock synchronization, external consistency (serializability), Processing Units (PUs), interleaved tables, and 5-nines multi-region SLA.
- [[GCP/databases/bigquery|Google BigQuery]] — Dremel execution engine, Colossus, Capacitor columnar format, partitioned/clustered tables, and on-demand vs slot editions.
- [[GCP/databases/alloydb/README|AlloyDB for PostgreSQL]] — Disaggregated storage engine, log processing service, in-memory columnar engine, and zero-data-loss cross-region replication.
- [[GCP/databases/bigtable/README|Cloud Bigtable]] — Petabyte-scale distributed NoSQL wide-column store, SSTables on Colossus, tablet auto-splitting, and row key design.
- [[GCP/databases/firestore/README|Cloud Firestore]] — Serverless document database, Native vs Datastore mode, real-time sync listeners, and ACID multi-document transactions.
- [[GCP/databases/memorystore/README|Cloud Memorystore]] — Managed in-memory caching for Redis and Memcached, cluster sharding up to 250 nodes, and high-availability failover.

### 7. [[GCP/analytics/README|Analytics & Big Data Hub]]

- [[GCP/databases/bigquery|Google BigQuery]] — Serverless data warehouse, BI Engine in-memory acceleration, and BigLake storage abstraction.
- [[GCP/analytics/dataflow/README|Cloud Dataflow]] — Serverless Apache Beam streaming and batch runner, dynamic work rebalancing, watermarks, windowing, and Streaming Engine.
- [[GCP/analytics/pubsub/README|Cloud Pub/Sub]] — Global Anycast messaging, serverless sharded log storage, ordering keys, exactly-once delivery, and dead-letter queues.
- [[GCP/analytics/dataproc|Cloud Dataproc]] — Managed Spark, Hadoop, Flink, and Presto clusters, ephemeral cluster lifecycle, and Dataproc Serverless.
- [[GCP/analytics/dataplex|Cloud Dataplex]] — Intelligent data mesh, universal metadata catalog, automated schema discovery, data quality (AutoDQ), and data lineage.
- [[GCP/analytics/looker|Looker & Looker Studio]] — LookML code-based semantic modeling, in-database SQL pushdown, Persistent Derived Tables (PDTs), and enterprise BI.
- [[GCP/analytics/composer|Cloud Composer]] — Managed Apache Airflow workflow orchestration on GKE with serverless DCU scaling.

### 8. [[GCP/ai/README|AI & Machine Learning Hub]]

- [[GCP/ai/vertex-ai|Vertex AI Architecture & MLOps]] — Model Garden, Gemini 1.5/2.0 multimodal APIs, Vector Search (ScaNN), Feature Store, custom training, and managed endpoints.
- [[GCP/ai/cloud-tpu|Cloud TPU Supercomputing]] — Matrix Multiply Units (MXUs), 2D/3D Torus Inter-Chip Interconnect (ICI), TPU v4/v5e/v5p hardware, and Queued Resources.
- [[GCP/compute/gke/gpu-tpu-orchestration|GKE GPU & TPU Orchestration]] — Kubernetes-native AI/ML clusters with Ray on GKE (KubeRay) and Kueue.

### 9. [[GCP/developer-tools/README|Developer Tools & Delivery Hub]]

- [[GCP/developer-tools/cloud-build|Cloud Build]] — Serverless CI build runner, parallel container steps, private worker pools in VPC, and SLSA Level 3 provenance.
- [[GCP/developer-tools/artifact-registry|Artifact Registry]] — Universal OCI container and package repository (Docker, Helm, Maven, npm, PyPI), and Container Analysis vulnerability scanning.
- [[GCP/developer-tools/cloud-deploy|Cloud Deploy]] — Continuous delivery orchestration for GKE, Cloud Run, and Anthos with automated canary traffic shifting and rollback.

### 10. [[GCP/application-integration/README|Application Integration & Eventing Hub]]

- [[GCP/application-integration/cloud-tasks|Cloud Tasks]] — Asynchronous HTTP push queue, token-bucket rate limiting, dispatch concurrency, and task deduplication.
- [[GCP/application-integration/workflows|Cloud Workflows]] — Low-latency serverless state machine orchestration, YAML DAGs, built-in connectors, and the Saga pattern.
- [[GCP/application-integration/eventarc|Eventarc]] — Standardized CloudEvents v1.0 routing from 130+ GCP sources and direct Cloud Storage mutations.
- [[GCP/application-integration/apigee|Apigee X API Management]] — Enterprise API gateway, traffic shaping (SpikeArrest/Quota), developer portal, and Cloud Armor security.

### 11. [[GCP/monitoring/README|Monitoring & Observability Hub]]

- [[GCP/monitoring/cloud-monitoring/README|Cloud Monitoring & MQL]] — Cross-project metric scopes, Monitoring Query Language (MQL), Managed Service for Prometheus (GMP), and SRE SLO error budgets.
- [[GCP/monitoring/cloud-logging/README|Cloud Logging & Log Analytics]] — High-throughput Log Router, exclusion filters, BigQuery SQL log analytics, log-based metrics, and enterprise sinks.
- [[GCP/monitoring/cloud-trace|Cloud Trace]] — Distributed latency tracing, OpenTelemetry (OTel) standard, W3C context propagation, and span waterfall root cause analysis.
- [[GCP/monitoring/cloud-profiler|Cloud Profiler]] — Zero-cost continuous production CPU, wall time, heap, and mutex profiling with flame graphs.

### 12. [[GCP/cost-management/README|Cost Optimization & FinOps Hub]]

- [[GCP/cost-management/pricing-models/README|Cost Optimization, CUDs & FinOps]] — Sustained Use Discounts (SUDs), Resource vs Flexible Committed Use Discounts (CUDs), Active Assist, and BigQuery billing export.
- [[GCP/compute/gke/cost-optimization-finops|GKE Cost Optimization & FinOps]] — GKE Cost Allocation in BigQuery, rightsizing, Spot node pools, and CUDs.

### 13. [[GCP/migration/README|Migration & Modernization Hub]]

- [[GCP/migration/migration-center|Migration Center]] — Automated infrastructure discovery, VMware vCenter integration, TCO rightsizing models, and migration wave planning.

---

## GCP vs AWS Architecture Translation

| Capability / Concept          | Google Cloud Platform (GCP) | Amazon Web Services (AWS)     | Key Architectural Distinction                                                                                                           |
| :---------------------------- | :-------------------------- | :---------------------------- | :-------------------------------------------------------------------------------------------------------------------------------------- |
| **Network Scope**             | **Global VPC**              | **Regional VPC**              | GCP VPC spans all regions globally; subnets are regional. AWS VPC is strictly bound to one region.                                      |
| **Cold Object Storage**       | **GCS Archive**             | **S3 Glacier Flexible**       | GCS Archive delivers **millisecond first-byte latency**; AWS Glacier requires a multi-hour asynchronous restore job.                    |
| **Serverless Containers**     | **Cloud Run**               | **ECS Fargate / Lambda**      | Cloud Run supports **1,000 concurrent requests per instance**; Lambda is strictly 1 invocation per container.                           |
| **Distributed Relational DB** | **Cloud Spanner**           | **Amazon Aurora**             | Spanner provides horizontal multi-master write scale globally via TrueTime atomic clocks; Aurora uses single-writer with read replicas. |
| **External Load Balancing**   | **Global Anycast IP**       | **Route 53 DNS + ALB**        | GCP advertises a single Anycast IP from 100+ global PoPs; AWS distributes regional IPs via DNS records.                                 |
| **Machine Sizing**            | **Custom VM Shapes**        | **Fixed Instance Types**      | GCP allows arbitrary vCPU and RAM combinations; AWS requires selecting predefined instance sizes.                                       |
| **Kubernetes eBPF**           | **Datapath V2 (Cilium)**    | **Amazon VPC CNI**            | GKE runs eBPF natively in the kernel for network policies and service routing without `kube-proxy`.                                     |
| **Cross-Account Networking**  | **Shared VPC / PSC**        | **Transit Gateway / RAM**     | Shared VPC lets projects share subnets directly from a host project without transit gateways or peering.                                |
| **AI Supercomputing**         | **Cloud TPU (v5e/v5p)**     | **AWS Trainium / Inferentia** | Cloud TPU uses direct 3D Torus Inter-Chip Interconnect (ICI) optical fabrics bypassing VPC networks.                                    |
| **Enterprise API Gateway**    | **Apigee X**                | **AWS API Gateway**           | Apigee X provides full lifecycle API governance, developer self-service portals, monetization, and policy pipelines.                    |
| **Continuous Code Profiling** | **Cloud Profiler**          | **AWS CodeGuru Profiler**     | Cloud Profiler runs permanently in production with <5% overhead and carries **$0.00 platform cost**.                                    |

---

## Related Hubs

- [[AWS]] — AWS architecture reference catalog
- [[Azure]] — Microsoft Azure architecture catalog
- [[Kubernetes]] — Cloud-native container orchestration and deep dives
- [[Security/cloud-security/gcp/README|GCP Security Hub]] — Cloud-native security operations
- [[DevOps]] — CI/CD, GitOps, and platform engineering patterns
- [[Architecture]] — System design, distributed systems, and enterprise data models
- [[Observability]] — Full-stack metrics, logs, traces, and profiling
