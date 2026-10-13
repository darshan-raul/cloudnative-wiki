---
title: CKS Track
tags: [kubernetes, certifications, cks, security, exam-prep]
date: 2026-10-13
description: "Certified Kubernetes Security Specialist study track mapping every exam objective to the concept notes, guides and labs in this wiki, with task drills and known gaps."
---

# CKS Track

The Certified Kubernetes Security Specialist exam tests whether you can harden a cluster and its workloads and investigate a compromise. It requires a passed CKA and assumes that level of speed. Most tasks involve a tool outside core Kubernetes (Falco, Trivy, kube-bench, AppArmor) or editing control plane static Pod manifests, so the exam rewards hands-on tool practice far more than reading.

Exam format, shell setup and time management are in the [[Kubernetes/certifications/index|Certifications hub]]. This page covers what to study.

| Domain                                   | Weight | Practice in this wiki                                                                                     |
| :--------------------------------------- | :----- | :-------------------------------------------------------------------------------------------------------- |
| Cluster Setup                            | 15%    | Lab + practice for NetworkPolicy; guided labs for the CIS benchmark, Ingress TLS and metadata             |
| Cluster Hardening                        | 15%    | Lab + practice for RBAC and ServiceAccounts; guided labs for API access                                   |
| System Hardening                         | 10%    | Guided labs for seccomp and host footprint; AppArmor not run; host IAM is reading only                    |
| Minimize Microservice Vulnerabilities    | 20%    | Lab + practice for Pod Security; guided labs for Secrets encryption, sandboxing and encryption in transit |
| Supply Chain Security                    | 20%    | Guided labs; signature verification at admission is a gap                                                 |
| Monitoring, Logging and Runtime Security | 20%    | Guided labs for Falco, audit logging and immutability; one unguided investigation                         |

The third column says what kind of practice exists, using the labels defined in the [[Kubernetes/certifications/index#what-the-coverage-labels-mean|hub]]. It is not a readiness score. Most CKS labs are still **guided**: they show a control working once. Only CKS-01, CKS-13 and CKS-14 have unguided tasks with checks.

Objectives are summarised from the Linux Foundation CKS page and curriculum as checked on 2026-10-13 (exam on Kubernetes v1.35; this wiki's baseline is 1.37).

> [!warning] Which version each CKS lab was run on
> CKS-01, CKS-13 and CKS-14 were run on Kubernetes v1.37.0 on 2026-10-13. CKS-02 to CKS-12 were run earlier on kind v0.31 with Kubernetes v1.35.0, which is the version the exam used on the check date, and have **not** been re-run on v1.37. Expect small differences in output on v1.37, and note that kind v0.33 or newer is needed for it. Each lab's header states its own test environment.

> [!note] Where the labs run
> Most CKS labs run on the `kind` cluster from Lab CKAD-01 and reach the node with `docker exec` in place of `ssh`. They edit the API server manifest repeatedly, so take the backup each lab asks for, and note that several labs write that backup to the same path: the copy is a safety net for the lab you are in, not a way back to an earlier lab. Run one CKS lab at a time and finish its cleanup before starting the next; if a lab leaves the API server unhealthy, recreate the cluster as [[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]] describes. Lab CKS-04 changes how Secrets are stored and cannot be undone by restoring a manifest alone. Lab CKS-09 and Lab CKS-11 create their own clusters, which changes your kubectl context; run `kubectl config use-context kind-k8s-lab` afterwards. They also need more memory than the other labs. AppArmor needs a virtual machine node.

---

## Prerequisites

- A passed CKA, or the [[Kubernetes/certifications/cka|CKA Track]] completed, including editing static Pod manifests and recovering when the API server does not come back.
- [[Kubernetes/concepts/L07-security/index|L07 Security]] and [[Kubernetes/concepts/L07-security/07-security|Security Overview]] for the layered model the domains follow.
- [[Kubernetes/review/security-refresher|Security refresher]] as a quick self-check.
- Linux security primitives: [[Linux/security/capabilities|Capabilities]], [[Linux/security/seccomp|seccomp]], [[Linux/security/apparmor|AppArmor]] and [[Linux/security/container-security|Container Security]].

---

## 1. Cluster Setup (15%)

| Objective                                                      | Read                                                                                                                                                                                                                                                                                                               | Practise                                                                                                                                             |
| :------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------- |
| Use network security policies to restrict cluster-level access | [[Kubernetes/concepts/L04-services-networking/05-network-policy\|NetworkPolicy]], [[Security/kubernetes-security/network-policies/README\|Network Policies (Security)]]                                                                                                                                            | [[Kubernetes/labs/cks/01-workload-security-hardening\|Lab CKS-01]], [[Kubernetes/labs/cks/11-cilium-encryption-and-metadata-protection\|Lab CKS-11]] |
| Use the CIS benchmark to review component configuration        | [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/22-compliance-frameworks\|Compliance Frameworks]], [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/20-cluster-hardening\|Cluster Hardening]], [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/21-node-hardening\|Node Hardening]] | [[Kubernetes/labs/cks/02-cis-benchmark-kube-bench\|Lab CKS-02]]                                                                                      |
| Properly set up Ingress with TLS                               | [[Kubernetes/concepts/L04-services-networking/04-ingress\|Ingress]], [[Kubernetes/concepts/L07-security/03-encryption-identity/08-tls-mtls\|TLS and mTLS]]                                                                                                                                                         | [[Kubernetes/labs/ckad/09-ingress\|Lab CKAD-09]]                                                                                                     |
| Protect node metadata and endpoints                            | [[Kubernetes/guides/non-functional/security-baseline\|Security Baseline]], [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/21-node-hardening\|Node Hardening]]                                                                                                                                          | [[Kubernetes/labs/cks/11-cilium-encryption-and-metadata-protection\|Lab CKS-11]]                                                                     |
| Verify platform binaries before deploying                      | Covered in the lab                                                                                                                                                                                                                                                                                                 | [[Kubernetes/labs/cks/07-image-scanning-and-static-analysis\|Lab CKS-07]]                                                                            |

