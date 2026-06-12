---
title: Security Baseline
tags:
  - Kubernetes
  - Non-Functional
  - Security
  - Pod Security Standards
  - NetworkPolicy
  - Policy
---

A practical, layered security baseline for a k8s cluster. **Defense in depth** — assume any single layer will fail. The goal isn't perfection, it's reducing the blast radius of compromise.

## The layers

```
┌─────────────────────────────────────────────────────────────┐
│  Cluster access (auth, RBAC, OIDC)                          │
├─────────────────────────────────────────────────────────────┤
│  Network (NetworkPolicy, service mesh, mTLS)                │
├─────────────────────────────────────────────────────────────┤
│  Workload (Pod Security Standards, seccomp, AppArmor)       │
├─────────────────────────────────────────────────────────────┤
│  Image (registry, scanning, signing)                        │
├─────────────────────────────────────────────────────────────┤
│  Runtime (admission control, Falco, audit logs)            │
├─────────────────────────────────────────────────────────────┤
│  Data (encryption at rest, secret management)              │
└─────────────────────────────────────────────────────────────┘
```

Failing any single layer is a vulnerability. Failing multiple = breach.

## Cluster access

### Authentication

**Production baseline:** no static credentials, no service account tokens in git, OIDC for users, IRSA/Workload Identity for service accounts.

```bash
# verify auth methods on the cluster
kubectl api-versions | grep authentication
# should see: authentication.k8s.io/v1

# see who's authenticated
kubectl auth whoami    # k8s 1.28+
# or
kubectl get cm -n kube-system -o jsonpath='{.items[*].data}' | grep -i "authn"
```

**Disable legacy auth:**

```yaml
# apiserver
--authorization-mode=Node,RBAC
--enable-bootstrap-token-auth=true
# disable token-based static auth in production
--token-auth-file=/dev/null
--basic-auth-file=/dev/null
```

**Audit auth:**

```bash
# check for static creds in use
grep -r "token:" ~/.kube/config
# bad: hardcoded tokens in kubeconfig
# good: exec-based auth (aws-iam, gke-gcloud, oidc-login)
```

### RBAC

**Default:** nothing has admin. Build roles from least-privilege.

```yaml
# bad: too permissive
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dev-all
subjects:
- kind: Group
  name: developers
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin   # too much
  apiGroup: rbac.authorization.k8s.io

# good: namespace-scoped, read-only
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-read
  namespace: dev
subjects:
- kind: Group
  name: developers
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: view
  apiGroup: rbac.authorization.k8s.io
```

**Check who can do what:**

```bash
# can I do X?
kubectl auth can-i create pods -n prod

# what can I do?
kubectl auth can-i --list -n prod

# as a ServiceAccount
kubectl auth can-i create pods -n prod --as=system:serviceaccount:dev:default
```

**Disable `system:anonymous`:**

```yaml
# apiserver
--anonymous-auth=false
```

Anonymous requests should be denied by default. RBAC allows them, which can be surprising.

### etcd

etcd holds all cluster state. Securing etcd is critical.

- **TLS for client connections** — required since k8s 1.13
- **TLS for peer connections** — etcd cluster members authenticate to each other
- **Encryption at rest** — encrypt secrets in etcd (see below)
- **Restrict network access** — only the apiserver should reach etcd
- **Backup encryption** — etcd backups can contain secrets, encrypt them

```yaml
# apiserver
--etcd-servers=https://etcd-1:2379,https://etcd-2:2379,https://etcd-3:2379
--etcd-cafile=/etc/kubernetes/pki/etcd-ca.crt
--etcd-certfile=/etc/kubernetes/pki/apiserver-etcd.crt
--etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd.key
```

## Network isolation

### Default-deny NetworkPolicy

**The single most important network control.** Default-deny + explicit allows is much safer than allow-by-default.

```yaml
# default-deny: no traffic in or out
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: my-app
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  # no rules = nothing allowed
---
# allow DNS
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: my-app
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
---
# allow ingress from the ingress controller
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-ingress
  namespace: my-app
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
    ports:
    - port: 8080
      protocol: TCP
```

### Service mesh for mTLS

For pod-to-pod encryption without a mesh, you'd need to manage certs in every app. A service mesh (Istio, Linkerd, Cilium) handles this transparently.

**Istio mTLS:**

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: my-app
spec:
  mtls:
    mode: STRICT    # require mTLS for all pods in namespace
