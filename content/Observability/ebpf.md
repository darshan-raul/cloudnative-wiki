---
title: eBPF for Observability
tags: [observability, ebpf, linux, kernel, networking, security]
date: 2026-10-10
description: What eBPF is and why it changed observability — the verifier and hooks, what it can see without code changes, the main tools for networking, profiling, tracing and security, and its real limits.
---

# eBPF for Observability

eBPF lets small, verified programs run inside the Linux kernel in response to events — a system call, a packet arriving, a function being entered — without changing kernel source or loading a kernel module. For observability, that means watching what every process on a machine does **from the outside**, with no SDK, no sidecar and no restart.

It is the technology underneath Cilium, Falco, the Amazon VPC CNI's network policy agent, GuardDuty's runtime monitoring and most zero-instrumentation tracing tools.

## How it works

```
 user space                         │ kernel
                                    │
 your tool ── loads bytecode ──────►│ verifier: proves the program is safe
      ▲                             │      │
      │                             │      ▼
      │                             │ JIT: compiles to native machine code
      │                             │      │
      │                             │      ▼
      └──── reads maps / ring buffer◄──── program runs when its hook fires
                                    │      hooks: kprobe, tracepoint, uprobe,
                                    │             XDP, tc, cgroup, LSM, perf event
```

| Piece           | Role                                                                                              |
| :-------------- | :------------------------------------------------------------------------------------------------ |
| **Program**     | Restricted C (or Rust) compiled to eBPF bytecode                                                  |
| **Verifier**    | Rejects anything that could crash or hang the kernel: unbounded loops, invalid memory access      |
| **JIT**         | Turns bytecode into native instructions, so overhead is small                                     |
| **Hooks**       | The events a program attaches to                                                                  |
| **Maps**        | Key-value stores shared between kernel programs and user space                                    |
| **CO-RE / BTF** | "Compile once, run everywhere": type information that lets one binary work across kernel versions |

The verifier is what distinguishes eBPF from a kernel module. A buggy module can panic the machine; a buggy eBPF program is refused at load time. Background on the kernel interfaces involved: [[Linux/kernel/proc-sys|/proc and /sys]], [[Linux/kernel/process-management|process management]] and [[Linux/observability/strace|strace]], which answers some of the same questions with far more overhead.

## Hook points and what they reveal

| Hook                 | Fires on                                          | Used for                                                        |
| :------------------- | :------------------------------------------------ | :-------------------------------------------------------------- |
| Tracepoints          | Stable, documented kernel events                  | Syscalls, scheduler, block I/O, TCP state changes               |
| kprobes / fentry     | Entry or exit of almost any kernel function       | Deep kernel tracing; not a stable interface                     |
| uprobes / USDT       | Functions in user-space binaries and libraries    | Reading TLS plaintext at the library boundary, tracing runtimes |
| XDP                  | A packet, at the driver, before the network stack | Very fast filtering and load balancing                          |
| tc (traffic control) | Packets entering or leaving an interface          | Container networking, policy, flow visibility                   |
| cgroup hooks         | Socket operations per cgroup                      | Per-container network accounting and policy                     |
| LSM hooks            | Security decisions                                | Enforcement, not only detection                                 |
| perf events          | Timer or hardware counter                         | Sampling profilers                                              |

## What you get without touching the application

**Network visibility.** Every connection, with source and destination workload, bytes, retransmits and latency. Because the program sees packets and sockets, it can build a service map and golden-signal metrics for HTTP, gRPC, DNS and Kafka without any instrumentation. Tools: Cilium Hubble, Pixie, Grafana Beyla, Coroot. The networking model underneath is in [[Kubernetes/concepts/L04-services-networking/06-cni|CNI]] and [[Linux/virtualization/network-namespace|network namespaces]].

**Continuous profiling.** A sampling profiler attached to a timer captures stack traces for every process on the node at a few percent overhead or less. The result is a flame graph of where CPU time goes fleet-wide, always on. Tools: Parca, Pyroscope's eBPF profiler, the OpenTelemetry eBPF profiler.

**Auto-instrumentation.** By hooking the kernel's socket calls and common libraries, tools generate request [[Observability/tracing|traces]] and RED [[Observability/prometheus/README|metrics]] for services that have none. This is a fast way to get baseline telemetry for legacy or third-party workloads. Grafana Beyla and the OpenTelemetry eBPF instrumentation project emit standard OTLP.

**Security observability.** Process executions, file opens, privilege changes and network connections, attributed to the container and pod that made them. Tools: Falco, Tetragon, Tracee. See [[Security/endpoint-security/falco/README|Falco]] and [[Kubernetes/concepts/L07-security/02-workload-sandboxing/18-runtime-detection|runtime detection]].

