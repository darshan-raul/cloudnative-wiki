---
title: Google Kubernetes Engine (GKE)
description: GKE architecture — Autopilot vs Standard, VPC-native alias IPs, Datapath V2 eBPF, private clusters, Workload Identity, and Gateway API.
tags:
  - gcp
  - compute
  - kubernetes
  - gke
  - containers
---

# Google Kubernetes Engine (GKE) ☸️

Google Kubernetes Engine is Google Cloud's managed Kubernetes service. As the original creators of Kubernetes, Google designed GKE with native cloud integrations: **VPC-native networking (Alias IPs)**, **Datapath V2 (kernel eBPF via Cilium)**, **GKE Autopilot (fully managed nodes & pod-level billing)**, and **Container-Native Load Balancing**.

---

## Architecture & Mental Model

### GKE Architecture Overview

```
                   Google-Managed Control Plane (Regional HA)
                   ┌──────────────────────────────────────┐
                   │  etcd (Quorum)  │  kube-apiserver    │ (Across 3 Zones)
                   │  kube-scheduler │  controller-mgr    │ 99.95% SLA
                   └──────────────────┬───────────────────┘
                                      │
               ┌──────────────────────┴──────────────────────┐
               │ Private Peering / Konnectivity Tunnel        │
               ▼                                             ▼
    ┌─────────────────────────┐                   ┌─────────────────────────┐
    │  Worker Node: Zone-a    │                   │  Worker Node: Zone-b    │
    │  ┌───────────────────┐  │                   │  ┌───────────────────┐  │
    │  │ Pod 1 (10.101.0.2)│  │                   │  │ Pod 3 (10.101.1.2)│  │
    │  └───────────────────┘  │                   │  └───────────────────┘  │
    │  ┌───────────────────┐  │                   │  ┌───────────────────┐  │
    │  │ Pod 2 (10.101.0.3)│  │                   │  │ Pod 4 (10.101.1.3)│  │
    │  └───────────────────┘  │                   │  └───────────────────┘  │
    │  Datapath V2 (eBPF)     │                   │  Datapath V2 (eBPF)     │
    │  GKE Metadata Server    │                   │  GKE Metadata Server    │
    └──────────┬──────────────┘                   └──────────┬──────────────┘
               │                                             │
               └────────── Subnet Primary Range (Node IPs) ──┘
                         Subnet Secondary Range (Pod IPs)
```

---

## Autopilot vs. Standard Mode

| Architecture Dimension | GKE Standard | GKE Autopilot |
| :--- | :--- | :--- |
| **Node Management** | Customer manages node pools, instance types, OS image, and scaling | Fully automated: Google provisions, configures, and scales nodes |
| **Billing Model** | Pay for the underlying VM instances + disk, regardless of pod utilization | Pay **only** for pod resource requests (vCPU, memory, ephemeral storage) |
| **Security Posture** | Default settings can be weakened; customer handles CIS benchmark | Hardened by default: Shielded nodes, Workload Identity, secure baseline |
| **Node Access / SSH** | Full root SSH access to nodes enabled | Node access restricted; no SSH (managed infrastructure) |
| **Custom DaemonSets** | Unrestricted custom DaemonSets permitted | Permitted with strict resource request restrictions |
| **Ideal For** | Custom kernels, specialized hardware configs, legacy setups | **Production default** for modern containerized cloud-native apps |

---

## GKE Deep Dive Engineering Modules 📚

Explore the exhaustive, battle-tested GKE architectural reference library:

### 1. Cluster Topologies & Operational Modes
* [[GCP/compute/gke/autopilot-deep-dive|GKE Autopilot Architecture & SRE Mechanics]] — Pod-level billing, mutating admission webhooks, DaemonSet economics, and compute classes.
* [[GCP/compute/gke/cluster-types|Zonal vs Multi-Zonal vs Regional Clusters]] — Master replication, etcd Raft quorum, 99.95% SLA, and cross-zone egress cost optimization.
* [[GCP/compute/gke/release-channels-upgrades|Release Channels & Zero-Downtime Node Upgrades]] — Rapid, Regular, Stable, Surge vs Blue-Green upgrades, and PodDisruptionBudgets.

