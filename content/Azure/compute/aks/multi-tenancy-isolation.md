---
title: AKS Multi-Tenancy, Hard Isolation, and Confidential Containers
description: Exhaustive engineering guide to multi-tenant architectures on AKS — Soft vs Hard multi-tenancy, Pod Security Standards (PSS), Azure Linux Kata Containers (Hyper-V micro-VM isolation), and AMD SEV-SNP Confidential Containers.
tags:
  - azure
  - aks
  - multi-tenancy
  - security
  - kata-containers
  - confidential-computing
  - isolation
---

# AKS Multi-Tenancy, Hard Isolation, and Confidential Containers 🏢🔒

Enterprise platform engineering teams face a fundamental architectural choice: operate dozens of small, single-tenant AKS clusters (incurring cluster management fee sprawl, underutilized nodes, and operational complexity), or consolidate hundreds of teams into a single high-density **Multi-Tenant AKS Cluster**. Implementing secure multi-tenancy requires understanding the boundary between **Soft Multi-Tenancy** (internal trusted teams separated by Kubernetes namespaces and network policies) and **Hard Multi-Tenancy** (untrusted third-party code, untrusted tenants, and regulated financial/healthcare workloads). AKS provides defense-in-depth isolation layers spanning **Pod Security Standards (PSS)**, **Kata Containers (Hyper-V micro-VM virtualization)**, and **AMD SEV-SNP Confidential Containers**.

---

## 1. Architecture: Soft vs. Hard Workload Isolation

```
═════════════════════════════════════════════════════════════════════════════════
LEVEL 1: SOFT MULTI-TENANCY (Shared Linux Kernel)
Tenants share the same host Linux kernel; isolated via namespaces, cgroups, and seccomp.
Vulnerability: Kernel privilege escalation or zero-day kernel exploit compromises all tenants!

  ┌─────────────────────────┐         ┌─────────────────────────┐
  │ Tenant A: Pod (`orders`)│         │ Tenant B: Pod (`users`) │
  └────────────┬────────────┘         └────────────┬────────────┘
               │                                   │
               ▼                                   ▼
  ┌─────────────────────────────────────────────────────────────┐
  │ SHARED HOST LINUX KERNEL (Node VM: Standard_D8ds_v5)        │
  └─────────────────────────────────────────────────────────────┘
═════════════════════════════════════════════════════════════════════════════════
LEVEL 2: HARD MULTI-TENANCY (Kata Containers / Hyper-V Micro-VM Isolation)
Every Pod executes inside its own dedicated lightweight Hyper-V Microkernel VM.
Zero shared kernel space! Direct syscalls to the host OS are completely blocked.

  ┌─────────────────────────┐         ┌─────────────────────────┐
  │ Tenant A: Pod (`orders`)│         │ Tenant B: Pod (`untrusted`)
  │ Dedicated Guest Kernel  │         │ Dedicated Guest Kernel  │
  │ Micro-VM (Kata/Hyper-V) │         │ Micro-VM (Kata/Hyper-V) │
  └────────────┬────────────┘         └────────────┬────────────┘
               │ Virtual Hardware Boundary         │ Virtual Hardware Boundary
               ▼                                   ▼
  ┌─────────────────────────────────────────────────────────────┐
  │ PHYSICAL HOST HYPERVISOR (No Direct Host Kernel Syscalls!)  │
  └─────────────────────────────────────────────────────────────┘
═════════════════════════════════════════════════════════════════════════════════
LEVEL 3: CONFIDENTIAL CONTAINERS (Hardware Memory Encryption - AMD SEV-SNP)
Memory is encrypted in hardware via CPU keys. Even Azure Cloud Admins and host
root hypervisors CANNOT inspect in-memory encryption keys or cleartext data!
═════════════════════════════════════════════════════════════════════════════════
```

---

## 2. Isolation Technology Comparison Matrix

