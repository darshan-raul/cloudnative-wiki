# Authentication vs Authorization

*"https://kubernetes.io/docs/reference/access-authn-authz/"*

These are **two different things** that get conflated constantly. Authentication answers "who are you?"; authorization answers "what can you do?". Kubernetes does them as separate steps, in that order, on every API request.

## The split

| Step | Question | Mechanism | Failure mode |
|---|---|---|---|
| **Authentication (authn)** | Who are you? | X.509 certs, bearer tokens, OIDC, webhooks | 401 Unauthorized |
| **Authorization (authz)** | What can you do? | RBAC, Node, ABAC, Webhook | 403 Forbidden |

The flow on every API request:

```
kubectl apply -f deployment.yaml
        ↓
  HTTPS POST to apiserver
        ↓
  ┌─────────────────────────────────┐
  │  1. TLS termination              │
  │     (transport security)         │
  └────────────┬────────────────────┘
               ↓
  ┌─────────────────────────────────┐
  │  2. Authentication               │  "who are you?"
  │     x509 / token / webhook / OIDC │  → 401 if fail
  │     → UserInfo attached          │
  └────────────┬────────────────────┘
               ↓
  ┌─────────────────────────────────┐
  │  3. Authorization                │  "what can you do?"
  │     RBAC / Node / ABAC / Webhook │  → 403 if fail
  │     → allow / deny               │
  └────────────┬────────────────────┘
               ↓
  ┌─────────────────────────────────┐
  │  4. Admission control            │  (see L09)
  │     mutating + validating        │
  └────────────┬────────────────────┘
               ↓
       Object stored in etcd
```

## Authentication — who are you?

The apiserver runs a chain of **authenticators** in order. The first one that returns "yes" wins. The rest are skipped.

| Authenticator | Source | Common use |
|---|---|---|
| **X.509 client certificates** | `~/.kube/config` `client-certificate` | `kubectl` from outside, kubelet, controllers |
| **Bearer tokens** | `~/.kube/config` `token` | ServiceAccount tokens, OIDC |
| **Bootstrap tokens** | `kube-system` `bootstrap-token-*` Secrets | `kubeadm join` |
| **ServiceAccount tokens** | JWT, mounted in Pods at `/var/run/secrets/kubernetes.io/serviceaccount/token` | In-cluster Pods |
| **OpenID Connect (OIDC)** | External IdP (Okta, Google, Azure AD) | User SSO |
| **Webhook token authentication** | External service you run | Custom auth |
| **Anonymous** | If `anonymous-auth=true` and no other matched | Healthz, debugging |

The result of authentication is a **UserInfo** object attached to the request:

```go
type UserInfo struct {
    Username string
    UID      string
    Groups   []string
    Extra    map[string][]string
}
```

`Username` is a string like `system:serviceaccount:default:my-sa` or `alice@example.com` (from OIDC). The format depends on the auth source.

### Authentication in practice

**kubectl from your laptop:**

```bash
# check your identity
kubectl auth whoami
# output: system:user:alice (or similar)
```

**Inside a Pod:**

```bash
# the kubelet mounts a token at a known path
cat /var/run/secrets/kubernetes.io/serviceaccount/token
# (this is a JWT, valid for the Pod's lifetime)
```