**Task drills**

- [ ] Write a default-deny policy for a namespace, then allow one tier to reach another on a single port and nothing else.
- [ ] Block Pod egress to the cloud metadata address `169.254.169.254` with an `ipBlock` and `except`, while leaving other egress open.
- [ ] Run `kube-bench` against a control plane node, pick three failed checks for the API server, kubelet and etcd, and fix each one.
- [ ] Create a TLS Secret from a certificate and key, and serve an Ingress host over HTTPS with it.
- [ ] Download a Kubernetes release binary, compare its `sha512sum` with the published checksum, and say whether the binary on the node matches.

---

## 2. Cluster Hardening (15%)

| Objective                                   | Read                                                                                                                                                                                                                                                                                                                                                                                                                  | Practise                                                                                                                        |
| :------------------------------------------ | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------ |
| Use RBAC to minimize exposure               | [[Kubernetes/concepts/L07-security/01-api-access/03-rbac\|RBAC]], [[Security/kubernetes-security/rbac/README\|RBAC (Security)]]                                                                                                                                                                                                                                                                                       | [[Kubernetes/labs/cks/01-workload-security-hardening\|Lab CKS-01]], [[Kubernetes/labs/cks/13-rbac-remediation\|Lab CKS-13]]     |
| Exercise caution in using service accounts  | [[Kubernetes/concepts/L07-security/01-api-access/02-service-accounts\|Service Accounts]]                                                                                                                                                                                                                                                                                                                              | [[Kubernetes/labs/cks/01-workload-security-hardening\|Lab CKS-01]], [[Kubernetes/labs/cks/13-rbac-remediation\|Lab CKS-13]]     |
| Restrict access to the Kubernetes API       | [[Kubernetes/concepts/L07-security/01-api-access/01-authentication-authorization\|Authentication vs Authorization]], [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/20-cluster-hardening\|Cluster Hardening]], [[Kubernetes/concepts/L07-security/04-admission-policy/10-admission-controllers\|Admission Controllers]], [[Kubernetes/concepts/L07-security/01-api-access/04-certificates\|Certificates]] | [[Kubernetes/labs/cks/02-cis-benchmark-kube-bench\|Lab CKS-02]], [[Kubernetes/labs/cks/08-image-admission-control\|Lab CKS-08]] |
| Upgrade Kubernetes to avoid vulnerabilities | [[Kubernetes/guides/non-functional/upgrade-strategy\|Upgrade Strategy]]                                                                                                                                                                                                                                                                                                                                               | [[Kubernetes/labs/cka/04-kubeadm-upgrade\|Lab CKA-04]]                                                                          |

**Task drills**