```

**When to use mTLS:**

- Compliance requirement (PCI-DSS, HIPAA, etc.)
- Multi-tenant cluster
- Zero-trust posture
- Pod-to-pod traffic carries sensitive data

**When NOT to use mTLS:**

- Performance-critical paths (mTLS adds ~1-2ms per hop)
- Small clusters where the operational cost of a mesh isn't worth it

### Ingress TLS

**Always use TLS at the ingress.** Modern certs are free (Let's Encrypt via cert-manager).

```yaml
# cert-manager Certificate
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: app-cert
  namespace: my-app
spec:
  secretName: app-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - app.example.com
```

```yaml
# Ingress with TLS
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
  namespace: my-app
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
  - hosts:
    - app.example.com
    secretName: app-tls
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web
            port:
              number: 80
```

## Workload security (Pod Security Standards)

The modern baseline is the **Pod Security Standards** (PSS) — three levels: `privileged`, `baseline`, `restricted`.

| Level | What's allowed |
|-------|----------------|
| `privileged` | Anything (escape hatch) |
| `baseline` | Minimal restrictions, prevents known privilege escalations |
| `restricted` | Hardened, current best practices |

**Production target: `restricted`.**

Apply at namespace level:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-app
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

**What `restricted` blocks:**

- Privileged containers
- Host namespaces (network, PID, IPC)
- HostPath volumes
- Host ports
- Running as root (must be non-root UID)
- Privilege escalation (no `allowPrivilegeEscalation: true`)
- Linux capabilities (no `NET_ADMIN`, etc.)
- AppArmor, seccomp default
- Many more

**What the restricted pod spec looks like:**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: web
    image: myorg/web:v1
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 512Mi
    volumeMounts:
    - name: tmp
      mountPath: /tmp
  volumes:
  - name: tmp
    emptyDir: {}
```

**Audit mode** is great for adoption — it shows what would be blocked, without blocking:

```yaml
pod-security.kubernetes.io/audit: restricted
pod-security.kubernetes.io/enforce: baseline
```

Start in audit, see what fails, fix, then enforce.

### Seccomp and AppArmor

**Seccomp** (Secure Computing Mode) restricts which syscalls a process can make. K8s has built-in support.

```yaml
securityContext:
  seccompProfile:
    type: RuntimeDefault    # or "Localhost" for custom profiles
```

**AppArmor** is more powerful but Linux-only. K8s supports it via annotations:

```yaml
metadata:
  annotations:
    container.apparmor.security.beta.kubernetes.io/web: runtime/default
```

**Best practice:** start with `RuntimeDefault`. It blocks the most dangerous syscalls without breaking apps.

## Image security

### Scanning

Scan every image for known CVEs. Tools:

- **Trivy** — open source, easy
- **Snyk** — commercial, comprehensive
- **Grype / Anchore** — open source
- **EKS Image Scanning** — built-in to ECR
- **GCR / GAR** — built-in to GCR

```bash
# Trivy
trivy image myorg/web:v1
# output: HIGH, MEDIUM, LOW CVEs

# in CI
trivy image --exit-code 1 --severity HIGH,CRITICAL myorg/web:v1
# fails the build if any HIGH/CRITICAL CVE
```

**Where to enforce:**

- **In CI** — block builds with critical CVEs
- **At admission** — block deployments with critical CVEs (Kyverno, OPA)
- **Continuously** — re-scan images on a schedule, alert on new CVEs

### Signing

Image signing proves an image wasn't tampered with. Tools:

- **Cosign (Sigstore)** — open source, free
- **Notary** — Docker's signing
- **AWS Signer** — for ECR images

```bash
# sign an image
cosign sign --key cosign.key myorg/web:v1

# verify at admission (Kyverno)
cosign verify --key cosign.pub myorg/web:v1
```

### Minimal base images

Smaller images have fewer CVEs.

```dockerfile
# bad: 1.2 GB, hundreds of CVEs
FROM ubuntu:22.04

# better: 80 MB, far fewer CVEs
FROM alpine:3.20

# best: 20 MB, almost no CVEs
FROM gcr.io/distroless/static:nonroot

# or
FROM cgr.dev/chainguard/static:latest
```

**Distroless** and **Chainguard** are purpose-built for security:
- No shell, no package manager
- No CVEs (Chainguard rebuilds daily)
- Run as non-root

### Pull policy and image digest pinning

Pin to a digest, not a tag:

```yaml
# bad: tag can change
image: myorg/web:v2

# better: digest is immutable
image: myorg/web:v2@sha256:abc123...
```

