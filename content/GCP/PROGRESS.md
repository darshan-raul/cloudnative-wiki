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
  - [x] **[[GCP/compute/gke/troubleshooting-runbook|GKE Troubleshooting & SRE Incident Runbook]]** — Exit code taxonomy, Node NotReady, OOMKilled (137), IP exhaustion (`PXC_K8S_POD_IP_RANGE_EXHAUSTED`), CSI attach/detach deadlocks
  - [x] **[[GCP/compute/gke/fleets-and-anthos|GKE Fleets & Anthos Service Mesh]]** — GKE Fleets, Anthos Service Mesh (ASM / Managed Istio), Policy Controller (Gatekeeper OPA), Config Sync GitOps
- [x] **[[GCP/compute/cloud-run|Cloud Run Services]]** — Stateless containers, request concurrency (up to 1,000/inst), Direct VPC Egress, and CPU allocation models
- [x] **[[GCP/compute/cloud-run/jobs|Cloud Run Jobs & Batch Processing]]** — Run-to-completion batch processing, task arrays, concurrency parallelism, Cloud Scheduler integration, and 24-hour execution limits
- [x] **[[GCP/compute/cloud-functions/README|Cloud Functions (2nd Gen) & Eventarc]]** — Cloud Run infrastructure, Eventarc CloudEvents triggers, concurrency, cold-start mitigation, and 60-minute execution limits

### 2. Networking 🌐
- [x] **[[GCP/networking/vpc|Virtual Private Cloud (VPC)]]** — Global VPC vs Regional Subnets, Primary/Secondary IP ranges, Shared VPC, Cloud NAT, and Hierarchical Firewalls
- [x] **[[GCP/networking/vpc/shared-vpc|Shared VPC Architecture]]** — Host projects vs Service projects, subnet-level IAM delegation, cross-project service accounts, centralized hybrid connectivity, and enterprise governance
- [x] **[[GCP/networking/vpc/firewalls|Firewalls & Hierarchical Policies]]** — Stateful inspection, rule priority (0-65535), Hierarchical Policies (Org/Folder), target tags vs Service Accounts, and rule logging
- [x] **[[GCP/networking/vpc/cloud-nat|Cloud NAT Deep Dive]]** — Software-defined distributed NAT, Cloud Router integration, dynamic port allocation, SNAT port exhaustion prevention, and outbound logging
- [x] **[[GCP/networking/load-balancing|Cloud Load Balancing & Cloud Armor]]** — Global Anycast IPs, Envoy ALBs, Maglev NLBs, Zonal NEGs, Cloud Armor WAF/DDoS, and Private Service Connect
- [x] **[[GCP/networking/cloud-dns/README|Cloud DNS Architecture]]** — 100% uptime SLA, Anycast nameservers, split-horizon DNS, private forwarding zones, DNS peering, Response Policies (RPZ), and DNSSEC
- [x] **[[GCP/networking/cloud-cdn/README|Cloud CDN Architecture & Edge Caching]]** — Google edge Points of Presence (PoPs), cache modes, cache key customization, negative caching, signed URLs/cookies, and cache invalidation
- [x] **[[GCP/networking/hybrid/README|Cloud Interconnect & HA VPN]]** — Cloud HA VPN (99.99% SLA), Dedicated vs Partner Interconnect, BGP routing with Cloud Router, and 99.99% enterprise topologies
- [x] **[[GCP/networking/private-service-connect/README|Private Service Connect (PSC)]]** — Private consumption of Google APIs and multi-tenant SaaS services, Service Attachments, PSC Endpoints, and eliminating VPC peering IP overlap

### 3. Storage 💽
- [x] **[[GCP/storage/gcs|Google Cloud Storage (GCS)]]** — Storage classes, sub-second archive retrieval, Object Lifecycle Management, Bucket Lock WORM, and Soft Delete
- [x] **[[GCP/storage/persistent-disk|Persistent Disk & Hyperdisk]]** — Zonal vs Regional synchronous mirroring, Hyperdisk ML, online volume expansion, and GKE CSI driver

