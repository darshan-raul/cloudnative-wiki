# Node Hardening

*"https://kubernetes.io/docs/tasks/administer-cluster/securing-a-cluster/#securing-the-kubelet"*

**Node hardening** is the practice of **securing the k8s node** (the host that runs the kubelet and Pods). It covers the **host OS**, the **kubelet config**, the **container runtime**, the **kernel parameters**, and the **node's network exposure**. The goal: even if a workload is compromised, the host should be hard to take over. This is the **per-node** counterpart to cluster hardening (which covers the control plane).

### Table of Contents

1. [The Node Attack Surface](#1-the-node-attack-surface)
2. [The Host OS Hardening](#2-the-host-os-hardening)
3. [The Container Runtime](#3-the-container-runtime)
4. [The Kubelet Config in Depth](#4-the-kubelet-config-in-depth)
5. [The Kernel Parameters](#5-the-kernel-parameters)
6. [The Node's Network Exposure](#6-the-nodes-network-exposure)
7. [The Filesystem Layout](#7-the-filesystem-layout)
8. [SSH and Login Hardening](#8-ssh-and-login-hardening)
9. [The Container Runtime's Security](#9-the-container-runtimes-security)
10. [The "NodeRestriction" Admission](#10-the-noderestriction-admission)
11. [The CIS Node Benchmark](#11-the-cis-node-benchmark)
12. [Common Tools (kubelet config, sysctl, auditd)](#12-common-tools-kubelet-config-sysctl-auditd)
13. [Operations and Debugging](#13-operations-and-debugging)
14. [Gotchas and Common Mistakes](#14-gotchas-and-common-mistakes)

---

## 1. The Node Attack Surface

A k8s node has many surfaces:

* **kubelet** — the per-node agent. Listens on `:10250` (API) and (deprecated) `:10255` (read-only).
* **Container runtime** — containerd / CRI-O. Listens on a Unix socket (or, misconfigured, a TCP port).
* **Pod network** — the bridge / overlay. Each Pod has an IP.
* **Host services** — SSH, monitoring, logging agents.
* **Host filesystem** — `/var/lib/kubelet`, `/var/lib/containerd`, etc.
* **Kernel** — the host's kernel. Syscalls from Pods land here.
* **Firmware / hardware** — the node's hardware. (Out of scope for most hardening.)

The attack paths:

* **Compromised Pod → kernel escape** — the workload has a kernel exploit. Mitigated by seccomp, AppArmor, RuntimeClass (gVisor, Kata), kernel hardening.
* **Compromised kubelet** — the kubelet is the node's identity. Mitigated by kubelet config, network exposure.
* **Compromised container runtime** — the runtime manages all Pods. Mitigated by runtime config, runtime sandboxing.
* **Compromised SSH** — anyone with SSH to the node can read everything. Mitigated by SSH hardening, no SSH from public.
* **Compromised network** — sniffing the node's network. Mitigated by mTLS, NetworkPolicy, network segmentation.

Node hardening addresses the **per-node** layers: the host OS, the kubelet, the runtime, the kernel, the network.

## 2. The Host OS Hardening

The host OS is the **base**. It should be minimal and hardened.

### 2.1 The OS choice

* **Distroless / Container-optimized OS** — Google's Container-Optimized OS, AWS Bottlerocket, Azure's CBL-Mariner, Talos Linux. Designed for k8s nodes.
* **Minimal Linux** — Ubuntu Server, RHEL, Alpine. Strip the GUI, unnecessary services.
* **Windows Server** — for Windows containers. Less common.

For most production, **a k8s-specific OS** is preferred. They're:

* Minimal (smaller attack surface).
* Auto-updating.
* Read-only root filesystem.
* Designed for the kubelet's needs.

### 2.2 Patching

The OS should be **patched regularly**. Critical patches within 24 hours, others within a week.

Automation:

* **Unattended-upgrades** (Debian / Ubuntu) — auto-apply security patches.
* **yum-cron** (RHEL) — same.
* **Container-optimized OS** — auto-updates by default (with rollback).

### 2.3 Disable unnecessary services

Disable anything that's not needed:

* **SSH** — keep it on, but restrict to a bastion. Use key auth only, no password.
* **Telnet** — off (use SSH).
* **FTP** — off (use SFTP / rsync over SSH).
* **NFS** — off (unless explicitly needed).
* **SMB / CIFS** — off.
* **HTTP servers** — off (Apache, Nginx, etc., unless it's the node's role).
* **Mail server** — off.
* **Print server** — off.
* **GUI / X11** — off (this is a server).

Most of these are off by default on minimal Linux. Audit with `systemctl list-unit-files --state=enabled`.

### 2.4 The host firewall

The node should have a firewall:

* **Allow SSH** (from a bastion only).
* **Allow kubelet API** (`:10250`) from the apiserver / control plane.
* **Allow the CNI network** (e.g. VXLAN port 4789, Calico BGP 179).
* **Allow DNS** (port 53) to the cluster DNS.
* **Block everything else**.

Tools:

* **iptables** — the standard.
* **nftables** — the newer replacement.
* **firewalld** (RHEL) — the high-level wrapper.
* **ufw** (Ubuntu) — the simple wrapper.

The **kubelet should not be exposed to the world**. The kubelet's `:10250` is a powerful API. The node's firewall (and the network's firewall / security group) should restrict access.

## 3. The Container Runtime

The container runtime is the **process that actually runs containers**. The kubelet talks to it via CRI (Container Runtime Interface). The most common:

* **containerd** — the standard.
* **CRI-O** — the Red Hat alternative.
* **Docker** — the original, now deprecated as a k8s runtime. Use containerd.

The runtime's config:

```toml
# /etc/containerd/config.toml
version = 2

[plugins."io.containerd.grpc.v1.cri"]
  sandbox_image = "k8s.gcr.io/pause:3.9"
  
  [plugins."io.containerd.grpc.v1.cri.containerd"]
    snapshotter = "overlayfs"
    disable_snapshot_annotations = true
    
  [plugins."io.containerd.grpc.v1.cri.cni"]
    bin_dir = "/opt/cni/bin"
    conf_dir = "/etc/cni/net.d"
    
  [plugins."io.containerd.grpc.v1.cri.containerd.runtimes.runc]
    runtime_type = "io.containerd.runc.v2"
    [plugins."io.containerd.grpc.v1.cri.containerd.runtimes.runc.options]
      SystemdCgroup = true
```

The security-relevant parts:

* **`disable_hugetlb_controller = true`** — disable the hugetlb controller (unless needed).
* **`restrict_oom_score_adj = true`** — restrict the OOM score adjustment.
* **`disable_proc_mount = true`** — don't auto-mount `/proc` for containers.
* **`seccomp_profile = ""`** — use the default (RuntimeDefault).
* **`enable_unprivileged_ports = false`** — restrict unprivileged port binding (k8s 1.27+).
* **`enable_unprivileged_icmp = false`** — restrict unprivileged ICMP.

### 3.1 The runtime's socket

The runtime's socket (`/run/containerd/containerd.sock` or `/var/run/crio/crio.sock`) is **the runtime's API**. It's a Unix socket, accessible only to root (or the containerd user).

**Don't expose the socket over TCP.** Don't mount it in a Pod (the Pod can control the runtime).

## 4. The Kubelet Config in Depth

The kubelet config is at `/var/lib/kubelet/config.yaml`. See [[Kubernetes/concepts/L07-security/20-cluster-hardening|Cluster Hardening]] for the basics. The full config:

```yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
# --- authentication ---
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
    cacheTTL: 2m
  x509:
    clientCAFile: /etc/kubernetes/pki/ca.crt

# --- authorization ---
authorization:
  mode: Webhook
  webhook:
    cacheAuthorizedTTL: 5m
    cacheUnauthorizedTTL: 30s

# --- network ---
address: 0.0.0.0
port: 10250
readOnlyPort: 0
tlsCertFile: /var/lib/kubelet/pki/kubelet.crt
tlsPrivateKeyFile: /var/lib/kubelet/pki/kubelet.key
rotateCertificates: true
serverTLSBootstrap: true

# --- resources ---
maxPods: 110
podsPerCore: 0
systemReserved: { cpu: "500m", memory: "1Gi", ephemeral-storage: "10Gi" }
kubeReserved: { cpu: "500m", memory: "1Gi", ephemeral-storage: "10Gi" }
evictionHard: { memory.available: "100Mi", nodefs.available: "10%" }

# --- runtime ---
runtimeRequestTimeout: 2m
cgroupDriver: systemd
cgroupRoot: /

# --- hardening ---
protectKernelDefaults: true
seccompDefault: true
# k8s 1.28+
# --enable-profiling-handler: false (not in config, but flag)

# --- images ---
imagePullPolicy: IfNotPresent
imageGCHighThresholdPercent: 85
imageGCLowThresholdPercent: 80

# --- misc ---
clusterDomain: cluster.local
clusterDNS: ["10.96.0.10"]
resolvConf: /etc/resolv.conf
hairpinMode: promiscuous-bridge
```

Key hardening flags:

* **`readOnlyPort: 0`** — disable the read-only port.
* **`protectKernelDefaults: true`** — prevent Pods from changing kernel tunables.
* **`seccompDefault: true`** — apply `RuntimeDefault` seccomp to all containers without an explicit profile.
* **`authentication.anonymous.enabled: false`** — disable anonymous access.
* **`rotateCertificates: true`** — auto-rotate the kubelet's serving cert.

## 5. The Kernel Parameters

The kernel has many tunables that affect security. The kubelet's `protectKernelDefaults: true` prevents Pods from changing these via `securityContext.sysctls`. But the **default values** are still in effect.

### 5.1 The relevant sysctls

```bash
# /etc/sysctl.d/99-k8s-hardening.conf
# IP forwarding (for routing)
net.ipv4.ip_forward = 1

# Reverse path filtering
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# ICMP redirects (should not be accepted)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Send redirects (only for routers)
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# SYN cookies (SYN flood protection)
net.ipv4.tcp_syncookies = 1

# Kernel panic on out-of-memory
vm.panic_on_oom = 0    # 0 = don't panic, let OOM killer run; 1 = panic

# ASLR (Address Space Layout Randomization)
kernel.randomize_va_space = 2     # full randomization
```

These are general Linux hardening. The `k8s-specific` tunables:

* **`net.ipv4.ip_forward = 1`** — required for Pod networking.
* **`net.bridge.bridge-nf-call-iptables = 1`** — required for CNI plugins that use iptables.
* **`net.bridge.bridge-nf-call-ip6tables = 1`** — same for IPv6.

### 5.2 The `sysctls` in Pods

Pods can request `sysctls` via `securityContext.sysctls`. With `protectKernelDefaults: true`, only "safe" sysctls are allowed:

* `kernel.shm*`
* `kernel.msg*`
* `kernel.sem`
* `fs.mqueue.*`
* `net.*` (a subset of safe networking tunables)

"Unsafe" sysctls (e.g. `kernel.*`, `vm.*`) require a Pod Security Policy (deprecated) or an admission policy (Kyverno / OPA) to allow.

## 6. The Node's Network Exposure

The node's network has multiple interfaces. The exposure:

* **Public IP** — the node may or may not have a public IP. In cloud-managed clusters, the nodes are usually on a private subnet. In self-managed, they may be public.
* **Private IP** — the node's internal IP. The kubelet and Pods listen here.
* **NodePort range** — 30000-32767. Services of type `NodePort` listen on these.

The hardening:

* **No public IP** — nodes are on a private subnet. A bastion / jumpbox for SSH.
* **Security groups / firewall** — allow only what's needed (kubelet, CNI, DNS).
* **No NodePort to the public** — use a LoadBalancer or Ingress instead.

### 6.1 The kubelet's port (10250)

`kubelet` listens on `:10250`. This is a powerful API:

* `/pods` — list Pods.
* `/exec` — exec into a Pod.
* `/logs` — read Pod logs.
* `/run` — run a command in a Pod.
* `/metrics` — kubelet metrics.

**Anyone with access to `:10250` can do all of the above.** Mitigations:

* **Network restriction** — the firewall / security group allows `:10250` from the apiserver's IP only.
* **Authn / authz** — the kubelet's webhook authn + Node authorizer. The `system:nodes` group is for kubelets; `system:anonymous` should be disabled.
* **TLS** — the kubelet's serving cert is TLS. The client cert (for X.509 auth) is verified against the cluster CA.

### 6.2 The read-only port (10255, deprecated)

`readOnlyPort: 10255` exposes a **read-only** kubelet API:

* `/metrics` — kubelet metrics.
* `/pods` — list Pods.
* `/healthz` — kubelet health.

**No authentication.** The port is unauthenticated. **Always disable** (`readOnlyPort: 0`).

This port is deprecated in k8s 1.24+ and will be removed. Disable it.

## 7. The Filesystem Layout

The node's filesystem has k8s-specific directories:

* `/var/lib/kubelet/` — the kubelet's state. Pods' volumes, secrets (cached), config.
* `/var/lib/containerd/` — the container runtime's state. Image layers, container state.
* `/var/lib/etcd/` — if etcd runs on the node (for self-managed control plane).
* `/etc/kubernetes/` — the kubelet's config, the cluster's PKI, manifests.
* `/var/log/` — kubelet logs, container logs, audit logs.
* `/opt/cni/bin/` — CNI plugins.
* `/etc/cni/net.d/` — CNI config.

### 7.1 Permissions

* **`/var/lib/kubelet/`** — root-owned. The kubelet runs as root.
* **`/etc/kubernetes/pki/`** — root-owned. The cluster's PKI.
* **`/var/log/kubernetes/audit/`** — root-owned, but readable by the audit log shipper.

The directories should be:

* **Owned by root** (or the kubelet's user, if not root).
* **Not world-writable.**
* **On a separate disk** (for performance and isolation).

### 7.2 Disk encryption

The node's disk should be **encrypted at rest**:

* **LUKS** (Linux Unified Key Setup) — full disk encryption.
* **Cloud provider's disk encryption** — EBS encryption (AWS), managed disk encryption (Azure), etc.
* **TPM-based key sealing** — for on-prem.

The encryption is transparent to k8s. The kubelet and runtime don't know.

## 8. SSH and Login Hardening

SSH is the **most common attack vector** for nodes. The hardening:

* **Key-based auth only** — disable password auth in `/etc/ssh/sshd_config`:

```bash
PasswordAuthentication no
PermitRootLogin prohibit-password    # or "no" for full disable
```

* **Restrict to specific users / groups** — `AllowUsers`, `AllowGroups`.
* **Disable root login** — `PermitRootLogin no`.
* **Change the SSH port** — 2222 instead of 22. (Security by obscurity, but reduces noise.)
* **Use fail2ban** — block IPs after N failed attempts.
* **Use a bastion** — only the bastion accepts SSH. The nodes accept SSH from the bastion only.
* **Disable SSH for the kubelet's user** — the kubelet user (typically `kubelet`) doesn't need SSH.
* **MFA** — for human users (rare on nodes, but useful for the bastion).

### 8.1 The bastion

A **bastion host** (or jump host) is the only entry point for SSH. The nodes accept SSH from the bastion only.

The bastion:

* Is in a public subnet (or accessible from the operator's VPN).
* Logs every SSH session (for audit).
- Has a small, hardened surface.
- May have MFA.

The operator SSHes to the bastion, then SSHes to the node from there. The node's firewall allows SSH from the bastion's IP only.

For cloud:

- AWS SSM Session Manager — agent-based, no SSH. Audited.
- Azure Bastion — browser-based, no SSH. Audited.
- GCP Identity-Aware Proxy — IAP for SSH, no public SSH.

## 9. The Container Runtime's Security

The runtime (containerd, CRI-O) has its own security knobs.

### 9.1 The runtime's user

The runtime should run as a **non-root user** (if possible). The default is root (for full functionality). Some runtimes support `rootless` mode (rootless containerd, podman in rootless mode).

Rootless mode has limitations (no `hostNetwork`, no privileged containers, etc.). For most production clusters, rootful is the standard.

### 9.2 The runtime's seccomp default

The runtime can apply a seccomp profile by default. The `RuntimeDefault` profile is in the runtime's source (containerd, CRI-O). With `seccompDefault: true` on the kubelet, the kubelet tells the runtime to apply it.

### 9.3 The runtime's AppArmor

The runtime can apply an AppArmor profile by default. The kubelet passes the Pod's AppArmor annotation to the runtime.

### 9.4 The runtime's user namespace

The runtime can use **user namespaces** to remap container UIDs to host UIDs. The container thinks it's root (UID 0), but the host sees a different UID (e.g. 100000). This is the **rootless** model.

User namespaces are GA in k8s 1.30 (alpha in earlier). They're a significant security improvement for rootless workloads.

## 10. The "NodeRestriction" Admission

The `NodeRestriction` admission plugin restricts what **kubelets can do**. With it enabled:

* A kubelet can only modify **its own Node and Pod status**.
* A kubelet can only add labels / taints to its own Node with the `kubernetes.io/hostname` or `topology.kubernetes.io/zone` prefix.
* A kubelet can't create arbitrary resources.

This prevents a **compromised kubelet** from doing more than reporting its own state.

`NodeRestriction` is enabled by default. It's a key defense.

## 11. The CIS Node Benchmark

The **CIS Kubernetes Benchmark** is a set of recommendations for k8s hardening. The Node-level recommendations are run by `kube-bench` (CIS's official tool).

The Node benchmark covers:

* **File permissions** — kubelet config, container runtime config, PKI files.
* **Process / service config** — kubelet, runtime, auditd.
* **Network** — kubelet port, CNI, etc.
* **Logging** — kubelet logs, audit logs.

`kube-bench` runs as a Pod on each node (or as a Docker container) and reports findings.

```bash
# run kube-bench in a Pod
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml

# run kube-bench in Docker
docker run --pid host --net host -v /etc:/etc:ro -v /var:/var:ro \
  aquasec/kube-bench:latest
```

The output is a list of PASS / FAIL / WARN. The benchmark is the standard for compliance.

## 12. Common Tools (kubelet config, sysctl, auditd)

### 12.1 `kubelet` config

The kubelet's config is the primary way to harden the node. The flags in `config.yaml` are the source of truth.

### 12.2 `sysctl`

For kernel parameters. The `/etc/sysctl.d/` directory is the standard location. `sysctl --system` applies the configs.

### 12.3 `auditd`

The Linux audit daemon. Logs syscall-level events to disk. Useful for forensics.

For k8s, the kubelet and runtime emit their own events (and structured logs). `auditd` is for the host-level events (e.g. file modifications on the kubelet's config).

```bash
# install auditd
apt install auditd
systemctl enable auditd

# a rule: watch /etc/kubernetes/
auditctl -w /etc/kubernetes/ -p wa -k kubernetes-config
```

The `auditd` logs go to `/var/log/audit/audit.log`. Ship them to a SIEM for analysis.

### 12.4 `kubelet-serving-cert-approver` (custom)

For automatic approval of kubelet's serving-cert CSRs. By default, the kubelet's CSR is approved automatically (since k8s 1.8+). For stricter control, custom controllers approve / deny.

## 13. Operations and Debugging

### 13.1 Common commands

```bash
# check the kubelet's config
cat /var/lib/kubelet/config.yaml

# check the kubelet's status
systemctl status kubelet
journalctl -u kubelet --since "1 hour ago"

# check the kubelet's port
ss -tlnp | grep 10250
# or
netstat -tlnp | grep 10250

# check the container runtime's status
systemctl status containerd   # or crio
crictl ps                     # list containers
crictl images                 # list images

# check the kernel parameters
sysctl -a | grep <parameter>

# run kube-bench
docker run --pid host --net host -v /etc:/etc:ro -v /var:/var:ro \
  aquasec/kube-bench:latest
```

### 13.2 The "kubelet won't start" case

```bash
# 1. Check the kubelet's log
journalctl -u kubelet --since "5 minutes ago"

# 2. Check the kubelet's config syntax
kubelet --help 2>&1 | head
# or
kubelet --config=/var/lib/kubelet/config.yaml --dry-run

# 3. Check the container runtime
systemctl status containerd

# 4. Revert the change
# edit /var/lib/kubelet/config.yaml
systemctl restart kubelet
```

### 13.3 The "node is NotReady" case

```bash
# 1. Check the node's status
kubectl describe node <node>

# 2. Check the kubelet's events
journalctl -u kubelet --since "10 minutes ago"

# 3. Check the container runtime
crictl ps
# are the Pods running?

# 4. Check the network
# can the kubelet reach the apiserver?
curl -k https://<apiserver>:6443/healthz
```

## 14. Gotchas and Common Mistakes

### 14.1 The 30+ common mistakes

1. **The kubelet's `:10250` is a powerful API.** Restrict network access. Authn + authz via webhook.

2. **The read-only port `:10255` is unauthenticated.** Disable (`readOnlyPort: 0`).

3. **The kubelet runs as root by default.** This is by design (mounts, cgroups, network). Don't try to run as non-root.

4. **The kubelet's `config.yaml` is parsed at startup.** Changes require a kubelet restart.

5. **`protectKernelDefaults: true` prevents Pods from changing kernel tunables.** A hardening default, k8s 1.27+.

6. **`seccompDefault: true` applies `RuntimeDefault` to all containers without a profile.** A hardening default.

7. **The kubelet's `maxPods: 110` is the per-node Pod limit.** Tune for your node size.

8. **The kubelet's `imageGCHighThresholdPercent: 85`** — at 85% disk used, start evicting images.

9. **The kubelet's `evictionHard`** — the threshold for evicting Pods. Configure for your workload.

10. **The kubelet's `systemReserved` and `kubeReserved`** — the resources reserved for the OS and k8s. Don't allocate 100% to Pods.

11. **The kubelet's `cgroupDriver` must match the runtime's.** Mismatches cause Pods to fail to start.

12. **The kubelet's `runtimeRequestTimeout: 2m`** — the max time for a runtime operation. Default 2m.

13. **The kubelet's `serverTLSBootstrap: true`** — request a serving cert from the apiserver. Required for `rotateCertificates: true`.

14. **The kubelet's `authentication.webhook.cacheTTL: 2m`** — cache auth decisions for 2m. A change in RBAC may not take effect for 2m.

15. **The kubelet's `authorization.webhook.cacheAuthorizedTTL: 5m`** — same, for authz. Negative decisions cached 30s.

16. **The kubelet's `tlsCertFile` and `tlsPrivateKeyFile`** — the serving cert. If not provided, the kubelet generates a self-signed one (which is rejected by most clients).

17. **The kubelet's `rotateCertificates: true`** — auto-rotate via the apiserver's CSR API. Requires the apiserver to have the `RotateKubeletServerCertificate` feature gate.

18. **The kubelet's `imagePullPolicy: IfNotPresent`** is the default for versioned tags. For `:latest`, the default is `Always`.

19. **The kubelet's `resolvConf: /etc/resolv.conf`** — the kubelet's DNS config. Should point to a real DNS server.

20. **The kubelet's `clusterDNS`** — the cluster's DNS service IP. The kubelet configures this in the Pod's `/etc/resolv.conf`.

21. **The kubelet's `hairpinMode: promiscuous-bridge`** — allows Pods to access themselves via the Service IP. Required for some patterns.

22. **The kubelet's `enableDebuggingHandlers: true`** (default) — enables `/debug/...` endpoints. Disable for production.

23. **The kubelet's `enableContentionProfiling: false`** (default) — disables profiling. Enable for debugging only.

24. **The kubelet's `registryBurst` and `registryPullQPS`** — limits on image pulls. Default 10 QPS, burst 10.

25. **The kubelet's `serializeImagePulls: true`** (default) — pull images one at a time. Disable for parallel pulls.

26. **The kubelet's `evictionPressureTransitionPeriod`** — the time between detecting pressure and evicting. Default 5m.

27. **The kubelet's `cpuCFSQuota: true`** — enable CPU CFS quota enforcement. Default true.

28. **The kubelet's `cpuCFSQuotaPeriod: "100ms"`** — the CFS period. Default 100ms.

29. **The kubelet's `topologyManagerPolicy: none`** (default) — the topology manager is for CPU / device alignment. Tune for latency-sensitive apps.

30. **The kubelet's `memorySwap`** — whether Pods can use swap. Default `false`. Enabling has performance implications.

## See also

* [[Kubernetes/concepts/L07-security/20-cluster-hardening|Cluster Hardening]] — the control plane
* [[Kubernetes/concepts/L07-security/16-seccomp-apparmor|Seccomp / AppArmor]] — kernel-level restrictions
* [[Kubernetes/concepts/L07-security/17-runtime-sandboxing|Runtime Sandboxing]] — gVisor / Kata for stronger isolation
* [[Kubernetes/concepts/L07-security/22-compliance-frameworks|Compliance Frameworks]] — CIS / NIST