**Ad hoc investigation.** `bpftrace` and the BCC tools answer one-off questions on a live system:

```bash
# Which processes are opening which files?
bpftrace -e 'tracepoint:syscalls:sys_enter_openat { printf("%s %s\n", comm, str(args->filename)); }'

# Block I/O latency as a histogram
biolatency

# New TCP connections, with process and destination
tcpconnect

# Short-lived processes that a `ps` loop would miss
execsnoop
```

These are the modern successors to much of [[Linux/tools/process-tools|the classic process tooling]], and they are the right instruments for the questions in [[Linux/troubleshooting/systematic-debugging|systematic debugging]].

## eBPF in Kubernetes networking

Cilium replaces `kube-proxy` and [[Linux/networking/iptables|iptables]] with eBPF programs and maps. Service load balancing becomes a hash-map lookup rather than a linear walk through rule chains, and network policy is enforced by identity rather than IP address. The same data path provides the flow logs. Managed platforms use the idea selectively: on EKS, the VPC CNI enforces [[Kubernetes/eks/networking/vpc-cni/network-policies|network policy]] with eBPF, and [[Kubernetes/eks/security/guardduty|GuardDuty]] uses an eBPF agent for runtime findings.

## Limits

eBPF is powerful, and it is oversold. Be clear about what it cannot do.

| Limitation                    | Why it matters                                                                                                                                                                   |
| :---------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **No application context**    | It sees an HTTP request, not that it was a checkout for a premium customer. Business attributes need SDKs.                                                                       |
| **Trace propagation is hard** | Linking spans across services requires injecting headers into requests, which is possible only for some protocols and languages. Many eBPF "traces" are per-hop, not end to end. |
| **Encrypted traffic**         | The kernel sees ciphertext. Plaintext requires uprobes on the TLS library, which differ per language and break with statically linked or custom crypto.                          |
| **Kernel dependency**         | Features depend on kernel version and configuration; very old or locked-down kernels are excluded.                                                                               |
| **Privilege**                 | Loading programs needs `CAP_BPF` and related capabilities — effectively root on the node. The agent is a high-value target. See [[Linux/security/capabilities\|capabilities]].   |
| **Not on every platform**     | No node access means no eBPF: serverless containers such as [[Kubernetes/eks/compute/fargate/README\|Fargate]], and some sandboxed runtimes.                                     |
| **Overhead is low, not zero** | A probe on a very hot path, or copying payloads to user space, is measurable.                                                                                                    |
| **Linux only**, in practice   | eBPF for Windows exists but the ecosystem is Linux.                                                                                                                              |

## How it fits with OpenTelemetry

They are complementary, not competing:

|                   | eBPF                                | SDK instrumentation ([[Observability/opentelemetry/overview\|OpenTelemetry]]) |
| :---------------- | :---------------------------------- | :---------------------------------------------------------------------------- |
| Effort            | Deploy one DaemonSet                | Per-service work                                                              |
| Coverage          | Everything on the node, immediately | Only what has been instrumented                                               |
| Depth             | Network and system boundary         | Inside the application, with business context                                 |
| End-to-end traces | Partial                             | Complete                                                                      |
| Runs where        | On nodes you control                | Anywhere the code runs                                                        |

A sensible sequence is eBPF first for instant breadth — service maps, golden signals, profiles — and SDK instrumentation for the services where depth pays off. Both can export OTLP into the same backends ([[Observability/lgtm-stack|the LGTM stack]] or any other).

## Related

- [[Observability/fundamentals|Observability fundamentals]]
- [[Linux/kernel/README|Linux kernel section]]
- [[Linux/networking/network-performance-tuning|Network performance tuning]]
- [[Linux/security/seccomp|seccomp]] — classic BPF used for syscall filtering
- [ebpf.io](https://ebpf.io/what-is-ebpf/)

## Further reading

- [EBPF (video)](https://youtu.be/xDrygKuR1ZM)
- [EBPF (video)](https://www.youtube.com/watch?v=jdQAU4DTsGo)

## Across the wiki

- [[Kubernetes/eks/networking/vpc-cni/README|Amazon VPC CNI]] — pod networking (Kubernetes)
- [[Azure/compute/aks/networking-cni|AKS Networking Deep Dive — Azure CNI, CNI Overlay, and Dynamic Pod IP Allocation]] — pod networking (Azure)
- [[GCP/compute/gke/networking|GKE Networking Deep Dive — Datapath V2, Alias IPs & Gateway API]] — pod networking (GCP)
