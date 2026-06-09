# Cluster Hardening (Control Plane, apiserver flags, etcd)

*"https://kubernetes.io/docs/tasks/administer-cluster/securing-a-cluster/"*

**Cluster hardening** is the practice of **securing the k8s control plane** — the apiserver, etcd, kubelet, controller-manager, scheduler, and the network around them. It's the **defense in depth** of the cluster: even if a workload is compromised, the cluster itself should be hard to take down. This note covers the apiserver flags, etcd access, control plane lockdown, and the operational patterns that go with them.

### Table of Contents

1. [The Control Plane Attack Surface](#1-the-control-plane-attack-surface)
2. [The apiserver Flags — Authentication](#2-the-apiserver-flags--authentication)
3. [The apiserver Flags — Authorization](#3-the-apiserver-flags--authorization)
4. [The apiserver Flags — Admission](#4-the-apiserver-flags--admission)
5. [The apiserver Flags — Audit](#5-the-apiserver-flags--audit)
6. [The apiserver Flags — Encryption](#6-the-apiserver-flags--encryption)
7. [The apiserver Flags — Networking](#7-the-apiserver-flags--networking)
8. [The apiserver Flags — Misc Hardening](#8-the-apiserver-flags--misc-hardening)
9. [etcd Hardening](#9-etcd-hardening)
10. [kubelet Hardening](#10-kubelet-hardening)
11. [The kube-controller-manager and kube-scheduler](#11-the-kube-controller-manager-and-kube-scheduler)
12. [The API Server Network](#12-the-api-server-network)
13. [Authentication and Authorization at the Edge](#13-authentication-and-authorization-at-the-edge)
14. [The "KMS-less" vs "KMS" Decision](#14-the-kms-less-vs-kms-decision)
15. [Common Audit Findings](#15-common-audit-findings)
16. [Operations and Debugging](#16-operations-and-debugging)
17. [Gotchas and Common Mistakes](#17-gotchas-and-common-mistakes)

---

## 1. The Control Plane Attack Surface

The control plane components are the **highest-value target** in a cluster. Compromising the apiserver gives full cluster control. Compromising etcd gives all data (Secrets, ConfigMaps, etc.).

The attack surface:

* **apiserver** — every request goes through it. The network endpoint, the authn/authz logic, admission, etc.
* **etcd** — the data store. Direct access reads all data.
* **kubelet** — on every node. Each kubelet can be a foothold to the node.
* **controller-manager, scheduler** — the controllers. Compromising these can disrupt the cluster.
* **Network paths** — the apiserver's network, the etcd peer network, the kubelet-to-apiserver path.

The defenses:

* **Authn / authz** at the apiserver.
* **mTLS** between components.
* **Network segmentation** — control plane on a private network.
* **Audit logging** of all requests.
* **Encryption at rest** for etcd.
* **Least privilege** for the components.

## 2. The apiserver Flags — Authentication

The apiserver's `--authentication-*` flags control who's allowed in.

### 2.1 Disable anonymous auth

```bash
--anonymous-auth=false
```

**This is the first flag to set.** Without it, requests with no credentials are accepted as `system:anonymous`. Many clusters have this on by default (k8s default is `true`).

### 2.2 TLS for the apiserver

```bash
--tls-cert-file=/etc/kubernetes/pki/apiserver.crt
--tls-private-key-file=/etc/kubernetes/pki/apiserver.key
--tls-min-version=VersionTLS12
--tls-cipher-suites=TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
```

**TLS 1.2 minimum.** TLS 1.3 preferred. Strong cipher suites only.

### 2.3 Client CA for X.509 auth

```bash
--client-ca-file=/etc/kubernetes/pki/ca.crt
```

The CA that signs client certs. For X.509 auth, the apiserver verifies client certs against this CA.

### 2.4 OIDC for users

```bash
--oidc-issuer-url=https://accounts.google.com
--oidc-client-id=kubernetes
--oidc-username-claim=email
--oidc-groups-claim=groups
```

For SSO. The apiserver validates OIDC tokens and extracts the username / groups.

### 2.5 ServiceAccount token signing

```bash
--service-account-key-file=/etc/kubernetes/pki/sa.pub
--service-account-signing-key-file=/etc/kubernetes/pki/sa.key
--service-account-issuer=https://kubernetes.default.svc.cluster.local
```

For issuing and verifying ServiceAccount JWTs. The issuer URL is what the apiserver publishes in the `iss` claim of bound tokens.

### 2.6 Webhook token auth

```bash
--authentication-token-webhook-config-file=/etc/kubernetes/authn-webhook.yaml
--authentication-token-webhook-cache-ttl=5m
```

For custom auth (e.g. a custom OIDC provider). The webhook is a service that validates tokens.

## 3. The apiserver Flags — Authorization

The `--authorization-mode` flag controls who's allowed to do what.

### 3.1 The standard mode

```bash
--authorization-mode=Node,RBAC
```

`Node` is for kubelets. `RBAC` is for everything else. **Don't include `ABAC`** (legacy, deprecated). **Don't include `AlwaysAllow`** (defeats the purpose).

The order matters: the first authorizer to give a definitive answer wins. `Node` first (kubelets), `RBAC` second (everyone else).

### 3.2 Webhook authorizer

```bash
--authorization-webhook-config-file=/etc/kubernetes/authz-webhook.yaml
--authorization-webhook-cache-authorized-ttl=5m
--authorization-webhook-cache-unauthorized-ttl=30s
```

For custom authz (e.g. OPA, Open Policy Agent). The webhook is a service that decides allow / deny.

The cache TTLs: positive decisions cached 5 min, negative decisions 30s. **Be careful with caches** — a change in the webhook's policy may not be reflected for up to 5 min.

## 4. The apiserver Flags — Admission

```bash
--enable-admission-plugins=NodeRestriction,PodSecurity,ServiceAccount,DefaultStorageClass,...
--disable-admission-plugins=...
```

The plugins to enable / disable. See [[Kubernetes/concepts/L07-security/10-admission-controllers|Admission Controllers]] for the full list.

The standard set (in addition to defaults):

* `NodeRestriction` — restrict kubelets to their own Node.
* `PodSecurity` — enforce PSS.
* `ServiceAccount` — default SA injection.
* `LimitRanger` — apply LimitRange.
* `ResourceQuota` — enforce quota.
* `DefaultStorageClass` — set default StorageClass.
* `DefaultTolerationSeconds` — set default not-ready toleration.
* `MutatingAdmissionWebhook`, `ValidatingAdmissionWebhook` — for OPA / Kyverno.

### 4.1 The `--admission-control-config-file`

For external admission webhook configs. The file is a YAML that defines the MutatingWebhookConfiguration and ValidatingWebhookConfiguration. (In practice, these are usually CRDs, not files.)

## 5. The apiserver Flags — Audit

```bash
--audit-policy-file=/etc/kubernetes/audit-policy.yaml
--audit-log-path=/var/log/kubernetes/audit/audit.log
--audit-log-format=json
--audit-log-maxage=30
--audit-log-maxbackup=10
--audit-log-maxsize=100
--audit-webhook-config-file=/etc/kubernetes/audit-webhook-config.yaml
```

See [[Kubernetes/concepts/L07-security/15-audit-logging|Audit Logging]] for the full picture.

## 6. The apiserver Flags — Encryption

```bash
--encryption-provider-config=/etc/kubernetes/encryption-config.yaml
```

The `EncryptionConfiguration` for etcd encryption. See [[Kubernetes/concepts/L07-security/13-etcd-encryption|etcd Encryption]] for the full picture.

## 7. The apiserver Flags — Networking

```bash
--bind-address=0.0.0.0       # listen on all interfaces (or specific IP)
--secure-port=6443           # the apiserver's port
--advertise-address=<IP>     # what the apiserver advertises to clients
--etcd-servers=https://127.0.0.1:2379
--etcd-cafile=/etc/ssl/etcd/ca.crt
--etcd-certfile=/etc/ssl/etcd/peer.crt
--etcd-keyfile=/etc/ssl/etcd/peer.key
```

The apiserver's bind address and port. The `--advertise-address` is what clients use to reach the apiserver (in HA, this is the load balancer's IP).

The etcd flags are for the apiserver's connection to etcd. **mTLS by default.**

## 8. The apiserver Flags — Misc Hardening

```bash
--feature-gates=...
--profiling=false             # disable profiling (don't expose internal data)
--request-timeout=60s         # default 60s
--watch-cache=true            # enable watch cache (default true)
```

`--profiling=false` is a hardening default. With profiling on, `/debug/pprof` is accessible. With it off, the apiserver doesn't expose internal profiling data.

## 9. etcd Hardening

etcd is the **data store**. Compromising etcd is a cluster compromise.

### 9.1 The etcd flags

```bash
# listen on a specific interface
--listen-client-urls=https://127.0.0.1:2379
# or for HA:
--listen-client-urls=https://10.0.0.1:2379,https://10.0.0.2:2379,https://10.0.0.3:2379

# advertise
--advertise-client-urls=https://10.0.0.1:2379

# peer URLs (for cluster communication)
--listen-peer-urls=https://10.0.0.1:2380
--advertise-peer-urls=https://10.0.0.1:2380

# TLS
--cert-file=/etc/ssl/etcd/server.crt
--key-file=/etc/ssl/etcd/server.key
--trusted-ca-file=/etc/ssl/etcd/ca.crt
--client-cert-auth=true        # require client certs

# peer TLS
--peer-cert-file=/etc/ssl/etcd/peer.crt
--peer-key-file=/etc/ssl/etcd/peer.key
--peer-trusted-ca-file=/etc/ssl/etcd/ca.crt
--peer-client-cert-auth=true
```

### 9.2 The etcd access rules

* **No public access** — etcd is on a private network. The only clients are the apiserver and operator tools.
* **mTLS** — both directions. Client cert auth is required.
* **No shell on the etcd host** — limit the attack surface.
* **Encrypted backups** — etcdctl snapshot save produces a backup file. Encrypt it.
* **Encryption at rest** — see [[Kubernetes/concepts/L07-security/13-etcd-encryption|etcd Encryption]].

### 9.3 The etcd storage

etcd stores data on disk. The disk should be:

* **Encrypted at rest** — full disk encryption (LUKS, cloud provider's disk encryption).
* **High-performance SSD** — etcd is sensitive to latency.
* **Separate from other data** — dedicated disk for etcd's `data-dir`.
* **Backed up** — regular snapshots, stored off-cluster, encrypted.

## 10. kubelet Hardening

The kubelet runs on every node. It's the **per-node entry point**.

### 10.1 The kubelet config

```yaml
# /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true                # use the apiserver for auth
  x509:
    clientCAFile: /etc/kubernetes/pki/ca.crt
authorization:
  mode: Webhook
readOnlyPort: 0                  # disable the read-only port (deprecated, dangerous)
protectKernelDefaults: true
tlsCertFile: /var/lib/kubelet/pki/kubelet.crt
tlsPrivateKeyFile: /var/lib/kubelet/pki/kubelet.key
rotateCertificates: true         # auto-rotate serving cert
serverTLSBootstrap: true
seccompDefault: true             # default seccomp profile
```

### 10.2 The kubelet's `readOnlyPort`

`readOnlyPort: 0` **disables the read-only port (10255)**. The read-only port exposes `/metrics`, `/pods`, `/healthz` without authentication. It's a footgun. **Always disable.**

### 10.3 The kubelet's authentication

* **`anonymous: enabled: false`** — disable anonymous access.
* **`webhook: enabled: true`** — use the apiserver for auth (the kubelet asks the apiserver "is this caller authorized?"). This way, RBAC applies to kubelet's API.
* **`x509: clientCAFile`** — the CA for verifying client certs.

### 10.4 The kubelet's authorization

`mode: Webhook` means the kubelet asks the apiserver for authorization. RBAC applies. The kubelet can only do what its RBAC allows (the Node authorizer, plus NodeRestriction).

### 10.5 The kubelet's TLS

* **`tlsCertFile`, `tlsPrivateKeyFile`** — the kubelet's serving cert (for `https://<node>:10250`).
* **`rotateCertificates: true`** — auto-rotate via the apiserver's CSR API.
* **`serverTLSBootstrap: true`** — request a cert from the apiserver on startup.

### 10.6 The kubelet's `seccompDefault`

`seccompDefault: true` makes the kubelet apply `RuntimeDefault` seccomp to all containers that don't have a seccomp profile. This is a hardening default (k8s 1.27+).

## 11. The kube-controller-manager and kube-scheduler

The controller-manager and scheduler are also attack targets, but less exposed (they're cluster-internal).

### 11.1 The controller-manager flags

```bash
--use-service-account-credentials=true   # give each controller its own SA
--root-ca-file=/etc/kubernetes/pki/ca.crt
--service-account-private-key-file=/etc/kubernetes/pki/sa.key
--authentication-kubeconfig=/etc/kubernetes/controller-manager.kubeconfig
--authorization-kubeconfig=/etc/kubernetes/controller-manager.kubeconfig
```

`--use-service-account-credentials=true` is the hardening default. Each controller has its own SA, with the minimum RBAC needed.

### 11.2 The scheduler flags

```bash
--authentication-kubeconfig=/etc/kubernetes/scheduler.kubeconfig
--authorization-kubeconfig=/etc/kubernetes/scheduler.kubeconfig
--leader-elect=true
```

Standard kubeconfig-based auth. The scheduler uses its own SA.

## 12. The API Server Network

The apiserver's network exposure is critical.

### 12.1 The standard

* **The apiserver is on a private network** — not directly accessible from the internet.
* **A load balancer** fronts the apiserver. The LB is in a public subnet (or has a public IP).
* **The kubelets and controllers** connect to the apiserver via the private network.

For cloud-managed clusters (EKS, GKE, AKS), the cloud provider manages this.

For self-managed:

* **Two subnets** — public (the LB) and private (the apiserver).
* **The LB is the only public endpoint.**
* **The apiserver's port (6443) is open to the private subnet only.**

### 12.2 The `--bind-address`

`--bind-address=0.0.0.0` listens on all interfaces. The `0.0.0.0` is for the apiserver's port. The exposure depends on the network (firewall, security group).

For **maximum hardening**, bind to a specific interface:

```bash
--bind-address=10.0.0.1     # the private IP
```

## 13. Authentication and Authorization at the Edge

The apiserver's authn is only as strong as the **edge**:

* **Cloud LB with mTLS** — the LB terminates TLS, re-encrypts to the apiserver. The client cert is verified at the LB.
* **Bastion / VPN** — for SSH to control plane nodes. **Never expose the control plane via SSH to the internet**.
* **kubectl access** — the user's kubeconfig is the credential. Treat it like a root password.
* **OIDC with MFA** — for human users. Multi-factor at the IdP.

The **network perimeter** is the first line of defense. The **apiserver's authn** is the second. Both must be strong.

## 14. The "KMS-less" vs "KMS" Decision

For etcd encryption, the choice:

* **`aescbc` / `secretbox`** — local keys in the config file. **No external dependency**. But the key is in the file, and the file is on the apiserver's host.
* **KMS (AWS / GCP / Azure / Vault)** — the key is in the cloud's HSM. **Production-grade**, but adds a network dependency.

For **production**, KMS is the standard. The performance cost is small (with caching), and the security gain is large (the key never leaves the cloud's HSM).

For **dev / test**, `aescbc` is fine. The key can be regenerated easily.

## 15. Common Audit Findings

When you run a k8s security audit (with kube-bench, kube-hunter, etc.), the common findings are:

| Finding | Severity | Fix |
|---|---|---|
| `anonymous-auth: true` | HIGH | `--anonymous-auth=false` |
| `readOnlyPort: 10255` enabled | HIGH | `readOnlyPort: 0` |
| `--profiling: true` | MEDIUM | `--profiling=false` |
| `ABAC` authorizer enabled | HIGH | Remove `ABAC`, use `RBAC` |
| `--tls-min-version: VersionTLS10` | MEDIUM | `--tls-min-version=VersionTLS12` |
| Secrets not encrypted at rest | MEDIUM | Add `EncryptionConfiguration` |
| `hostPID: true` in app Pods | MEDIUM | Use PSS `restricted` |
| NetworkPolicy: default-allow | MEDIUM | Add default-deny |
| Audit log not shipped off-cluster | LOW | Ship to a SIEM |
| kubelet `--read-only-port` enabled | HIGH | `readOnlyPort: 0` |
| `:latest` images in production | MEDIUM | Use versioned tags |
| `privileged: true` containers | HIGH | Remove or justify |
| `imagePullPolicy: Always` for versioned | LOW | Use `IfNotPresent` |
| No `PodSecurity` admission | MEDIUM | Enable PSS |

The standard for "production-grade" is: **none of the high / medium findings are present**.

## 16. Operations and Debugging

### 16.1 Common commands

```bash
# check the apiserver's flags
kubectl -n kube-system get pod kube-apiserver-<node> -o yaml
# or
cat /etc/kubernetes/manifests/kube-apiserver.yaml

# check the kubelet's config
cat /var/lib/kubelet/config.yaml

# run kube-bench (CIS benchmark)
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml
# or as a Docker container:
docker run --pid host --net host -v /etc:/etc:ro -v /var:/var:ro \
  aquasec/kube-bench:latest

# run kube-hunter (penetration test)
docker run --network host -it securecodebox/kube-hunter

# check for common misconfigs
kubectl get pods -A -o json | jq '.items[].spec.containers[].securityContext'
```

### 16.2 The "apiserver won't start" case

The apiserver fails to start after a config change.

```bash
# 1. Check the kubelet's log
journalctl -u kubelet --since "5 minutes ago"
# look for: "failed to start apiserver"

# 2. Check the static pod's manifest
cat /etc/kubernetes/manifests/kube-apiserver.yaml

# 3. Test the apiserver's flags manually
# (run kube-apiserver with --help to see all flags)
# look for typos in the flags

# 4. Revert the change
# the kubelet auto-restarts the apiserver; revert the manifest
```

### 16.3 The "kubelet can't register" case

A node's kubelet is `NotReady`.

```bash
# 1. Check the kubelet's log
journalctl -u kubelet --since "5 minutes ago"
# look for: "failed to register", "x509", "RBAC"

# 2. Check the kubelet's config
cat /var/lib/kubelet/config.yaml
# look for: clientCAFile, tlsCertFile

# 3. Check the apiserver's view of the node
kubectl get node <node> -o yaml
# look for: conditions, addresses
```

## 17. Gotchas and Common Mistakes

### 17.1 The 30+ common mistakes

1. **The apiserver is the central point.** Compromising it compromises everything. The authn flags are critical.

2. **Anonymous auth is on by default.** Always set `--anonymous-auth=false` for production.

3. **`--profiling=true` exposes internal data.** Disable for production.

4. **The read-only kubelet port is dangerous.** Always `readOnlyPort: 0`.

5. **etcd's data dir is on the kubelet's disk by default.** This is wrong — etcd should be on a separate disk for performance and isolation.

6. **The `apiserver`'s `--bind-address=0.0.0.0` listens on all interfaces.** Restrict to the private IP if possible.

7. **The `--advertise-address` is what clients use.** In HA, this is the load balancer's IP.

8. **The `--request-timeout=60s` is the default.** For slow operations (large list), this is too low. Increase for specific use cases.

9. **The `--watch-cache=true` is the default.** For very large clusters, the watch cache uses memory. Tune.

10. **OIDC group claims are fetched from the IdP on every request.** A slow IdP = slow authn. Cache or use short-lived tokens.

11. **The `--service-account-issuer` is the `iss` claim of bound tokens.** Bound tokens are validated against this.

12. **The `--service-account-key-file` is the public key for verifying SA tokens.** Rotate the key (and the corresponding `--service-account-signing-key-file`).

13. **The `--client-ca-file` is the CA for X.509 client certs.** Different from the apiserver's serving cert CA.

14. **The `--requestheader-client-ca-file` is the CA for the front proxy.** Different from the cluster CA.

15. **The `--authorization-mode` order matters.** `Node,RBAC` is standard. `RBAC,Node` is wrong (Node authorizer may not run).

16. **The `--enable-admission-plugins` is additive to defaults.** You can disable defaults, but be careful.

17. **The `--encryption-provider-config` is read on startup.** Changes require an apiserver restart.

18. **The audit policy is read on startup.** Changes require an apiserver restart.

19. **The `--feature-gates` is the apiserver's feature gates.** Different from the kubelet's or the controller-manager's.

20. **The kubelet's `--node-labels` adds labels to the node.** Don't add labels that conflict with built-in ones.

21. **The kubelet's `--register-with-taints` adds taints on registration.** Useful for keeping Pods off until ready.

22. **The kubelet's `--max-pods` is the per-node Pod limit.** Default is 110. Tune for your node size.

23. **The kubelet's `--image-gc-high-threshold` and `--image-gc-low-threshold` control image GC.** Default 85% / 80%. Tune for your disk.

24. **The kubelet's `--container-runtime` is the runtime.** Default is `remote` (CRI). The endpoint is `--container-runtime-endpoint`.

25. **The kubelet's `--root-dir` is the root for kubelet state.** Default `/var/lib/kubelet`.

26. **The kubelet's `--resolv-conf` is the DNS config.** Default `/etc/resolv.conf`. Don't change unless you know why.

27. **The kubelet's `--cgroup-driver` must match the container runtime's.** Mismatches cause Pods to fail.

28. **The kubelet's `--hairpin-mode` controls hairpin NAT.** Default `promiscuous-bridge`. Affects Service routing for Pods that access themselves.

29. **The kubelet's `--read-only-port` defaults to 10255.** Disable for production.

30. **The kubelet's `--protect-kernel-defaults` (1.27+) prevents Pods from changing kernel tunables.** A hardening default.

## See also

* [[Kubernetes/concepts/L07-security/21-node-hardening|Node Hardening]] — kubelet and node-level
* [[Kubernetes/concepts/L07-security/13-etcd-encryption|etcd Encryption]] — the encryption deep-dive
* [[Kubernetes/concepts/L07-security/15-audit-logging|Audit Logging]] — what's logged
* [[Kubernetes/concepts/L07-security/10-admission-controllers|Admission Controllers]] — the admission layer
* [[Kubernetes/concepts/L07-security/22-compliance-frameworks|Compliance Frameworks]] — NIST / CIS / OWASP
