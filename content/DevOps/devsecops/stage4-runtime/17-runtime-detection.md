---
title: "M17: Runtime Detection & Response"
tags: [devsecops, stage4, runtime, falco, wazuh, detection, runtime-protection, shift-right]
date: 2026-06-16
description: Module 17 of 20 — runtime detection for shift-right. Falco for K8s, eBPF-based detection, anomaly response, and the SOC playbook for containerized workloads.
---

# M17: Runtime Detection & Response

Stages 0–3 are shift-left: catch the issue before it ships. Stage 4 is shift-right: catch the issue *after* it ships, when an attacker is exploiting it. This module covers runtime detection (Falco, eBPF, Wazuh), the response pattern, and the integration with the rest of the pipeline.

## Learning Objectives

By the end of this module you should be able to:

  - Deploy Falco for K8s runtime detection
  - Read and tune Falco rules
  - Design a runtime-detection response playbook
  - Integrate runtime alerts with the SIEM
  - Distinguish detection (M17) from compliance audit (M18)

## 1. Shift-Right: The Other Half

```
  Code       Build      Deploy      Runtime
  ----       -----      ------      -------
  SAST       Image      OIDC        Falco
  Secrets    IaC        Sign        eBPF
  SCA        Policy     SLSA        Wazuh
  (M05-M08)  (M09-M11)  (M12-M15)   (M17)
                                ↑↑↑
                                here
```

Shift-left catches the issue at design/code/build time. Shift-right catches the issue at runtime, when:
  - A new CVE was disclosed between build and deploy
  - A workload behaves anomalously even though it passed all scans
  - An attacker is exploiting a zero-day
  - A misconfiguration was missed by IaC scanning

The two halves are not redundant; they are complementary. Shift-left is for *known* issues. Shift-right is for *everything else*.

## 2. The Detection Stack

Three layers, each with different tradeoffs:

### Layer 1: eBPF Kernel-Level Detection

eBPF (extended Berkeley Packet Filter) runs sandboxed programs in the Linux kernel. It can observe:
  - Syscalls (open, read, execve, connect, setuid, ...)
  - Network activity (TCP connect, DNS queries)
  - File access (read, write, chmod)

The advantages: no instrumentation in the app, no sidecar, very low overhead, sees everything. The disadvantage: kernel-level; requires kernel expertise to extend.

### Layer 2: Container/K8s-Level Detection

Tools that hook into the container runtime (Falco for K8s, Aqua, Sysdig, Prisma Cloud):
  - Syscall tracing via kernel module or eBPF
  - K8s API audit log monitoring
  - Container image metadata
  - Network policy violations

### Layer 3: Application-Level Detection

Inside the app or as a sidecar:
  - Custom audit logs
  - Anomaly detection on app behavior
  - Auth log analysis
  - API call patterns

The full stack: eBPF (kernel) + K8s-aware tool (Falco) + app logs → SIEM → alert.

## 3. Falco: The Default for K8s

Falco is the CNCF-incubated runtime detection tool. Originally created by Sysdig, now a graduated project. The killer feature: a huge library of community rules that detect common attack patterns in containers.

### Install

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm install falco falcosecurity/falco --namespace falco --create-namespace \
  --set tty=true \
  --set falco.json_output=true \
  --set falco.http_output.enabled=true \
  --set falco.http_output.url="https://falco-sidekick.example.com"
```

Or use Falco Sidekick for richer output routing:

```bash
helm install falco-sidekick falcosecurity/falco-sidekick --namespace falco
```

Sidekick can route to Elasticsearch, Loki, Slack, PagerDuty, OpsGenie, and more.

### What Falco Detects (Default Rules)

  - Shell spawned in container (potential RCE)
  - Sensitive file read (/etc/shadow, /proc/1/environ)
  - Outbound connection to known-bad IP
  - Crypto miner indicators
  - Unexpected process in container
  - Privilege escalation attempts
  - Container namespace escape attempts
  - And ~150+ more

### A Falco Rule

```yaml
- rule: Terminal shell in container
  desc: A shell was spawned in a container, which may indicate a compromise
  condition: >
    spawned_process and container and
    proc.name in (bash, sh, zsh, ash, csh, ksh)
  output: >
    Shell spawned in container (user=%user.name command=%proc.cmdline
    container=%container.name image=%container.image.repository:%container.image.tag)
  priority: WARNING
  tags: [process, mitre_execution]