- [ ] Audit an over-permissive Role (wildcards, `secrets` access, `escalate` or `bind`) and reduce it to the verbs a workload actually uses.
- [ ] Find every subject bound to `cluster-admin` and remove one that should not be.
- [ ] Disable token automounting on the `default` ServiceAccount of a namespace, and give one workload a dedicated ServiceAccount with a short-lived projected token.
- [ ] Turn off anonymous authentication on the API server and confirm the `NodeRestriction` admission plugin and `Node,RBAC` authorization modes are set.
- [ ] Stop a Service from exposing the API server through a NodePort, and confirm the insecure and profiling endpoints are off.
- [ ] Upgrade a cluster by one patch version to pick up a fix, control plane first.

---

## 3. System Hardening (10%)

| Objective                                               | Read                                                                                                                                                                                                                                 | Practise                                                                                                 |
| :------------------------------------------------------ | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------- |
| Minimize host OS footprint                              | [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/21-node-hardening\|Node Hardening]], [[Linux/security/linux-cis-hardening\|Linux CIS Hardening]], [[Linux/security/systemd-service-hardening\|systemd Service Hardening]] | [[Kubernetes/labs/cks/12-host-os-footprint\|Lab CKS-12]]                                                 |
| Use least-privilege identity and access management      | [[Linux/security/pam\|PAM]], [[Kubernetes/guides/non-functional/oidc-integration\|OIDC Integration]]                                                                                                                                 | Reading only                                                                                             |
| Minimize external access to the network                 | [[Linux/networking/iptables\|iptables]], [[Linux/networking/firewalld\|firewalld]], [[Linux/networking/ss\|ss]], [[Linux/networking/ports\|Ports]]                                                                                   | [[Kubernetes/labs/cks/12-host-os-footprint\|Lab CKS-12]]                                                 |
| Use kernel hardening tools such as AppArmor and seccomp | [[Kubernetes/concepts/L07-security/02-workload-sandboxing/16-seccomp-apparmor\|Seccomp and AppArmor]], [[Linux/security/apparmor\|AppArmor]], [[Linux/security/seccomp\|seccomp]], [[Linux/security/sysctl\|sysctl]]                 | [[Kubernetes/labs/cks/05-seccomp-apparmor-and-immutability\|Lab CKS-05]] (seccomp run; AppArmor not run) |

**Task drills**

- [ ] On a node, list listening sockets with `ss -tlnp`, identify a service that should not be running, stop and disable it, and remove its package.
- [ ] Find the process bound to a given port and the binary behind it.
- [ ] Load an AppArmor profile on a node with `apparmor_parser`, confirm it with `aa-status`, and apply it to a container through `securityContext.appArmorProfile`.
- [ ] Place a custom seccomp profile under the kubelet's seccomp directory and reference it from a Pod with type `Localhost`. Then switch another Pod to `RuntimeDefault`.
- [ ] Prevent a kernel module from loading by blacklisting it.

---

## 4. Minimize Microservice Vulnerabilities (20%)

| Objective                                     | Read                                                                                                                                                                                                                                                                                                                                      | Practise                                                                         |
| :-------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------- |
| Use appropriate Pod Security Standards        | [[Kubernetes/concepts/L07-security/02-workload-sandboxing/06-pod-security-standards\|Pod Security Standards]], [[Kubernetes/concepts/L07-security/02-workload-sandboxing/05-security-context\|SecurityContext]], [[Security/kubernetes-security/pod-security/README\|Pod Security (Security)]]                                            | [[Kubernetes/labs/cks/01-workload-security-hardening\|Lab CKS-01]]               |
| Manage Kubernetes Secrets                     | [[Kubernetes/concepts/L05-config-storage/02-secrets\|Secrets]], [[Kubernetes/concepts/L07-security/03-encryption-identity/14-secret-encryption\|Secret Encryption]], [[Kubernetes/concepts/L07-security/03-encryption-identity/13-etcd-encryption\|etcd Encryption]], [[Security/kubernetes-security/secrets/README\|Secrets (Security)]] | [[Kubernetes/labs/cks/04-secrets-encryption-at-rest\|Lab CKS-04]]                |
| Understand and implement isolation techniques | [[Kubernetes/concepts/L07-security/02-workload-sandboxing/17-runtime-sandboxing\|Runtime Sandboxing]], [[Kubernetes/guides/non-functional/multi-tenancy\|Multi-Tenancy]]                                                                                                                                                                  | [[Kubernetes/labs/cks/10-runtime-sandboxing-gvisor\|Lab CKS-10]]                 |
| Implement Pod-to-Pod encryption               | [[Kubernetes/concepts/L04-services-networking/07-k8s-networking-deep-dive\|Networking Deep Dive]], [[Kubernetes/guides/networking/istio\|Istio]], [[Kubernetes/concepts/L07-security/03-encryption-identity/08-tls-mtls\|TLS and mTLS]]                                                                                                   | [[Kubernetes/labs/cks/11-cilium-encryption-and-metadata-protection\|Lab CKS-11]] |