**ServiceAccount tokens (modern, bound):**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: { name: app, namespace: default }
# When a Pod uses this SA, the projected token is:
# - valid for 1h by default
# - scoped to a specific audience
# - bound to the Pod (can't be reused elsewhere)
```

**OIDC for humans:**

```bash
# apiserver flag
--oidc-issuer-url=https://accounts.google.com
--oidc-client-id=kubernetes
--oidc-username-claim=email
--oidc-groups-claim=groups
```

With this config, a user can `kubectl login` (or `kubelogin`) and the apiserver validates the OIDC token, extracts `email` as the username and `groups` as the groups.

### Authentication gotchas

* **Authentication is anonymous by default** if `anonymous-auth=true` (the default). If no authenticator matches, the request proceeds as `system:anonymous`. If RBAC grants `system:anonymous` access, anyone can do anything.
* **ServiceAccount tokens in the cluster are not the same as OIDC tokens.** SA tokens are JWTs signed by the apiserver, validated by any k8s-aware consumer. OIDC tokens are signed by an external IdP.
* **Long-lived SA tokens (legacy) are deprecated.** The new bound tokens (k8s 1.21+) are short-lived and audience-scoped.
* **The `client-cert` in `~/.kube/config` is the cluster-admin key.** Anyone with this can do anything. Treat it like a root password.
* **`kubectl auth can-i` is what the apiserver thinks you can do** — useful for debugging RBAC, but it's not a security boundary (the apiserver itself can be compromised).

## Authorization — what can you do?

The apiserver has multiple **authorizers** configured. They're tried in order; the first one to give a definitive answer wins. If none give a definitive answer, the default is **deny**.

| Authorizer | Model | Use case |
|---|---|---|
| **RBAC** (Role-Based Access Control) | Roles + bindings | Most common, default in 1.8+ |
| **Node** | Special case for kubelets | Node authorizer, not for users |
| **ABAC** (Attribute-Based) | Policy file with attrs | Legacy, deprecated |
| **Webhook** | Call out to an external authorizer (OPA, etc.) | Custom policy engines |

**RBAC is the default and the only one most clusters use.** It has two main concepts:

* **Role** / **ClusterRole** — a set of allowed verbs on a set of resources
* **RoleBinding** / **ClusterRoleBinding** — assigns a Role to a User / Group / ServiceAccount

→ [[Kubernetes/concepts/L07-security/03-rbac|RBAC]] — the full deep dive

### Authorization in practice

```bash
# can I do this?
kubectl auth can-i create deployments --namespace=default

# can the "app" SA do this?
kubectl auth can-i list pods --as=system:serviceaccount:default:app -n default

# what can this user do in this namespace?
kubectl auth can-i --list --as=alice@example.com -n production
```

`kubectl auth can-i` is a debugging tool. Use it to figure out why a request is failing.

### Authorization gotchas

* **No answer = deny.** If RBAC doesn't have a rule that matches, the request is denied. There's no implicit "allow if no rule says otherwise" — every verb needs an explicit allow.
* **RoleBinding is namespaced; ClusterRoleBinding is cluster-wide.** A ClusterRoleBinding gives the same permissions in every namespace.
* **ABAC is deprecated.** Don't use it for new clusters. Migrate to RBAC if you have an old one.
* **Webhook authorizers are on the hot path.** A slow or unavailable webhook blocks all requests. Always have a fallback or `failurePolicy: NoOpinion`.
* **The `system:masters` group is cluster-admin.** Anyone in this group has full access. Don't add users to it.
* **The `system:anonymous` and `system:unauthenticated` groups exist.** Make sure they're not granted anything.
* **Node authorization is special.** It's used only by the kubelet to update its Node and Pod status. You don't normally interact with it.
* **ServiceAccounts don't have cluster-wide permissions by default.** They have whatever's bound in their namespace. ClusterRoleBinding a SA = cluster-wide for that SA.

## The "deny by default" rule

A request that **no authorizer has an opinion on** is denied. This is the safe default.

```
kubectl apply -f foo.yaml
# 403 Forbidden
# (even if you're authenticated as a valid user)
```

The fix: add a Role / ClusterRole + binding for the user / SA.

## Authentication AND authorization together

Here's the full flow for `kubectl apply` from your laptop:

```
1. kubectl loads your kubeconfig
2. kubectl extracts the client cert + key
3. kubectl constructs the HTTP request
4. TLS to the apiserver
5. apiserver authenticates the client cert → user "system:user:alice"
6. RBAC checks: does alice have "create deployments" in this namespace?
   - Yes: proceed
   - No: 403
7. Admission control runs
8. Object stored
9. Response back to kubectl
```

And the same flow for an in-cluster Pod:

```
1. Pod's code reads /var/run/secrets/kubernetes.io/serviceaccount/token
2. Constructs HTTP request with "Authorization: Bearer <token>"
3. TLS to the apiserver (in-cluster)
4. apiserver validates the JWT → user "system:serviceaccount:default:app"
5. RBAC checks: does app have "list pods" in default?
   - Yes: proceed
   - No: 403
6. Admission control
7. Response
```

## Common patterns

### "I want to give the dev team access to their namespace"

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: devs, namespace: team-a }
subjects:
- kind: Group
  name: "developers"             # OIDC group
  apiGroup: rbac.authorization.k8s.io
- kind: Group
  name: "team-a-admins"
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: edit                      # built-in "edit" role
  apiGroup: rbac.authorization.k8s.io
```

