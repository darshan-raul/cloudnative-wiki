---
title: Falco Runtime Security & eBPF
tags: [security, falco, ebpf, kubernetes, runtime-security, cncf]
date: 2026-09-06
description: "Falco cloud-native runtime security: eBPF probe architecture, syscall monitoring, container escape detection, custom threat rules, and alert forwarders."
---

# Falco Runtime Security & eBPF 🦅

Falco is the CNCF-graduated open-source standard for cloud-native runtime security. It intercepts Linux kernel syscalls via eBPF probes or kernel modules to detect unauthorized container behavior, shell executions, privilege escalations, and namespace escapes in real time.

---

## 1. Architectural Overview

```mermaid
flowchart TD
    UserSpace["Container / Workload (Pod)"] -->|Executes Syscall (e.g., execve, open, clone)| Kernel["Linux Kernel"]
    Kernel -->|Intercepted by| Probe["Falco eBPF Probe / Modern BPF"]
    Probe -->|Ring Buffer (Zero-Copy)| FalcoEngine["Falco Userspace Daemon"]
    FalcoEngine -->|Evaluates Rules Engine| RuleSet["Falco Rules & Macro Library"]
    RuleSet -->|Generates Alert JSON| Output["Outputs: stdout / syslog / gRPC / Webhook"]
    Output --> Sidekick["FalcoSidekick Forwarder"]
    Sidekick --> Slack["Slack / PagerDuty"]
    Sidekick --> SIEM["Wazuh / Elasticsearch"]
    Sidekick --> AutoKill["Kubernetes Response Engine (Kill Pod / Cordon Node)"]
```

---

## 2. Kernel Drivers: Modern eBPF vs Kernel Module

Falco supports three drivers:

1. **Modern eBPF (`modern-bpf`):** Recommended for Linux >= 5.8. Uses BPF ring buffers, CO-RE (Compile Once – Run Everywhere), requires no external kernel headers or `clang` on nodes.
2. **Traditional eBPF (`bpf`):** Requires kernel headers; works on older 4.14+ kernels.
3. **Kernel Module (`kmod`):** Legacy fallback; requires loading an out-of-tree kernel driver (disallowed in hardened environments like Bottlerocket, Talos, or GKE COS).

---

## 3. Core Rule Structure & Threat Detection

Falco rules use condition expressions evaluating syscall events and container metadata:

### Example 1: Terminal Shell Spawned in Container

```yaml
- rule: Terminal shell in container
  desc: A shell was spawned by a container with an attached terminal
  condition: >
    spawned_process and container
    and shell_procs and proc.tty != 0
    and container_entrypoint
  output: >
    Shell spawned in container (user=%user.name user_loginuid=%user.loginuid
    pod=%k8s.pod.name ns=%k8s.ns.name image=%container.image.repository
    cmd=%proc.cmdline tty=%proc.tty)
  priority: WARNING
  tags: [container, shell, mitre_execution]
```

### Example 2: Container Namespace / Host Escape Attempt

```yaml
- rule: Sensitive Mount or Namespace Escape
  desc: Detect attempt to mount host root or escape via nsenter
  condition: >
    spawned_process and container and
    (proc.name in (nsenter, unshare) or proc.cmdline contains "/host")
  output: >
    Host escape or sensitive tool invoked (user=%user.name pod=%k8s.pod.name cmd=%proc.cmdline)
  priority: CRITICAL
  tags: [mitre_privilege_escalation]
```

### Example 3: Sensitive File Read (`/etc/shadow`)

```yaml
- rule: Read sensitive file untrusted
  desc: Attempt to read sensitive credential files
  condition: >
    open_read and container and
    fd.name in (/etc/shadow, /etc/sudoers) and
    not proc.pname in (passwd, useradd)
  output: >
    Sensitive file accessed (file=%fd.name user=%user.name pod=%k8s.pod.name cmd=%proc.cmdline)
  priority: ERROR
  tags: [filesystem, mitre_credential_access]
```

---

## 4. Deploying Falco on Kubernetes (Helm)

Install Falco as a DaemonSet across all worker nodes using modern eBPF:

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

helm install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  --set driver.kind=modern_ebpf \
  --set tty=true \
  --set falcosidekick.enabled=true \
  --set falcosidekick.webui.enabled=true
```

---

## 5. Automated Remediation with FalcoSidekick & Response Engine

When Falco detects a critical threat (e.g., crypto miner or reverse shell):

1. **FalcoSidekick** forwards JSON alert to **FalcoSidekick-response-engine**.
2. Action triggered automatically:
   - Terminate offending Pod via Kubernetes API (`kubectl delete pod`).
   - Isolate Pod with a quarantine NetworkPolicy.
   - Cordon node if host escape detected.

---

## Related Guides in Wiki

- [[Kubernetes/concepts/L07-security/02-workload-sandboxing/18-runtime-detection|Kubernetes Runtime Detection & Falco]]
- [[Security/endpoint-security/hardening/README|Linux Host Hardening]]
- [[Security/siem/wazuh/README|Wazuh SIEM Security Platform]]
- [[Linux/kernel/README|Linux Kernel Internals & cgroups]]