Policy engines appear in tasks as something already installed that you must read and adjust, so know [[Kubernetes/concepts/L07-security/04-admission-policy/11-opa-gatekeeper|OPA and Gatekeeper]] and [[Kubernetes/concepts/L07-security/04-admission-policy/12-kyverno|Kyverno]] well enough to edit a constraint or policy.

**Task drills**

- [ ] Label a namespace to enforce the `restricted` Pod Security Standard, then fix a Deployment until it is admitted.
- [ ] Find every Pod in a cluster that runs privileged, as root, or with a `hostPath`, and remediate or delete as the task directs.
- [ ] Write an `EncryptionConfiguration` for Secrets, wire it into the API server manifest with the flag and a volume mount, re-encrypt existing Secrets, and prove it by reading the raw key from etcd with `etcdctl`.
- [ ] Read a Secret straight out of etcd to show that it was stored unencrypted.
- [ ] Create a RuntimeClass for gVisor (`runsc`) and run a Pod with it; confirm from `dmesg` inside the Pod that it is sandboxed.
- [ ] Fix a Gatekeeper constraint or Kyverno policy so that it rejects images from an untrusted registry.
- [ ] Enable transparent encryption between Pods with Cilium and prove it from a packet capture. Encryption gives confidentiality on the wire.
- [ ] Separately, read how a CiliumNetworkPolicy requires mutual authentication. That proves the **identity** of the peer and is a different control from encryption; one does not imply the other.

---

## 5. Supply Chain Security (20%)

| Objective                                                         | Read                                                                                                                                                                                                                                                                      | Practise                                                                                                                         |
| :---------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | :------------------------------------------------------------------------------------------------------------------------------- |
| Minimize base image footprint                                     | [[Kubernetes/concepts/L07-security/02-workload-sandboxing/19-image-hardening\|Image Hardening]], [[Containers/dockerfile-best-practices\|Dockerfile Best Practices]], [[Containers/images-and-layers\|Images and Layers]]                                                 | [[Kubernetes/labs/cks/07-image-scanning-and-static-analysis\|Lab CKS-07]]                                                        |
| Understand your supply chain (SBOM, CI/CD, artifact repositories) | [[Kubernetes/concepts/L07-security/04-admission-policy/23-sboms\|SBOMs]], [[Kubernetes/guides/delivery/ci-cd-integration\|CI/CD Integration]], [[Containers/registries\|Registries]]                                                                                      | [[Kubernetes/labs/cks/07-image-scanning-and-static-analysis\|Lab CKS-07]]                                                        |
| Secure your supply chain (permitted registries, signing)          | [[Kubernetes/concepts/L07-security/04-admission-policy/10-admission-controllers\|Admission Controllers]], [[Kubernetes/concepts/L07-security/04-admission-policy/12-kyverno\|Kyverno]], [[Kubernetes/concepts/L07-security/04-admission-policy/23-sboms\|SBOMs]] (cosign) | [[Kubernetes/labs/cks/08-image-admission-control\|Lab CKS-08]], [[Kubernetes/labs/cks/09-image-signing-with-cosign\|Lab CKS-09]] |
| Perform static analysis of workloads and images                   | [[Security/kubernetes-security/vulnerability-scanning/README\|Vulnerability Scanning]], [[Kubernetes/concepts/L07-security/02-workload-sandboxing/19-image-hardening\|Image Hardening]]                                                                                   | [[Kubernetes/labs/cks/07-image-scanning-and-static-analysis\|Lab CKS-07]]                                                        |

**Task drills**

