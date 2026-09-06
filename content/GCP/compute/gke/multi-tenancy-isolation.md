---
title: GKE Multi-Tenancy Architecture — Hard vs Soft Isolation, GKE Sandbox (gVisor), and PSS
description: Exhaustive engineering guide to multi-tenant GKE clusters — Hard vs Soft multi-tenancy models, GKE Sandbox (gVisor user-space microkernel), Hierarchical Namespace Controller (HNC), Pod Security Standards (PSS), and Calico/Cilium network isolation.
tags:
  - gcp
  - gke
  - multi-tenancy
  - security
  - gvisor
  - pss
---

# GKE Multi-Tenancy Architecture — Hard vs Soft Isolation, GKE Sandbox (gVisor), and PSS 🏢🔒

Enterprise platform engineering teams face a fundamental architectural choice: provision dozens of small, dedicated single-tenant GKE clusters (resulting in cluster management fee sprawl, underutilized nodes, and operational complexity), or consolidate hundreds of teams into a single, high-density **Multi-Tenant GKE Cluster**. Implementing secure multi-tenancy requires understanding the difference between **Soft Multi-Tenancy** (internal trusted teams separated by RBAC and NetworkPolicies) and **Hard Multi-Tenancy** (untrusted third-party code, untrusted tenants, and SaaS isolation). GKE provides defense-in-depth isolation layers: **Pod Security Standards (PSS)**, **Hierarchical Namespaces (HNC)**, and **GKE Sandbox (gVisor microkernel virtualization)**.

---

## 1. Architecture: Multi-Tenant Defense-in-Depth

True multi-tenant isolation requires layered boundaries spanning control plane, networking, storage, and the Linux kernel.

```
                         MULTI-TENANT USER SUBMISSIONS
                                       │
        ┌──────────────────────────────┴──────────────────────────────┐
        │                                                             │
   Tenant A: Internal Accounting                                 Tenant B: Untrusted SaaS Code
   (Soft Multi-Tenancy Boundary)                                 (Hard Multi-Tenancy Boundary)
        │                                                             │
        ▼                                                             ▼
 ┌──────────────────────────────┐                              ┌──────────────────────────────┐
 │ NAMESPACE: `tenant-a-prod`   │                              │ NAMESPACE: `tenant-b-untrusted`
 │ - RBAC: Tenant A Admin Role  │                              │ - RBAC: Tenant B Admin Role  │
 │ - ResourceQuota: 20 CPU, 80G │                              │ - ResourceQuota: 10 CPU, 20G │
 │ - LimitRange: Max 4 CPU/pod  │                              │ - PSS: Restricted (Enforced) │
 └──────────────┬───────────────┘                              └──────────────┬───────────────┘
                │                                                             │
 ═══════════════╪═════════════════════════════════════════════════════════════╪════════════════
 KERNEL EXECUTION PLANE                                                       │
                │                                                             ▼
                │ Standard runc Container                      ┌──────────────────────────────┐
                ▼ (Shares Host Linux Kernel)                   │ GKE SANDBOX (gVisor / Sentry)│
 ┌───────────────────────────────────────────────┐             │ - Dedicated user-space kernel│
 │ HOST LINUX KERNEL                             │             │ - Intercepts all syscalls    │
 │ (cgroups, seccomp, AppArmor, eBPF NetworkPol) │             │ - Host kernel ZERO exposure  │
 └───────────────────────────────────────────────┘             └──────────────┬───────────────┘
                                                                              │
                                                               ┌──────────────▼───────────────┐
                                                               │ HOST LINUX KERNEL            │
                                                               │ (Protected from 0-day exploits
                                                               └──────────────────────────────┘
```

### Isolation Boundary Matrix

| Multi-Tenancy Model | Typical Tenants | Threat Vector | Primary Isolation Controls |
| :--- | :--- | :--- | :--- |
| **Soft Multi-Tenancy** | Internal engineering teams in the same enterprise | Accidental resource starvation, unauthorized cross-team reads | Kubernetes Namespaces, RBAC, NetworkPolicies, ResourceQuotas, PSS Baseline |
| **Hard Multi-Tenancy** | External customers, SaaS tenants, untrusted user-submitted code | Malicious kernel privilege escalation, container escape, host compromise | **GKE Sandbox (gVisor)**, dedicated tainted node pools, PSS Restricted, network micro-segmentation |

---

## 2. GKE Sandbox (gVisor) Mechanics

In standard Kubernetes, containers use `runc`. While containers are isolated via Linux cgroups and namespaces, **they share the underlying host operating system kernel**. A zero-day privilege escalation vulnerability in the Linux kernel (e.g., Dirty COW, Dirty Pipe) allows a compromised container to escape and compromise the entire node.

