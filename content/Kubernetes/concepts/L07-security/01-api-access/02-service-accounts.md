# Service Accounts

*"https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/"*

A **ServiceAccount (SA)** is the **identity a Pod runs as** when it talks to the apiserver. It's the workload-side counterpart to a human user: where a person has an OIDC identity, a Pod has a SA. This note covers the SA lifecycle, the token evolution (legacy → projected → bound), the automount / `default` SA footguns, and the operational patterns for binding SAs to RBAC. SAs are **namespaced**; each namespace has a `default` SA that the apiserver auto-mounts to every Pod that doesn't ask for a different one.

### Table of Contents

1. [What a Service Account Is](#1-what-a-service-account-is)
2. [The Default Service Account](#2-the-default-service-account)
3. [Creating a Custom SA](#3-creating-a-custom-sa)
4. [The SA Token (the credential)](#4-the-sa-token-the-credential)
5. [The Legacy Long-Lived Token (Deprecated)](#5-the-legacy-long-lived-token-deprecated)
6. [Bound ServiceAccount Tokens (the modern way)](#6-bound-serviceaccount-tokens-the-modern-way)
7. [The Projected Token Mechanics](#7-the-projected-token-mechanics)
8. [The TokenRequest API](#8-the-tokenrequest-api)
9. [Audience and Expiry in Depth](#9-audience-and-expiry-in-depth)
10. [Disabling Automount](#10-disabling-automount)
11. [The Pod's `serviceAccountName`](#11-the-pods-serviceaccountname)
12. [ServiceAccount and Image Pull Secrets](#12-serviceaccount-and-image-pull-secrets)
13. [RBAC for ServiceAccounts](#13-rbac-for-serviceaccounts)
14. [IRSA and Pod Identity (Cloud-Native)](#14-irsa-and-pod-identity-cloud-native)
15. [The SA User Identity](#15-the-sa-user-identity)
16. [The ServiceAccount Signing Key](#16-the-serviceaccount-signing-key)
17. [The OIDC Discovery Endpoint](#17-the-oidc-discovery-endpoint)
18. [Common Patterns](#18-common-patterns)
19. [Operations and Debugging](#19-operations-and-debugging)
20. [Gotchas and Common Mistakes](#20-gotchas-and-common-mistakes)

---

## 1. What a Service Account Is

A `ServiceAccount` is a **namespaced k8s resource** that:

* Identifies a workload (a Pod) to the apiserver.
* Carries a token credential (a JWT) for the apiserver to verify.
* Optionally references **image pull Secrets** (for pulling from private registries).
* Optionally references a **bound token volume** (the modern way to project a token into the Pod).

SAs are **not for humans**. A human's identity is from OIDC, a client cert, or a webhook. A SA is **for processes**.

A SA's `metadata` has the standard fields (name, namespace, labels, annotations). The `spec` is small:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app
  namespace: default
automountServiceAccountToken: false    # optional: disable automount for this SA
imagePullSecrets:                      # optional: pull secrets for this SA
- name: my-registry-creds
secrets:                               # legacy: long-lived token Secret (deprecated)
- name: my-app-token-xyz
```

The `secrets` field is **legacy**. With bound tokens, the secret is created automatically by the apiserver only if `kubernetes.io/service-account-token` is the secret's type. New clusters don't create these.

The `imagePullSecrets` field is the standard way to give a Pod access to a private registry. The Pod's spec can also list `imagePullSecrets` directly; the SA's `imagePullSecrets` are merged in.

## 2. The Default Service Account

Every namespace has a `default` SA. It's **created automatically** when the namespace is created. The `default` SA:

* Has no RBAC bindings by default (in most clusters).
* Is auto-mounted to every Pod that doesn't specify a different SA.

```bash
# list the SAs in a namespace
kubectl get sa -n default
# NAME      SECRETS   AGE
# default   0         30d
```

The `SECRETS` column is 0 if the legacy long-lived token Secret isn't created. With bound tokens, the column is `0` (no Secret); the token is in a projected volume.

A Pod without an explicit `serviceAccountName` uses `default`:

```yaml
spec:
  # serviceAccountName: default    # implicit
  containers:
  - name: app
    image: myapp:1.0
```

The `default` SA's automount is the source of the **"every Pod has a token"** behavior. **For Pods that don't talk to the apiserver, this is wasted and a small attack surface.** Disable it.

## 3. Creating a Custom SA

A custom SA is just a YAML:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app
  namespace: default
```

Or via `kubectl`:

```bash
kubectl create serviceaccount my-app
```

The SA is in the namespace. **A SA in one namespace can be referenced by a Pod in any namespace** (the `serviceAccountName` in the Pod spec must be a fully qualified name if cross-namespace, but typically Pods use SAs in the same namespace).

A custom SA is **just an identity** — it has no permissions by default. The permissions come from RBAC bindings.

## 4. The SA Token (the credential)

A SA's "token" is a **JWT** (JSON Web Token) signed by the apiserver. The token's claims:

* `iss` (issuer) — the apiserver's `--service-account-issuer` URL.
* `sub` (subject) — `system:serviceaccount:<namespace>:<sa-name>`.
* `aud` (audience) — the apiserver's `--api-audiences` (default `kubernetes`).
* `exp` (expiry) — the token's expiration.
* `iat` (issued at) — when the token was issued.
* Other custom claims (e.g. bound token extensions).

A Pod reads the token from `/var/run/secrets/kubernetes.io/serviceaccount/token` and uses it in the `Authorization: Bearer *** header.

The apiserver verifies the token:

1. Validates the signature against `--service-account-key-file` (the public key).
2. Checks the `iss` against `--service-account-issuer`.
3. Checks the `aud` against the request's audience.
4. Checks the `exp` is in the future.
5. If valid, the user is `system:serviceaccount:<ns>:<sa>`.

The token is the Pod's **only** built-in credential. The Pod can also have additional credentials (e.g. AWS IAM via IRSA), but those are **not** managed by the SA.

## 5. The Legacy Long-Lived Token (Deprecated)

*"https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/#manual-secret-management-for-serviceaccounts"*

Pre-k8s 1.21, the standard was a **long-lived Secret**:

```yaml
apiVersion: v1
kind: Secret
type: kubernetes.io/service-account-token
metadata:
  name: my-app-token
  annotations:
    kubernetes.io/service-account.name: my-app
data:
  token: <base64>
  ca.crt: <base64>
  namespace: <base64>
```

The token was **indefinite** (no `exp`). The Secret was mounted to the Pod.

This was a security footgun:

* A leaked token was **indefinitely usable** (until the Secret was manually deleted).
* No rotation.
* No audience binding.

K8s 1.21+ deprecated the auto-creation of these Secrets. In k8s 1.24+, the auto-creation was removed. **New clusters don't create them.** For old clusters, you can disable the legacy token creation with the apiserver's `--service-account-extend-token-expiration=false` and `--api-audiences` flags.

For new clusters, **use bound tokens** (the next section).

## 6. Bound ServiceAccount Tokens (the modern way)

*"https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/#bound-service-account-tokens"*

A **bound token** is a short-lived, audience-scoped JWT. It's **bound to a specific Pod** (the pod's UID is in the token's claims).

A Pod gets a bound token via a **projected volume**:

```yaml
apiVersion: v1
kind: Pod
metadata: { name: app }
spec:
  serviceAccountName: my-app
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
          audience: https://my-service.example.com
          expirationSeconds: 3600
```

The kubelet requests a bound token from the apiserver. The token is mounted to the Pod at `/var/run/secrets/kubernetes.io/serviceaccount/token`. The kubelet **rotates** the token before it expires.

### 6.1 The audience

The `audience` is the **recipient** of the token. The token is valid only for that recipient.

```yaml
serviceAccountToken:
  audience: https://vault.example.com
```

The Pod uses this token to authenticate to Vault. Vault validates the token's `aud` against its expected audience. If the token has `aud: vault` but Vault expects `aud: kubernetes`, Vault rejects it.

This is the **service-to-service auth** model. The audience is the security boundary.

### 6.2 The expiration

`expirationSeconds` is the token's lifetime. Default is 3600 (1 hour). The kubelet requests a new token before the current one expires.

A shorter `expirationSeconds` = more rotation = more requests to the apiserver, but a smaller window for a stolen token.

A longer `expirationSeconds` = less rotation, less load, but a longer window for a stolen token.

For most workloads, 3600 (1 hour) is the right balance.

### 6.3 The bound token's claim

The bound token has a custom claim:

```json
{
  "sub": "system:serviceaccount:default:my-app",
  "iss": "https://kubernetes.default.svc.cluster.local",
  "aud": ["https://vault.example.com"],
  "exp": 1234567890,
  "iat": 1234564290,
  "kubernetes.io": {
    "namespace": "default",
    "serviceaccount": {
      "name": "my-app",
      "uid": "..."
    },
    "pod": {
      "name": "app",
      "uid": "..."
    }
  }
}
```

The `kubernetes.io.pod.uid` makes the token **bound to the Pod**. A different Pod can't use the token (even with the same SA). The recipient can validate the bound via the apiserver's TokenReview API.

## 7. The Projected Token Mechanics

The projected volume sources are merged into a single directory:

```yaml
volumes:
- name: sa-token
  projected:
    sources:
    - serviceAccountToken:
        path: token
        audience: https://vault.example.com
        expirationSeconds: 3600
    - configMap:
        name: app-config
        items:
        - key: config.yaml
          path: config.yaml
    - secret:
        name: app-secrets
        items:
        - key: password
          path: password
```

The Pod sees:

```
/var/run/secrets/kubernetes.io/serviceaccount/
├── token           # the bound SA token
├── config.yaml     # from the ConfigMap
└── password        # from the Secret
```

All sources are projected into the same directory. The kubelet updates them atomically.

### 7.1 The default token projection

For Pods without an explicit projected volume, the kubelet auto-creates one with the bound token. The token's audience is the apiserver's `--api-audiences` (default `kubernetes`), and the path is `token`. This is the **backward-compatible** behavior.

If you want a different audience, you need an explicit projected volume. The auto-projected token has the apiserver's audience only.

## 8. The TokenRequest API

*"https://kubernetes.io/docs/reference/kubernetes-api/authentication-resources/token-request-v1/"*

The kubelet requests a bound token via the **TokenRequest API**:

```http
POST /api/v1/namespaces/default/serviceaccounts/my-app/token
{
  "apiVersion": "authentication.k8s.io/v1",
  "kind": "TokenRequest",
  "spec": {
    "audiences": ["https://vault.example.com"],
    "expirationSeconds": 3600,
    "boundObjectRef": {
      "kind": "Pod",
      "name": "app",
      "uid": "..."
    }
  }
}
```

The apiserver returns a token:

```json
{
  "apiVersion": "authentication.k8s.io/v1",
  "kind": "TokenRequest",
  "status": {
    "token": "eyJhbGc...",
    "expirationTimestamp": "2024-01-15T13:00:00Z"
  }
}
```

The token is a JWT. The kubelet stores it in the projected volume.

The `boundObjectRef` makes the token **bound to a specific object** (typically a Pod). The token is valid only when used in the context of that object.

The TokenRequest API is **also the way external services get tokens**. An external service can call this API to get a token for a specific SA. The `boundObjectRef` is optional (the external service is the object).

## 9. Audience and Expiry in Depth

### 9.1 The audience is the security boundary

The token's `aud` claim is **who can use it**. A token for Vault is rejected by Consul. A token for "kubernetes" (the apiserver) is rejected by Vault (unless Vault is configured to accept it).

For the **in-cluster apiserver** use case, the audience is `kubernetes` (or whatever `--api-audiences` is set to).

For **external service** use cases (Vault, Consul, etc.), the audience is the service's expected value.

### 9.2 The expiry is the rotation window

`expirationSeconds` is the token's lifetime. The kubelet requests a new one before expiry. The Pod sees a continuous valid token.

For **production**, 3600 (1 hour) is the default. For **high-security**, lower it (e.g. 600 = 10 min). For **low-security**, you can go higher, but bound tokens are still better than legacy.

### 9.3 The apiserver-side validation

The apiserver validates the token's `aud`:

* The request's URL is `https://apiserver:6443/...`.
* The apiserver's `--api-audiences` is `kubernetes`.
* The token's `aud` includes `kubernetes`.
* Match: the apiserver accepts.

If the token's `aud` doesn't include `kubernetes`, the apiserver rejects with 401.

## 10. Disabling Automount

By default, the kubelet **auto-mounts the SA token** to every Pod. For Pods that don't need it, this is wasted and a small attack surface.

Disable at the **Pod level**:

```yaml
spec:
  automountServiceAccountToken: false
  containers:
  - name: app
    image: myapp:1.0
```

Disable at the **SA level** (applies to all Pods that use this SA):

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: { name: my-app }
automountServiceAccountToken: false
```

**Pod-level overrides SA-level.** If the Pod says `automountServiceAccountToken: true` and the SA says `false`, the Pod wins.

For most apps that don't talk to the apiserver, set `automountServiceAccountToken: false` on the SA. **This is the standard hardening.**

## 11. The Pod's `serviceAccountName`

```yaml
spec:
  serviceAccountName: my-app    # use the my-app SA
  containers:
  - name: app
    image: myapp:1.0
```

If not set, the Pod uses the `default` SA. If the SA doesn't exist, the Pod is rejected (admission error).

A Pod can only use **one** SA. For multi-Pod designs (e.g. an app + a sidecar that needs different permissions), the standard pattern is:

* The app + sidecar in the same Pod, using the same SA.
* The sidecar's permissions come from the SA's RBAC.

If the sidecar needs different permissions, use **two SAs** and two Pods, or use **init containers** for the privileged work.

## 12. ServiceAccount and Image Pull Secrets

A SA can carry `imagePullSecrets`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: { name: my-app }
imagePullSecrets:
- name: my-registry-creds
```

The Pod's effective `imagePullSecrets` = Pod's `imagePullSecrets` + SA's `imagePullSecrets`. The merge is **additive** (both lists are used).

For private registries, the standard is to put the credentials in the SA, not the Pod. This way, **all Pods using the SA can pull the image** without each Pod specifying the secret.

For ECR, the standard is **IRSA** (pod identity), not a SA's imagePullSecrets. For GKE, Workload Identity. For AKS, Pod Identity.

## 13. RBAC for ServiceAccounts

A SA is just an identity. **It has no permissions by default.** To give it permissions, create a Role / ClusterRole + binding:

```yaml
# Role: read pods in default
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: default
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
# RoleBinding: bind to my-app SA in default
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: my-app-pod-reader
  namespace: default
subjects:
- kind: ServiceAccount
  name: my-app
  namespace: default
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

The SA can now read pods in `default`. **It cannot read in any other namespace** (Role is namespaced). To grant cluster-wide access, use ClusterRole + ClusterRoleBinding.

For a **cross-namespace binding** (a SA in one namespace, bound to a Role in another):

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ci-deploy
  namespace: prod            # the namespace being granted access
subjects:
- kind: ServiceAccount
  name: ci
  namespace: ci              # the SA's namespace
roleRef:
  kind: Role
  name: deploy
  apiGroup: rbac.authorization.k8s.io
```

The `ci` SA in `ci` namespace can deploy in `prod` namespace. **The binding's namespace determines where the permissions apply; the subject's namespace determines the SA.**

## 14. IRSA and Pod Identity (Cloud-Native)

For AWS, GCP, Azure, the SA can be **linked to a cloud IAM identity**. This is the **secret-zero** solution: no Secret holds the cloud credential; the pod's SA is the credential.

### 14.1 IRSA (AWS)

*"https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html"*

IRSA links a k8s SA to an AWS IAM role:

1. Create an IAM role with a trust policy that allows the SA's OIDC identity to assume it.
2. Annotate the SA: `eks.amazonaws.com/role-arn: arn:aws:iam::123:role/my-role`.
3. The Pod uses the AWS SDK, which automatically uses the SA's projected token to assume the IAM role.

The Pod's process gets **temporary AWS credentials** for the IAM role. No static Secret.

### 14.2 GKE Workload Identity

*"https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity"*

GKE Workload Identity links a k8s SA to a Google Cloud Service Account:

1. Bind the k8s SA to a Google SA: `gcloud iam service-accounts add-iam-policy-binding ...`.
2. Annotate the k8s SA: `iam.gke.io/gcp-service-account: my-gsa@project.iam.gserviceaccount.com`.
3. The Pod's process gets the Google SA's identity.

### 14.3 AKS Pod Identity / Workload Identity

*"https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview"*

Similar pattern. The k8s SA is linked to an Azure Managed Identity, which has Azure RBAC permissions.

The pattern is the same across clouds: **the SA is the bridge between k8s and cloud IAM**. The pod's identity is the SA's identity (extended).

## 15. The SA User Identity

When a SA authenticates, the apiserver's `UserInfo` is:

```go
Username: "system:serviceaccount:<namespace>:<sa-name>"
Groups: ["system:serviceaccounts", "system:authenticated", "system:serviceaccounts:<namespace>"]
```

The username is **standardized**. RBAC bindings match on this. The `system:serviceaccounts` and `system:serviceaccounts:<namespace>` groups are for broader matches (e.g. "all SAs in the prod namespace can read this config").

The `Extra` field has the SA's UID, the namespace, etc. (for bound tokens).

## 16. The ServiceAccount Signing Key

The apiserver signs SA tokens with a **private key** (`--service-account-signing-key-file`, default `/etc/kubernetes/pki/sa.key`). The **public key** (`--service-account-key-file`, default `/etc/kubernetes/pki/sa.pub`) is for verifiers.

The keypair is generated by `kubeadm init` (or the cluster's bootstrap). It's a **separate keypair from the cluster CA**. The SA keys are not for X.509; they're for JWTs.

### 16.1 Rotation

To rotate the SA signing key:

1. Generate a new keypair.
2. Add the **new public key** to `--service-account-key-file` (the verifiers' file). Multiple keys can be in this file (verifiers try each).
3. Update `--service-account-signing-key-file` to the **new private key**.
4. Restart the apiserver.

After rotation:

* New tokens are signed with the new key.
* Old tokens are still verifiable (the old public key is still in `--service-account-key-file`).
* Old tokens expire naturally (their lifetime is short, ~1h).
* The old private key can be deleted after all old tokens have expired.

The rotation is **transparent** to consumers. The verifiers (the apiserver itself, external services) try each public key in the list.

## 17. The OIDC Discovery Endpoint

*"https://kubernetes.io/docs/reference/access-authn-authz/authentication/#service-account-token-volume-projection"*

The apiserver publishes an OIDC discovery endpoint:

```
https://<apiserver>/.well-known/openid-configuration
```

This returns:

```json
{
  "issuer": "https://kubernetes.default.svc.cluster.local",
  "jwks_uri": "https://<apiserver>/openid/v1/jwks",
  "authorization_endpoint": "...",
  "response_types_supported": ["id_token"],
  "subject_types_supported": ["public"],
  "id_token_signing_alg_values_supported": ["RS256"]
}
```

The `jwks_uri` returns the JWKS (the public keys). External services fetch this to verify bound tokens.

The `--service-account-issuer` is the `issuer` URL. The apiserver publishes the OIDC doc at `/.well-known/openid-configuration` and the JWKS at `/openid/v1/jwks`.

For **external service verification** (Vault, etc.), the service is configured with the OIDC issuer URL. The service fetches the discovery doc, the JWKS, and verifies the token.

## 18. Common Patterns

### 18.1 "I want the app to read its own ConfigMap"

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: { name: app, namespace: default }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: app-reader, namespace: default }
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  resourceNames: ["app-config"]    # only this ConfigMap
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

The `resourceNames` field is the trick — the Role is limited to one specific ConfigMap.

### 18.2 "I want the CI to deploy to a specific namespace"

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: { name: ci, namespace: ci }
automountServiceAccountToken: false    # CI doesn't need an in-cluster token
---
apiVersion: v1
kind: Secret
metadata:
  name: ci-token
  namespace: ci
  annotations:
    kubernetes.io/service-account.name: ci
type: kubernetes.io/service-account-token
# for CI systems that don't use bound tokens (e.g. older GitLab)
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
  namespace: ci
roleRef:
  kind: Role
  name: ci-deploy
  apiGroup: rbac.authorization.k8s.io
```

CI's SA in `ci` namespace can deploy in `prod` namespace. **The long-lived Secret is for the CI runner** (which runs outside the cluster). For in-cluster CI (e.g. GitLab Runner in-cluster), use bound tokens.

### 18.3 "Disable automount for an app that doesn't talk to the apiserver"

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: { name: no-apiserver-app }
automountServiceAccountToken: false
```

Every Pod using this SA has no SA token mounted. **No apiserver access** (the Pod can't talk to the apiserver even if it tried).

For **most apps that don't talk to the apiserver** (web servers, batch jobs, etc.), this is the right setup.

## 19. Operations and Debugging

### 19.1 Common commands

```bash
# list SAs
kubectl get sa -A

# describe
kubectl describe sa my-app -n default

# see the SA's RBAC bindings
kubectl get rolebindings -A -o json | jq '.items[] | select(.subjects[]?.name == "my-app")'
kubectl get clusterrolebindings -o json | jq '.items[] | select(.subjects[]?.name == "my-app")'

# check a Pod's SA
kubectl get pod <pod> -o jsonpath='{.spec.serviceAccountName}'

# check the SA token (inside the Pod)
kubectl exec <pod> -- cat /var/run/secrets/kubernetes.io/serviceaccount/token
kubectl exec <pod> -- cat /var/run/secrets/kubernetes.io/serviceaccount/namespace
kubectl exec <pod> -- cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt

# test the SA's permissions
kubectl auth can-i list pods --as=system:serviceaccount:default:my-app -n default
```

### 19.2 The "Pod can't talk to the apiserver" case

The Pod is running but the app can't reach the apiserver.

```bash
# 1. Does the Pod have a token mounted?
kubectl exec <pod> -- ls /var/run/secrets/kubernetes.io/serviceaccount/
# should show: ca.crt, namespace, token

# 2. Is the SA correct?
kubectl get pod <pod> -o jsonpath='{.spec.serviceAccountName}'

# 3. Is the SA's automount enabled?
kubectl get sa <sa> -n <ns> -o jsonpath='{.automountServiceAccountToken}'

# 4. Is the token valid?
kubectl exec <pod> -- cat /var/run/secrets/kubernetes.io/serviceaccount/token
# decode the JWT
# check the iss, aud, exp claims

# 5. Does the SA have RBAC?
kubectl auth can-i list pods --as=system:serviceaccount:<ns>:<sa> -n <ns>
```

### 19.3 The "Pod is rejected at admission (SA doesn't exist)" case

A Pod is rejected because the SA doesn't exist in the namespace.

```bash
# 1. What SA does the Pod request?
kubectl get pod <pod> -o jsonpath='{.spec.serviceAccountName}'

# 2. Does the SA exist?
kubectl get sa -n <ns>
# if not, the Pod is rejected

# 3. Create the SA
kubectl create sa <sa-name> -n <ns>
```

## 20. Gotchas and Common Mistakes

### 20.1 The 30+ common mistakes

1. **The `default` SA is auto-mounted to every Pod.** Disable it if the Pod doesn't talk to the apiserver.

2. **The `default` SA has no RBAC bindings by default.** In most clusters, it's intentionally empty. Don't add bindings to it (every Pod in the namespace inherits them).

3. **Legacy long-lived SA tokens are deprecated.** Use bound tokens (projected volumes).

4. **The SA token's audience is the security boundary.** A token for Vault is rejected by Consul.

5. **The SA token is a JWT, not an X.509 cert.** They're different credentials.

6. **The SA token is signed by the apiserver's SA signing key.** Different from the cluster CA.

7. **The bound token's `expirationSeconds` is the rotation window.** A stolen token is valid for at most `expirationSeconds` (until the next rotation).

8. **A bound token is bound to a specific Pod.** A different Pod can't use it (the `kubernetes.io.pod.uid` claim is different).

9. **The `--service-account-issuer` is the `iss` claim.** Consumers verify this against the apiserver's OIDC discovery doc.

10. **The TokenRequest API is how kubelets and external services get tokens.** Use it for both.

11. **The `imagePullSecrets` in a SA are merged with the Pod's `imagePullSecrets`.** Both lists are used.

12. **A Pod can only have one `serviceAccountName`.** For multi-Pod designs, all containers share the SA.

13. **A SA in one namespace can be a subject in a binding in another namespace.** The binding's namespace is where the permissions apply.

14. **`automountServiceAccountToken: false` at the Pod level overrides the SA level.** If the Pod says true and the SA says false, the Pod wins.

15. **The `automountServiceAccountToken: false` is the standard hardening.** Most apps don't need the token.

16. **The bound token is mounted as a file, not env var.** The file is updated atomically (kubelet uses a symlink + file replace).

17. **A bound token's expiry is 1h by default.** Configurable via `expirationSeconds`.

18. **The kubelet's rotation interval is shorter than `expirationSeconds`.** Default is 50% of the lifetime. The Pod always has a valid token.

19. **The `system:serviceaccounts` group includes all SAs cluster-wide.** Don't grant it broad permissions.

20. **The `system:serviceaccounts:<ns>` group includes all SAs in a namespace.** Useful for "all SAs in this ns can read this config".

21. **The default SA's automount is the same as a custom SA's automount (default true).** Set `automountServiceAccountToken: false` for both if not needed.

22. **The `--api-audiences` flag (k8s 1.24+) is the audience of in-cluster tokens.** Default is `kubernetes`. External services need their own audience.

23. **A SA's `secrets` field is legacy.** With bound tokens, the apiserver doesn't create a Secret.

24. **The `kubernetes.io/service-account-token` Secret type is legacy.** New SAs don't create it automatically.

25. **The OIDC discovery endpoint is at `/.well-known/openid-configuration` on the apiserver.** Consumers fetch this to verify bound tokens.

26. **The JWKS endpoint is at `/openid/v1/jwks`.** The public keys are here.

27. **The apiserver can serve multiple `--service-account-issuer` URLs.** Tokens for different audiences are signed separately.

28. **The SA signing key is not a CA.** It signs JWTs, not certs.

29. **A SA's `secrets` field with `kubernetes.io/service-account-token` type is the legacy pattern.** Use the projected volume instead.

30. **The `--service-account-extend-token-expiration` flag (deprecated) was for legacy tokens.** Removed in 1.24+.

## See also

* [[Kubernetes/concepts/L07-security/01-authentication-authorization|AuthN/AuthZ]] — the bigger picture
* [[Kubernetes/concepts/L07-security/03-rbac|RBAC]] — what the SA can do
* [[Kubernetes/concepts/L07-security/14-secret-encryption|Secret Encryption]] — encrypting the SA's data
* [[Kubernetes/concepts/L07-security/20-cluster-hardening|Cluster Hardening]] — the apiserver flags
* [[Kubernetes/eks/security/iam-roles-for-sa|IRSA]] — AWS-specific