- [ ] Rewrite a Dockerfile as a multi-stage build on a minimal base, with a non-root `USER`, a pinned tag and no secrets in layers.
- [ ] Scan the images of every Pod in a namespace with `trivy image`, and delete the Pods whose images have `CRITICAL` vulnerabilities.
- [ ] Generate an SBOM for an image in SPDX or CycloneDX format, and find which image in a set contains a given package version.
- [ ] Configure the `ImagePolicyWebhook` admission plugin: admission configuration file, kubeconfig for the backend, `defaultAllow: false`, the API server flags and the volume mount.
- [ ] Restrict a namespace to images from one registry using a policy engine or a `ValidatingAdmissionPolicy`.
- [ ] Review a Pod manifest and a Dockerfile by eye and with a scanner (`kubesec scan`, KubeLinter), and fix the two worst findings in each.

---

## 6. Monitoring, Logging and Runtime Security (20%)

| Objective                                                          | Read                                                                                                                                                                                                 | Practise                                                                                                                                                                                       |
| :----------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Perform behavioural analytics to detect malicious activity         | [[Kubernetes/concepts/L07-security/02-workload-sandboxing/18-runtime-detection\|Runtime Detection (Falco, Tetragon)]]                                                                                | [[Kubernetes/labs/cks/06-falco-runtime-detection\|Lab CKS-06]]                                                                                                                                 |
| Detect threats across infrastructure, apps, networks and workloads | [[Kubernetes/concepts/L07-security/02-workload-sandboxing/18-runtime-detection\|Runtime Detection]], [[Linux/security/auditd\|auditd]], [[Security/kubernetes-security/README\|Kubernetes Security]] | [[Kubernetes/labs/cks/06-falco-runtime-detection\|Lab CKS-06]], [[Kubernetes/labs/cks/03-audit-logging\|Lab CKS-03]]                                                                           |
| Investigate and identify phases of attack and bad actors           | [[Security/assume-breach-principle\|Assume Breach Principle]], [[Kubernetes/concepts/L08-operations/02-kubectl-debug\|kubectl Debug Toolkit]]                                                        | [[Kubernetes/labs/cks/06-falco-runtime-detection\|Lab CKS-06]], [[Kubernetes/labs/cks/03-audit-logging\|Lab CKS-03]], [[Kubernetes/labs/cks/14-incident-investigation\|Lab CKS-14]] (unguided) |
| Ensure immutability of containers at runtime                       | [[Kubernetes/concepts/L07-security/02-workload-sandboxing/05-security-context\|SecurityContext]]                                                                                                     | [[Kubernetes/labs/cks/05-seccomp-apparmor-and-immutability\|Lab CKS-05]]                                                                                                                       |
| Use Kubernetes audit logs to monitor access                        | [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/15-audit-logging\|Audit Logging]]                                                                                                         | [[Kubernetes/labs/cks/03-audit-logging\|Lab CKS-03]]                                                                                                                                           |

**Task drills**

- [ ] Read Falco output on a node (`journalctl -u falco` or its log file), identify which Pod spawned a shell or wrote under `/etc`, and scale its Deployment to zero.
- [ ] Change the output format of an existing Falco rule to include specific fields, and override a rule in the local rules file instead of editing the default one.
- [ ] Find the container running an unexpected process using `crictl ps`, `crictl inspect` and the process ID on the node.
- [ ] Make a container immutable: read-only root filesystem, `emptyDir` only for the paths that must be writable, no privilege escalation.
- [ ] Write an audit policy that logs Secrets at `Metadata`, a named namespace at `RequestResponse` and drops everything else, then enable it on the API server with log path, max age, max backups and the two volume mounts.
- [ ] From an audit log, find who deleted a given Secret and when.

---

## Gaps in the wiki