### 2. Capacity & Advanced Autoscaling
* [[GCP/compute/gke/autoscaling|GKE Autoscaling Architecture]] — Cluster Autoscaler (CA), Node Auto-Provisioning (NAP), HPA v2 with custom metrics, and VPA.
* [[GCP/compute/gke/node-pools-heterogeneous|Heterogeneous Node Pools & Accelerators]] — Taints, Tolerations, Node Affinity, Local NVMe SSD RAID arrays, and Tau Arm (T2A).

### 3. Ingress, Networking & Service Discovery
* [[GCP/compute/gke/networking|GKE Networking Deep Dive]] — VPC-native alias IPs, Datapath V2 (Cilium eBPF), Zonal NEGs, and Cloud Armor WAF.
* [[GCP/compute/gke/gateway-api|GKE Gateway API Architecture]] — HTTPRoute, GatewayClasses, GCPBackendPolicy, and canary traffic splitting.
* [[GCP/compute/gke/multi-cluster-services|Multi-Cluster Services (MCS) & Multi-Cluster Ingress (MCI)]] — ServiceExport, ServiceImport, `clusterset.local`, and global Anycast failover.
* [[GCP/compute/gke/network-security|Advanced Network Security & FQDN Policies]] — Datapath V2 eBPF, Layer 7 FQDN egress filtering, and dedicated Egress NAT per namespace.

### 4. Storage & Stateful Systems
* [[GCP/compute/gke/storage-csi|Storage CSI, Hyperdisk & Volume Snapshots]] — Persistent Disk CSI driver, Hyperdisk Extreme/Balanced, online expansion, and volume snapshots.
* [[GCP/compute/gke/cloud-storage-fuse|Cloud Storage FUSE CSI Driver]] — POSIX object storage mounts, AI/ML dataset streaming, and local NVMe caching.
* [[GCP/compute/gke/filestore-csi|Filestore CSI Driver (Managed NFS)]] — ReadWriteMany (RWX) multi-pod state, multi-share instance packing, and automated snapshots.

### 5. AI/ML Accelerators & Batch Processing
* [[GCP/compute/gke/gpu-tpu-orchestration|GPU & TPU Orchestration]] — NVIDIA L4/A100/H100, Cloud TPU v5e/v5p slices, GPUDirect RDMA, Ray on GKE, and Kueue.
* [[GCP/compute/gke/batch-workloads-kueue|Batch Workloads & Kueue Queueing]] — IndexedJob API, fair-share scheduling, preemption handling, and Spot VM fault tolerance.

### 6. Enterprise Security & Multi-Tenancy
* [[GCP/compute/gke/security|GKE Security & Hardening]] — Workload Identity, Shielded nodes, Binary Authorization, and CIS benchmark enforcement.
* [[GCP/compute/gke/binary-authorization|Binary Authorization & Supply Chain Security]] — Cryptographic attestations, Cloud KMS image signing, Grafeas metadata, and Break-Glass procedures.
* [[GCP/compute/gke/multi-tenancy-isolation|Multi-Tenancy Isolation & GKE Sandbox (gVisor)]] — Hard vs soft multi-tenancy, gVisor user-space microkernel, and Pod Security Standards (PSS).

### 7. Observability, Disaster Recovery & Incident Response
* [[GCP/compute/gke/observability-gmp|GKE Observability & Managed Prometheus (GMP)]] — PodMonitoring, ClusterPodMonitoring, ContainerLogV2 structured logging, and PromQL.
* [[GCP/compute/gke/backup-for-gke|Backup for GKE & Disaster Recovery]] — Native Kubernetes resource and Persistent Volume backups, RestorePlans, and cross-region recovery.
* [[GCP/compute/gke/troubleshooting-runbook|GKE SRE Production Troubleshooting Runbook]] — CrashLoopBackOff, Node NotReady, OOMKilled (Exit Code 137), IP exhaustion, and volume mount deadlocks.

### 8. FinOps & Fleet Governance
* [[GCP/compute/gke/cost-optimization-finops|GKE Cost Optimization & FinOps]] — GKE Cost Allocation in BigQuery, rightsizing, Spot node pools, and Committed Use Discounts (CUDs).
* [[GCP/compute/gke/fleets-and-anthos|GKE Fleets, Anthos Service Mesh & Policy Controller]] — Multi-cluster Fleet federation, managed Istio mTLS, and OPA Gatekeeper guardrails.

