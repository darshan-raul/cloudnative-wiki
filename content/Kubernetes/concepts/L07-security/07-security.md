# Security (L07 Overview)

*"https://kubernetes.io/docs/concepts/security/"*

A high-level overview of the **security model** in Kubernetes. Use this as a quick reference for "where do I look when I have a security question". The deeper notes are linked in the [[Kubernetes/concepts/L07-security/00-README|L07 README]].

## The five concerns

Kubernetes "security" is actually five different things:

1. **API access** — who can talk to the apiserver, and what can they do.
2. **Workload sandboxing** — what a Pod is allowed to do on the node.
3. **Network policy** — what traffic is allowed between Pods.
4. **Encryption** — at rest and in transit.
5. **Supply chain + detection** — what code/images are allowed to run, and how to detect what got through.

```
┌──────────────────────────────────────────────────────┐
│  1. API access (authn, authz, ServiceAccounts)       │
│     → 01-authentication-authorization                │
│     → 02-service-accounts                            │
│     → 03-rbac                                        │
│     → 04-certificates                                │
└──────────────────────────────────────────────────────┘
                ↓
┌──────────────────────────────────────────────────────┐
│  2. Workload sandboxing (PSS, SecurityContext,       │
│     seccomp, AppArmor, runtime sandboxing)           │
│     → 05-security-context                            │
│     → 06-pod-security-standards                      │
│     → 16-seccomp-apparmor                            │
│     → 17-runtime-sandboxing                          │
└──────────────────────────────────────────────────────┘
                ↓
┌──────────────────────────────────────────────────────┐
│  3. Network policy + mTLS (NetworkPolicy, CNI,      │
│     service mesh, SPIFFE)                            │
│     → L04 network-policy                             │
│     → 08-tls-mtls                                    │
│     → 09-spiffe-spire                                │
└──────────────────────────────────────────────────────┘
                ↓
┌──────────────────────────────────────────────────────┐
│  4. Encryption (etcd, Secrets, in transit)            │
│     → 13-etcd-encryption                             │
│     → 14-secret-encryption                           │
└──────────────────────────────────────────────────────┘
                ↓
┌──────────────────────────────────────────────────────┐
│  5. Supply chain + detection (admission, image       │
│     scanning, signing, runtime detection, audit)     │
│     → 10-admission-controllers                       │
│     → 11-opa-gatekeeper                              │
│     → 12-kyverno                                     │
│     → 15-audit-logging                               │
│     → 18-runtime-detection                           │
│     → 19-image-hardening                             │
│     → 22-compliance-frameworks                       │
└──────────────────────────────────────────────────────┘
```

Concern 1 and 2 are in this L07. Concern 3 is in L04 (network-policy) and the TLS/mTLS/SPIFFE notes here. Concern 4 is the encryption notes. Concern 5 is the admission, runtime, image, and compliance notes.

## The threat model

Different threats require different defenses. Map your controls to threats:

| Threat | Primary defense | Secondary |
|---|---|---|
| Compromised user credential | OIDC + short sessions, audit logs | RBAC least-privilege |
| Compromised ServiceAccount | Bound tokens, audience-scoped | NetworkPolicy, mTLS |
| Compromised container image | Image scanning, signed images | PSS, NetworkPolicy |
| Compromised Pod | PSS, SecurityContext, seccomp | NetworkPolicy, Falco |
| Compromised kubelet | NodeRestriction, etcd encryption | Audit logs |
| Compromised etcd | etcd access control, encryption at rest | Backups, DR |
| Network sniffing | TLS everywhere, mTLS in cluster | NetworkPolicy |
| Insider threat | Audit logs, RBAC, separation of duties | OIDC, MFA |
| Misconfiguration | OPA / Kyverno, admission policies | PSS, NetworkPolicy |
| Kernel exploit | seccomp, RuntimeClass (gVisor / Kata) | Node hardening |