The digest is the actual content hash. Tags are mutable.

## Secret management

### Don't put secrets in environment variables

Plain env vars are visible in:
- `kubectl describe pod`
- `kubectl logs` (if the app logs env vars)
- Container runtime debug
- Crash dumps

**Use volume mounts:**

```yaml
volumes:
- name: db-creds
  secret:
    secretName: db-credentials
containers:
- name: web
  volumeMounts:
  - name: db-creds
    mountPath: /etc/db
    readOnly: true
# the file is at /etc/db/password
```

### Encrypt secrets at rest in etcd

```yaml
# apiserver
--encryption-provider-config=/etc/kubernetes/encryption-config.yaml
```

```yaml
# /etc/kubernetes/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
    - secrets
    providers:
    - aescbc:
        keys:
        - name: key1
          secret: <base64-encoded-32-byte-key>
    - identity: {}
```

**Rotate the key regularly.** Old keys are kept for decryption of existing data; new keys are used for encryption.

### External secret stores

Don't store secrets in k8s at all. Use:
- **HashiCorp Vault** — pull secrets at runtime
- **AWS Secrets Manager / SSM Parameter Store** — with ESO (External Secrets Operator)
- **GCP Secret Manager** — with ESO
- **Azure Key Vault** — with ESO

```yaml
# ExternalSecrets
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: db-credentials   # k8s Secret to create
  data:
  - secretKey: password
    remoteRef:
      key: secret/data/db
      property: password
```

The k8s Secret is auto-generated from Vault. Rotate in Vault, k8s Secret updates, pods restart (or hot-reload).

## Runtime security

### Audit logging

The apiserver's audit log is the source of truth for "who did what." Enable it.

```yaml
# apiserver
--audit-policy-file=/etc/kubernetes/audit-policy.yaml
--audit-log-path=/var/log/kubernetes/audit.log
--audit-log-maxage=30
--audit-log-maxbackup=10
--audit-log-maxsize=100
```

```yaml
# audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: Metadata
  namespaces: ["prod", "staging"]
- level: Request
  verbs: ["create", "update", "patch", "delete"]
  resources:
  - group: ""
    resources: ["pods", "services", "secrets", "configmaps"]
```

**Send to a SIEM (Splunk, Elasticsearch, Datadog) for analysis.**

### Runtime detection with Falco

Falco (CNCF) detects anomalous runtime behavior:
- Shell spawned in container
- Sensitive file accessed
- Outbound connection to suspicious IP
- Unexpected process

```yaml
# Falco rule
- rule: Shell in container
  desc: A shell was spawned in a container
  condition: >
    spawned_process and container and
    proc.name in (bash, sh, zsh, fish, ksh)
  output: >
    shell spawned in container
    (user=%user.name container=%container.name image=%container.image.repository
     shell=%proc.name command=%proc.cmdline)
  priority: WARNING
```

**Deploy via Helm:**

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm install falco falcosecurity/falco --namespace falco --create-namespace
```

### Admission control

Admission controllers are the gatekeepers. They run on every request to the apiserver.

**Built-in:**

- `PodSecurity` — enforces PSS
- `LimitRanger` — enforces resource limits
- `ResourceQuota` — enforces namespace quotas
- `NodeRestriction` — restricts kubelet permissions
- `ServiceAccount` — auto-mounts SA tokens

**Third-party (recommended):**

- **OPA Gatekeeper** — Rego-based policy
- **Kyverno** — YAML-based policy (easier than Rego)
- **ValidatingAdmissionPolicy** (k8s 1.30+) — CEL-based, built-in

**Example: Kyverno policy requiring resource limits**

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-limits
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-limits
    match:
      any:
      - resources:
          kinds:
          - Pod
    validate:
      message: "All containers must have CPU and memory limits."
      pattern:
        spec:
          containers:
          - resources:
              limits:
                memory: "?*"
                cpu: "?*"
```

**Example: block privileged containers**

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: block-privileged
spec:
  validationFailureAction: Enforce
  rules:
  - name: deny-privileged
    match:
      any:
      - resources:
          kinds:
          - Pod
    validate:
      message: "Privileged containers are not allowed."
      pattern:
        spec:
          containers:
          - securityContext:
              privileged: "false|nil"
