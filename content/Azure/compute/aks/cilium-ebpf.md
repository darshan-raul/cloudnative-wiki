---
title: Azure CNI Powered by Cilium — eBPF Datapath, WireGuard Encryption, and Hubble Observability
description: Exhaustive engineering guide to Azure CNI Powered by Cilium — eBPF kernel datapath, kube-proxy iptables replacement, transparent WireGuard node-to-node encryption, Layer 7 CiliumNetworkPolicies, and Hubble deep observability.
tags:
  - azure
  - aks
  - cilium
  - ebpf
  - networking
  - security
  - observability
  - hubble
---

# Azure CNI Powered by Cilium — eBPF Datapath, WireGuard Encryption, and Hubble Observability 🐝⚡

In large-scale Kubernetes clusters running thousands of microservices, traditional networking architectures rely on **`kube-proxy` with Linux `iptables` or IPVS**. As service counts exceed 5,000, `iptables` exhibits severe performance degradation: packet processing slows to $O(N)$ linear complexity, and rule updates take minutes to sync. **Azure CNI Powered by Cilium** replaces legacy `iptables` with **extended Berkeley Packet Filter (eBPF)** programs loaded directly into the Linux kernel, enabling $O(1)$ constant-time packet routing, transparent **WireGuard encryption**, and deep Layer 7 observability via **Hubble**.

---

## 1. Architecture: The eBPF Kernel Dataplane

By combining Azure CNI for IP Address Management (IPAM) with Cilium for packet routing and network policies, AKS runs eBPF programs attached to the host VM's `tc` (traffic control) and XDP (eXpress Data Path) kernel hooks.

```
                           LINUX KERNEL eBPF DATAPATH (Node VM)
       ┌────────────────────────────────────────────────────────────────────────┐
       │ APPLICATION POD A (Namespace: `payments`)                              │
       │ IP: 192.168.1.50 ──► Socket Buffer (sk_buff)                           │
       └──────────────────────────────────┬─────────────────────────────────────┘
                                          │ eBPF Socket Filter
                                          ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                      CILIUM eBPF KERNEL SUBSYSTEM                      │
       │                                                                        │
       │  ┌────────────────────────┐         ┌────────────────────────┐         │
       │  │ eBPF Service Proxy     │         │ eBPF Network Policy    │         │
       │  │ (Replaces kube-proxy)  │         │ (Identity-Based, L3-L7)│         │
       │  │ - BPF Hash Map ($O(1)$)│         │ - Security Labels      │         │
       │  │ - Zero iptables churn  │         │ - FQDN egress filter   │         │
       │  └───────────┬────────────┘         └───────────┬────────────┘         │
       │              │ BPF Map Lookup                   │ Allows Traffic       │
       │              ▼                                  ▼                      │
       │  ┌──────────────────────────────────────────────────────────┐          │
       │  │          TRANSPARENT WIREGUARD ENCRYPTION HOOK           │          │
       │  │          - Kernel-level ChaCha20-Poly1305 encryption     │          │
       │  │          - Encrypts inter-node pod traffic on the fly    │          │
       │  └───────────────────────────┬──────────────────────────────┘          │
       └──────────────────────────────┼─────────────────────────────────────────┘
                                      │ Encrypted WireGuard Packet
                                      ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                AZURE VNET PHYSICAL FIBER FABRIC                        │
       │  (Encrypted inter-zone node-to-node transport: TCP/UDP 51871)          │
       └────────────────────────────────────────────────────────────────────────┘
```

### Why eBPF Outperforms `kube-proxy` + `iptables`

| Dimension | `kube-proxy` (iptables Mode) | Azure CNI Powered by Cilium (eBPF) |
| :--- | :--- | :--- |
| **Lookup Algorithm** | **$O(N)$ Linear Scan:** Evaluates every rule sequentially | **$O(1)$ Hash Map:** Direct memory hash table lookup |
| **Routing Overhead (10K Services)**| **~5 to 15 milliseconds** latency penalty | **< 10 microseconds** latency penalty |
| **Control Plane Rule Updates**| Re-writes the entire `iptables` chain in kernel | Atomic BPF map update without flushing tables |
| **CPU Utilization during Churn**| High (Kube-proxy consumes CPU during pod scaling)| Near Zero (BPF maps update asynchronously) |
| **Network Policy Security** | IP/CIDR-based (vulnerable to IP reuse race conditions)| **Cryptographic Identity Labels** (e.g., `app=order`) |
| **L7 DNS / FQDN Filtering** | Not supported natively | **Fully Supported** (Wildcard FQDN filtering) |