| Dimension | Standard Container (Soft) | Kata Containers (Hard) | Confidential Containers (Hardware) |
| :--- | :--- | :--- | :--- |
| **Isolation Mechanism** | Linux Namespaces + cgroups | **Dedicated Micro-VM (Hyper-V)**| **Hardware Memory Encryption (SEV-SNP)**|
| **Kernel Sharing** | **Shared Host Kernel** | **Independent Guest Kernel** | **Independent Guest Kernel + Memory Enc**|
| **Startup Latency** | ~500 milliseconds | ~1 to 2 seconds | ~2 to 3 seconds |
| **CPU/RAM Overhead** | Negligible (< 1%) | Low (~25 MiB RAM per pod) | Low (~3–5% CPU encryption overhead) |
| **Untrusted Code Execution**| **High Risk (Unsafe)** | **Completely Safe** | **Completely Safe + Zero-Trust Operator**|
| **Target Workload** | Internal trusted services | Multi-tenant SaaS, tenant plugins| Banking, Health, Defense, Clean Rooms |

---

## 3. Production Deployment & CLI Operations (`az` CLI & `kubectl`)

### 1. Provision Node Pool with Kata Containers Support (Azure Linux)

```bash
# Add specialized user node pool running Azure Linux with Kata Containers enabled
az aks nodepool add \
    --resource-group rg-prod-security \
    --cluster-name aks-core-prod \
    --name katapool \
    --os-sku AzureLinux \
    --workload-runtime KataMshvVmIsolation \
    --node-vm-size Standard_D8ds_v5 \
    --node-count 3 \
    --node-taints "isolation=kata:NoSchedule"
```

### 2. Deploy Untrusted Tenant Pod with Dedicated Kata Micro-VM Runtime

Create `untrusted-tenant-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: untrusted-customer-code
  namespace: tenant-sandbox
spec:
  # Instructs Kubernetes to wrap container inside Hyper-V Micro-VM
  runtimeClassName: kata-mshv-vm-isolation
  tolerations:
  - key: "isolation"
    operator: "Equal"
    value: "kata"
    effect: "NoSchedule"
  containers:
  - name: code-runner
    image: python:3.11-slim
    command: ["python", "-c", "import time; print('Running inside isolated microkernel'); time.sleep(3600)"]
    resources:
      requests:
        cpu: "500m"
        memory: "512Mi"
      limits:
        cpu: "1000m"
        memory: "1Gi"
```

Apply pod:

```bash
kubectl apply -f untrusted-tenant-pod.yaml
```

### 3. Enforce Soft Multi-Tenancy: Pod Security Standards & Quotas

Enforce that the `tenant-alpha` namespace adheres to the **Restricted** security baseline and strictly caps compute consumption:

Create `tenant-alpha-governance.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-alpha
  labels:
    # Pod Security Admission: Blocks root containers and privilege escalation
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: tenant-alpha-quota
  namespace: tenant-alpha
spec:
  hard:
    requests.cpu: "20"
    requests.memory: "40Gi"
    limits.cpu: "40"
    limits.memory: "80Gi"
    pods: "30"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: tenant-alpha-limits
  namespace: tenant-alpha
spec:
  limits:
  - default:
      cpu: "500m"
      memory: "512Mi"
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
    type: Container
```

Apply governance manifests:

```bash
kubectl apply -f tenant-alpha-governance.yaml
```

---

## 4. Quotas, Performance & Configuration Limits

| Parameter | Platform Limit | Production Rule |
| :--- | :--- | :--- |
| **Max Namespaces per Cluster** | **10,000 Namespaces** | Logical tenancy capacity |
| **Kata Micro-VM Memory Floor** | **~25 MiB RAM overhead**| Required to host lightweight guest kernel |
| **Confidential VM Series** | DCasv5 / ECasv5 | Hardware memory encryption requires AMD EPYC |
| **Network Isolation Engine** | Cilium NetworkPolicy | Enforces default-deny between tenant namespaces |