```

This rule fires when a shell is spawned in any container. Most production containers don't run shells (distroless). When the rule fires, it's signal.

### Tuning Falco

Default rules produce noise. The tuning process:

  - **Week 1** — Run with defaults; collect all alerts
  - **Week 2** — Classify: true positive, false positive, accepted risk
  - **Week 3** — Suppress false positives via exceptions:

```yaml
- rule: Terminal shell in container
  exceptions:
    - name: known-dev-tools
      fields: [container.name]
      comps: [=]
      values: [[dev-tools, debugger, ctr-tools]]
```

  - **Week 4** — Custom rules for your environment

### Custom Rules

The rules that catch real attacks in your environment are the ones you write. Examples:

```yaml
# Detect exec into a specific sensitive pod
- rule: Exec into production-db
  condition: >
    k8s_audit and
    ka.target.resource = "pods/exec" and
    ka.response.status.code = 200 and
    ka.target.namespace = "prod" and
    ka.req.pod = "production-db"
  output: "Production DB pod exec by user=%ka.user.name"
  priority: CRITICAL
```

## 4. eBPF Direct: Tetragon, Inspektor Gadget, Pixie

For teams that want eBPF without Falco's rule DSL, the alternatives:

### Tetragon (Cilium)

Kernel-level eBPF, but with a more powerful policy language (YAML, not DSL). Tracing policies can be version-controlled.

```yaml
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: block-spawned-shell
spec:
  kprobes:
    - call: "security_bpf_prog"
      syscall: false
      args:
        - index: 0
          type: "nop"
  tracepoints:
    - subsystem: "sched"
      event: "sched_process_exec"
      args:
        - index: 0
          type: "nop"
  kprobeMaxActive: 512
```

Tetragon can also *enforce* — block the syscall, not just alert.

### Inspektor Gadget

Collection of eBPF-based debugging tools. Good for ad-hoc investigation, less for production.

### Pixie (New Relic)

eBPF-based observability for K8s. Strong on visibility, weaker on enforcement.

For production, Falco (detection) + Tetragon (enforcement) is the modern stack.

## 5. Wazuh for Runtime SIEM

Wazuh is covered in [[Security/siem/wazuh/README]] in detail. The DevSecOps integration:

  - Falco alerts → Sidekick → Wazuh indexer
  - K8s audit logs → Wazuh
  - CloudTrail → Wazuh
  - Wazuh correlates: a Falco "shell in container" + a CloudTrail "IAM key used from new IP" = critical alert

The pipeline that produced the alert becomes part of the detection story. An alert in production is fed back into M19 (incident response in CI).

## 6. The Runtime Response Playbook

An alert fires. The clock starts. The on-call engineer:

```
00:00  Alert: "Shell spawned in container prod/my-app-abc123"
00:02  Acknowledge; open incident channel
00:05  Triage: is this expected (debug container, CI build) or unexpected?
       - kubectl describe pod prod/my-app-abc123
       - kubectl logs prod/my-app-abc123 --previous
       - Falco Sidekick shows process tree
00:10  If expected: silence the alert; add an exception
       If unexpected: assume compromise; go to step 7
00:15  Containment options:
       a. Cordon and drain the node (limits lateral movement)
       b. Snapshot the pod's filesystem and memory (forensics)
       c. Apply a network policy that blocks egress (call-home prevention)
       d. Revoke any service account tokens the pod may have used
00:25  Eradication:
       a. Roll the deployment to a known-good image
       b. Rotate all secrets the pod had access to
       c. If RCE suspected: rebuild the node
00:35  Recovery:
       a. Restore service from a clean deployment
       b. Verify health and traffic
00:45  Postmortem:
       a. Root cause: how did the shell get there?
       b. Detection: was the alert timely? Was the rule right?
       c. Response: what slowed the response?
       d. Improvements: file stories for each
```

The playbook is a document, but the document only matters if it has been drilled. Run a chaos game day quarterly (M19).

## 7. The Feedback Loop to CI

The most valuable output of runtime detection is not the alert — it is the *learning* that goes back to the pipeline.

```
  Runtime detection
       |
       +-- Real attack seen in prod
       |     → write a Falco rule
       |     → write a SAST rule
       |     → write an IaC rule
       |     → add a CI gate
       |
       +-- False positive in prod
       |     → tune the rule
       |     → add an exception
       |
       +-- Anomaly indicates a vulnerability
             → file CVE for the dep
             → SBOM re-scan
             → trigger emergency patch