---

## 2. Core Capabilities: WireGuard Encryption & Hubble

### 1. Transparent Node-to-Node Pod Encryption (WireGuard)
Enterprise compliance regimes (HIPAA, PCI-DSS, FedRAMP) require end-to-end encryption in transit across all internal network links. Rather than burdening developers with Istio or Linkerd mTLS sidecars, Cilium integrates **kernel-space WireGuard encryption**:
- Encryption occurs transparently at the Linux kernel boundary before packets leave the host VM.
- Uses high-speed modern cryptographic primitives: **ChaCha20** for symmetric encryption and **Poly1305** for authentication.
- Automatically handles key exchange and peer management between AKS nodes.
- Pods experience **zero sidecar memory overhead**.

### 2. Hubble Deep Observability
Hubble uses eBPF to monitor raw socket operations, providing zero-overhead distributed tracing, DNS query analytics, and flow logging:
- Tracks HTTP status codes (`200 OK`, `500 Error`), latency percentiles (P95, P99), and TCP drops.
- Exposes visual service dependency graphs via the Hubble UI and Prometheus metric endpoints.

---

## 3. Production Deployment & CLI Operations (`az` CLI & `kubectl`)

### 1. Provision an AKS Cluster with Azure CNI Powered by Cilium

```bash
# Provision AKS cluster with Cilium dataplane and Azure CNI Overlay
az aks create \
    --resource-group rg-prod-cilium \
    --name aks-cilium-cluster \
    --location eastus \
    --tier standard \
    --node-count 6 \
    --node-vm-size Standard_D4ds_v5 \
    --network-plugin azure \
    --network-plugin-mode overlay \
    --network-dataplane cilium \
    --pod-cidr 192.168.0.0/16 \
    --service-cidr 10.240.0.0/16 \
    --dns-service-ip 10.240.0.10 \
    --enable-managed-identity
```

### 2. Enable Transparent Node-to-Node WireGuard Encryption

```bash
# Verify Cilium pods are running in kube-system
kubectl get pods -n kube-system -l k8s-app=cilium

# Enable WireGuard encryption across all nodes via Cilium ConfigMap
kubectl -n kube-system patch configmap cilium-config --type merge -p '{"data":{"enable-wireguard":"true"}}'

# Perform rolling restart of Cilium DaemonSet to load WireGuard kernel modules
kubectl -n kube-system rollout restart daemonset cilium
```

### 3. Deploy Layer 7 FQDN Egress Security Policy

Create `payments-egress-fqdn-policy.yaml` to restrict the `payments` service to only reach authorized external APIs (e.g., Stripe) over TLS port 443:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: secure-stripe-egress
  namespace: payments
spec:
  endpointSelector:
    matchLabels:
      app: payment-processor
  egress:
  # Allow CoreDNS resolution
  - toEndpoints:
    - matchLabels:
        io.kubernetes.pod.namespace: kube-system
        k8s-app: coredns
    toPorts:
    - ports:
      - port: "53"
        protocol: UDP
      rules:
        dns:
        - matchPattern: "*"
  # Allow egress ONLY to Stripe API via FQDN inspection
  - toFQDNs:
    - matchPattern: "*.stripe.com"
    toPorts:
    - ports:
      - port: "443"
        protocol: TCP
```

Apply the policy:

```bash
kubectl apply -f payments-egress-fqdn-policy.yaml
```

### 4. Inspect Real-Time Flows via Hubble CLI

```bash
# Port-forward Hubble relay service
kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &

# Stream live network drops across all namespaces
hubble observe --server localhost:4245 --verdict DROPPED --follow
```

---

## 4. Quotas, Performance & Configuration Limits

| Parameter / Capability | Metric / Limit | Production Impact |
| :--- | :--- | :--- |
| **Max Kubernetes Services** | **20,000+ Services** | $O(1)$ BPF hash map lookup eliminates latency scaling |
| **WireGuard Throughput Penalty**| **< 3% CPU overhead** | Significantly faster and lighter than mTLS proxy sidecars |
| **Max Network Policy Rules**| **Up to 100,000 rules** | Limited only by Linux kernel BPF map memory allocation |
| **Hubble Event Buffer Size** | **4,096 events per CPU** | Ring buffer in kernel memory prevents packet drop during spikes|
| **Supported OS Families** | **Ubuntu & Azure Linux 3**| Both include pre-compiled eBPF kernel headers |

---

## 5. Official References

- [Azure CNI Powered by Cilium Documentation](https://learn.microsoft.com/en-us/azure/aks/azure-cni-powered-by-cilium)
- [Cilium Network Policy Reference](https://docs.cilium.io/en/stable/security/policy/)
- [Hubble Observability Architecture](https://docs.cilium.io/en/stable/observability/hubble/)
- [WireGuard Transparent Encryption on Cilium](https://docs.cilium.io/en/stable/security/encryption-wireguard/)

---

## 6. Realistic Pricing Scenarios

### Scenario A: High-Scale Financial Core (5,000 Services, Zero Sidecars)

- **Architecture:** 50x `Standard_D8ds_v5` nodes running 2,500 pods and 5,000 internal services.
- **Cost Comparison vs Service Mesh Sidecars:**
  - *Option 1 (Istio Sidecars for mTLS & Metrics):* 2,500 pods × 128 MiB RAM sidecar overhead = **320 GiB RAM wasted** on sidecars (~5 extra VM nodes @ $1,400/mo).
  - *Option 2 (Azure CNI Powered by Cilium):* **$0.00 extra VM spend**. WireGuard and Hubble operate inside the Linux kernel.
- **Monthly Cost:**
  - Control Plane Fee: $0.10/hr × 730 hrs = **$73.00**
  - Compute Nodes: 50 × $0.384/hr × 730 hrs = **$14,016.00**
  - Cilium & WireGuard Surcharge: **$0.00 (Built into AKS)**.
- **Total Monthly Cost:** **$14,089.00 / month** *(Delivering ~$1,400/mo in savings compared to sidecar meshes).*

### Scenario B: Regulatory Compliance Workload with FQDN Egress Auditing

- **Architecture:** 6x `Standard_D4ds_v5` nodes running healthcare applications.
- **Requirements:** Strict FQDN egress whitelisting and packet drop auditing.
- **Monthly Cost Breakdown:**
  - Standard Cluster Fee: **$73.00**
  - Compute Costs: 6 × $0.192/hr × 730 hrs = **$840.96**
  - Azure Monitor Prometheus Workspace (Ingesting Hubble metrics): 20 GB/mo × $0.36/GB = **$7.20**
- **Total Monthly Cost:** **$921.16 / month**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **DNS TTL Race Conditions in FQDN Network Policies:** Cilium's FQDN egress policies work by intercepting DNS responses from CoreDNS and dynamically populating BPF IP sets with the resolved A/AAAA records. If a third-party external service (like AWS S3 or Cloudflare) uses ultra-low DNS TTLs (e.g., 5 seconds) and the pod caches the IP longer than the TTL, Cilium may expire the IP from the BPF table while the application continues sending traffic, causing unexpected **`Connection Refused` or dropped packets**. Increase `toFQDNs.ttl` override in the `CiliumNetworkPolicy`.
2. **WireGuard MTU Overhead Requires 1420 MTU:** While standard Azure CNI Overlay uses MTU 1450, enabling WireGuard adds another 60 bytes for the outer UDP WireGuard header. Running WireGuard on top of Azure CNI Overlay without reducing pod MTU to **1420** results in fragmentation, severely degrading throughput on bulk TLS downloads.
3. **Hubble UI Memory Exhaustion on Heavy Traffic Clusters:** The Hubble UI uses a Node.js backend to poll `hubble-relay` for real-time flow telemetry. In clusters processing 50,000+ flows/second, the Hubble UI pod can quickly exhaust its default memory limit and get killed with **`OOMKilled (Exit Code 137)`**. Adjust the `hubble.ui.backend.resources.limits.memory` in production to at least 2 GiB.
4. **Cannot Enable Cilium on Existing Clusters:** Just like Azure CNI Overlay, **Azure CNI Powered by Cilium must be chosen at cluster creation time**. You cannot transition an existing cluster running standard Azure CNI or Kubenet to Cilium in place.
5. **Cilium Endpoint Regeneration Bottlenecks during Rapid Scaling:** When hundreds of pods are scheduled simultaneously during a massive traffic burst, the Cilium agent on each node compiles and injects new eBPF bytecode for each new endpoint. If worker nodes have under-sized CPUs (e.g., 2 vCPUs), the `cilium-agent` can saturate the CPU, delaying pod readiness (`ContainersNotReady` state for 30–60 seconds). Ensure worker nodes running Cilium have at least 4 vCPUs (`D4ds_v5` or higher).
