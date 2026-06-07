# Pod Security Standards (PSS)

*"https://kubernetes.io/docs/concepts/security/pod-security-standards/"*

Pod Security Standards (PSS) are **three predefined security profiles** for Pods. You apply them at the **namespace level** via labels, and any Pod that doesn't meet the standard is rejected.

## The three levels

| Level | Intended for | What it allows |
|---|---|---|
| **`privileged`** | System / infrastructure workloads | Essentially unrestricted |
| **`baseline`** | Default for most namespaces | Prevents known privilege escalations |
| **`restricted`** | Hardened, security-sensitive namespaces | Strict — k8s best practices |

**`restricted` is the goal** for application code. **`baseline`** is the floor. **`privileged`** is only for system Pods (CNI, storage, monitoring) that genuinely need access.

## How to apply

PSS is enforced by the **Pod Security Admission** controller, which is on by default in modern k8s. You opt in by labeling the namespace:

```bash
# Apply the "restricted" profile in audit-and-warn mode
kubectl label ns production pod-security.kubernetes.io/enforce=restricted \
                       pod-security.kubernetes.io/enforce-version=latest

# Also surface violations as warnings
kubectl label ns production pod-security.kubernetes.io/warn=restricted
kubectl label ns production pod-security.kubernetes.io/audit=restricted
```

Three modes:

* **`enforce`** — reject violating Pods (admission rejects)
* **`audit`** — allow but log violations
* **`warn`** — allow but show a warning to the user via `kubectl`

You typically set `enforce=restricted, audit=restricted, warn=restricted` — all three modes at the same level.

## What each profile blocks

### `privileged` blocks nothing (it's the escape hatch)

### `baseline` blocks (the most common ones)

* `privileged: true`
* `hostNetwork`, `hostPID`, `hostIPC: true`
* `hostPath` volumes (except a few safe read-only ones)
* Many dangerous capabilities: `SYS_ADMIN`, `NET_ADMIN`, etc.
* `seccompProfile.type: Unconfined` is allowed
* Running as root is allowed

### `restricted` adds (on top of baseline)

* `runAsNonRoot: true` (must be set, or default to non-root)
* `seccompProfile.type` must be `RuntimeDefault` or `Localhost`
* `allowPrivilegeEscalation: false`
* `capabilities.drop` must include `ALL`
* `readOnlyRootFilesystem` is not required but is recommended

A Pod that meets `restricted` is generally considered safe to run as your everyday workload.

## Migration strategy

A common rollout:

1. **Start in warn mode.** Apply `warn=restricted` everywhere. Watch what `kubectl` yells about.
2. **Move to audit.** Set `audit=restricted` in dev / staging namespaces. Logs violations but doesn't block.
3. **Fix the violations.** Most common: containers need `runAsNonRoot: true`, `seccompProfile`, and dropped capabilities.
4. **Promote to enforce.** Set `enforce=restricted` in the namespace. Now violations are rejected.
5. **Roll out cluster-wide.** Once dev/staging has been clean for weeks, promote prod.

The same labels can be set differently per namespace. A common pattern:

```yaml
# kube-system: privileged (system Pods)
pod-security.kubernetes.io/enforce: privileged
pod-security.kubernetes.io/enforce-version: latest

# production: restricted
pod-security.kubernetes.io/enforce: restricted
pod-security.kubernetes.io/enforce-version: latest

# staging: baseline
pod-security.kubernetes.io/enforce: baseline
pod-security.kubernetes.io/enforce-version: latest
```

## Dry-run debug

```bash
# Try a Pod against a namespace's PSS without applying
kubectl auth can-i create pods --as=system:serviceaccount:default:default -n production
# doesn't actually check PSS — you need a real apply to see the admission response
```

Easier: just deploy in warn mode and read the warnings.

## Gotchas

* **PSS is admission-time only.** Once a Pod is admitted, PSS doesn't enforce anything at runtime. The kubelet doesn't kill a Pod mid-flight for violating PSS.
* **The "warn" and "audit" modes are different.** `warn` shows a `kubectl`-side message; `audit` adds an entry to the cluster's audit log. They both still allow the Pod.
* **The `latest` version is not always what you want.** You can pin to a specific version, e.g. `pod-security.kubernetes.io/enforce-version: v1.28` to lock behavior. Recommended for production.
* **PSS replaced PodSecurityPolicy (PSP).** PSP was deprecated in 1.21 and removed in 1.25. Don't write new PSPs. PSS is the way.
* **PSS doesn't replace NetworkPolicy.** A `restricted` Pod can still talk to anything. Pair with [[Kubernetes/concepts/L04-services-networking/05-network-policy|NetworkPolicy]].
* **The default namespace has no PSS labels** — it inherits the cluster's default, which is "allow everything". Don't deploy to `default`. Make a namespace, label it `restricted`, deploy there.
* **"Restricted" is a moving target.** Each k8s release may tighten the rules. Pin a version, or expect warnings on k8s upgrades.
* **Some legit workloads can't meet `restricted`.** A workload that genuinely needs to write to `/` (legacy daemon) or run as root — these need `baseline` or `privileged`, and a documented exception.

## PSS vs OPA / Kyverno

PSS is **built into the apiserver** — no extra components, no policy files. It only checks a fixed set of fields.

OPA / Kyverno / Gatekeeper check **arbitrary constraints** ("every image must come from our registry", "every Pod must have these labels"). Use PSS first (it's free and built-in), and add OPA/Kyverno when you need custom rules.
