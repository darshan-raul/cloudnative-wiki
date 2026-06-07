# Security (L07 Overview)

*"https://kubernetes.io/docs/concepts/security/"*

A high-level overview of the **security model** in Kubernetes. Use this as a quick reference for "where do I look when I have a security question". The deeper notes are linked below.

## The four concerns

Kubernetes "security" is actually four different things:

1. **API access** — who can talk to the apiserver, and what can they do
2. **Workload sandboxing** — what a Pod is allowed to do on the node
3. **Network policy** — what traffic is allowed between Pods
4. **Supply chain** — what code/images are allowed to run, and how they're signed

```
┌──────────────────────────────────────────────────────┐
│  1. API access (authn, authz, ServiceAccounts)       │
│     → [[01-authentication-authorization]]            │
│     → [[03-rbac]]                                    │
│     → [[02-service-accounts]]                        │
└──────────────────────────────────────────────────────┘
                ↓
┌──────────────────────────────────────────────────────┐
│  2. Workload sandboxing (PSS, SecurityContext)       │
│     → [[06-pod-security-standards]]                  │
│     → [[05-security-context]]                        │
└──────────────────────────────────────────────────────┘
                ↓
┌──────────────────────────────────────────────────────┐
│  3. Network policy (NetworkPolicy, CNI)              │
│     → [[L04-services-networking/05-network-policy|network-policy]]  │
└──────────────────────────────────────────────────────┘
                ↓
┌──────────────────────────────────────────────────────┐
│  4. Supply chain (image scanning, signing, admission)│
│     → [[guides/security-scanning|security-scanning]]│
│     → [[guides/image-signing|image-signing]]         │
└──────────────────────────────────────────────────────┘
```

This section (L07) covers concerns 1 and 2. Concern 3 is in L04 (network-policy). Concern 4 is in the guides (security-scanning, image-signing).

## The defense-in-depth stack

A production cluster has **multiple layers** of security, each addressing a different threat:

```
Threat                    Defense
─────────────────────────────────────────────────────────
Unauthorized kubectl       OIDC SSO, RBAC, audit logs
Compromised kubelet        PSS restricted, SecurityContext
Compromised Pod → host     PSS, NetworkPolicy, seccomp, AppArmor
Compromised Pod → DB       NetworkPolicy, mTLS, secrets encryption
Compromised Pod → other    NetworkPolicy, mTLS
Pods
Compromised image          Image scanning, signed images,
                           admission control
Lateral movement           NetworkPolicy, microsegmentation
Data exfiltration          NetworkPolicy egress, audit logs
Privilege escalation       PSS baseline+, capabilities
                           dropped
```

The layers **complement each other** — no single layer is sufficient. A misconfigured NetworkPolicy + a privileged Pod = root on the host.

## The "Kubernetes security" checklist

A practical, ordered checklist. Work through it from the top.

### 1. The API server

* [ ] **Anonymous auth is disabled** (`--anonymous-auth=false`)
* [ ] **TLS is enforced** (`--tls-cert-file`, `--tls-private-key-file`)
* [ ] **Audit logging is enabled** and shipped off-cluster
* [ ] **RBAC is the only authorizer** (no ABAC)
* [ ] **OIDC is configured** for human users (no static tokens)
* [ ] **No static admin tokens** in `kube-system`
* [ ] **ServiceAccount tokens are short-lived** (bound tokens, k8s 1.21+)
* [ ] **Encryption at rest is enabled** for Secrets and ConfigMaps

### 2. Workload defaults

* [ ] **All namespaces have PSS labels** (`enforce=restricted` for app namespaces)
* [ ] **`kube-system` is `privileged`**, but tightly controlled
* [ ] **Default NetworkPolicy** is "deny all" + explicit allows
* [ ] **Default ServiceAccount** doesn't have any RoleBindings
* [ ] **ResourceQuotas** are set per namespace

### 3. Image / supply chain

* [ ] **Only approved registries** are allowed (admission webhook)
* [ ] **Images are scanned** for CVEs (Trivy, Grype, Snyk, etc.)
* [ ] **Critical / high CVEs block deployment**
* [ ] **Images are signed** (cosign, Notary) and verified at admission
* [ ] **No `:latest` tags** in production
* [ ] **Image pull policy is `IfNotPresent` or `Always`** (never omitted in prod)

### 4. Runtime

* [ ] **Containers run as non-root** (`runAsNonRoot: true`)
* [ ] **`readOnlyRootFilesystem: true`** for app containers
* [ ] **`allowPrivilegeEscalation: false`**
* [ ] **All capabilities dropped** except what's explicitly needed
* [ ] **seccomp profile is `RuntimeDefault`**
* [ ] **Resource limits are set** (memory limit is the most important)
* [ ] **Liveness / readiness probes are present**