**GKE Sandbox** replaces `runc` with **gVisor**:
- **Sentry (User-Space Kernel):** Each sandboxed pod runs its own dedicated user-space microkernel called Sentry. Sentry implements the Linux system call interface (over 300 system calls).
- **Zero Host Kernel Syscalls:** When the container executes `read()`, `write()`, or `socket()`, the system call is handled entirely inside the Sentry user-space process. The container never talks directly to the physical host Linux kernel.
- **Gofer (File System Proxy):** File system operations are isolated behind a secure proxy daemon running in a separate namespace.

---

## 3. Production Deployment & CLI Operations (`gcloud` & `kubectl`)

### 1. Provision GKE Cluster with GKE Sandbox (gVisor) Node Pool

```bash
# Provision GKE cluster
gcloud container clusters create prod-multitenant-cluster \
    --region=us-central1 \
    --enable-ip-alias \
    --enable-dataplane-v2 \
    --project=core-infrastructure-prod

# Add dedicated GKE Sandbox node pool for untrusted code execution
gcloud container node-pools create untrusted-sandbox-pool \
    --cluster=prod-multitenant-cluster \
    --region=us-central1 \
    --machine-type=n2-standard-8 \
    --enable-sandbox \
    --num-nodes=2 \
    --node-taints="sandbox.gke.io/runtime=gvisor:NoSchedule" \
    --project=core-infrastructure-prod
```
*(Note: `--enable-sandbox` installs gVisor and registers the `RuntimeClass: gvisor`).*

### 2. Deploy Untrusted Workload with gVisor RuntimeClass and Toleration

Create `untrusted-runner.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-code-executor
  namespace: tenant-untrusted
spec:
  replicas: 3
  selector:
    matchLabels:
      app: code-runner
  template:
    metadata:
      labels:
        app: code-runner
    spec:
      # 1. Instructs GKE to run this container inside gVisor microkernel
      runtimeClassName: gvisor
      # 2. Toleration to land on the tainted sandbox node pool
      tolerations:
      - key: "sandbox.gke.io/runtime"
        operator: "Equal"
        value: "gvisor"
        effect: "NoSchedule"
      containers:
      - name: executor
        image: python:3.11-slim
        command: ["python3", "-c", "import os; print('Running in gVisor sandbox!')"]
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "1"
            memory: "2Gi"
```

Apply deployment:

```bash
kubectl apply -f untrusted-runner.yaml

# Verify runtime isolation: inspect node and runtime
kubectl get pods -n tenant-untrusted -o wide
```

### 3. Enforce Pod Security Standards (PSS) via Namespace Labels

Enforce the Kubernetes **Restricted** security standard across tenant namespaces:

```bash
# Enforce PSS Restricted on tenant namespace
kubectl label --overwrite namespace tenant-untrusted \
    pod-security.kubernetes.io/enforce=restricted \
    pod-security.kubernetes.io/enforce-version=latest \
    pod-security.kubernetes.io/audit=restricted \
    pod-security.kubernetes.io/warn=restricted
```
*(Any pod attempting to run as root, mount host paths, or request privileged escalation will be rejected at admission).*

### 4. Enforce Multi-Tenant ResourceQuotas and LimitRanges

Create `tenant-quotas.yaml`:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: tenant-compute-quota
  namespace: tenant-untrusted
spec:
  hard:
    requests.cpu: "20"
    requests.memory: "80Gi"
    limits.cpu: "40"
    limits.memory: "160Gi"
    pods: "50"
    services.loadbalancers: "0" # Prevents tenants from spinning up expensive public load balancers
---
apiVersion: v1
kind: LimitRange
metadata:
  name: tenant-limit-range
  namespace: tenant-untrusted
spec:
  limits:
  - default:
      cpu: "1"
      memory: "2Gi"
    defaultRequest:
      cpu: "250m"
      memory: "512Mi"
    max:
      cpu: "4"
      memory: "8Gi"
    min:
      cpu: "100m"
      memory: "128Mi"
    type: Container
