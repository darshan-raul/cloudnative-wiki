# Pod Security Standards (PSS)

*"https://kubernetes.io/docs/concepts/security/pod-security-standards/"*

**Pod Security Standards (PSS)** are **three predefined security profiles** for Pods — `privileged`, `baseline`, and `restricted`. They're applied at the **namespace level** via labels, and any Pod that doesn't meet the standard is rejected (or warned) at admission. PSS replaced the deprecated PodSecurityPolicy (PSP) in k8s 1.25+. It covers the **workload hardening** part of the L07 layer; the **API access** and **network** parts are in other notes.

### Table of Contents

1. [The Three Profiles](#1-the-three-profiles)
2. [The Three Modes (Enforce / Audit / Warn)](#2-the-three-modes-enforce--audit--warn)
3. [How PSS Is Enforced](#3-how-pss-is-enforced)
4. [The Privileged Profile](#4-the-privileged-profile)
5. [The Baseline Profile in Depth](#5-the-baseline-profile-in-depth)
6. [The Restricted Profile in Depth](#6-the-restricted-profile-in-depth)
7. [Namespace Label Syntax](#7-namespace-label-syntax)
8. [The Profile Versions](#8-the-profile-versions)
9. [The Migration Cookbook](#9-the-migration-cookbook)
10. [Per-Namespace Patterns](#10-per-namespace-patterns)
11. [The PSS vs PSP Differences](#11-the-pss-vs-psp-differences)
12. [PSS vs OPA / Kyverno](#12-pss-vs-opa--kyverno)
13. [Common Exceptions](#13-common-exceptions)
14. [Operations and Debugging](#14-operations-and-debugging)
15. [Gotchas and Common Mistakes](#15-gotchas-and-common-mistakes)

---

## 1. The Three Profiles

| Profile | Intended for | What it allows |
|---|---|---|
| **`privileged`** | System / infrastructure workloads | Essentially unrestricted |
| **`baseline`** | Default for most namespaces | Prevents known privilege escalations |
| **`restricted`** | Hardened, security-sensitive namespaces | Strict — k8s best practices |

The profiles are **cumulative**: `restricted` is a superset of `baseline`, which is a superset of `privileged`. A Pod that meets `restricted` also meets `baseline` and `privileged`.

The decision:

* **`privileged`** for `kube-system` (system Pods need full access).
* **`baseline`** for dev / test namespaces (some flexibility).
* **`restricted`** for production (the safe default).

## 2. The Three Modes (Enforce / Audit / Warn)

PSS has **three modes** for each profile:

* **`enforce`** — reject violating Pods. The admission controller denies them.
* **`audit`** — allow but log violations. The audit log has the violation.
* **`warn`** — allow but show a warning to the user via `kubectl`.

The standard pattern:

```bash
# all three modes at the same profile
kubectl label ns production \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/enforce-version=latest
```

* **`enforce`** — actual enforcement.
* **`audit`** — log violations (so you can see them in the audit log).
* **`warn`** — UX for users; they see a warning when they try to deploy a violating Pod.

The modes are independent. You can have `enforce: baseline, audit: restricted` (enforce baseline, but log restricted violations as well). This is for the migration phase.

## 3. How PSS Is Enforced

PSS is enforced by the **Pod Security admission controller**, which is built into the apiserver. It's enabled by default in k8s 1.25+ (and was in alpha/beta before).

The flow:

1. A Pod is created (or updated).
2. The apiserver's `PodSecurity` admission plugin runs.
3. For each namespace label (`enforce`, `audit`, `warn`), the plugin checks the Pod against the corresponding profile.
4. If `enforce` is violated, the Pod is rejected.
5. If `audit` is violated, the violation is added to the audit log.
6. If `warn` is violated, the admission response includes a warning.

The plugin is **fast** (in-process, no external call). It's evaluated on every Pod creation / update.

### 3.1 The PodSecurity admission

The plugin is in `--enable-admission-plugins=PodSecurity`. It's enabled by default.

The plugin reads the namespace's labels:

* `pod-security.kubernetes.io/enforce` — `privileged` / `baseline` / `restricted`
* `pod-security.kubernetes.io/enforce-version` — `latest` / `v1.30` / etc.
* `pod-security.kubernetes.io/audit` — same
* `pod-security.kubernetes.io/audit-version` — same
* `pod-security.kubernetes.io/warn` — same
* `pod-security.kubernetes.io/warn-version` — same

If the label is not set, the mode is disabled for that profile (no enforcement, no audit, no warn).

## 4. The Privileged Profile

`privileged` is the **escape hatch**. It blocks nothing. Any Pod is allowed.

```bash
kubectl label ns kube-system pod-security.kubernetes.io/enforce=privileged
```

Use for:

* `kube-system` (system Pods).
* `monitoring` (Prometheus, Grafana, etc.).
* Any namespace with system-level infrastructure.

If you set `enforce: privileged`, the namespace has no PSS enforcement. **It's not a "no security" setting per se** — other policies (NetworkPolicy, RBAC, etc.) still apply. But PSS doesn't add any checks.

## 5. The Baseline Profile in Depth

`baseline` is the **default** for most namespaces. It prevents **known privilege escalations** but allows common patterns (root, default `hostPath` for logs, etc.).

The `baseline` profile blocks (in detail):

* **`privileged: true`** — privileged containers are rejected.
* **`hostNetwork: true`** — Pods sharing the host's network are rejected.
* **`hostPID: true`** — Pods sharing the host's PID namespace are rejected.
* **`hostIPC: true`** — Pods sharing the host's IPC namespace are rejected.
* **`hostPath` volumes** — almost all `hostPath` mounts are rejected. Exception: a few safe read-only paths (none by default; depends on the k8s version).
* **Specific capabilities** — `SYS_ADMIN`, `NET_ADMIN`, `SYS_MODULE`, `SYS_RAWIO`, `SYS_PTRACE`, `SYS_BOOT`, etc. (about 25 capabilities).
* **Specific procMount values** — `procMount: Unmasked` is blocked.
* **Specific AppArmor profiles** — `unconfined` is blocked (the default is `runtime/default`, which is allowed).
* **Specific SELinux options** — custom user / role / type / level is blocked.

`baseline` **allows**:

* `runAsUser: 0` (root).
* `readOnlyRootFilesystem: false` (the default).
* `allowPrivilegeEscalation: true` (the default).
* `seccompProfile.type: Unconfined` (the default).
* Most other "less than ideal" settings.

`baseline` is for **app namespaces that can't meet `restricted`**. Common reasons:

* The app needs to write to `/` (legacy daemon).
* The app needs root (no USER set in the image).
* The app uses `hostPath` (e.g. for `/dev` access).

## 6. The Restricted Profile in Depth

`restricted` is the **safe default** for new clusters. It enforces the k8s best practices.

The `restricted` profile blocks everything `baseline` blocks, plus:

* **`runAsNonRoot: true`** is **required** (must be set in the SecurityContext, OR the image's `USER` must be non-root, OR `runAsUser` must be set to non-zero).
* **`seccompProfile.type`** must be `RuntimeDefault` or `Localhost` (not `Unconfined`).
* **`allowPrivilegeEscalation: false`** is required.
* **`capabilities.drop`** must include `ALL`.
* **`capabilities.add`** is restricted to a small allow list: `NET_BIND_SERVICE`.

The `restricted` profile is **strict**. A Pod that meets `restricted`:

* Runs as non-root.
* Has all capabilities dropped (except the explicit allow list).
* Has a seccomp filter.
* Has no privilege escalation.
* Has no host namespaces.
* Has no privileged flag.
* Has a read-only root filesystem (recommended, not required).

A Pod that meets `restricted` is **generally considered safe to run**.

## 7. Namespace Label Syntax

The labels are well-known keys. The values are the profile name (or `latest` for the version):

```bash
# the most common setup
kubectl label ns production \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/audit-version=latest \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/warn-version=latest
```

The `*-version` label controls the **PSS version**. `latest` means "use the version of the apiserver". A specific version (e.g. `v1.30`) means "use the rules as defined in PSS v1.30". Pin the version for production.

### 7.1 The label keys

| Key | Purpose | Values |
|---|---|---|
| `pod-security.kubernetes.io/enforce` | Hard enforcement (reject) | `privileged` / `baseline` / `restricted` |
| `pod-security.kubernetes.io/enforce-version` | The version for enforce | `latest` / `v1.X` |
| `pod-security.kubernetes.io/audit` | Log violations | same as enforce |
| `pod-security.kubernetes.io/audit-version` | Version for audit | same |
| `pod-security.kubernetes.io/warn` | Warn the user | same |
| `pod-security.kubernetes.io/warn-version` | Version for warn | same |

### 7.2 The version pinning

The `*-version` label pins the profile version. The default (no version) is `latest`, which is the version of the apiserver you're using.

**For production, pin the version.** A k8s upgrade may tighten the profile (e.g. add a new check). If you're on `latest`, the new check applies immediately. If you're on `v1.28`, the old rules apply.

The version format:

* `latest` — current apiserver version.
* `v1.X` — the version of PSS in k8s 1.X.

The official PSS versions match k8s releases. v1.30 is the PSS in k8s 1.30.

## 8. The Profile Versions

PSS has versions that match k8s releases:

* `v1.22` — initial GA.
* `v1.23` — no changes.
* `v1.24` — no changes.
* `v1.25` — `restricted` adds `runAsNonRoot: true` enforcement, additional `capabilities.add` checks.
* `v1.26` — `unhealthyPodEvictionPolicy` (separate feature).
* `v1.27` — no major changes.
* `v1.28` — additional `hostPath` restrictions in `baseline`.
* `v1.29` — additional `seccompProfile` checks.
* `v1.30` — additional checks.

The versions are **cumulative** — v1.30 includes all v1.22 rules plus the additions.

## 9. The Migration Cookbook

The standard migration from a permissive cluster to `restricted`:

### 9.1 Phase 1: Audit (no enforcement)

```bash
# turn on audit for all production namespaces
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  kubectl label ns $ns \
    pod-security.kubernetes.io/audit=restricted \
    pod-security.kubernetes.io/audit-version=latest \
    --overwrite
done
```

* No Pod is rejected.
* The audit log has violations.
* Use the log to see what's broken.

### 9.2 Phase 2: Warn (UX)

```bash
# turn on warn for the same namespaces
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  kubectl label ns $ns \
    pod-security.kubernetes.io/warn=restricted \
    pod-security.kubernetes.io/warn-version=latest \
    --overwrite
done
```

* Users see warnings when they deploy violating Pods.
* The CI can fail on warnings (with `kubectl apply --dry-run=server`).

### 9.3 Phase 3: Fix

For each violation, fix the Pod:

* `runAsNonRoot: true` — add to SecurityContext, or build a non-root image.
* `seccompProfile` — add `seccompProfile: type: RuntimeDefault`.
* `allowPrivilegeEscalation: false` — add to SecurityContext.
* `capabilities.drop: [ALL]` — add to SecurityContext.

Or, mark the namespace as a documented exception (`baseline` or `privileged`).

### 9.4 Phase 4: Enforce

```bash
# turn on enforce
kubectl label ns production \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest \
  --overwrite
```

* Violating Pods are rejected.
* New violations are blocked immediately.
* The cluster is hardened.

The transition is **per-namespace**. Don't enforce on a namespace with a non-compliant workload — fix the workload first.

## 10. Per-Namespace Patterns

The standard pattern for a cluster:

```yaml
# kube-system
metadata: { labels: { pod-security.kubernetes.io/enforce: privileged } }

# production
metadata: { labels: { pod-security.kubernetes.io/enforce: restricted, pod-security.kubernetes.io/enforce-version: latest } }

# staging
metadata: { labels: { pod-security.kubernetes.io/enforce: baseline } }

# dev
metadata: { labels: { pod-security.kubernetes.io/enforce: baseline } }

# monitoring (Prometheus, etc.)
metadata: { labels: { pod-security.kubernetes.io/enforce: baseline } }
```

`kube-system` is `privileged` because system Pods (CNI, storage, etc.) need access. `production` is `restricted` (the safe default). `staging` and `dev` are `baseline` (more flexibility for dev work).

For multi-tenant clusters:

* Each tenant's namespace is `restricted` by default.
* Documented exceptions get `baseline`.
* A privileged workload (e.g. CI runner) gets `privileged` and is locked down by NetworkPolicy and RBAC.

## 11. The PSS vs PSP Differences

*"https://kubernetes.io/docs/concepts/security/pod-security-standards/#pod-security-vs-podsecuritypolicy"*

PSP (PodSecurityPolicy) was the older, more flexible mechanism. PSS replaced it. The differences:

| | PSP | PSS |
|---|---|---|
| **Status** | Deprecated in 1.21, removed in 1.25 | Active, GA |
| **Configuration** | Custom per-policy | Three predefined profiles |
| **Mechanism** | RBAC (the user must be allowed to use a PSP) | Namespace labels |
| **Flexibility** | Highly configurable | Fixed rules |
| **Use case** | Custom policies | Standard hardening |

PSP allowed **per-user** policies (a user could use a specific PSP based on RBAC). PSS is **per-namespace** (the namespace determines the policy).

For most clusters, **PSS is enough**. For complex custom policies (e.g. "only the security team can deploy privileged containers"), use **OPA / Kyverno** alongside PSS.

## 12. PSS vs OPA / Kyverno

PSS is **built into the apiserver**. It only checks a **fixed set of fields** (the PSS rules). It's fast (in-process) and free.

OPA / Kyverno / Gatekeeper check **arbitrary constraints**. They're extensible but slower (separate process) and require configuration.

The standard pattern:

* **PSS** for the **baseline** (privileged containers, host namespaces, etc.). Built-in, free.
* **OPA / Kyverno** for **organization-specific** rules (e.g. "every image must come from our registry", "every Pod must have these labels"). Extensible.

PSS + OPA / Kyverno is the standard "defense in depth" for admission.

## 13. Common Exceptions

Workloads that can't meet `restricted` and need `baseline` or `privileged`:

* **CNI plugins** (Calico, Cilium, Weave) — need `hostNetwork`, `privileged`.
* **GPU device plugins** (NVIDIA) — need `privileged` for GPU access.
* **Storage daemons** (some CSI drivers) — need `hostPath` for device access.
* **Monitoring agents** (Prometheus node-exporter, Datadog agent) — need `hostPath` for `/proc`, `/sys`.
* **Logging agents** (Fluentd, Vector) — need `hostPath` for log dirs.
* **Init containers** that do migrations — may need `hostPath` for backup/restore.

For these, document the exception and set the namespace to `baseline` or `privileged`. The exception should be **scoped** (only the system Pods, not all Pods in the namespace).

## 14. Operations and Debugging

### 14.1 Common commands

```bash
# list namespaces and their PSS labels
kubectl get ns -L pod-security.kubernetes.io/enforce,pod-security.kubernetes.io/warn,pod-security.kubernetes.io/audit

# describe a namespace
kubectl describe ns <ns>
# look at the labels

# try a Pod against a PSS namespace (dry-run)
kubectl apply -f pod.yaml --dry-run=server
# the response includes warnings if it violates

# check the audit log for violations
# (the audit log has the violation message)
```

### 14.2 The "Pod rejected by PSS" case

A Pod creation fails with "violates PodSecurity \"baseline:latest\"" or similar.

```bash
# 1. Read the error message
kubectl describe pod <pod>
# the error says which field violates which profile

# 2. Fix the Pod
# - add runAsNonRoot: true
# - add seccompProfile.type: RuntimeDefault
# - drop capabilities
# etc.

# 3. Re-apply
kubectl apply -f pod.yaml
```

### 14.3 The "PSS isn't enforcing" case

PSS labels are set, but violations aren't rejected.

```bash
# 1. Check the apiserver's enabled admission plugins
kubectl -n kube-system get pod kube-apiserver-<node> -o yaml | grep admission
# PodSecurity should be in the list

# 2. Check the namespace's labels
kubectl get ns <ns> -o jsonpath='{.metadata.labels}'
# the enforce label should be set

# 3. Check the apiserver's version
kubectl version
# PodSecurity is GA in 1.25+
```

## 15. Gotchas and Common Mistakes

### 15.1 The 30+ common mistakes

1. **PSS is admission-time only.** Once a Pod is admitted, PSS doesn't enforce anything at runtime. The kubelet doesn't kill a Pod mid-flight for violating PSS.

2. **The `warn` and `audit` modes are different.** `warn` shows a `kubectl`-side message; `audit` adds an entry to the cluster's audit log.

3. **The `latest` version is not always what you want.** Pin a specific version (e.g. `v1.28`) for production.

4. **PSS replaced PSP.** PSP was deprecated in 1.21 and removed in 1.25. Don't write new PSPs. PSS is the way.

5. **PSS doesn't replace NetworkPolicy.** A `restricted` Pod can still talk to anything. Pair with NetworkPolicy.

6. **The default namespace has no PSS labels.** It inherits the cluster's default, which is "allow everything". Don't deploy to `default`. Make a namespace, label it `restricted`, deploy there.

7. **`"restricted"` is a moving target.** Each k8s release may tighten the rules. Pin a version, or expect warnings on k8s upgrades.

8. **Some legit workloads can't meet `restricted`.** A workload that genuinely needs to write to `/` (legacy daemon) or run as root — these need `baseline` or `privileged`, and a documented exception.

9. **`baseline` allows root, `restricted` doesn't.** A common migration: switch from `baseline` to `restricted` and discover that every Pod runs as root. Fix by adding `runAsUser: 1000` to the Pod spec.

10. **`capabilities.drop: [ALL]` is required for `restricted`.** A common migration step.

11. **`seccompProfile.type: RuntimeDefault` is required for `restricted`.** A common migration step.

12. **`allowPrivilegeEscalation: false` is required for `restricted`.** A common migration step.

13. **`readOnlyRootFilesystem` is recommended but not required for `restricted`.** However, it's a hardening best practice.

14. **`runAsNonRoot: true` requires the image to have a non-root USER.** If the image's USER is 0 (root), the Pod is rejected. Set `runAsUser: 1000` explicitly.

15. **The `hostPath` restrictions in `baseline` are strict.** Almost all `hostPath` mounts are blocked. Use `emptyDir` or `persistentVolumeClaim` instead.

16. **The `baseline` profile allows `seccompProfile.type: Unconfined`.** `restricted` doesn't.

17. **The `baseline` profile allows `procMount: Default`.** `restricted` requires `procMount: Default` (but doesn't block `Unconfined` in `baseline`).

18. **The `baseline` profile blocks ~25 specific capabilities.** `restricted` allows only `NET_BIND_SERVICE` as an add.

19. **The `baseline` profile allows `privileged: false` (the default).** It only blocks `privileged: true`.

20. **PSS doesn't check container images for vulnerabilities.** Use Trivy / Snyk for that.

21. **PSS doesn't enforce resource requests / limits.** That's ResourceQuota / LimitRange.

22. **PSS doesn't enforce image registry restrictions.** Use OPA / Kyverno for that.

23. **PSS doesn't enforce NetworkPolicy.** Use NetworkPolicy.

24. **The PodSecurity admission controller is per-Pod, not per-Container.** Container-level violations are caught if the Pod-level SecurityContext doesn't override.

25. **The PodSecurity admission controller doesn't check init containers for `restricted`.** Wait — it does, since k8s 1.25. The init containers must meet the profile too.

26. **The `latest` profile version may differ across apiservers.** In HA, the apiservers may have different versions (during upgrades). Pin the version.

27. **The `audit` and `warn` modes can be on different profiles.** E.g. `enforce: baseline, audit: restricted` — enforce baseline, but log restricted violations.

28. **The PodSecurity admission controller's check is fast.** It runs on every Pod creation, in-process. No external call.

29. **A Pod that violates `restricted` but meets `baseline` is admitted in a `baseline` namespace.** The Pod's spec doesn't change; only the namespace's policy.

30. **PSS doesn't validate that an admission policy (Kyverno, OPA) is also in place.** Use PSS for the standard checks, OPA / Kyverno for the custom ones.

## See also

* [[Kubernetes/concepts/L07-security/05-security-context|SecurityContext]] — the per-Pod / per-Container settings
* [[Kubernetes/concepts/L07-security/10-admission-controllers|Admission Controllers]] — the broader admission layer
* [[Kubernetes/concepts/L07-security/11-opa-gatekeeper|OPA / Gatekeeper]] — for custom rules
* [[Kubernetes/concepts/L07-security/12-kyverno|Kyverno]] — for custom rules (YAML)
* [[Kubernetes/concepts/L07-security/22-compliance-frameworks|Compliance Frameworks]] — the CIS / NIST view