### 5. Network

* [ ] **NetworkPolicy: default-deny in every namespace**
* [ ] **Explicit allows** for required traffic
* [ ] **Egress is restricted** to known destinations
* [ ] **mTLS** for in-cluster traffic (service mesh, or app-level)
* [ ] **Ingress is HTTPS-only** with valid certs
* [ ] **No ClusterIP services exposed publicly** without an Ingress or LoadBalancer

### 6. Secrets

* [ ] **No plaintext Secrets in git**
* [ ] **External secret manager** (Vault, AWS Secrets Manager, etc.) is the source of truth
* [ ] **Encryption at rest** is configured
* [ ] **RBAC restricts who can read Secrets** (resourceNames + Role)
* [ ] **ServiceAccount tokens are bound** to specific audiences

### 7. Operations

* [ ] **Audit logs are shipped off-cluster** and analyzed
* [ ] **Falco / Tetragon / similar** for runtime threat detection
* [ ] **Regular backups of etcd** (off-cluster, encrypted)
* [ ] **Disaster recovery tested** (can you restore from backup?)
* [ ] **Incident response plan** documented and practiced
* [ ] **CVE monitoring** for k8s and your dependencies

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

## The "Kubernetes security" landscape

A map of the ecosystem, organized by concern:

### API access
* **OIDC providers** — Okta, Auth0, Google, Azure AD, Keycloak
* **RBAC managers** — kubectl, Terraform k8s provider, ArgoCD
* **Audit** — k8s audit logs → Elasticsearch / Loki / Datadog

### Workload sandboxing
* **PSS** — built into k8s
* **OPA / Kyverno / Gatekeeper** — policy engines
* **gVisor, Kata Containers** — extra sandboxing
* **seccomp / AppArmor** — kernel-level restrictions
* **Falco / Tetragon** — runtime threat detection

### Network policy
* **CNI** — Calico, Cilium, Weave
* **NetworkPolicy** — built into k8s
* **Service mesh** — Istio, Linkerd, Cilium (for mTLS)
* **eBPF tools** — Cilium, Tetragon

### Supply chain
* **Image registries** — ECR, GCR, ACR, Harbor, Quay
* **Scanners** — Trivy, Grype, Snyk, Clair
* **Signers** — cosign (Sigstore), Notary
* **Admission controllers** — Connaisseur, Kyverno, OPA

### Secrets
* **External stores** — Vault, AWS Secrets Manager, Azure Key Vault
* **Operators** — External Secrets Operator, Vault Agent Injector
* **Encryption** — k8s encryption at rest, KMS providers

### Backup / DR
* **Velero** — backup / restore
* **etcd snapshots** — etcdctl, etcd-backup operators
* **Volume snapshots** — CSI snapshot support

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

`privileged: true` is almost never needed. If an app claims to need it, find out what capability it actually needs and grant that explicitly.

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

## What this section doesn't cover

* **Cloud-specific security** (IAM, KMS, security groups) — see [[Kubernetes/eks/security/README|EKS Security]] for EKS
* **Image scanning** in depth — see [[Kubernetes/guides/security-scanning|security-scanning]]
* **Image signing** — see [[Kubernetes/guides/image-signing|image-signing]]
* **Service mesh** security — see [[Kubernetes/guides/service-mesh|service-mesh]]
* **Secrets management** in depth — see [[Kubernetes/guides/secret-management|secret-management]]

## The notes in this level

→ [[Kubernetes/concepts/L07-security/01-authentication-authorization|Authentication vs Authorization]] — the conceptual split
→ [[Kubernetes/concepts/L07-security/02-service-accounts|ServiceAccounts]] — the in-cluster identity
→ [[Kubernetes/concepts/L07-security/03-rbac|RBAC]] — what each user / SA can do
→ [[Kubernetes/concepts/L07-security/04-certificates|Certificates]] — the cluster PKI
→ [[Kubernetes/concepts/L07-security/05-security-context|SecurityContext]] — the per-Pod hardening
→ [[Kubernetes/concepts/L07-security/06-pod-security-standards|Pod Security Standards]] — apply PSS cluster-wide

## See also

* [[Kubernetes/concepts/L04-services-networking/05-network-policy|NetworkPolicy]] — the network layer
* [[Kubernetes/eks/security/README|EKS Security]] — AWS-specific details
* [[Kubernetes/guides/security-scanning|security-scanning]] — image scanning in practice