The `edit` ClusterRole gives most read/write permissions in the namespace. The Group `developers` is from OIDC.

### "I want the app to read its own ConfigMap but no others"

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: app-reader, namespace: default }
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  resourceNames: ["app-config"]   # ONLY this ConfigMap
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: app-reader, namespace: default }
subjects:
- kind: ServiceAccount
  name: app
  namespace: default
roleRef:
  kind: Role
  name: app-reader
  apiGroup: rbac.authorization.k8s.io
```

The `resourceNames` field is the trick — it limits the Role to one specific ConfigMap.

### "I want the CI system to deploy to a specific namespace"

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: { name: ci, namespace: ci }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: ci-deploy, namespace: prod }
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "update", "patch"]
- apiGroups: [""]
  resources: ["pods", "services", "configmaps"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: ci-deploy, namespace: prod }
subjects:
- kind: ServiceAccount
  name: ci
  namespace: ci                 # SA in one ns, bound in another
roleRef:
  kind: Role
  name: ci-deploy
  apiGroup: rbac.authorization.k8s.io
```

CI's ServiceAccount can deploy but not create new resources or read secrets.

## When to use which authenticator

| Scenario | Authenticator |
|---|---|
| `kubectl` from your laptop | X.509 client cert, or OIDC |
| `kubectl` for users with SSO | OIDC |
| In-cluster Pods calling the API | ServiceAccount token |
| kubelets talking to the apiserver | X.509 client cert (bootstrapped via `kubeadm`) |
| CI/CD systems | ServiceAccount token (k8s 1.21+ bound tokens) |
| Legacy integrations | Static tokens (deprecated) |

## When to use which authorizer

| Scenario | Authorizer |
|---|---|
| Most clusters | RBAC (default) |
| Compliance / strict policy | RBAC + Webhook (OPA / Kyverno) for additional checks |
| Multi-tenancy with custom rules | Webhook authorizer (OPA, keto) |
| Legacy (pre-1.8) | ABAC (migrate away) |

## Gotchas

* **Authentication and authorization are separate.** A valid user can still be denied. The error message is the only way to tell which step failed.
* **The error message says 401 for authn failure, 403 for authz failure.** Clients should react differently — 401 means "your credentials are wrong", 403 means "your credentials are fine, you can't do this".
* **`--as` and `--as-group` flags on kubectl** are for impersonation. They let you "become" a different user for one command. Requires the impersonator to have permission to impersonate.
* **The `system:authenticated` group is automatic.** Anyone who authenticates (regardless of who they are) is in this group. Don't grant it broad permissions.
* **The `system:unauthenticated` group exists for unauthenticated requests.** With anonymous auth enabled, unauthenticated requests are in this group. **Don't grant it any permissions.**
* **ServiceAccount tokens are JWTs.** The signing key is the apiserver's. The token's `iss` claim is the apiserver; the `sub` claim is `system:serviceaccount:<ns>:<sa>`; the `aud` is `kubernetes` (or a custom audience for bound tokens).
* **Bound tokens (k8s 1.21+) have a `aud` claim.** A consumer (like Vault) verifies this and rejects tokens for other audiences. This is the security model for service-to-service auth in k8s.
* **`kubectl auth can-i` works in real time.** Use it after changing RBAC to verify the change took effect.
* **ServiceAccount discovery tokens are cached.** Changes to a SA's bindings might not take effect for ~1 minute (the token's default TTL).
* **The `kubernetes` username is special.** It's used internally; you can't authenticate as `kubernetes`.
* **OIDC group claims can be slow.** The apiserver calls out to the IdP to verify groups. If the IdP is slow, auth is slow. Use a local cache or short-lived tokens.

## See also

* [[Kubernetes/concepts/L07-security/02-service-accounts|ServiceAccounts]] — the in-cluster identity
* [[Kubernetes/concepts/L07-security/03-rbac|RBAC]] — the authorization model
* [[Kubernetes/concepts/L07-security/07-security|Security Overview]] — the big picture
* [[Kubernetes/concepts/L07-security/04-certificates|Certificates]] — the X.509 piece