```

Apply Quotas:

```bash
kubectl apply -f tenant-quotas.yaml
```

---

## 4. Quotas, Performance, and Configuration Limits

| Dimension / Parameter | GKE Standard runc | GKE Sandbox (gVisor) |
| :--- | :--- | :--- |
| **System Call Virtualization** | None (Direct host kernel) | Handled in user-space Sentry kernel |
| **Syscall Latency Overhead** | None (~0%) | 10% to 30% overhead on syscall-heavy code |
| **Raw Compute / Math Overhead**| None (~0%) | 0% overhead (CPU computations execute natively) |
| **Supported Syscalls** | All standard Linux syscalls | ~320 core Linux syscalls (95% coverage) |
| **Host Device Passthrough** | Supported (GPUs, InfiniBand) | Limited (GPU support is experimental) |
| **Container Escape Risk** | High (Vulnerable to 0-day)| **Near Zero** (Isolated within Sentry process) |

---

## 5. Official References & Documentation

- [GKE Multi-Tenancy Architecture Guide](https://cloud.google.com/kubernetes-engine/docs/concepts/multitenancy-overview)
- [GKE Sandbox (gVisor) Documentation](https://cloud.google.com/kubernetes-engine/docs/concepts/sandbox-pods)
- [Kubernetes Pod Security Standards (PSS)](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Hierarchical Namespace Controller (HNC)](https://github.com/kubernetes-sigs/hierarchical-namespaces)
- [gVisor Open Source Project](https://gvisor.dev/)

---

## 6. Realistic Pricing Scenarios

Multi-tenancy cluster consolidation delivers massive cost savings by eliminating GKE management fees and node fragmentation:
1. **Cluster Management Fee:** $0.10/hour ($73/month) per cluster.
2. **Cluster Consolidation Savings:** Merging 20 small single-tenant clusters into 1 multi-tenant cluster eliminates 19 cluster management fees ($1,387/month).
3. **GKE Sandbox Surcharge:** **$0.00** (Included free with GKE).

### Scenario A: Multi-Tenant Cluster Consolidation (20 Teams)

- **Siloed Cluster Model (20 Single-Tenant Clusters):**
  - 20 separate clusters (3 `n2-standard-4` nodes each = 60 nodes total).
  - Cluster Fees: 20 × $73.00 = $1,460.00/month.
  - Compute Nodes: 60 × $0.194/hr × 730 hrs = $8,497.20/month.
  - Total: **$9,957.20 / month**.
- **Consolidated Multi-Tenant Model (1 Large Cluster):**
  - 1 Multi-Tenant Regional GKE Cluster.
  - Workloads bin-packed onto 35 `n2-standard-8` nodes (eliminates idle slack space).
  - Cluster Fee (1 cluster): $73.00/month.
  - Compute Nodes: 35 × $0.388/hr × 730 hrs = $9,913.40.
  - SRE Overhead: Centralized monitoring, unified patching, zero multi-cluster sprawl.
- **Net Impact:** Eliminates $17,520/year in idle cluster fees while providing automated burst capacity for all 20 teams.

### Scenario B: Hard Multi-Tenant SaaS Code Runner (gVisor Sandbox)

- **Workload Profile:**
  - Online education platform executing 50,000 user-submitted Python scripts daily.
  - Runs in a dedicated GKE Sandbox node pool (4 `n2-standard-8` nodes).
  - GKE Sandbox prevents rogue scripts from reading host files or attacking internal VPC endpoints.
- **Monthly Cost Calculation:**
  - Sandbox Node Pool: 4 nodes × $0.388/hr × 730 hrs = **$1,132.96**
  - GKE Sandbox Licensing / Engine: **$0.00**
- **Total Monthly Cost:** **$1,132.96 / month** (Delivers microVM isolation at bare-metal container costs).

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **Syscall-Heavy Applications Experience Performance Penalties on gVisor:** While compute-heavy Python scripts or CPU math execute at 100% native speed under GKE Sandbox, applications that generate hundreds of thousands of network syscalls per second (like NGINX reverse proxies, Envoy proxies, or heavy Redis instances) will experience a **15% to 30% throughput drop** due to context switching between container and the Sentry user-space kernel. Reserve GKE Sandbox for untrusted backend application code, not high-throughput network proxies.
2. **HostPath and Privileged Containers Are Incompatible with gVisor:** GKE Sandbox explicitly forbids `securityContext.privileged: true` and host volume mounts (`hostPath`). If a third-party container requires access to physical host devices or raw block volumes, it will fail to start under `runtimeClassName: gvisor`.
3. **ResourceQuotas Require LimitRanges for Omitted Pod Specs:** If you apply a `ResourceQuota` requiring CPU limits, and a developer submits a pod specification that omits `resources.requests.cpu`, Kubernetes rejects the pod admission with `403 Forbidden: failed quota: must specify cpu`. Always deploy a companion **LimitRange** in every tenant namespace; the LimitRange automatically injects default request/limit values into pods that omit them, preventing pipeline failures.
4. **Tenant LoadBalancer Service Quota Exhaustion:** If you do not restrict service types via ResourceQuotas (`spec.hard.services.loadbalancers: "0"`), an unauthorized tenant can deploy 20 Kubernetes `type: LoadBalancer` services. Each service provisions a Google Cloud external Network Load Balancer and public IP address ($0.025/hr + IP charges), rapidly exhausting your project's regional load balancer forwarding rule quota and increasing cloud bills.
5. **Cross-Tenant NetworkPolicy Default Isolation:** Creating separate namespaces does **not** restrict network traffic between them; by default, any pod in namespace `tenant-b` can initiate TCP connections to `tenant-a.internal.svc.cluster.local`. You **must enforce a default-deny Ingress NetworkPolicy** across all tenant namespaces, explicitly whitelisting only authorized ingress traffic.
6. **Hierarchical Namespace Controller (HNC) Tree Inheritance:** When using HNC to create parent-child namespace hierarchies (e.g., parent namespace `enterprise-org` propagates RBAC and NetworkPolicies down to child namespaces `team-a` and `team-b`), modifying a policy on the parent namespace **instantly propagates down to all children**. Test parent policy updates in staging to avoid accidentally locking out dozens of child tenant namespaces simultaneously.
