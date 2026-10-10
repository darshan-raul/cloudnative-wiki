---
title: GuardDuty for EKS
tags: [eks, security, guardduty, threat-detection]
date: 2026-05-17
description: Threat detection for EKS with Amazon GuardDuty — audit log monitoring versus runtime monitoring, how the agent is deployed, finding types, response automation and what GuardDuty does not cover.
---

# GuardDuty for EKS

[[AWS/security/guardduty/README|Amazon GuardDuty]] is AWS's managed threat-detection service. For EKS it offers two independent features that watch two different layers:

| Feature                | Data source             | Sees                                                                 | Deployment                   |
| :--------------------- | :---------------------- | :------------------------------------------------------------------- | :--------------------------- |
| **EKS Protection**     | Kubernetes audit logs   | What was _asked of the API server_: who created, exec'd, bound, read | None — read directly by AWS  |
| **Runtime Monitoring** | eBPF agent on each node | What _happened inside containers_: processes, files, network calls   | A DaemonSet (managed add-on) |

They complement each other. Audit logs reveal a stolen credential creating a privileged pod; runtime monitoring reveals that pod downloading a miner. Enable both.

## EKS Protection (audit log monitoring)

GuardDuty consumes the audit log stream straight from the control plane. You do **not** need to turn on [[Kubernetes/eks/observability/logging/control-plane-logs|control plane logging]] to CloudWatch for this to work, and it adds no load to the cluster.

Representative findings:

| Finding                                              | Meaning                                                 |
| :--------------------------------------------------- | :------------------------------------------------------ |
| `Policy:Kubernetes/AnonymousAccessGranted`           | A binding granted permissions to `system:anonymous`     |
| `Policy:Kubernetes/ExposedDashboard`                 | The Kubernetes dashboard is reachable from the internet |
| `PrivilegeEscalation:Kubernetes/PrivilegedContainer` | A privileged container was launched                     |
| `Persistence:Kubernetes/ContainerWithSensitiveMount` | A pod mounted a sensitive host path                     |
| `CredentialAccess:Kubernetes/MaliciousIPCaller`      | Secrets were read from a known-malicious IP             |
| `Discovery:Kubernetes/TorIPCaller`                   | API calls arrived from a Tor exit node                  |
| `Execution:Kubernetes/ExecInKubeSystemPod`           | Someone ran `exec` into a `kube-system` pod             |

## Runtime Monitoring

The GuardDuty security agent is an eBPF program that observes system calls on the node: process execution, file access, network connections, privilege changes. Background on the mechanism is in [[Observability/ebpf|eBPF]] and [[Kubernetes/concepts/L07-security/02-workload-sandboxing/18-runtime-detection|runtime detection]].

Enable automated agent management and GuardDuty installs the `aws-guardduty-agent` EKS add-on and creates the VPC endpoint the agent reports to:

```bash
aws guardduty update-detector \
  --detector-id <detector-id> \
  --features '[
    {"Name":"EKS_AUDIT_LOGS","Status":"ENABLED"},
    {"Name":"RUNTIME_MONITORING","Status":"ENABLED",
     "AdditionalConfiguration":[{"Name":"EKS_ADDON_MANAGEMENT","Status":"ENABLED"}]}
  ]'
```

Use inclusion or exclusion tags on clusters (`GuardDutyManaged=true|false`) to control rollout. Check coverage afterwards — a node without a healthy agent is silently unmonitored:

```bash
kubectl get ds -n amazon-guardduty
aws guardduty list-coverage --detector-id <detector-id>
```

Representative runtime findings:

| Finding                                                    | Meaning                                                    |
| :--------------------------------------------------------- | :--------------------------------------------------------- |
| `CryptoCurrency:Runtime/BitcoinTool.B`                     | A process contacted a mining pool                          |
| `Execution:Runtime/NewBinaryExecuted`                      | A binary created after container start was executed        |
| `PrivilegeEscalation:Runtime/DockerSocketAccessed`         | A container process touched the container runtime socket   |
| `PrivilegeEscalation:Runtime/ContainerMountsHostDirectory` | A container escaped towards the host filesystem            |
| `DefenseEvasion:Runtime/FilelessExecution`                 | Code executed from memory                                  |
| `Backdoor:Runtime/C&CActivity.B`                           | A process is talking to a known command-and-control server |
| `Execution:Runtime/ReverseShell`                           | A reverse shell was opened                                 |

Runtime Monitoring also covers [[Kubernetes/eks/compute/fargate/README|Fargate]] on ECS, but on EKS it requires EC2 nodes.

## Responding to findings

Findings go to EventBridge, which is where automation hangs:

```
GuardDuty finding ──► EventBridge rule (severity ≥ 7) ──► SNS / Slack / PagerDuty
                                                      └─► Lambda or SSM runbook
```

Sensible automated responses, in order of aggressiveness:

1. **Notify** with the finding's cluster, namespace, workload and image.
2. **Isolate** the pod by applying a deny-all [[Kubernetes/concepts/L04-services-networking/05-network-policy|NetworkPolicy]] and a quarantine label that removes it from Services.
3. **Preserve** evidence: snapshot the node's volumes before anything is deleted.
4. **Cordon** the node so nothing new lands on it.

Do not auto-delete pods. The Deployment simply recreates them, and you destroy the evidence. Send findings to [[AWS/security/security-hub/README|Security Hub]] for aggregation and to [[AWS/security/detective/README|Detective]] for investigation; the general process is in [[Security/incident-response/README|incident response]].

## What GuardDuty is not

- **It detects, it does not prevent.** Blocking privileged pods is the job of [[Kubernetes/eks/security/pod-security-standards|Pod Security Standards]] and [[Kubernetes/eks/security/policy-management|policy engines]].
- **Rules are AWS-managed.** You cannot write custom detections; for that, run [[Security/endpoint-security/falco/README|Falco]] alongside.
- **It does not scan images.** Use [[AWS/security/inspector/README|Inspector]] for vulnerabilities.

## Cost

EKS Protection is billed per million audit events, Runtime Monitoring per vCPU-hour of monitored nodes. Chatty controllers inflate the first; large node fleets the second. Review the usage breakdown in the GuardDuty console after the 30-day trial.

## Related

- [[Kubernetes/eks/security/README|EKS security overview]]
- [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/15-audit-logging|Kubernetes audit logging]]
- [[Security/siem/README|SIEM]] — where findings usually end up
- [GuardDuty EKS Protection](https://docs.aws.amazon.com/guardduty/latest/ug/kubernetes-protection.html)

## Across the wiki

- [[Azure/monitoring/sentinel/README|Microsoft Sentinel Architecture, Threat Intelligence, and SOAR]] — threat detection (Azure)
- [[GCP/security/scc|GCP Security Command Center (SCC) & Secret Manager]] — threat detection (GCP)
