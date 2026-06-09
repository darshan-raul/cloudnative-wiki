# Runtime Detection (Falco, Tetragon)

*"https://falco.org/ | https://cilium.io/products/#:~:text=Tetragon"*

**Runtime detection** is the practice of **observing what workloads actually do** at runtime and **alerting on suspicious behavior**. It's the last line of defense: when the workload is compromised, runtime detection sees the abnormal behavior (e.g. shell spawned in a Pod, sensitive file read, unexpected network call) and alerts. **Falco** and **Tetragon** are the two leading tools. Both use **eBPF** (extended Berkeley Packet Filter) to observe kernel-level events with low overhead.

### Table of Contents

1. [The Threat Runtime Detection Solves](#1-the-threat-runtime-detection-solves)
2. [Prevention vs Detection](#2-prevention-vs-detection)
3. [eBPF — the Foundation](#3-ebpf--the-foundation)
4. [Falco Architecture](#4-falco-architecture)
5. [Falco Rules](#5-falco-rules)
6. [Falco Outputs](#6-falco-outputs)
7. [Tetragon Architecture](#7-tetragon-architecture)
8. [Tetragon TracingPolicies](#8-tetragon-tracingpolicies)
9. [Tetragon vs Falco — When to Use Which](#9-tetragon-vs-falco--when-to-use-which)
10. [Common Detections](#10-common-detections)
11. [The "in-cluster" vs "sidecar" deployment](#11-the-in-cluster-vs-sidecar-deployment)
12. [Operations and Debugging](#12-operations-and-debugging)
13. [Gotchas and Common Mistakes](#13-gotchas-and-common-mistakes)

---

## 1. The Threat Runtime Detection Solves

Runtime detection answers: **"what is this workload actually doing?"**

The shift-left defenses (image scanning, PSS, NetworkPolicy, mTLS, seccomp) all happen **before or at admission**. They prevent known-bad behavior. They don't help when:

* The workload is compromised at runtime (zero-day in the app).
* The credentials are stolen (a leaked Secret).
* The defenses are misconfigured (NetworkPolicy has a hole).
* The attacker uses a legitimate capability (e.g. shells out to bash to download malware).

Runtime detection sees **the actual behavior**: the syscall, the file read, the network call. It detects anomalies that prevention missed.

### 1.1 The example

A Pod is running `nginx`. The expected behavior:

* Read config files.
* Serve HTTP requests.
* Write access logs.

An unexpected behavior:

* `bash` is spawned (shell).
* A file in `/etc/shadow` is read.
* A connection to an external IP is made.

Runtime detection sees the `bash` spawn, the `/etc/shadow` read, the external connection. It alerts: "this Pod is doing something it shouldn't."

## 2. Prevention vs Detection

The "security onion" model:

```
Prevention (before / at admission):
  - Image scanning (Trivy)
  - Signed images (cosign)
  - PSS / SecurityContext
  - NetworkPolicy
  - mTLS (service mesh)
  - RBAC

Detection (at runtime):
  - Falco / Tetragon
  - Audit logs (apiserver)
  - SIEM (Splunk / Elastic / Datadog)

Response (after detection):
  - Alert → on-call
  - Forensics (audit logs, Falco events)
  - Mitigation (cordon node, evict Pod, rotate Secrets)
```

Prevention is **stronger** (the bad thing doesn't happen). Detection is **broader** (catches what prevention missed). You need both.

The analogy:

* **Prevention** — locks on the doors. Most burglars can't get in.
* **Detection** — alarms. When a burglar gets in (locks failed), the alarm goes off.

## 3. eBPF — the Foundation

*"https://ebpf.io/"*

**eBPF (extended Berkeley Packet Filter)** is a Linux kernel technology that lets **user-space programs run safely in the kernel**. The user-space program is verified by the kernel (no loops, bounded memory access) and runs at near-native speed.

eBPF is used for:

* **Networking** — Cilium uses eBPF for kube-proxy replacement, NetworkPolicy enforcement, load balancing.
* **Observability** — Pixie, Parca use eBPF to capture metrics without instrumentation.
* **Security** — Falco, Tetragon, Tracee use eBPF to capture syscalls, file events, network events.

For runtime detection, eBPF is the **perfect tool**:

* **Sees all syscalls** — every `open`, `read`, `write`, `connect`, `exec` is visible.
* **Low overhead** — eBPF programs run in the kernel; the cost is small.
* **No instrumentation** — the workload's code doesn't change. eBPF is transparent.
* **Per-container or per-process** — the eBPF program can filter by container ID, cgroup, etc.

The alternative (without eBPF) is to read `/proc` periodically, or to use ptrace, or to use auditd. eBPF is faster, more flexible, and the modern way.

## 4. Falco Architecture

*"https://falco.org/"*

**Falco** is a CNCF-graduated runtime detection tool. It was created by Sysdig and is now a top-level CNCF project.

```
┌──────────────────────────────────────────┐
│  Host Linux Kernel                       │
│  ┌──────────────────────────────────┐    │
│  │  eBPF probe (or kernel module)   │    │
│  │  captures syscalls, file events, │    │
│  │  network events                  │    │
│  └────────────┬─────────────────────┘    │
│               │ (shared ring buffer)     │
│               ▼                          │
│  ┌──────────────────────────────────┐    │
│  │  falco (userspace)               │    │
│  │  reads events, evaluates rules,  │    │
│  │  emits alerts                    │    │
│  └────────────┬─────────────────────┘    │
│               │                          │
└───────────────┼──────────────────────────┘
                │
                ▼
        Outputs (stdout, file, syslog, HTTP, Kafka, ...)
```

Components:

* **eBPF probe** (or kernel module) — captures kernel events. eBPF is the modern, kernel-version-dependent option. The kernel module is the older, more portable option.
* **falco** (userspace) — reads events from the shared ring buffer, evaluates rules, emits alerts.
* **Outputs** — the alerts go to stdout (default), files, syslog, HTTP webhooks, Kafka, etc.

In k8s, Falco is typically deployed as a **DaemonSet** (one Pod per node). Each Pod captures events for its node.

## 5. Falco Rules

Falco rules are YAML files that define **what to detect**:

```yaml
- rule: Terminal shell in container
  desc: Detect shell spawned in a container
  condition: >
    spawned_process and container and
    proc.name in (bash, sh, zsh, fish)
  output: >
    Shell spawned in container
    (user=%user.name command=%proc.cmdline container=%container.name
     image=%container.image.repository:%container.image.tag)
  priority: WARNING
  tags: [process, container]

- rule: Read sensitive file
  desc: Detect reads of /etc/shadow
  condition: >
    open_read and container and
    fd.name startswith /etc/shadow
  output: >
    Sensitive file read
    (user=%user.name file=%fd.name container=%container.name)
  priority: CRITICAL
  tags: [file, container]
```

The structure:

* **`rule`** — the rule's name (used for suppression, etc.).
* **`desc`** — description.
* **`condition`** — a Falco filter expression. The rule fires when the expression is true.
* **`output`** — the alert message. Uses `%` placeholders.
* **`priority`** — DEBUG / INFO / NOTICE / WARNING / ERROR / CRITICAL / ALERT / EMERGENCY.
* **`tags`** — labels for organization.

The **condition** is the rule's logic. Falco has a rich set of fields:

* `proc.name`, `proc.cmdline`, `proc.pid`, `proc.ppid`
* `fd.name` (file path), `fd.type` (file, socket, etc.)
* `container.name`, `container.image.repository`, `container.image.tag`
* `k8s.pod.name`, `k8s.ns.name`, `k8s.deployment.name`
* `evt.type` (the event type — `open`, `read`, `connect`, `execve`, etc.)
* `user.name`, `user.uid`

The condition uses **boolean operators and functions**:

* `and`, `or`, `not`
* `in (...)` — match against a list
* `startswith`, `endswith`, `contains`
* `count() > N` — count of events
* `>`, `<`, `=`, `!=`

## 6. Falco Outputs

The alert is emitted via **output channels**:

```yaml
# falco.yaml
stdout_output:
  enabled: true

file_output:
  enabled: true
  filename: /var/log/falco/events.log
  keep_alive: false

http_output:
  enabled: true
  url: http://alert-collector:8080/alert
  method: POST

syslog_output:
  enabled: true

kafka_output:
  enabled: true
  brokers: kafka:9092
  topic: falco-alerts
```

Multiple outputs can be enabled. The standard setup:

* **stdout** for the kubelet's log (kubectl logs).
* **file** for local persistence.
* **http / syslog / kafka** for shipping to a SIEM.

For k8s, **Falco Sidekick** is a common add-on — it formats the alerts and ships to multiple destinations (Elasticsearch, Loki, Slack, PagerDuty, etc.).

## 7. Tetragon Architecture

*"https://cilium.io/products/"*

**Tetragon** is Cilium's runtime detection tool. It's tightly integrated with Cilium (and works without it, but with less context). Like Falco, it uses eBPF.

```
┌──────────────────────────────────────────┐
│  Host Linux Kernel                       │
│  ┌──────────────────────────────────┐    │
│  │  eBPF programs (per-container)   │    │
│  │  syscalls, file events, network  │    │
│  │  events, function calls          │    │
│  └────────────┬─────────────────────┘    │
│               │ (perf events / ring buf)  │
│               ▼                          │
│  ┌──────────────────────────────────┐    │
│  │  tetragon agent                  │    │
│  │  reads events, evaluates         │    │
│  │  TracingPolicies, takes action   │    │
│  └────────────┬─────────────────────┘    │
│               │                          │
└───────────────┼──────────────────────────┘
                │
                ▼
        Outputs (stdout, file, hubble, k8s events)
```

Tetragon's key difference from Falco: **Tetragon can take action in-kernel, not just observe**. With a `TracingPolicy`, Tetragon can:

* **Block** a syscall (e.g. block `execve` for non-allowed binaries).
* **Signal** a process (e.g. SIGKILL a process that does a forbidden action).
* **Trace** function calls (e.g. trace specific libc functions).

This is **enforcement at the syscall level**, not just detection. Tetragon is closer to "policy enforcement" than "just detection".

## 8. Tetragon TracingPolicies

A `TracingPolicy` is a CRD that defines what to trace and what to do:

```yaml
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata: { name: block-spawn-shell }
spec:
  kprobes:
  - call: "security_bpf_prog"  # or syscall
    syscall: true
    args:
    - index: 0
      type: "nop"
  tracepoints:
  - subsystem: "sched"
    event: "sched_process_exec"
    args:
    - index: 0
      type: "nop"
  filters:
  - type: "tracepoint"
    matchArgs:
    - index: 0
      operator: "Equal"
      values:
      - "bash"
      - "sh"
  actions:
  - type: "signal"
    args:
    - sig: "SIGKILL"
```

This policy **traces `execve` syscalls** and **kills processes** that are `bash` or `sh`. It's a strict "no shell in container" enforcement.

Tetragon's `TracingPolicy` is more complex than Falco's rules. The power is in the action (kill, block, signal). The complexity is the eBPF-specific config (kprobes, tracepoints, maps).

## 9. Tetragon vs Falco — When to Use Which

| | Falco | Tetragon |
|---|---|---|
| **Primary purpose** | Detection (observe + alert) | Detection + enforcement (observe + alert + act) |
| **Rule language** | YAML (Falco filter syntax) | YAML (`TracingPolicy`, eBPF-specific) |
| **Action** | Alert (no action) | Alert, signal, block |
| **Integration** | Standalone | Cilium-native (works without) |
| **eBPF dependency** | Yes | Yes |
| **Kernel support** | Broad (kernel module for older) | Modern kernels (5.x+) |
| **Maturity** | CNCF Graduated, very mature | Mature, growing |
| **Rule library** | Huge (Falco rules repo, hundreds of rules) | Smaller, growing |
| **Performance** | Low overhead | Low overhead |

The decision:

* **Use Falco** for **detection-first** clusters. The rule library is huge, the community is mature, the integration is simple.
* **Use Tetragon** if you already run **Cilium** (it's a natural extension) or want **enforcement** (block, signal).
* **Use both** — Falco for broad detection, Tetragon for targeted enforcement.

For most clusters, **Falco is the easier starting point**. Add Tetragon if you need enforcement.

## 10. Common Detections

### 10.1 "Shell in container"

```yaml
# Falco
- rule: Terminal shell in container
  condition: spawned_process and container and proc.name in (bash, sh, zsh, fish)
  output: "Shell spawned in container (command=%proc.cmdline container=%container.name)"
  priority: WARNING
```

Most app containers should never spawn a shell. If they do, it's likely a compromise (or a debugging session gone wrong).

### 10.2 "Read sensitive file"

```yaml
- rule: Read /etc/shadow
  condition: open_read and container and fd.name = "/etc/shadow"
  output: "Read /etc/shadow (user=%user.name container=%container.name)"
  priority: CRITICAL
```

A read of `/etc/shadow` (or `/etc/passwd`, `/root/.ssh/id_rsa`, etc.) is a red flag.

### 10.3 "Unexpected network connection"

```yaml
- rule: Outbound connection to suspicious IP
  condition: outbound and container and not fd.sip.name in (allowed_egress_ips)
  output: "Outbound connection to %fd.sip.name (container=%container.name)"
  priority: WARNING
```

Detect egress to non-allowed destinations. (Use a `list` with the allowed IPs.)

### 10.4 "Container namespace changes"

```yaml
- rule: Container namespace change
  condition: evt.type = unshare and evt.dir = < and container
  output: "Container namespace change (container=%container.name)"
  priority: WARNING
```

A process inside a container changing namespaces is a sign of an escape attempt.

### 10.5 "Cryptocurrency miner"

```yaml
- rule: Crypto miner
  condition: >
    spawned_process and container and
    proc.name in (minerd, xmrig, minergate, c3pool)
  output: "Crypto miner detected (command=%proc.cmdline container=%container.name)"
  priority: CRITICAL
```

A process name matching a known miner is a strong indicator of compromise.

## 11. The "in-cluster" vs "sidecar" deployment

### 11.1 In-cluster (DaemonSet)

The standard deployment for Falco and Tetragon:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata: { name: falco }
spec:
  selector: { matchLabels: { app: falco } }
  template:
    metadata: { labels: { app: falco } }
    spec:
      hostPID: true       # to see all processes
      hostNetwork: true   # to see all network
      containers:
      - name: falco
        image: falcosecurity/falco:latest
        # ...
```

The Pod runs on every node, with `hostPID` and `hostNetwork` to see all processes and network on the host. The eBPF probe is in the kernel; the userspace reads events.

### 11.2 Sidecar

For per-workload detection (rare):

```yaml
spec:
  containers:
  - name: app
    image: myapp:1.0
  - name: falco-sidecar
    image: falcosecurity/falco:latest
    # ...
```

The sidecar only sees its own Pod's events. This is **less useful** than DaemonSet (you want cluster-wide detection, not per-Pod).

DaemonSet is the standard. Sidecar is for special cases (e.g. a high-security workload that needs dedicated monitoring).

## 12. Operations and Debugging

### 12.1 Common commands

```bash
# check the Falco / Tetragon pods
kubectl -n falco get pods
# or
kubectl -n cilium get pods -l k8s-app=tetragon

# tail the alerts
kubectl -n falco logs -l app=falco -f

# check the rules
kubectl -n falco exec <falco-pod> -- cat /etc/falco/falco_rules.local.yaml

# trigger a test event
# (run a shell in a pod)
kubectl run test --image=alpine --rm -it -- sh
# Falco should alert
```

### 12.2 The "Falco isn't alerting" case

Falco is running but no alerts.

```bash
# 1. Is the eBPF probe loaded?
kubectl -n falco logs <falco-pod> | grep -i "probe\|ebpf"
# should say "probe loaded" or similar

# 2. Is the rule fired?
# (in dry-run mode, the rule's condition is logged)
# set falco config:
# - "log_level: debug"
# - "dry_run: true"

# 3. Is the output reaching the SIEM?
# check the SIEM for the expected events

# 4. Is the rule correct?
# test the condition manually with `falco --validate`
```

### 12.3 The "Falco is too noisy" case

Falco alerts on every container start, every health check, every log read.

```bash
# 1. Use the `exceptions` feature
# define exceptions to the rules
# e.g. "don't alert on health checks from the k8s service"

# 2. Use `priority` filters
# only alert on WARNING / CRITICAL

# 3. Use `tags` to filter
# only deliver certain tags to the SIEM
```

## 13. Gotchas and Common Mistakes

### 13.1 The 25+ common mistakes

1. **Falco / Tetragon are detection, not prevention.** They alert on bad behavior. They don't stop it (Tetragon can, but it's a different mode).

2. **The eBPF probe is per-kernel-version.** A kernel upgrade may break the probe. The DaemonSet needs to be updated.

3. **The kernel module is the fallback** for older kernels. eBPF is preferred but requires Linux 4.17+.

4. **Falco's rule library is huge.** Start with the defaults, add custom rules as needed. Don't write rules from scratch.

5. **A rule with a too-broad condition fires too often.** Be specific. "Read /etc/shadow" is good; "read any file" is too broad.

6. **Tetragon's `TracingPolicy` is more complex than Falco's rules.** eBPF-specific concepts (kprobes, tracepoints, maps) require learning.

7. **The `hostPID: true, hostNetwork: true` on the DaemonSet is required.** Without it, the agent doesn't see all processes / network on the host.

8. **The eBPF program runs in the kernel.** A bug in the eBPF code can crash the kernel. Use the upstream eBPF programs (Cilium, Falco), not custom ones.

9. **Falco's outputs are configurable.** A common mistake is enabling all outputs (stdout, file, http, kafka) and wondering why the disk is full.

10. **The alert format is not standardized.** Falco's output is Falco-specific. SIEMs need parsers.

11. **Falco Sidekick is the standard output shim.** It formats and ships to multiple destinations. Use it.

12. **Tetragon requires Cilium's CRDs.** Even if you don't run Cilium as a CNI, Tetragon needs the `cilium.io` API group.

13. **The `TracingPolicy` actions are powerful.** A misconfigured action can kill processes. Test in non-prod first.

14. **The `signal: SIGKILL` action kills the process immediately.** Use `SIGTERM` for graceful shutdown (the process can clean up).

15. **The kprobe / tracepoint names are kernel-version specific.** A tracepoint may not exist on all kernels. Use generic ones.

16. **The `args` in a `TracingPolicy` are positional.** The first arg of `execve` is the filename, the second is argv. Know the syscall signature.

17. **The eBPF program has a size limit (~1M instructions for the verifier).** Complex policies may exceed this. Test.

18. **The `hostPath` for the kernel headers is required** for the eBPF probe to compile. The DaemonSet must mount the right path.

19. **The performance overhead is per-event.** A busy node (1000s of syscalls / sec) has measurable overhead. Benchmark.

20. **The alerts are not deduplicated by default.** A 1000-syscall event fires 1000 alerts. Use the `exceptions` feature to dedup.

21. **The `priority` is not the alert's severity.** It's a label. SIEMs map it to severity.

22. **The `tags` are for organization, not filtering.** The SIEM gets all alerts (unless filtered by config).

23. **The `condition` language is specific to Falco.** Not a standard. Learn it.

24. **The `proc.cmdline` may be very long** (full command line + args). Truncate in the output.

25. **The `container.image` is the image reference at the time of the event.** If the Pod's image is updated, the new image is used.

26. **A `priority: DEBUG` alert is usually suppressed.** Use DEBUG for noise reduction.

27. **A `priority: CRITICAL` alert is for known-bad.** Use sparingly (alert fatigue is real).

28. **The `exceptions` feature is for known-OK exceptions.** "The k8s service account can read /var/run/secrets" is an exception.

29. **The `output` is a Go template.** Variables are in `%var` form. Format carefully.

30. **The eBPF probe's events are not in the audit log.** The audit log is for apiserver requests. Falco / Tetragon are for workload-level events. Different layers.

## See also

* [[Kubernetes/concepts/L07-security/15-audit-logging|Audit Logging]] — apiserver-level audit
* [[Kubernetes/concepts/L07-security/17-runtime-sandboxing|Runtime Sandboxing]] — gVisor / Kata as alternatives
* [[Kubernetes/concepts/L07-security/16-seccomp-apparmor|Seccomp / AppArmor]] — the prevention layer
* [[Kubernetes/concepts/L07-security/19-image-hardening|Image Hardening]] — reduce attack surface before runtime
