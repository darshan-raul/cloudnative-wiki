# Compliance Frameworks (NIST, CIS, OWASP)

*"https://www.nist.gov/cyberframework | https://www.cisecurity.org/ | https://owasp.org/"*

If your cluster has to satisfy an external standard — a regulator, a customer, a partner — you need to know the major **compliance frameworks** and how they apply to k8s. The three most relevant for k8s security: **NIST 800-190** (Application Container Security Guide), **CIS Kubernetes Benchmark** (the de-facto operational standard), and **OWASP** (Top 10 for containers / k8s, separate from the web app Top 10). This note is the **L07 layer** for compliance — it ties the other L07 notes to the frameworks they implement.

### Table of Contents

1. [Why Compliance Frameworks Matter](#1-why-compliance-frameworks-matter)
2. [NIST 800-190 — Application Container Security Guide](#2-nist-800190--application-container-security-guide)
3. [CIS Kubernetes Benchmark](#3-cis-kubernetes-benchmark)
4. [The kube-bench Tool](#4-the-kube-bench-tool)
5. [CIS Docker Benchmark](#5-cis-docker-benchmark)
6. [OWASP Container / k8s Top 10](#6-owasp-container--k8s-top-10)
7. [PCI-DSS, SOC2, HIPAA, FedRAMP — How They Map](#7-pci-dss-soc2-hipaa-fedramp--how-they-map)
8. [The SLSA Framework](#8-the-slsa-framework)
9. [The Compliance Audit Process](#9-the-compliance-audit-process)
10. [The "Continuous Compliance" Idea](#10-the-continuous-compliance-idea)
11. [Mapping L07 Notes to Controls](#11-mapping-l07-notes-to-controls)
12. [Common Audit Findings (and their L07 fix)](#12-common-audit-findings-and-their-l07-fix)
13. [Operations and Debugging](#13-operations-and-debugging)
14. [Gotchas and Common Mistakes](#14-gotchas-and-common-mistakes)

---

## 1. Why Compliance Frameworks Matter

Compliance is the **"have to"** of security. Most production k8s clusters have one of:

* **Regulatory** — PCI-DSS (payment cards), HIPAA (healthcare), FedRAMP (US gov), GDPR (EU).
* **Customer-driven** — SOC2 (the SaaS standard), ISO 27001 (international).
* **Industry-driven** — NIST CSF, CIS Controls, SLSA (supply chain).

The frameworks give you:

* A **checklist** of controls — what to implement.
* A **common language** — auditors, partners, customers understand the framework.
* A **shared standard** — what "good" looks like.

For k8s specifically, the relevant frameworks are:

* **NIST 800-190** — application container security. The federal / standards view.
* **CIS Kubernetes Benchmark** — the operational standard. Adopted by EKS, GKE, AKS hardening guides.
* **OWASP Container / k8s Top 10** — the developer's view. What's commonly wrong.
* **SLSA** — supply-chain integrity. Google's framework, increasingly adopted.

The frameworks **complement each other**. NIST is the high-level; CIS is the operational; OWASP is the developer; SLSA is the supply chain.

## 2. NIST 800-190 — Application Container Security Guide

*"https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-190.pdf"*

NIST 800-190 is the **federal standard** for container security. It covers the full lifecycle: image, registry, orchestrator, container, host OS.

The 5 sections:

1. **Image** — what's in the image, the base, the layers, the dependencies.
2. **Registry** — how images are stored, scanned, signed.
3. **Orchestrator** — k8s itself: the apiserver, etcd, RBAC, NetworkPolicy.
4. **Container** — runtime: SecurityContext, seccomp, AppArmor, capabilities.
5. **Host OS** — the node's OS: kernel, services, network.

The recommendations (paraphrased):

* **Image** — use minimal base images, scan for CVEs, use multi-stage builds, sign images.
* **Registry** — use a private registry, enable vulnerability scanning, encrypt at rest, require authentication.
* **Orchestrator** — enable RBAC, use PSS / SecurityContext, NetworkPolicy, audit logging, encryption at rest, namespace isolation.
* **Container** — drop capabilities, run as non-root, read-only root filesystem, seccomp, AppArmor, resource limits.
* **Host OS** — minimal OS, patch regularly, disable unnecessary services, kernel hardening, dedicated hosts for k8s components.

NIST 800-190 is the **federal baseline**. For US government clusters (FedRAMP), it's required. For others, it's a useful reference.

## 3. CIS Kubernetes Benchmark

*"https://www.cisecurity.org/benchmark/kubernetes"*

The **CIS Kubernetes Benchmark** is the de-facto operational standard. It's a list of recommendations (with check commands) for hardening a k8s cluster.

The benchmark is **versioned** per k8s release. CIS publishes a v1.30 benchmark, a v1.29 benchmark, etc. Each has ~100-200 recommendations.

The sections:

* **Control Plane** — apiserver flags, etcd config, scheduler, controller-manager.
* **Worker Node** — kubelet config, container runtime, kernel.
* **Policies** — RBAC, PSS, NetworkPolicy.
* **Managed Services** — EKS, GKE, AKS specifics.

A sample recommendation (from the kubelet section):

```
3.2.1 Ensure that the --anonymous-auth argument is set to false
  Description: Disable anonymous requests to the Kubelet.
  Audit: /bin/ps -ef | grep kubelet | grep -v grep
         # verify --anonymous-auth=false is set
  Remediation: Edit /var/lib/kubelet/config.yaml, set
               authentication.anonymous.enabled: false
```

Each recommendation has:

* **ID** — `3.2.1` (section 3, subsection 2, item 1).
* **Description** — what to do.
* **Audit** — the check command.
* **Remediation** — the fix.

The benchmark is **automated** by **kube-bench** (CIS's official tool).

## 4. The kube-bench Tool

*"https://github.com/aquasecurity/kube-bench"*

`kube-bench` runs the CIS benchmark automatically. It checks:

* Apiserver flags (via the static pod manifest).
* Kubelet config.
* Container runtime config.
* etcd config.
* File permissions.
* Network / firewall (limited).

It outputs a report:

```
[PASS] 3.2.1 Ensure that the --anonymous-auth argument is set to false
[PASS] 3.2.2 Ensure that the --authorization-mode argument is not set to AlwaysAllow
[FAIL] 3.2.3 Ensure that the --client-ca-file argument is set as appropriate
[WARN] 3.2.4 Ensure that the --read-only-port argument is set to 0
```

### 4.1 Running kube-bench

```bash
# in a Pod
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml
# check the logs
kubectl logs job/kube-bench

# in Docker (on a node)
docker run --pid host --net host -v /etc:/etc:ro -v /var:/var:ro \
  aquasec/kube-bench:latest
```

### 4.2 Interpreting the output

* **PASS** — the recommendation is met.
* **FAIL** — the recommendation is not met. Action required.
* **WARN** — the recommendation is partially met or not applicable. Investigate.

The output is a **Junit XML** (for CI integration) and a human-readable text. In CI, the exit code is non-zero on FAIL.

## 5. CIS Docker Benchmark

The **CIS Docker Benchmark** is for the Docker daemon. It's less relevant for k8s (where the runtime is containerd or CRI-O, not Docker), but useful for any system that runs Docker directly (CI machines, dev laptops).

The recommendations:

* **Daemon config** — `daemon.json` (or `config.toml` for containerd).
* **Images** — vulnerability scanning, content trust.
* **Container runtime** — capability drops, security options, read-only root filesystem.
* **Networking** — inter-container communication, IP forwarding.
* **Storage** — `/var/lib/docker` permissions.

For k8s, the **CIS Kubernetes Benchmark** is the relevant one. The CIS Docker Benchmark is for non-k8s Docker usage.

## 6. OWASP Container / k8s Top 10

*"https://owasp.org/www-project-kubernetes-top-ten/"*

The **OWASP Kubernetes Top 10** is a list of the most common security issues in k8s environments. It's the **k8s-specific counterpart** to the OWASP Top 10 for web apps.

The current top 10 (2022):

1. **Insecure Workload Configurations** — privileged containers, host namespaces, default SAs with permissions.
2. **Supply Chain Vulnerabilities** — vulnerable base images, unscanned images, no SBOM.
3. **Overly Permissive RBAC** — `cluster-admin` for everyone, SAs with `*` verbs.
4. **Lack of Centralized Policy Enforcement** — no PSS, no NetworkPolicy, no admission policies.
5. **Inadequate Logging and Monitoring** — no audit logs, no runtime detection, no SIEM.
6. **Broken Authentication Mechanisms** — anonymous auth, static tokens, weak SA tokens.
7. **Missing Network Segmentation Controls** — no NetworkPolicy, default-allow everywhere.
8. **Secrets Management Failures** — plaintext Secrets in git, no encryption at rest.
9. **Misconfigured Cluster Components** — apiserver flags, etcd, kubelet, runtime misconfigs.
10. **Outdated and Vulnerable Kubernetes Components** — old k8s versions, known CVEs in core components.

The OWASP list is the **developer's view** — what's commonly wrong, with examples. For each, the L07 notes in this vault cover the fixes.

## 7. PCI-DSS, SOC2, HIPAA, FedRAMP — How They Map

The "big four" compliance frameworks and how they apply to k8s:

### 7.1 PCI-DSS (Payment Card Industry)

*"https://www.pcisecuritystandards.org/"*

For clusters that process payment data. Requirements:

* **Network segmentation** — NetworkPolicy, namespace isolation.
* **Access control** — RBAC, OIDC, MFA.
* **Encryption** — TLS in transit, encryption at rest for data.
* **Logging** — audit logs, retention.
* **Vulnerability management** — image scanning, CVE monitoring.
* **Patch management** — k8s version upgrades.

The k8s side: the cluster is the **CDE (Cardholder Data Environment)** boundary. The k8s-specific controls come from CIS + NIST 800-190.

### 7.2 SOC2 (Service Organization Control 2)

For SaaS providers. Trust Service Criteria:

* **Security** — access control, monitoring, incident response.
* **Availability** — uptime, DR, backups.
* **Confidentiality** — data encryption, access control.
* **Processing Integrity** — accuracy, completeness of data.
* **Privacy** — PII handling.

The k8s side: the cluster is part of the **system description**. The controls (RBAC, encryption, logging, etc.) are part of the audit.

### 7.3 HIPAA (Health Insurance Portability and Accountability Act)

For clusters that handle PHI (Protected Health Information). Requirements:

* **Access control** — RBAC, unique user IDs.
* **Audit controls** — audit logs of PHI access.
* **Integrity** — data integrity (encryption, checksums).
* **Transmission security** — TLS in transit.

The k8s side: PHI must be in **encrypted Secrets**, **encrypted at rest in etcd**, **access logged**, and **only accessible by authorized SAs**.

### 7.4 FedRAMP (US Federal Risk and Authorization Management Program)

For US government clusters. Baselines:

* **Low** — minimal controls.
* **Moderate** — most clusters.
* **High** — sensitive data.

Requirements: NIST 800-53 controls. The k8s implementation is via CIS + NIST 800-190 + FedRAMP-specific overlays.

## 8. The SLSA Framework

*"https://slsa.dev/"*

**SLSA (Supply chain Levels for Software Artifacts)** is Google's framework for **supply chain integrity**. It defines levels:

* **Level 0** — no SLSA. No guarantees.
* **Level 1** — documented build process. Basic provenance.
* **Level 2** — signed provenance. Hosted build platform.
* **Level 3** — hardened build platform. Two-party review.

The k8s implementation:

* **Build provenance** — generate a `provenance.json` for each image (what built it, from what source).
* **Signing** — sign the provenance with cosign.
* **Verification** — the cluster verifies the provenance at admission (via Kyverno / Connaisseur).

The **SLSA levels** map to image signing and supply chain controls:

* **Level 1** — use a private registry, scan images.
* **Level 2** — sign images with cosign, generate SBOMs.
* **Level 3** — two-party review of changes, hermetic builds, signed provenance.

Most production clusters aim for **SLSA Level 2** for the application images.

## 9. The Compliance Audit Process

A typical k8s audit:

1. **Scope** — what's in scope (the cluster, the apps, the data).
2. **Evidence collection** — config files, audit logs, scan results, RBAC, etc.
3. **Control mapping** — map your evidence to the framework's controls.
4. **Gap analysis** — what's missing? What needs to be fixed?
5. **Remediation** — fix the gaps.
6. **Continuous compliance** — automated checks (kube-bench, OPA, etc.) in CI/CD.

The audit is **continuous**, not annual. The auditor wants evidence of **ongoing** compliance, not a snapshot.

## 10. The "Continuous Compliance" Idea

Manual audits are point-in-time. **Continuous compliance** is the practice of:

* **Running kube-bench in CI** — every PR, every cluster change.
* **Scanning images in CI** — every image build.
* **Verifying RBAC** — every change to a Role / ClusterRole.
* **Verifying NetworkPolicy** — every namespace change.
* **Alerting on audit log anomalies** — failed logins, escalation attempts.

Tools:

* **kube-bench** in CI.
* **Trivy** for image scanning.
* **Conftest** (OPA) for manifest validation.
* **Kyverno / OPA** for policy enforcement.
* **Falco / Tetragon** for runtime detection.

The goal: **compliance is enforced in the build, not discovered in the audit**.

## 11. Mapping L07 Notes to Controls

A mapping of L07 notes to common controls:

| Control | L07 Note(s) |
|---|---|
| **Anonymous auth disabled** | [[Kubernetes/concepts/L07-security/01-api-access/01-authentication-authorization\|AuthN/AuthZ]] |
| **RBAC** | [[Kubernetes/concepts/L07-security/01-api-access/03-rbac\|RBAC]] |
| **PSS** | [[Kubernetes/concepts/L07-security/02-workload-sandboxing/06-pod-security-standards\|PSS]] |
| **SecurityContext** | [[Kubernetes/concepts/L07-security/02-workload-sandboxing/05-security-context\|SecurityContext]] |
| **seccomp / AppArmor** | [[Kubernetes/concepts/L07-security/02-workload-sandboxing/16-seccomp-apparmor\|Seccomp / AppArmor]] |
| **NetworkPolicy** | [[Kubernetes/concepts/L04-services-networking/05-network-policy\|NetworkPolicy]] (L04) |
| **mTLS** | [[Kubernetes/concepts/L07-security/03-encryption-identity/08-tls-mtls\|TLS / mTLS]] |
| **SPIFFE** | [[Kubernetes/concepts/L07-security/03-encryption-identity/09-spiffe-spire\|SPIFFE / SPIRE]] |
| **Admission policies** | [[Kubernetes/concepts/L07-security/04-admission-policy/10-admission-controllers\|Admission Controllers]], [[Kubernetes/concepts/L07-security/04-admission-policy/11-opa-gatekeeper\|OPA]], [[Kubernetes/concepts/L07-security/04-admission-policy/12-kyverno\|Kyverno]] |
| **etcd encryption** | [[Kubernetes/concepts/L07-security/03-encryption-identity/13-etcd-encryption\|etcd Encryption]] |
| **Secret encryption** | [[Kubernetes/concepts/L07-security/03-encryption-identity/14-secret-encryption\|Secret Encryption]] |
| **Audit logging** | [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/15-audit-logging\|Audit Logging]] |
| **Runtime sandboxing** | [[Kubernetes/concepts/L07-security/02-workload-sandboxing/17-runtime-sandboxing\|Runtime Sandboxing]] |
| **Runtime detection** | [[Kubernetes/concepts/L07-security/02-workload-sandboxing/18-runtime-detection\|Runtime Detection]] |
| **Image hardening** | [[Kubernetes/concepts/L07-security/02-workload-sandboxing/19-image-hardening\|Image Hardening]] |
| **Cluster hardening** | [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/20-cluster-hardening\|Cluster Hardening]] |
| **Node hardening** | [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/21-node-hardening\|Node Hardening]] |

The auditor asks: "do you have NetworkPolicy?" — you point to the L04 note + the policy in your repo. The control is documented, the implementation is in your cluster, and the evidence is in your CI.

## 12. Common Audit Findings (and their L07 fix)

The most common findings, and where to fix them:

| Finding | Severity | L07 Fix |
|---|---|---|
| Anonymous auth enabled | HIGH | Set `--anonymous-auth=false` (Cluster Hardening) |
| Read-only kubelet port enabled | HIGH | Set `readOnlyPort: 0` (Node Hardening) |
| Profiling enabled on apiserver | MEDIUM | Set `--profiling=false` (Cluster Hardening) |
| `ABAC` authorizer enabled | HIGH | Use `RBAC` only (AuthN/AuthZ) |
| TLS 1.0/1.1 enabled | MEDIUM | Set `--tls-min-version=VersionTLS12` (Cluster Hardening) |
| Secrets not encrypted at rest | MEDIUM | Add `EncryptionConfiguration` (etcd Encryption) |
| `hostPID: true` in app Pods | MEDIUM | Use PSS `restricted` (PSS) |
| NetworkPolicy: default-allow | MEDIUM | Add default-deny (L04 NetworkPolicy) |
| Audit log not shipped off-cluster | LOW | Ship to a SIEM (Audit Logging) |
| `:latest` images in production | MEDIUM | Use versioned tags (Image Hardening) |
| `privileged: true` containers | HIGH | Remove or justify (SecurityContext) |
| No `PodSecurity` admission | MEDIUM | Enable PSS (PSS) |
| `cluster-admin` granted widely | HIGH | Use least-privilege RBAC (RBAC) |
| No image scanning | HIGH | Add Trivy / Snyk in CI (Image Hardening) |
| No runtime detection | MEDIUM | Add Falco / Tetragon (Runtime Detection) |
| SSH password auth enabled | HIGH | Disable, use key auth (Node Hardening) |

The auditor's report is a **checklist of these**. Each fix maps to an L07 note.

## 13. Operations and Debugging

### 13.1 Common commands

```bash
# run kube-bench
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml
kubectl logs job/kube-bench

# or in Docker
docker run --pid host --net host -v /etc:/etc:ro -v /var:/var:ro \
  aquasec/kube-bench:latest

# check the SBOM of an image
syft myapp:1.0

# scan an image
trivy image myapp:1.0

# check the OWASP k8s Top 10
# (most CI tools check this; armo / kubewall / etc.)

# check a specific CIS rule
# (kube-bench has the rule IDs)
```

### 13.2 The "kube-bench report is full of FAIL" case

```bash
# 1. Start with the HIGH severity findings
# (kube-bench output has severity)

# 2. For each FAIL, see the remediation
# the output includes the fix

# 3. Apply the fix
# edit the relevant config file
# restart the component (apiserver, kubelet, etc.)

# 4. Re-run kube-bench
# the FAIL should be PASS now
```

### 13.3 The "we need to comply with X, where do we start" case

```bash
# 1. Read the framework's k8s-specific guidance
# - NIST 800-190 for federal
# - CIS benchmark for operational
# - OWASP k8s Top 10 for developer

# 2. Run kube-bench as a baseline
# shows what's already met

# 3. Map the gaps to the L07 notes
# each L07 note is a control

# 4. Implement the fixes
# prioritized by severity and the framework's requirements

# 5. Set up continuous compliance
# kube-bench in CI, Trivy in CI, etc.
```

## 14. Gotchas and Common Mistakes

### 14.1 The 20+ common mistakes

1. **NIST 800-190 is the standard, not a checklist.** It's a guideline. Map it to your specific implementation.

2. **CIS benchmark is version-specific.** A benchmark for k8s 1.27 may not apply to 1.30. Use the right version.

3. **CIS benchmark is automated but not complete.** kube-bench checks config, not behavior. Some recommendations are manual.

4. **OWASP k8s Top 10 is the developer's view, not the auditor's.** It's useful for awareness, not for compliance certification.

5. **SLSA levels are aspirational.** Most clusters are at SLSA 1 (private registry) or 2 (signing). Level 3 is rare.

6. **PCI-DSS, HIPAA, etc. are not k8s-specific.** They apply to the whole system. k8s is a component.

7. **Compliance is not security.** A cluster can be compliant but insecure (the controls are met but the implementation is bad). Or secure but non-compliant (the controls are stricter than the framework requires).

8. **The auditor's interpretation matters.** A finding can be "fixed" in different ways. Discuss with the auditor.

9. **Compliance is continuous, not annual.** The auditor wants ongoing evidence, not a snapshot.

10. **Automated tools generate noise.** kube-bench's WARN / INFO is usually informational. Focus on FAIL.

11. **The "we have CIS compliance" badge is from a point-in-time scan.** It doesn't mean the cluster is compliant today. Re-scan continuously.

12. **A "PASS" in kube-bench is for the specific check, not the overall posture.** A PASS for "anonymous-auth is false" doesn't mean the cluster is secure.

13. **The OWASP k8s Top 10 is a 2022 publication.** It may be updated. Check the current version.

14. **The CIS benchmark is updated for each k8s release.** Make sure you're using the right one for your k8s version.

15. **The kube-bench Pod runs with `hostPID: true, hostNetwork: true`.** Required to read the kubelet's config.

16. **kube-bench is a snapshot tool, not a continuous monitor.** For continuous compliance, integrate with a CI/CD pipeline.

17. **The OWASP k8s Top 10 #1 (Insecure Workload Configurations) is the most common finding.** PSS `restricted` addresses most of it.

18. **The OWASP k8s Top 10 #3 (Overly Permissive RBAC) is the second most common.** Audit your ClusterRoleBindings.

19. **The OWASP k8s Top 10 #7 (Missing Network Segmentation) is the third most common.** Default-deny NetworkPolicy everywhere.

20. **The OWASP k8s Top 10 #5 (Inadequate Logging) is common but easy to fix.** Enable audit logging, ship to a SIEM.

21. **Compliance frameworks are international.** SOC2 is US, ISO 27001 is international, GDPR is EU. Choose based on your customers' requirements.

22. **The compliance evidence is in git, not in the cluster.** The configs, the policies, the runs of kube-bench — all in git. The cluster is the result.

23. **The auditor asks for "how do you ensure this" not "is this set".** Document the process.

24. **Compliance is per-framework, not universal.** A SOC2 audit doesn't satisfy PCI-DSS, and vice versa.

25. **The CIS benchmark is a starting point, not the final answer.** Add your own internal controls.

## See also

* All other L07 notes — each addresses specific controls.
* [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/20-cluster-hardening|Cluster Hardening]] — control plane controls
* [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/21-node-hardening|Node Hardening]] — node-level controls
* [[Kubernetes/concepts/L07-security/02-workload-sandboxing/19-image-hardening|Image Hardening]] — supply chain (SLSA)