```

## Compliance frameworks

If you're subject to compliance (PCI-DSS, HIPAA, SOC 2, FedRAMP), k8s has a few options:

- **CIS Benchmark** — `kube-bench` checks your cluster against CIS
- **NSA/CISA Hardening Guide** — k8s-specific
- **Compliance Operator** — automates compliance scanning
- **Cloud-specific** — EKS has AWS Audit Manager, GKE has GKE Security Posture

```bash
# kube-bench
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml
kubectl logs job/kube-bench
# shows PASS/FAIL/WARN for each CIS check
```

## The security baseline checklist

For a production cluster:

- [ ] **Auth**: OIDC for users, no static tokens, IRSA/Workload Identity for service accounts
- [ ] **RBAC**: least-privilege, namespace-scoped, regular `auth can-i` audits
- [ ] **etcd**: TLS, encryption at rest, restricted network access
- [ ] **Network**: default-deny NetworkPolicy, ingress TLS, mTLS for sensitive traffic
- [ ] **Workload**: PSS `restricted` enforced, seccomp `RuntimeDefault`, no privileged containers
- [ ] **Images**: scanned in CI, signed (cosign), minimal base images, digest pinning
- [ ] **Secrets**: external store (Vault/SSM), volume mounts not env vars, etcd encryption
- [ ] **Runtime**: audit logging to SIEM, Falco for anomaly detection
- [ ] **Admission**: Kyverno/OPA for policy enforcement
- [ ] **Compliance**: kube-bench regular runs, scan results tracked

## Common gotchas

* **PSS `restricted` breaks some apps.** Audit first, fix, then enforce. The "fix" usually involves a few lines in the pod spec.
* **NetworkPolicy doesn't apply if the CNI doesn't support it.** Flannel and basic Calico don't enforce. Use Calico, Cilium, or Weave for production.
* **`hostPath` volumes bypass many security controls.** Avoid them in production.
* **Service account tokens are auto-mounted by default.** Disable for pods that don't need them (`automountServiceAccountToken: false`).
* **The default ServiceAccount has wide permissions in some clusters.** Bind to a less-privileged SA, or use a "default deny" SA.
* **Reading a secret requires RBAC.** If a pod's ServiceAccount can't `get` the secret, the volume mount fails.
* **Don't disable `automountServiceAccountToken` cluster-wide.** Some workloads need it (kube-system pods, etc.).
* **Admission policies are enforced only on creation/update.** If you change a policy, existing resources aren't re-validated. Run an audit job.
* **Image scanning finds existing CVEs.** A scan today doesn't fix a CVE in an image already deployed. Re-build and re-deploy.
* **Defense in depth, not defense in one.** A single layer (NetworkPolicy, RBAC, PSS) isn't enough.
* **Don't put secrets in `kubectl describe pod` output.** They're shown. Don't let screenshots leak.
* **Cloud metadata service can be exploited.** SSRF attacks on the metadata endpoint (169.254.169.254) can leak IAM creds. Use network policies to block pod access to the metadata service.

## A worked example

Cluster: 200 namespaces, 1500 workloads, 5 teams. Recently had a CVE in a popular base image that was deployed across 50+ workloads.

**Reactive: find all affected workloads**

```bash
# find pods using the affected image
kubectl get pods -A -o json | \
  jq '.items[] | select(.spec.containers[].image | test("python:3.11")) | {ns: .metadata.namespace, name: .metadata.name}'

# or with Kyverno policy
# (audit mode: shows what would be flagged, doesn't block)
```

**Proactive: prevent this in the future**

```yaml
# 1. PSS restricted on all namespaces
apiVersion: v1
kind: Namespace
metadata:
  name: my-app
  labels:
    pod-security.kubernetes.io/enforce: restricted

# 2. Kyverno policy to require image scanning
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: check-image-vulns
spec:
  validationFailureAction: Audit   # don't block yet
  rules:
  - name: check-trivy-scan
    match:
      any:
      - resources:
          kinds:
          - Pod
    validate:
      message: "Image must be scanned and have no critical CVEs."
      pattern:
        metadata:
          annotations:
            trivy.scan.result: "no-critical"

# 3. CI: scan in pipeline, fail on critical
# (trivy step in CI)
```

After rolling this out, the next CVE gets caught at admission or in CI, not in production.

## See also

* [[Kubernetes/guides/non-functional/oidc-integration|oidc-integration]] — cluster auth
* [[Kubernetes/concepts/L07-security|L07-security]] — concept-level security notes
* [[Kubernetes/guides/troubleshooting/crashloop-backoff|crashloop-backoff]] — when PSS is too strict
* [[Kubernetes/guides/delivery/ci-cd-integration|ci-cd-integration]] — image scanning in CI