## The "Kubernetes security" checklist (priority order)

A practical, ordered checklist. Work through it from the top.

### 1. The API server

- [ ] **Anonymous auth is disabled** (`--anonymous-auth=false`)
- [ ] **TLS is enforced** (`--tls-cert-file`, `--tls-private-key-file`, `--tls-min-version=VersionTLS12`)
- [ ] **RBAC is the only authorizer** (`--authorization-mode=Node,RBAC`)
- [ ] **OIDC is configured** for human users (no static tokens)
- [ ] **ServiceAccount tokens are short-lived** (bound tokens, k8s 1.21+)
- [ ] **Encryption at rest is enabled** for Secrets (EncryptionConfiguration + KMS)

### 2. Workload defaults

- [ ] **All namespaces have PSS labels** (`enforce=restricted` for app namespaces)
- [ ] **`kube-system` is `privileged`**, but tightly controlled
- [ ] **Default NetworkPolicy** is "deny all" + explicit allows
- [ ] **Default ServiceAccount** has no RoleBindings
- [ ] **ResourceQuotas and LimitRanges** are set per namespace

### 3. Image / supply chain

- [ ] **Only approved registries** are allowed (admission webhook / Kyverno)
- [ ] **Images are scanned** for CVEs (Trivy, Grype, Snyk)
- [ ] **Critical / high CVEs block deployment** (CI gate)
- [ ] **Images are signed** (cosign, Notary) and verified at admission
- [ ] **SBOMs are generated** for every image
- [ ] **No `:latest` tags** in production
- [ ] **Image pull policy is `IfNotPresent` for versioned tags**

### 4. Runtime hardening

- [ ] **Containers run as non-root** (`runAsNonRoot: true`)
- [ ] **`readOnlyRootFilesystem: true`** for app containers
- [ ] **`allowPrivilegeEscalation: false`**
- [ ] **All capabilities dropped** except what's explicitly needed
- [ ] **seccomp profile is `RuntimeDefault`**
- [ ] **Resource limits are set** (memory limit is the most important)
- [ ] **Liveness / readiness probes are present**

### 5. Network

- [ ] **NetworkPolicy: default-deny in every namespace**
- [ ] **Explicit allows** for required traffic
- [ ] **Egress is restricted** to known destinations
- [ ] **mTLS** for in-cluster traffic (service mesh, or app-level)
- [ ] **Ingress is HTTPS-only** with valid certs
- [ ] **No ClusterIP services exposed publicly** without an Ingress or LoadBalancer

### 6. Secrets

- [ ] **No plaintext Secrets in git**
- [ ] **External secret manager** (Vault, AWS Secrets Manager) is the source of truth
- [ ] **Encryption at rest** is configured (etcd encryption)
- [ ] **RBAC restricts who can read Secrets** (resourceNames + Role)
- [ ] **ServiceAccount tokens are bound** to specific audiences

### 7. Detection and response

- [ ] **Audit logs are enabled** and shipped off-cluster (audit.log or webhook to SIEM)
- [ ] **Runtime threat detection** is running (Falco / Tetragon)
- [ ] **kube-bench is run regularly** (CIS benchmark)
- [ ] **Regular backups of etcd** (off-cluster, encrypted)
- [ ] **Disaster recovery tested** (can you restore from backup?)
- [ ] **Incident response plan** documented and practiced
- [ ] **CVE monitoring** for k8s and your dependencies

### 8. Compliance (if applicable)

- [ ] **NIST 800-190** controls implemented
- [ ] **CIS Kubernetes Benchmark** passing (kube-bench report)
- [ ] **OWASP k8s Top 10** issues addressed
- [ ] **PCI-DSS / SOC2 / HIPAA / FedRAMP** controls as required by your auditors

## Common security anti-patterns

### 1. "Just give it cluster-admin"

```yaml
# DON'T
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: { name: jane }
subjects:
- kind: User
  name: jane
roleRef:
  kind: ClusterRole
  name: cluster-admin
```