---

## Core Concepts

### 1. VPC-Native Clusters & Alias IPs

Every production GKE cluster should be created in **VPC-native mode** (using VPC Alias IPs):
* **No Overlay Encapsulation:** Pods get real, routable IP addresses directly from the VPC subnet's secondary IP range.
* **Direct Routability:** Compute Engine VMs, Cloud SQL databases, and on-premises networks (via Cloud Interconnect) can route directly to Pod IPs without NAT.
* **Container-Native Load Balancing:** Google Cloud Load Balancer routes traffic directly to Pod IPs via Zonal NEGs, completely bypassing `kube-proxy` iptables overhead.

### 2. Datapath V2 (eBPF / Cilium)

Datapath V2 is GKE's modern networking dataplane built on open-source **Cilium** and Linux kernel **eBPF**:
* **Replaces `kube-proxy`:** Routing, service load balancing, and network policies are executed in the Linux kernel via eBPF bytecode instead of sequential iptables evaluation.
* **Extreme Scale:** Eliminates the CPU performance cliff encountered when clusters grow to thousands of Kubernetes Services.
* **Built-in Network Policy Enforcement:** Enforces Kubernetes `NetworkPolicy` objects natively without installing third-party CNI plugins (like Calico).

### 3. Regional vs. Zonal Clusters

* **Zonal Cluster:** Control plane runs in a single zone. If that zone experiences an outage or control plane upgrade, the Kubernetes API server is unavailable (existing pods continue running). SLA: **99.5%**.
* **Regional Cluster:** Control plane replicates across three zones in the region with automated multi-zone etcd quorum. SLA: **99.95%**. **Mandatory for all production environments.**

### 4. Private GKE Clusters & Control Plane Access

In a private cluster:
* **Worker nodes have NO public IPs:** Nodes reside exclusively in private subnets and reach the public internet via Cloud NAT.
* **Private Control Plane Endpoint:** The API server communicates with nodes over a private peering network.
* **Master Authorized Networks:** Restricts access to the Kubernetes API server endpoint to explicit corporate CIDR blocks or bastion jump hosts.

---

## Production `gcloud` CLI Commands

### 1. Creating a Production GKE Autopilot Regional Cluster

```bash
gcloud container clusters create-auto prod-autopilot-cluster \
  --region=us-central1 \
  --network=prod-vpc \
  --subnetwork=prod-us-central1 \
  --cluster-secondary-range-name=gke-pods \
  --services-secondary-range-name=gke-services \
  --enable-private-nodes \
  --master-ipv4-cidr=172.16.0.0/28 \
  --enable-master-authorized-networks \
  --master-authorized-networks=203.0.113.50/32 \
  --release-channel=regular
```

### 2. Creating a Production GKE Standard Private Cluster with Datapath V2

```bash
gcloud container clusters create prod-standard-cluster \
  --region=us-central1 \
  --release-channel=regular \
  --network=prod-vpc \
  --subnetwork=prod-us-central1 \
  --cluster-secondary-range-name=gke-pods \
  --services-secondary-range-name=gke-services \
  --enable-ip-alias \
  --enable-dataplane-v2 \
  --workload-pool=my-prod-project.svc.id.goog \
  --enable-private-nodes \
  --master-ipv4-cidr=172.16.0.16/28 \
  --num-nodes=1 \
  --enable-autoscaling \
  --min-nodes=1 \
  --max-nodes=5 \
  --node-locations=us-central1-a,us-central1-b,us-central1-c \
  --shielded-secure-boot \
  --shielded-integrity-monitoring
```

### 3. Deploying Gateway API (Next-Gen Ingress)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: prod-external-gateway
  namespace: production
spec:
  gatewayClassName: gke-l7-global-external-managed
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      tls:
        mode: Terminate
        certificateRefs:
          - name: prod-tls-cert
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-route
  namespace: production
spec:
  parentRefs:
    - name: prod-external-gateway
  hostnames:
    - "api.company.com"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /v1/users
      backendRefs:
        - name: user-service
          port: 8080