---

## 5. Official References

- [Azure Linux Container Isolation (Kata Containers) on AKS](https://learn.microsoft.com/en-us/azure/aks/use-kata-containers)
- [Confidential Containers on AKS Overview](https://learn.microsoft.com/en-us/azure/confidential-computing/confidential-containers-aks-overview)
- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Best Practices for Multi-Tenancy and Cluster Isolation in AKS](https://learn.microsoft.com/en-us/azure/aks/operator-best-practices-cluster-isolation)

---

## 6. Realistic Pricing Scenarios

### Scenario A: Multi-Tenant SaaS Platform with Kata Containers

- **Architecture:** 50 enterprise customers sharing a 12-node AKS cluster running untrusted custom user scripts inside Kata Micro-VMs.
- **Cost Comparison vs Dedicated Single-Tenant Clusters:**
  - *Option 1 (50 Small Single-Tenant Clusters):* 50 clusters × $73/mo control plane + 150 VMs = **~$25,000 / month**.
  - *Option 2 (Consolidated Multi-Tenant Cluster with Kata):* 12x `Standard_D8ds_v5` nodes + 1 control plane = **~$3,440 / month**.
- **Monthly Cost Breakdown:**
  - Control Plane Fee: **$73.00**
  - Compute Nodes (12 nodes): 12 × $0.384/hr × 730 hrs = **$3,363.84**
  - Kata Containers Surcharge: **$0.00 (Built into Azure Linux)**.
- **Total Monthly Spend:** **$3,436.84 / month** *(Delivering over $21,000/month in infrastructure savings).*

### Scenario B: High-Security Banking Core with Confidential Containers

- **Architecture:** 4x `Standard_DC4as_v5` Confidential VMs with AMD SEV-SNP hardware memory encryption.
- **Monthly Cost Breakdown:**
  - Confidential Compute Nodes: 4 × $0.298/hr × 730 hrs = **$870.16**
  - Standard Control Plane SLA: **$73.00**
- **Total Monthly Spend:** **$943.16 / month**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **HostPath Volume Mounts Forbidden in Kata Micro-VMs:** Because Kata Containers run inside isolated Hyper-V micro-virtual machines, they do not share the host VM's filesystem. Any pod attempting to mount a `hostPath` volume (e.g., `/var/log` or `/var/run/docker.sock`) will fail during container initialization with `FailedToCreateContainer: hostPath is not supported by Kata runtime`. Use `emptyDir` or persistent volumes.
2. **Missing `Default-Deny` NetworkPolicy Allows Cross-Namespace Snooping:** By default in Kubernetes, all namespaces can freely communicate over the network. Creating namespaces without an explicit default-deny `NetworkPolicy` allows Tenant A to query internal HTTP services and Redis caches running in Tenant B's namespace. Always deploy a cluster-wide baseline denying cross-namespace traffic unless explicitly permitted.
3. **Kata Containers Micro-VM Memory Sizing:** When declaring pod memory limits for Kata containers, the pod memory limit must encompass both the application container *and* the lightweight guest Linux kernel (~25–35 MiB). If you declare an extremely small memory limit (e.g., `memory: 32Mi`), the pod will be abruptly killed before the application even boots.
4. **Confidential Containers Signature Verification Bottlenecks:** Confidential Containers on AKS enforce image signature verification and attestation before booting. If container images are stored in an external registry with high network latency, container boot times can stretch to **15–30 seconds**. Always co-locate container images inside an Azure Container Registry (ACR) Premium in the same Azure region.
5. **ResourceQuota Saturation Silent Pipeline Failures:** When a tenant reaches their namespace CPU or pod count `ResourceQuota`, Kubernetes does not queue new pods; it rejects the API deployment outright. If an automated CI/CD pipeline does not inspect the error code, deployments silently fail while reporting success. Configure alert rules on `kube_resourcequota{type="used"}` exceeding 85%.