Instead, give the smallest set of permissions actually needed.

### 2. "Default ServiceAccount has permissions"

The `default` ServiceAccount should have **no** permissions. Don't bind it to anything.

### 3. "Privileged containers because the app needs it"

`privileged: true` is almost never needed. Find out what capability is actually needed and grant that explicitly.

### 4. "Networking is fine, all Pods can talk"

Without NetworkPolicy, all Pods can talk. A compromised Pod can reach the database, the API server, every other Pod. **Default-deny is the right starting point.**

### 5. "Secrets in environment variables"

Env vars are visible in `/proc/<pid>/environ`. Files are only readable by the container's UID. Prefer files.

### 6. "No resource limits"

A container with no memory limit can OOM-kill the whole node. Always set `limits.memory` (at minimum).

### 7. "Plaintext Secrets in git"

Use Sealed Secrets, SOPS, or an external manager. Don't commit plaintext.

### 8. "Trusting the registry"

Pulling from public Docker Hub is a known attack vector. Use a private registry, scan images, sign them.

### 9. "Ad-hoc kubectl from anywhere"

Bind RBAC to OIDC groups, restrict by namespace, audit the access. Don't allow `kubectl` from random IPs.

## The "shift left" idea

Catch security issues at **build / deploy time**, not at runtime. Each layer you shift left is a layer that doesn't need runtime defense:

```
LATE (runtime)                           EARLY (build)
  ↓                                          ↑
  Falco detecting an exploit           Trivy blocking the image at build
  PSS blocking a Pod at admission      OPA blocking a manifest at apply
  NetworkPolicy blocking traffic       Snyk scanning a Dockerfile at PR
```

Tools for shift-left:

* **Trivy** — image scan, runs in CI
* **Snyk** — code, image, IaC scan
* **Conftest / OPA** — manifest validation
* **Datree** — policy-as-code
* **Kyverno** — admission control
* **Connaisseur** — image signature verification at admission

## The compliance question

If you have to satisfy a framework (PCI-DSS, SOC2, HIPAA, FedRAMP), k8s has answers for most things but you need to know what the auditor wants:

* **Audit logs** — k8s audit policy, shipped to immutable storage
* **Encryption at rest** — etcd encryption + cloud storage encryption
* **Encryption in transit** — TLS everywhere (apiserver, etcd, kubelet)
* **Access control** — RBAC + OIDC + MFA at the IdP
* **Network segmentation** — NetworkPolicy + separate namespaces
* **Vulnerability management** — image scanning + k8s CVE monitoring
* **Backups** — Velero + etcd snapshots
* **Disaster recovery** — tested restore procedures
* **Logging** — pod logs + control plane logs to a SIEM

Most compliance failures in k8s are **not k8s problems** — they're organizational problems (no runbook, no review, no off-cluster backups).

See [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/22-compliance-frameworks|Compliance Frameworks]] for the full picture.

## The L07 layer at a glance

This section (L07) is the **largest** of the concept layers, with 22 notes. The other layers are smaller; security is the broadest topic.

For a **fast read**: start with the [[Kubernetes/concepts/L07-security/00-README|L07 README]], then read this overview, then dive into the specific note for your concern.

For a **complete read**: follow one of the four reading paths in the README (API access, workload hardening, encryption, operations/compliance).

## See also

* [[Kubernetes/concepts/L07-security/00-README|L07 README]] — the full note list
* [[Kubernetes/concepts/L04-services-networking/05-network-policy|NetworkPolicy]] — the network layer
* [[Kubernetes/eks/security/README|EKS Security]] — AWS-specific details
* [[Kubernetes/guides/security-scanning|security-scanning]] — image scanning in practice
* [[Kubernetes/guides/image-signing|image-signing]] — image signing in practice
* [[Kubernetes/guides/secrets-management|secrets-management]] — external secret stores