### 4. Identity & Security 🔐
- [x] **[[GCP/identity/README|Identity & Access Management (IAM)]]** — Resource Hierarchy (Org > Folder > Project), Roles, Service Accounts, Impersonation, Org Policies, and CEL Conditions
- [x] **[[GCP/identity/workload-identity|Workload Identity & Federation]]** — GKE Workload Identity, GitHub Actions OIDC federation, STS token exchange
- [x] **[[GCP/security/scc|Security Command Center & Secret Manager]]** — SCC tiers, agentless VM Threat Detection (VMTD), Secret Manager, and Cloud KMS envelope encryption
- [x] **[[GCP/security/kms/README|Cloud KMS, Cloud HSM & CMEK Envelope Encryption]]** — FIPS 140-2 Level 3 HSM, automated rotation, asymmetric keys, and Cloud EKM

### 5. Databases & Analytics 🗄️
- [x] **[[GCP/databases/cloud-sql|Cloud SQL]]** — PostgreSQL/MySQL/SQL Server, regional synchronous HA failover, Cloud SQL Auth Proxy, and IAM database authentication
- [x] **[[GCP/databases/spanner|Cloud Spanner]]** — TrueTime atomic clock synchronization, external consistency, Processing Units (PUs), interleaved tables, and 5-nines multi-region SLA
- [x] **[[GCP/databases/bigquery|Google BigQuery]]** — Dremel, Colossus, Capacitor columnar storage, partitioned/clustered tables, on-demand vs slot editions
- [x] **[[GCP/databases/alloydb/README|AlloyDB for PostgreSQL]]** — Disaggregated storage engine, log processing service, columnar engine, and cross-region replication
- [x] **[[GCP/databases/bigtable/README|Cloud Bigtable]]** — Petabyte-scale distributed NoSQL wide-column store, SSTables on Colossus, and row key schema design
- [x] **[[GCP/databases/firestore/README|Cloud Firestore]]** — Serverless document store, Native vs Datastore mode, real-time listeners, and distributed multi-document ACID transactions
- [x] **[[GCP/databases/memorystore/README|Cloud Memorystore]]** — Fully managed Redis & Memcached, standard HA vs Cluster sharding (up to 250 shards), and eviction policies
- [x] **[[GCP/analytics/pubsub/README|Cloud Pub/Sub]]** — Global Anycast messaging, serverless log storage, ordering keys, exactly-once delivery, and dead-letter queues
- [x] **[[GCP/analytics/dataflow/README|Cloud Dataflow]]** — Serverless Apache Beam runner, dynamic work rebalancing, watermarks, windowing, and Streaming Engine

### 6. Operations & Cost Optimization 📈💰
- [x] **[[GCP/monitoring/cloud-monitoring/README|Cloud Monitoring & MQL]]** — Cross-project metric scopes, MQL, Managed Service for Prometheus (GMP), and SRE SLO error budgets
- [x] **[[GCP/monitoring/cloud-logging/README|Cloud Logging & Log Analytics]]** — Log Router, exclusion filters, BigQuery SQL log analytics, log-based metrics, and enterprise sinks
- [x] **[[GCP/cost-management/pricing-models/README|Cost Optimization, CUDs & FinOps]]** — Sustained Use Discounts (SUDs), Resource vs Flexible Committed Use Discounts (CUDs), and BigQuery billing exports

---

## Roadmap & Next Phases

- [x] **GCP Databases Expansion** — Cloud Bigtable, Firestore, Memorystore (Redis), AlloyDB
- [x] **GCP Big Data & Streaming** — Cloud Pub/Sub, Cloud Dataflow (Beam)
- [x] **GCP Operations Suite** — Cloud Monitoring (MQL), Cloud Logging (Log Router)
- [x] **GCP Cost & Security** — Cloud KMS & HSM, CUDs / SUDs FinOps
- [x] **GKE Mega Expansion (20x Content Depth)** — 23 exhaustive engineering modules covering Autopilot, Networking, Storage CSI, GPU/TPU AI/ML, Security, Multi-Cluster, Fleets, FinOps, SRE Runbooks
- [ ] **Azure Section Full Breadth Deepening** — Expanding Azure to mirror the identical 40+ module standard
