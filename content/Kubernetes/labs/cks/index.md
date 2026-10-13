---
title: CKS Labs
tags: [kubernetes, labs, cks, hands-on]
date: 2026-10-13
description: "Hands-on labs for the Certified Kubernetes Security Specialist exam, covering workload, API server and node hardening, supply chain security and runtime detection."
---

# CKS Labs

Fourteen labs for the [[Kubernetes/certifications/cks|CKS Track]]. Each is self-contained and most run on the `kind` cluster from [[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]]. Labs 09 and 11 create their own clusters, need more memory, and leave your kubectl context pointing elsewhere until you switch back.

Labs 01, 13 and 14 were run on Kubernetes v1.37.0. Labs 02 to 12 were run on v1.35.0, the version the exam used on 2026-10-13, and not re-run on v1.37.

Several labs edit the API server manifest. Each keeps its backup in its own directory under `/root/backup/` on the node. Do one lab at a time, finish its cleanup, and do [[Kubernetes/labs/cka/07-control-plane-and-kubelet-repair|Lab CKA-07]] first so a failed restart is something you can fix. Lab 04 changes how Secrets are stored, which restoring a manifest does not undo; recreate the cluster after it if in doubt.

| Lab                                                                          | Title                                       | Core Focus                                                                                                    | Controlled Failure Scenario                                                    |
| :--------------------------------------------------------------------------- | :------------------------------------------ | :------------------------------------------------------------------------------------------------------------ | :----------------------------------------------------------------------------- |
| [[Kubernetes/labs/cks/01-workload-security-hardening\|CKS-01]]               | **Workload Security Hardening**             | Inventory, ServiceAccounts, RBAC, Pod Security Standards, `securityContext`, NetworkPolicy with a test matrix | Enforcement that leaves old Pods running; privileged Pod rejected at admission |
| [[Kubernetes/labs/cks/02-cis-benchmark-kube-bench\|CKS-02]]                  | **CIS Benchmark with kube-bench**           | Running the benchmark, reading remediations, fixing component flags                                           | Hardening flag that stops the API server                                       |
| [[Kubernetes/labs/cks/03-audit-logging\|CKS-03]]                             | **Audit Logging**                           | Audit policy, API server flags and mounts, querying the log                                                   | Policy file not mounted into the container                                     |
| [[Kubernetes/labs/cks/04-secrets-encryption-at-rest\|CKS-04]]                | **Secrets Encryption at Rest**              | EncryptionConfiguration, re-encrypting, reading etcd directly                                                 | Losing the encryption key                                                      |
| [[Kubernetes/labs/cks/05-seccomp-apparmor-and-immutability\|CKS-05]]         | **Seccomp, AppArmor & Immutability**        | RuntimeDefault and Localhost profiles, read-only root filesystem                                              | Profile missing on the node                                                    |
| [[Kubernetes/labs/cks/06-falco-runtime-detection\|CKS-06]]                   | **Falco Runtime Detection**                 | Reading alerts, tracing to a Pod, custom rules, overrides                                                     | Invalid rule that stops Falco                                                  |
| [[Kubernetes/labs/cks/07-image-scanning-and-static-analysis\|CKS-07]]        | **Image Scanning & Static Analysis**        | Trivy, SBOMs, kubesec, KubeLinter, binary checksums                                                           | Scan flags that change the answer                                              |
| [[Kubernetes/labs/cks/08-image-admission-control\|CKS-08]]                   | **Image Admission Control**                 | ValidatingAdmissionPolicy, ImagePolicyWebhook                                                                 | Replacing the admission plugin list                                            |
| [[Kubernetes/labs/cks/09-image-signing-with-cosign\|CKS-09]]                 | **Image Signing with cosign**               | Key pairs, signing by digest, verification, digest-only admission                                             | Tag overwritten with unsigned content                                          |
| [[Kubernetes/labs/cks/10-runtime-sandboxing-gvisor\|CKS-10]]                 | **Runtime Sandboxing with gVisor**          | Installing `runsc`, containerd handler, RuntimeClass                                                          | Missing class versus missing handler                                           |
| [[Kubernetes/labs/cks/11-cilium-encryption-and-metadata-protection\|CKS-11]] | **Cilium Encryption & Metadata Protection** | WireGuard transparent encryption, packet capture, egress `ipBlock`                                            | Egress policy that also blocks the cluster                                     |
| [[Kubernetes/labs/cks/12-host-os-footprint\|CKS-12]]                         | **Host OS Footprint**                       | Listening ports, tracing to a package, removing services, blocking kernel modules                             | Stopping the kubelet by mistake                                                |
| [[Kubernetes/labs/cks/13-rbac-remediation\|CKS-13]]                          | **RBAC Remediation**                        | Finding every grant to an identity, least privilege, allowed and denied checks                                | A binding that names the wrong namespace                                       |
| [[Kubernetes/labs/cks/14-incident-investigation\|CKS-14]]                    | **Investigating an Unknown Incident**       | Unguided: find the workload, its actions and reach, contain it and keep the evidence                          | A containment step that recreates the workload                                 |

The AppArmor section of Lab CKS-05 needs a virtual machine node. Remaining gaps are listed in the track's gap table. Test yourself with the [[Kubernetes/certifications/cks-mock-exam|CKS practice set]], which covers only part of the exam's range.
