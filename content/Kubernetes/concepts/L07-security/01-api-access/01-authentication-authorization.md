# Authentication vs Authorization

*"https://kubernetes.io/docs/reference/access-authn-authz/"*

These are **two different things** that get conflated constantly. **Authentication** answers "who are you?"; **Authorization** answers "what can you do?". Kubernetes does them as **separate steps**, in that order, on every API request. A request that fails authn returns 401; a request that passes authn but fails authz returns 403. Understanding the split is the foundation for RBAC, OIDC, ServiceAccount tokens, and webhook authz.

### Table of Contents

1. [The Split in the Request Flow](#1-the-split-in-the-request-flow)
2. [Authentication — who are you?](#2-authentication--who-are-you)
3. [The Authentication Chain](#3-the-authentication-chain)
4. [X.509 Client Certificates](#4-x509-client-certificates)
5. [Bearer Tokens (ServiceAccount, OIDC, Bootstrap)](#5-bearer-tokens-serviceaccount-oidc-bootstrap)
6. [Bound ServiceAccount Tokens (k8s 1.21+)](#6-bound-serviceaccount-tokens-k8s-121)
7. [OIDC for Human Users](#7-oidc-for-human-users)
8. [Webhook Token Authentication](#8-webhook-token-authentication)
9. [The UserInfo Object](#9-the-userinfo-object)
10. [Authorization — what can you do?](#10-authorization--what-can-you-do)
11. [The Authorization Chain](#11-the-authorization-chain)
12. [The Authorizers in Detail (Node, RBAC, ABAC, Webhook)](#12-the-authorizers-in-detail-node-rbac-abac-webhook)
13. [The "Deny by Default" Rule](#13-the-deny-by-default-rule)
14. [Anonymous Authentication — the Footgun](#14-anonymous-authentication--the-footgun)
15. [The system:* Groups](#15-the-system-groups)
16. [Impersonation (--as, --as-group)](#16-impersonation--as---as-group)
17. [The Authentication and Authorization in Practice](#17-the-authentication-and-authorization-in-practice)
18. [Common Patterns](#18-common-patterns)
19. [Operations and Debugging](#19-operations-and-debugging)
20. [Gotchas and Common Mistakes](#20-gotchas-and-common-mistakes)

---

## 1. The Split in the Request Flow

On every API request, the apiserver runs:

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

The two steps are **independent**. A valid user can be denied. The error message is the only way to tell which step failed.

The error codes:

* **401 Unauthorized** — authn failed. The credentials are wrong.
* **403 Forbidden** — authz failed. The credentials are fine, but you can't do this.

Clients should react differently:

* **401** — "your credentials are wrong, fix them and retry."
* **403** — "your credentials are fine, you can't do this, talk to an admin."

## 2. Authentication — who are you?

The apiserver runs a chain of **authenticators** in order. The first one that returns "yes" wins. The rest are skipped.

| Authenticator | Source | Common use |
|---|---|---|
| **X.509 client certificates** | `~/.kube/config` `client-certificate` | `kubectl` from outside, kubelet, controllers |
| **Bearer tokens** | `~/.kube/config` `token`, or HTTP `Authorization: Bearer` | ServiceAccount tokens, OIDC |
| **Bootstrap tokens** | `kube-system` `bootstrap-token-*` Secrets | `kubeadm join` |
| **ServiceAccount tokens** | JWT, mounted in Pods at `/var/run/secrets/kubernetes.io/serviceaccount/token` | In-cluster Pods |
| **OpenID Connect (OIDC)** | External IdP (Okta, Google, Azure AD) | User SSO |
| **Webhook token authentication** | External service you run | Custom auth |
| **Anonymous** | If `anonymous-auth=true` and no other matched | Healthz, debugging |

The result of authentication is a **UserInfo** object attached to the request.

## 3. The Authentication Chain

The chain runs **in order**. The first authenticator to return "yes" wins. If no authenticator returns "yes", the request is either:

* **401 Unauthorized** — if `--anonymous-auth=false` (the safe default).
* **Authenticated as `system:anonymous`** — if `--anonymous-auth=true`.

The order is configured via the apiserver's `--authentication-*` flags. The most common:

```bash
# standard setup
--client-ca-file=/etc/kubernetes/pki/ca.crt
--oidc-issuer-url=https://accounts.google.com
--oidc-client-id=kubernetes
--oidc-username-claim=email
--oidc-groups-claim=groups
--api-audiences=kubernetes
--service-account-key-file=/etc/kubernetes/pki/sa.pub
--service-account-signing-key-file=/etc/kubernetes/pki/sa.key
--service-account-issuer=https://kubernetes.default.svc.cluster.local
```

The order:

1. X.509 client cert (if `client-ca-file` is set).
2. Bearer token (ServiceAccount, OIDC, bootstrap).
3. Anonymous (if enabled).

The X.509 check is first. If the request has a client cert, it's verified against the client CA. If the cert is valid, the user is set from the cert's CN.

The bearer token check is next. The token is verified against the configured auth methods (SA key, OIDC, etc.).

Anonymous is the catch-all. If no other authenticator matched and anonymous is enabled, the user is `system:anonymous`.

## 4. X.509 Client Certificates

X.509 client certs are the **legacy** but still common auth method for:

* `kubectl` users (the `client-certificate` and `client-key` in kubeconfig).
* Kubelets (each kubelet has a client cert).
* Controllers (kube-scheduler, kube-controller-manager, etc.).

The cert is verified against `--client-ca-file` (the cluster CA). The cert's CN becomes the user, the O becomes the group.

Example:

```bash
# generate a client cert signed by the cluster CA
openssl genrsa -out alice.key 2048
openssl req -new -key alice.key -out alice.csr -subj "/CN=alice/O=developers"
openssl x509 -req -in alice.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key \
  -CAcreateserial -out alice.crt -days 365
```

The kubeconfig:

```yaml
apiVersion: v1
kind: Config
users:
- name: alice
  user:
    client-certificate: /path/to/alice.crt
    client-key: /path/to/alice.key
```

The user `alice` is authenticated. The `developers` group is set. RBAC matches on these.

**Client certs are powerful.** The CN of the cert becomes the user; if the CN is `kubernetes-admin`, the user is cluster-admin. Treat the cert / key as a root password.

## 5. Bearer Tokens (ServiceAccount, OIDC, Bootstrap)

Bearer tokens are in the HTTP `Authorization: Bearer <token>` header. The apiserver extracts the token and verifies it.

The token types:

* **ServiceAccount token** — a JWT signed by the apiserver. Verifiable by any k8s consumer.
* **OIDC token** — a JWT signed by an external IdP. The apiserver validates via the OIDC issuer's JWKS.
* **Bootstrap token** — a short-lived token in `kube-system/bootstrap-token-*` Secret. Used for `kubeadm join`.

### 5.1 The kubeconfig token

```yaml
apiVersion: v1
kind: Config
users:
- name: alice
  user:
    token: <bearer-token>
```

Or:

```yaml
users:
- name: alice
  user:
    auth-provider:
      name: oidc
      config:
        id-token: <jwt>
        refresh-token: <refresh>
```

### 5.2 The in-cluster Pod

A Pod in the cluster has its SA token mounted:

```bash
# inside the Pod
cat /var/run/secrets/kubernetes.io/serviceaccount/token
# a JWT, valid for the Pod's lifetime
```

The Pod uses this token to authenticate to the apiserver.

### 5.3 The bootstrap token

`kubeadm join` uses a bootstrap token:

```bash
kubeadm token create --print-join-command
# generates: kubeadm join ... --token <token> --discovery-token-ca-cert-hash sha256:...
```

The token is in a Secret in `kube-system`. It's short-lived (24h by default). After `kubeadm join`, the token is consumed.

## 6. Bound ServiceAccount Tokens (k8s 1.21+)

*"https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/#bound-service-account-tokens"*

Legacy SA tokens were **long-lived** (the lifetime of the Secret). The bound tokens (k8s 1.21+, GA in 1.30) are **short-lived** and **audience-scoped**.

A bound token:

* Is a JWT.
* Has a specific `aud` (audience) — only valid for the configured audience.
* Has a short expiry (~1h by default).
* Is bound to a specific Pod — can't be reused by another Pod.

The Pod gets a bound token via a **projected volume**:

```yaml
apiVersion: v1
kind: Pod
metadata: { name: app }
spec:
  serviceAccountName: my-sa
  containers:
  - name: app
    image: app:1.0
    volumeMounts:
    - name: sa-token
      mountPath: /var/run/secrets/kubernetes.io/serviceaccount
      readOnly: true
  volumes:
  - name: sa-token
    projected:
      sources:
      - serviceAccountToken:
          path: token
          audience: https://my-service.example.com   # the audience
          expirationSeconds: 3600                    # 1 hour
```

The kubelet requests a bound token from the apiserver. The token is mounted to the Pod. The Pod can use it to authenticate to `https://my-service.example.com` (or any service that validates the `aud`).

The `audience` is critical. A token for `https://my-service.example.com` is rejected by `https://other-service.example.com`. This is the **security model for service-to-service auth**.

The legacy long-lived tokens (via Secrets) are **deprecated**. Use bound tokens.

## 7. OIDC for Human Users

*"https://kubernetes.io/docs/reference/access-authn-authz/authentication/#openid-connect-tokens"*

OIDC is the standard for **user SSO**. The apiserver is configured to trust an OIDC issuer:

```bash
--oidc-issuer-url=https://accounts.google.com
--oidc-client-id=kubernetes
--oidc-username-claim=email
--oidc-groups-claim=groups
--oidc-required-claim=hd=example.com     # optional: only users in this domain
```

The flow:

1. User authenticates to the OIDC IdP (Okta, Google, Azure AD).
2. The IdP issues a JWT.
3. The user passes the JWT to the apiserver (via `kubectl` with a kubeconfig that has the OIDC provider config).
4. The apiserver validates the JWT against the IdP's JWKS.
5. The apiserver extracts the username (from `email`) and groups (from `groups`).
6. The user is `alice@example.com`, the groups are `developers`, `platform`, etc.
7. RBAC matches on these.

For `kubectl`, the `kubelogin` plugin handles the OIDC flow. It opens a browser, the user logs in, the plugin gets the token, and `kubectl` uses it.

### 7.1 The OIDC claims

The claims the apiserver uses:

* `iss` (issuer) — must match `--oidc-issuer-url`.
* `sub` (subject) — the user's unique ID.
* `aud` (audience) — must include `--oidc-client-id`.
* `exp` (expiry) — must be in the future.
* `--oidc-username-claim` — the claim to use as the username (e.g. `email`, `sub`, `preferred_username`).
* `--oidc-groups-claim` — the claim to use as the groups (e.g. `groups`).

### 7.2 The required-claim filter

`--oidc-required-claim=hd=example.com` — only users from the `example.com` G Suite domain are allowed. The `hd` claim is Google-specific; for Okta, you'd use a different claim.

## 8. Webhook Token Authentication

*"https://kubernetes.io/docs/reference/access-authn-authz/authentication/#webhook-token-authentication"*

The apiserver can call out to an **external service** to validate tokens:

```yaml
# /etc/kubernetes/authn-webhook-config.yaml
apiVersion: v1
kind: Config
clusters:
- name: my-authn
  cluster:
    server: https://my-authn-service/authn
    certificate-authority: /etc/kubernetes/ca.crt
contexts:
- context:
    cluster: my-authn
    user: ""
  name: default
current-context: default
preferences: {}
users: []
```

The apiserver calls the webhook for each bearer token. The webhook returns:

```json
{
  "apiVersion": "authentication.k8s.io/v1beta1",
  "kind": "TokenReview",
  "status": {
    "authenticated": true,
    "user": {
      "username": "alice@example.com",
      "groups": ["developers"]
    }
  }
}
```

The apiserver extracts the user and groups from the response. The webhook is **on the hot path** — every API request that uses a token goes through it.

The webhook is used for:

* **Custom auth** — your own SSO (e.g. a non-OIDC IdP).
* **JWT validation** — a service that validates JWTs from your IdP.
* **Static tokens** — a service that looks up tokens in a database.

The webhook's response is cached (`--authentication-token-webhook-cache-ttl`, default 5m). The cache reduces load on the webhook.

## 9. The UserInfo Object

The result of authentication is a `UserInfo` object attached to the request:

```go
type UserInfo struct {
    Username string
    UID      string
    Groups   []string
    Extra    map[string][]string
}
```

* **`Username`** — a string. `system:serviceaccount:default:my-sa` for a SA. `alice@example.com` for OIDC. `kubernetes-admin` for a client cert.
* **`UID`** — a unique ID for the user (k8s-internal). Used by RBAC.
* **`Groups`** — a list of groups. `system:authenticated`, `system:serviceaccounts`, `developers`, `system:masters`, etc.
* **`Extra`** — extra claims. For OIDC, the IdP's other claims (e.g. `extra.email`).

The UserInfo is **read by RBAC** and **recorded in the audit log**.

## 10. Authorization — what can you do?

The apiserver has **multiple authorizers** configured. They're tried in order. The first one to give a definitive answer wins. If none give a definitive answer, the default is **deny**.

| Authorizer | Model | Use case |
|---|---|---|
| **RBAC** (Role-Based Access Control) | Roles + bindings | Most common, default in 1.8+ |
| **Node** | Special case for kubelets | Node authorizer, not for users |
| **ABAC** (Attribute-Based) | Policy file with attrs | Legacy, deprecated |
| **Webhook** | Call out to an external authorizer (OPA, etc.) | Custom policy engines |

**RBAC is the default and the only one most clusters use.**

## 11. The Authorization Chain

The chain runs **in order**. The first authorizer to return a definitive `allow` or `forbid` wins. If none return a definitive answer, the request is **denied**.

```bash
--authorization-mode=Node,RBAC
```

The order:

1. `Node` — for kubelet requests. The Node authorizer allows kubelets to update their own Node and Pod status.
2. `RBAC` — for everything else. Matches Roles / ClusterRoles / RoleBindings / ClusterRoleBindings.

Other modes:

* `--authorization-mode=Node,RBAC,Webhook` — adds a webhook authorizer. The webhook is called only if RBAC returns a definitive answer (or to override, depending on config).
* `--authorization-mode=ABAC,RBAC` — ABAC is deprecated, don't use.
* `--authorization-mode=AlwaysAllow` — disables all authz. **Don't use.**

The chain's order is critical. If `RBAC` is before `Webhook`, the RBAC answer wins for matching requests. The webhook is not called.

## 12. The Authorizers in Detail (Node, RBAC, ABAC, Webhook)

### 12.1 Node authorizer

*"https://kubernetes.io/docs/reference/access-authn-authz/node/"*

A special authorizer for **kubelet requests**. Allows kubelets to:

* Read their own Node.
* Update their own Node's status (conditions, addresses).
* Update their own Pod's status.
* Read most API resources (for `kubectl exec`, `kubectl logs`).

A kubelet is identified by its username `system:node:<node-name>`. The Node authorizer matches this and allows the relevant actions.

The Node authorizer works with the **NodeRestriction** admission plugin. NodeRestriction restricts what kubelets can do on the Node / Pod (e.g. only add certain labels / taints).

### 12.2 RBAC authorizer

*"https://kubernetes.io/docs/reference/access-authn-authz/rbac/"*

The workhorse. RBAC has:

* **Role** / **ClusterRole** — a set of allowed verbs on resources.
* **RoleBinding** / **ClusterRoleBinding** — assigns a Role to a subject (User, Group, ServiceAccount).

See [[Kubernetes/concepts/L07-security/01-api-access/03-rbac|RBAC]] for the full picture.

### 12.3 ABAC authorizer

*"https://kubernetes.io/docs/reference/access-authn-authz/abac/"*

**Legacy**. Uses a policy file with attributes. Deprecated; use RBAC.

ABAC has a few drawbacks:

* Policies are in a file (not API objects).
* No default-deny (you have to deny explicitly).
* No way to update without restarting the apiserver.
* No way to delegate (you have to edit the file).

For new clusters, don't use ABAC.

### 12.4 Webhook authorizer

*"https://kubernetes.io/docs/reference/access-authn-authz/webhook/"*

A custom authorizer. The apiserver calls a webhook for each request:

```yaml
# /etc/kubernetes/authz-webhook-config.yaml
apiVersion: v1
kind: Config
clusters:
- name: my-authz
  cluster:
    server: https://my-authz-service/authz
    certificate-authority: /etc/kubernetes/ca.crt
```

The webhook receives a `SubjectAccessReview`:

```json
{
  "apiVersion": "authorization.k8s.io/v1",
  "kind": "SubjectAccessReview",
  "spec": {
    "user": "alice",
    "group": ["developers"],
    "resourceAttributes": {
      "namespace": "default",
      "verb": "get",
      "resource": "pods"
    }
  }
}
```

The webhook returns `allowed: true` or `allowed: false`.

The webhook is on the **hot path**. A slow webhook slows down all API requests. Cache aggressively (`--authorization-webhook-cache-authorized-ttl=5m`).

The `failurePolicy` (in the SAR spec, not the apiserver) is important:

* `FailurePolicy: allow` — if the webhook fails, the request is allowed.
* `FailurePolicy: deny` — if the webhook fails, the request is denied.

For most custom authz, `allow` is the safe default (don't break the API when the webhook is down). For security-critical authz, `deny`.

## 13. The "Deny by Default" Rule

A request that **no authorizer has an opinion on** is **denied**. This is the safe default.

```
kubectl apply -f foo.yaml
# 403 Forbidden
# (even if you're authenticated as a valid user)
```

The fix: add a Role / ClusterRole + binding for the user / SA.

This is the **principle of least privilege** at the authz level. Nothing is allowed by default; every action needs a rule.

## 14. Anonymous Authentication — the Footgun

`--anonymous-auth=true` (the k8s default) **allows requests with no credentials** to be authenticated as `system:anonymous`.

The `system:anonymous` user is in the `system:unauthenticated` group. If RBAC grants these any permission, **anyone can use them** (no credentials needed).

The standard hardening:

```bash
--anonymous-auth=false
```

This rejects unauthenticated requests. A request with no credentials is **401 Unauthorized**. No `system:anonymous` user is created.

The trade-off:

* **With anonymous on** — backward-compatible, some tools (like `kubectl auth can-i` without a user) work without credentials. But the footgun is real.
* **With anonymous off** — strict. All requests must have credentials. `kubectl auth can-i` requires `--as <user>` or a kubeconfig.

**For production, set `--anonymous-auth=false`.** The footgun outweighs the convenience.

## 15. The system:* Groups

Some groups are **automatic** and **special**:

* **`system:authenticated`** — anyone who authenticates (regardless of who they are) is in this group. Don't grant it broad permissions.
* **`system:unauthenticated`** — unauthenticated requests (with anonymous auth on). Don't grant it anything.
* **`system:masters`** — cluster-admin. Anyone in this group has full access. Don't add users to it.
* **`system:serviceaccounts`** — all ServiceAccounts in all namespaces. Don't grant it broad permissions.
* **`system:serviceaccounts:<namespace>`** — all SAs in a specific namespace.
* **`system:nodes`** — all kubelets.
* **`system:kube-controller-manager`**, **`system:kube-scheduler`**, **`system:kube-proxy`** — the control plane components. Don't grant them extra permissions.

The convention: `system:` is reserved for k8s-internal groups. You should **not** create a group with a `system:` prefix.

## 16. Impersonation (--as, --as-group)

*"https://kubernetes.io/docs/reference/access-authn-authz/authentication/#user-impersonation"*

`kubectl` supports **impersonation**: act as a different user for one command.

```bash
# act as alice
kubectl get pods --as=alice

# act as a member of a group
kubectl get pods --as=alice --as-group=developers

# act as a ServiceAccount
kubectl get pods --as=system:serviceaccount:default:my-sa
```

The apiserver's user is set to the impersonated user, but the apiserver records **both** the original user (in `user.extra.authentication.kubernetes.io/impersonator`) and the impersonated user.

Impersonation is **powerful and dangerous**. The original user must be allowed to impersonate the target user (via an RBAC rule with `impersonate` / `impersonate` verbs on `users` / `groups`).

The standard:

```yaml
# allow alice to impersonate ServiceAccounts
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: { name: impersonator }
rules:
- apiGroups: [""]
  resources: ["users", "groups", "serviceaccounts"]
  verbs: ["impersonate"]
- apiGroups: ["authentication.k8s.io"]
  resources: ["uids"]
  verbs: ["impersonate"]
```

The `impersonator` ClusterRole is for debugging. **Don't grant it broadly.**

## 17. The Authentication and Authorization in Practice

### 17.1 `kubectl` from your laptop

```
1. kubectl loads your kubeconfig
2. kubectl extracts the client cert + key (or token)
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

### 17.2 In-cluster Pod

```
1. Pod's code reads /var/run/secrets/kubernetes.io/serviceaccount/token
2. Constructs HTTP request with "Authorization: Bearer ***"
3. TLS to the apiserver (in-cluster)
4. apiserver validates the JWT → user "system:serviceaccount:default:app"
5. RBAC checks: does app have "list pods" in default?
   - Yes: proceed
   - No: 403
6. Admission control
7. Response
```

## 18. Common Patterns

### 18.1 "I want to give the dev team access to their namespace"

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

### 18.2 "I want the app to read its own ConfigMap but no others"

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

### 18.3 "I want the CI system to deploy to a specific namespace"

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

## 19. Operations and Debugging

### 19.1 Common commands

```bash
# check your identity
kubectl auth whoami
# output: system:user:alice (or similar)

# can I do this?
kubectl auth can-i create deployments --namespace=default

# can the "app" SA do this?
kubectl auth can-i list pods --as=system:serviceaccount:default:app -n default

# what can this user do in this namespace?
kubectl auth can-i --list --as=alice@example.com -n production

# debug authn
kubectl -n kube-system logs kube-apiserver-<node> | grep -i "authn\|401"

# debug authz
kubectl auth can-i <verb> <resource> --as=<user>
```

### 19.2 The "401 Unauthorized" case

A request is rejected with 401.

```bash
# 1. Is the apiserver's anonymous-auth on?
kubectl -n kube-system get pod kube-apiserver-<node> -o yaml | grep anonymous-auth
# if --anonymous-auth=true, requests with no credentials are accepted as system:anonymous

# 2. Is the token valid?
# (for bearer tokens)
kubectl -n kube-system logs kube-apiserver-<node> | grep "401\|invalid\|expired"

# 3. Is the cert valid?
# (for client certs)
openssl verify -CAfile /etc/kubernetes/pki/ca.crt alice.crt
```

### 19.3 The "403 Forbidden" case

A request passes authn but fails authz.

```bash
# 1. What user is the apiserver seeing?
kubectl auth whoami
# or, in the apiserver log:
kubectl -n kube-system logs kube-apiserver-<node> | grep "user\|forbid"

# 2. Does the user have a RoleBinding?
kubectl get rolebindings -A
kubectl get clusterrolebindings

# 3. What can the user do?
kubectl auth can-i --list --as=<user> -n <ns>

# 4. Is the RBAC correct?
kubectl get role <name> -n <ns> -o yaml
kubectl get rolebinding <name> -n <ns> -o yaml
```

## 20. Gotchas and Common Mistakes

### 20.1 The 30+ common mistakes

1. **Anonymous auth is on by default** (`--anonymous-auth=true`). For production, set it to false. The footgun outweighs the convenience.

2. **ServiceAccount tokens in the cluster are not the same as OIDC tokens.** SA tokens are JWTs signed by the apiserver, validated by any k8s-aware consumer. OIDC tokens are signed by an external IdP.

3. **Long-lived SA tokens (legacy) are deprecated.** The new bound tokens (k8s 1.21+) are short-lived and audience-scoped.

4. **The `client-cert` in `~/.kube/config` is the cluster-admin key.** Anyone with this can do anything. Treat it like a root password.

5. **`kubectl auth can-i` is what the apiserver thinks you can do** — useful for debugging RBAC, but it's not a security boundary (the apiserver itself can be compromised).

6. **No authorizer answer = deny.** If RBAC doesn't have a rule that matches, the request is denied. There's no implicit "allow if no rule says otherwise".

7. **RoleBinding is namespaced; ClusterRoleBinding is cluster-wide.** A ClusterRoleBinding gives the same permissions in every namespace.

8. **ABAC is deprecated.** Don't use it for new clusters. Migrate to RBAC if you have an old one.

9. **Webhook authorizers are on the hot path.** A slow or unavailable webhook blocks all requests. Always have a fallback or `failurePolicy: allow`.

10. **The `system:masters` group is cluster-admin.** Anyone in this group has full access. Don't add users to it.

11. **The `system:anonymous` and `system:unauthenticated` groups exist.** Make sure they're not granted anything.

12. **Node authorization is special.** It's used only by the kubelet to update its Node and Pod status. You don't normally interact with it.

13. **ServiceAccounts don't have cluster-wide permissions by default.** They have whatever's bound in their namespace. ClusterRoleBinding a SA = cluster-wide for that SA.

14. **The `system:authenticated` group is automatic.** Anyone who authenticates is in this group. Don't grant it broad permissions.

15. **The 401 vs 403 distinction matters.** 401 = authn failed. 403 = authz failed. Clients should react differently.

16. **Impersonation requires an RBAC rule.** The original user must have `impersonate` on `users` / `groups` / `serviceaccounts`.

17. **The apiserver records both the original and impersonated user** in the audit log and the request's UserInfo. The `impersonator` is in `user.extra`.

18. **OIDC group claims can be slow.** The apiserver validates the token (calls the IdP's JWKS endpoint, cached). If the IdP is slow, auth is slow.

19. **A bootstrap token is short-lived** (default 24h). After `kubeadm join`, the token is consumed.

20. **The `--requestheader-client-ca-file` is for the front proxy** (API aggregation), not for client certs.

21. **A RoleBinding subject can be a User, Group, or ServiceAccount.** Different `kind`s.

22. **A `ServiceAccount` in one namespace can be a subject in a RoleBinding in another.** The cross-namespace binding is a useful pattern.

23. **Bound SA tokens (k8s 1.21+) are the standard.** The legacy long-lived SA token Secret is deprecated.

24. **The `--service-account-issuer` is the `iss` claim of bound tokens.** Consumers verify the `iss` to confirm the token is from this cluster.

25. **The `aud` claim of a bound token is the audience.** A token for `vault` is rejected by `consul`. This is the security model for service-to-service auth.

26. **The `kubernetes` audience is the default.** The apiserver issues tokens with `aud: kubernetes` by default.

27. **A bound token's expirationSeconds is per-token, not per-SA.** The token is valid for 1h (default). The kubelet requests a new one before expiry.

28. **The kubelet's serving cert is separate from the kubelet's client cert.** Two certs, two roles.

29. **The apiserver's `--bind-address` is the IP it listens on.** Set it to a private IP for production.

30. **The `kubectl auth can-i` command can be slow on large clusters** (queries RBAC for every match). Use the namespace-scoped version for performance.

## See also

* [[Kubernetes/concepts/L07-security/01-api-access/02-service-accounts|ServiceAccounts]] — the in-cluster identity
* [[Kubernetes/concepts/L07-security/01-api-access/03-rbac|RBAC]] — the authorization model
* [[Kubernetes/concepts/L07-security/01-api-access/04-certificates|Certificates]] — the X.509 piece
* [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/20-cluster-hardening|Cluster Hardening]] — the apiserver flags