| Objective                                      | What is missing                                                                                                                                          | Use instead                                                                                                                       |
| :--------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------- | :-------------------------------------------------------------------------------------------------------------------------------- |
| AppArmor                                       | Lab CKS-05 includes it, but that section was not run because `kind` nodes do not expose AppArmor                                                         | Run the section on a virtual machine node, and pin the Pod to the node where the profile is loaded                                |
| Signature verification at admission            | Lab CKS-09 signs and verifies with the CLI and enforces digests. A digest policy admits an **unsigned** image; no lab makes the cluster check signatures | [Kyverno verifyImages](https://kyverno.io/docs/policy-types/cluster-policy/verify-images/)                                        |
| A working ImagePolicyWebhook backend           | Lab CKS-08 configures the plugin with no backend, which proves the fail-closed path only, not TLS, the ImageReview exchange or an allow/deny decision    | [ImagePolicyWebhook](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#imagepolicywebhook)           |
| Cilium mutual authentication                   | Lab CKS-11 covers encryption; `authentication.mode: required` needs SPIRE and is not practised                                                           | [Cilium mutual authentication](https://docs.cilium.io/en/stable/network/servicemesh/mutual-authentication/mutual-authentication/) |
| Least-privilege identity and access management | Host and cloud IAM are reading only. Kubernetes RBAC is covered by Lab CKS-13                                                                            | [[Kubernetes/guides/non-functional/oidc-integration\|OIDC Integration]]                                                           |
| Investigation with detection tooling           | Lab CKS-14 investigates from API and node evidence only. No lab correlates audit-log and Falco evidence for an unknown actor                             | Repeat Lab CKS-14 on a cluster with Lab CKS-03's audit policy enabled                                                             |
| Unguided practice for CKS-02 to CKS-12         | These labs are guided walk-throughs with no independent task or check                                                                                    | The [[Kubernetes/certifications/cks-mock-exam\|CKS practice set]] and the domain drills                                           |
| Re-run on Kubernetes v1.37                     | CKS-02 to CKS-12 were last run on v1.35.0                                                                                                                | Run them on a v1.35 cluster, which matches the exam, or expect minor output differences                                           |
| Independent grading                            | The practice tasks give checks you run yourself; nothing scores you automatically                                                                        | The exam simulator, if your registration includes it                                                                              |

---

## Study plan

The plan below is a **revision schedule for someone with a recent CKA**, at about an hour a day. It does not include provisioning a virtual machine for AppArmor. Finishing it is not a pass prediction.

| Week | Focus                                                                                   | Practice                                                      |
| :--- | :-------------------------------------------------------------------------------------- | :------------------------------------------------------------ |
| 1    | L07 overview, domain 2 (RBAC, ServiceAccounts, API access)                              | Lab CKS-01, Lab CKS-13, domain 2 drills                       |
| 2    | Domain 1 (NetworkPolicy, CIS benchmark, Ingress TLS)                                    | Lab CKS-02, Lab CKAD-09                                       |
| 3    | Domain 4 (Pod Security Standards, Secrets encryption, sandboxing, policy engines)       | Lab CKS-04, Lab CKS-10, Lab CKS-11                            |
| 4    | Domain 3 (AppArmor, seccomp, host footprint), domain 5 (images, Trivy, SBOM, admission) | Lab CKS-05, Lab CKS-12, Lab CKS-07, Lab CKS-08, Lab CKS-09    |
| 5    | Domain 6 (Falco, audit logging, immutability, investigation)                            | Lab CKS-03, Lab CKS-06, Lab CKS-14                            |
| 6    | The timed practice set, weak spots, the simulator sessions if you have them             | [[Kubernetes/certifications/cks-mock-exam\|CKS practice set]] |

## Ready when

- [ ] You can edit the API server manifest, add a flag with its volume and mount, and recover promptly when the API server fails to restart, using `crictl` and the container's log to find the mistake.
- [ ] You can write an audit policy and an `EncryptionConfiguration` starting from the documentation page, and verify each from evidence: a log entry, a ciphertext prefix in etcd.
- [ ] For every control you apply, you can name one request that must still succeed and one that must now fail, and you test both.
- [ ] You know where each tool keeps its configuration and output on a node: Falco rules, AppArmor profiles, seccomp profiles, audit logs.
- [ ] You finish the [[Kubernetes/certifications/cks-mock-exam|CKS practice set]] inside two hours at or above the pass mark, using only the sites the CKS allows.
- [ ] If you have the simulator, your second session is at or above the pass mark.

## Further reading

- [CKS curriculum](https://github.com/cncf/curriculum)
- [CKS exam page](https://training.linuxfoundation.org/certification/certified-kubernetes-security-specialist/)
- [Securing a cluster](https://kubernetes.io/docs/tasks/administer-cluster/securing-a-cluster/)
- [Falco documentation](https://falco.org/docs/)
- [Trivy documentation](https://trivy.dev/latest/docs/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)

## Across the wiki

- [[Kubernetes/certifications/cka|CKA Track]]: the prerequisite exam.
- [[Kubernetes/certifications/ckad|CKAD Track]]
- [[Security/kubernetes-security/README|Kubernetes Security]]: the security domain's view of the same topics.
- [[Security/zero-trust|Zero Trust]]
- [[Kubernetes/eks/security/README|EKS Security]]: how these controls map onto a managed cluster.