```

This is the "shift-left" half of shift-right: the runtime teaches the build what to look for.

## 8. Network Detection at Runtime

Beyond the host, network-level detection catches:
  - East-west traffic between compromised pods
  - Crypto miner pool connections
  - Data exfiltration patterns
  - DNS tunneling

Tools:
  - **Cilium** with Hubble for L3/L4 visibility
  - **Calico** with flow logs
  - **Service mesh** (Istio, Linkerd) sidecar metrics
  - **eBPF** in host networking namespace

The pattern: every pod-to-pod call is logged, anomaly detection flags unusual patterns.

## 9. The Cost of Runtime Detection

| Tool | Cost | Trade-off |
| ---- | ---- | --------- |
| Falco (OSS) | Free, ops overhead | You run it, you tune it |
| Falco (managed via Sidekick + SIEM) | SIEM ingest cost | Higher signal, lower ops |
| Tetragon | Free, eBPF expertise required | More powerful, harder |
| Commercial runtime protection (Aqua, Sysdig, Prisma) | $$$ per node | Less ops, vendor lock |

For most orgs, Falco + Wazuh is the right starting point. Add Tetragon when you need enforcement, not just detection.

## 10. Common Anti-Patterns

| Anti-pattern | Symptom | Fix |
| ------------ | ------- | --- |
| Run with default rules forever | Alert fatigue | Tune in week 2–4 |
| Alert to a Slack channel only | Alerts get scrolled past | Page on critical |
| No runbook for the alert | Every alert is researched from scratch | Playbook per top-10 alerts |
| No feedback to CI | Same incident twice | File a story for each new alert type |
| Detection only, no enforcement | Attacker has 10 minutes of dwell time | Add Tetragon for blocking |
| Runtime only, no shift-left | Catching everything at runtime is expensive | Use both |

## 11. Self-Check

  1. What is your mean time to detect (MTTD) for a container compromise? Pick a number; it's a baseline.
  2. For the top 3 alerts in the last month, is there a runbook? If not, write one this week.
  3. For each alert, is there a story filed to prevent it from happening again?

## 12. Detection Engineering

Detection engineering is the discipline of writing and tuning detection rules. The lifecycle:

```
  1. Hypothesis — "we believe an attacker could do X"
  2. Data source — what logs would show X? (eBPF, audit, network)
  3. Rule — write a rule that fires on X
  4. Test — produce a sample event; verify the rule fires
  5. Tune — adjust for false positives
  6. Deploy — apply the rule in production
  7. Operate — monitor the rule's performance
  8. Improve — when the rule fails (FN) or fires too much (FP), iterate
```

The role of a detection engineer: 0.5–1 FTE for a mid-size org. Writes Falco rules, tunes Wazuh correlation, owns the rule library.

## 13. The MITRE ATT&CK Mapping for Containers

ATT&CK has a Containers matrix that enumerates container-specific techniques. Some highlights:

| Tactic | Technique | Detection |
| ------ | --------- | --------- |
| Initial Access | Exploit public-facing app | WAF, runtime detection |
| Execution | Exec into container | Falco: k8s_audit, exec |
| Persistence | Add malicious sidecar | K8s admission policy |
| Privilege Escalation | Privileged container | K8s policy, Falco |
| Defense Evasion | Disable security tools | Audit log anomaly |
| Credential Access | Steal service account token | Falco, k8s audit |
| Discovery | Enumerate cloud metadata | Falco: egress to 169.254.169.254 |
| Lateral Movement | Cross-namespace connection | K8s NetworkPolicy + Falco |
| Collection | Mount host filesystem | K8s policy, Falco |
| Exfiltration | Outbound to known-bad IP | Falco, network IDS |
| Impact | Cryptominer | Falco: process patterns |

The ATT&CK matrix is the *catalog* of what to detect. Mapped to Falco rules, it is the detection coverage.

## 14. Detection in Non-K8s Environments

Not every workload runs in K8s. For VMs, bare metal, serverless:

### VM Detection

  - **osquery** + **Fleet** — SQL-based host telemetry
  - **Falco** on the host (not the container) — same rules, different scope
  - **EDR** (CrowdStrike, SentinelOne, etc.) — vendor-managed
  - **Sysmon** (Windows) — process, file, network events

### Serverless Detection

  - **Cloud-native logs** — Lambda invocation logs, CloudWatch
  - **CloudTrail** — IAM activity
  - **App-layer logs** — structured logs from the function

The pattern is the same: collect, normalize, detect, alert. The tools differ.

## 15. Detection and Compliance

| Framework | Control | Detection evidence |
| --------- | ------- | ------------------ |
| SOC 2 CC7.2 | System monitoring | Falco, Wazuh, audit logs |
| SOC 2 CC7.3 | Anomaly evaluation | Wazuh correlation rules |
| SOC 2 CC7.4 | Incident response | Alert → IR runbook |
| ISO A.8.16 | Monitoring activities | SIEM, audit logs |
| PCI 10 | Logging | Audit trail, immutable |
| PCI 11.4 | Intrusion detection | Falco, NIDS |
| PCI 11.5 | Change detection | File integrity monitoring |
| FedRAMP SI-4 | System monitoring | Continuous monitoring |
| FedRAMP IR-4 | Incident handling | IR runbooks |
| HIPAA §164.308 | Workforce | Detection + response |

The audit asks "how do you know when an incident is happening?" The answer is the alert log + the IR cycle.

## 16. Detection as Code

A mature org manages detection rules in code:

```
  detections/
  ├── falco/
  │   ├── k8s_audit/
  │   │   ├── exec_into_pod.yaml
  │   │   ├── privileged_container.yaml
  │   │   └── suspicious_egress.yaml
  │   ├── syscall/
  │   │   ├── shell_in_container.yaml
  │   │   ├── crypto_miner.yaml
  │   │   └── package_manager.yaml
  │   └── tests/
  │       └── ...
  ├── wazuh/
  │   ├── correlation/
  │   │   ├── credential_compromise.yaml
  │   │   └── lateral_movement.yaml
  │   └── tests/
  │       └── ...
  └── siem/
      └── splunk/
          └── queries/
              └── ...