```

---

## Quotas & Limits

| Resource / Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Max nodes per cluster** | 15,000 nodes | Standard cluster scale limit |
| **Max pods per cluster** | 300,000 pods | Requires careful CIDR capacity planning |
| **Default max pods per node** | 110 pods | Configurable down to 8–64 to conserve CIDR space |
| **Control plane management fee** | $0.10 / hour ($72/mo) | Free tier: 1 free cluster management fee per billing account |
| **Master IPv4 CIDR** | Must be `/28` | 16 IPs used exclusively by Google control plane VMs |

---

## References

* **Homepage:** https://cloud.google.com/kubernetes-engine
* **Documentation:** https://cloud.google.com/kubernetes-engine/docs
* **Autopilot Overview:** https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview
* **Datapath V2 (eBPF):** https://cloud.google.com/kubernetes-engine/docs/concepts/about-dataplane-v2
* **Pricing:** https://cloud.google.com/kubernetes-engine/pricing

---

## Pricing Examples

### Scenario 1: GKE Standard Cluster (Sustained Workload)
* 1 Regional Cluster ($0.10/hr = ~$72.00 / month management fee).
* 9 Worker Nodes across 3 zones using `e2-standard-4` (4 vCPU, 16 GB RAM each).
* Compute cost: 9 × ~$97.00 / month = $873.00.
* Storage: 9 × 100 GB `pd-balanced` boot disks ($0.10/GB = $90.00).
* **Total Cost:** $72 + $873 + $90 = **~$1,035 / month**.

### Scenario 2: GKE Autopilot Cluster (Variable Microservices)
* 1 Regional Autopilot Cluster ($0.10/hr = ~$72.00 / month management fee, waived if first cluster on billing account).
* Workload footprint: 100 microservice pods averaging 0.5 vCPU and 1 GB RAM requested per pod.
* Total requested: 50 vCPUs, 100 GB RAM continuously.
* Autopilot pricing (us-central1):
  * vCPU: 50 × $0.0445 / hour × 730 hrs = ~$1,624.25
  * RAM: 100 × $0.0049225 / GB-hr × 730 hrs = ~$359.34
* **Total Autopilot Cost:** ~$1,624.25 + $359.34 + $72 = **~$2,055.59 / month** (Zero node management overhead, zero idle node capacity wasted).

---

## Nuggets & Gotchas

1. **The `/28` Master CIDR Cannot Overlap Anything:** When creating a private GKE cluster, the `--master-ipv4-cidr` requires a `/28` block. This block is peered directly to your VPC. If this `/28` overlaps with any existing subnet, peered VPC, or on-premises CIDR routed via VPN, cluster creation will fail after 20 minutes with a vague peering conflict error.
2. **Default Max Pods per Node Consumes `/24` Secondary IP Space:** By default, GKE allocates a `/24` (256 addresses) from the Pod secondary CIDR for *every single node*, even if the node only runs 10 pods. For a 100-node cluster, this burns 25,600 Pod IPs. Use `--default-max-pods-per-node=32` or `64` to dramatically reduce subnet consumption.
3. **Autopilot Resource Request Enforcement:** In GKE Autopilot, Google bills you based on **Resource Requests**, not limits. Furthermore, if you specify `limits` without `requests`, Autopilot automatically sets `requests = limits`. If an unconfigured pod has a memory limit of 8 GiB, Autopilot charges you for 8 GiB from the instant it schedules!
4. **Maintenance Windows & Automated Upgrades:** GKE automatically upgrades control planes and nodes to track the selected Release Channel. Without a configured **Maintenance Window and Exclusion Window**, upgrades can trigger during peak production hours, causing rolling pod restarts. Always configure an explicit maintenance window (e.g., Saturday 02:00-06:00 UTC).
5. **Kubelet Eviction on Boot Disk Exhaustion:** In GKE Standard, container logs written to stdout/stderr are stored on the node's root boot disk under `/var/log/pods`. If an application enters a crash loop and emits gigabytes of logs per minute, the node's boot disk will fill to 85%, triggering `DiskPressure` and evicting all non-daemonset pods from that node.