```

Each rule is versioned, tested, reviewed. The library is the *detection coverage*. New threats → new rules. Old rules that no longer fire → investigate (the threat may have evolved, or the rule is dead).

## 17. Detection and the Loop-Back (Deep Dive)

The loop-back from runtime to CI is the highest-value detection work:

```
  Runtime alert (e.g., "exec into production-db")
       |
       v
  Postmortem
       |
       +-- Write a Falco rule: "any exec into production-db" (already exists)
       |
       +-- Write a SAST rule: "code that calls k8s API to exec into pods"
       |   (catches the code that would do this)
       |
       +-- Write an IaC policy: "pods in production cannot be exec'd into"
       |   (catches the manifest that would allow this)
       |
       +-- Write a CI gate: "PRs that add kubectl exec are flagged"
           (catches the PR that would do this)
       |
       v
  Stories filed, improvements shipped
       |
       v
  Same incident can't recur
```

The loop-back is a *force multiplier*. One runtime incident becomes five controls that prevent the next one.

## 18. The Cost of Detection

The total cost of detection:

| Component | Cost (annual) | Notes |
| --------- | ------------- | ----- |
| Falco deployment | $0 + ops time | Open source |
| Wazuh deployment | $0 + ops time | Open source; ~0.5 FTE |
| SIEM (commercial) | $10k–$100k | Per GB ingested |
| Commercial EDR | $50–$200 per endpoint | Per-endpoint license |
| 24/7 SOC | $1M+ | Outsourced, per-region |
| Detection engineer | $150k–$250k | 1 FTE |

The cost ranges from "almost free" (open source, no SOC) to "a small SOC" (24/7, commercial SIEM). Most orgs are in the middle: open source + part-time detection engineer + on-call rotation.

## 19. The Runtime Detection Playbook (Template)

```yaml
# detections/falco/k8s_audit/exec_into_pod.yaml
- rule: Exec into pod in production
  desc: Detect kubectl exec into a pod in the production namespace
  condition: >
    k8s_audit and
    ka.verb = "create" and
    ka.target.resource = "pods/exec" and
    ka.target.namespace = "prod" and
    ka.response.status.code = 200
  output: >
    Exec into production pod (user=%ka.user.name namespace=%ka.target.namespace
    pod=%ka.target.name)
  priority: WARNING
  tags: [k8s, audit, mitre_lateral_movement]
```

The rule is:
  - Named clearly
  - Documented
  - Testable (sample audit log → rule fires)
  - Tagged (for ATT&CK mapping)
  - Version-controlled
  - Reviewed

## Related

  - [[DevOps/devsecops/stage0-foundations/01-devsecops-mindset|M01: DevSecOps Mindset]]
  - [[Security/siem/wazuh/README|Wazuh SIEM]]
  - [[DevOps/devsecops/stage4-runtime/19-incident-response-in-ci|M19: Incident Response in CI]]
  - [[DevOps/devsecops/stage4-runtime/README|Stage 4 — Runtime]]
