# Certificates

*"https://kubernetes.io/docs/setup/best-practices/certificates/"*

Every TLS-protected connection in a k8s cluster is backed by an X.509 certificate. The cluster is a **PKI (Public Key Infrastructure)** with one or more CAs, multiple intermediate CAs, and dozens of leaf certs — apiserver, etcd, kubelet, controller-manager, scheduler, ServiceAccount tokens, webhook servers, ingresses. This note walks the **full cluster PKI**: what's signed, by which CA, with what lifetime, and how to debug it.

### Table of Contents

1. [The Cluster PKI at a Glance](#1-the-cluster-pki-at-a-glance)
2. [The CAs](#2-the-cas)
3. [The Control Plane Certs](#3-the-control-plane-certs)
4. [The kubelet Certs](#4-the-kubelet-certs)
5. [The Front-Proxy CA](#5-the-front-proxy-ca)
6. [The ServiceAccount Signing Key](#6-the-serviceaccount-signing-key)
7. [The kube-apiserver's `--client-ca-file`](#7-the-kube-apiservers---client-ca-file)
8. [The kube-apiserver's `--tls-cert-file`](#8-the-kube-apiservers---tls-cert-file)
9. [The kube-apiserver's `--requestheader-client-ca-file`](#9-the-kube-apiservers---requestheader-client-ca-file)
10. [Cert Lifetimes and Rotation](#10-cert-lifetimes-and-rotation)
11. [The kubelet's Cert Rotation](#11-the-kubelets-cert-rotation)
12. [External PKI (custom CA)](#12-external-pki-custom-ca)
13. [CSI Driver and Webhook Certs](#13-csi-driver-and-webhook-certs)
14. [Ingress and Service Certs](#14-ingress-and-service-certs)
15. [Cert Files on Disk](#15-cert-files-on-disk)
16. [The OpenSSL Debug Toolkit](#16-the-openssl-debug-toolkit)
17. [Common Cert Errors and Fixes](#17-common-cert-errors-and-fixes)
18. [Operations and Debugging](#18-operations-and-debugging)
19. [Gotchas and Common Mistakes](#19-gotchas-and-common-mistakes)

---

## 1. The Cluster PKI at a Glance

A standard k8s cluster has **3 CAs and ~15-20 leaf certs** (more with HA, more with webhooks).

```
            ┌────────────────────────────────┐
            │      Cluster CA                │
            │   (signs most certs)           │
            └─────────────┬──────────────────┘
                          │
                          ├─ kube-apiserver server cert
                          ├─ kube-apiserver etcd client cert
                          ├─ kube-apiserver kubelet client cert
                          ├─ etcd server cert
                          ├─ etcd peer cert
                          ├─ etcd apiserver client cert
                          ├─ kubelet server cert (one per node)
                          ├─ kubelet client cert (one per node)
                          ├─ kube-scheduler client cert
                          ├─ kube-controller-manager client cert
                          ├─ kube-proxy client cert
                          ├─ cloud-controller-manager client cert
                          ├─ admin client cert (for kubectl)
                          └─ admission webhook certs

            ┌────────────────────────────────┐
            │     Front-Proxy CA             │
            │  (for API aggregation)         │
            └─────────────┬──────────────────┘
                          │
                          ├─ front-proxy-client cert (apiserver)
                          └─ extension-apiserver certs

            ┌────────────────────────────────┐
            │   ServiceAccount signing key   │
            │   (signs SA JWTs)              │
            └────────────────────────────────┘
```

The `cluster CA` signs most of the certs. The `front-proxy CA` is for API aggregation (extension apiservers). The `SA signing key` is not a CA — it signs JWTs.

The **PKI tree** is built by `kubeadm` on `kubeadm init`, with certs in `/etc/kubernetes/pki/`.

## 2. The CAs

### 2.1 The Cluster CA

The **cluster CA** is the root of trust for most k8s components. Its cert is in `/etc/kubernetes/pki/ca.crt` (and its key in `ca.key`, only on the first control plane node).

The cluster CA signs:

* All control plane component certs.
* All kubelet certs.
* All client certs (for `kubectl`, controllers, etc.).

For HA, the CA's key is **only on the first control plane node**. Subsequent control plane nodes have the cert but not the key. Certs are signed on the first node, distributed to others.

### 2.2 The Front-Proxy CA

The **front-proxy CA** is for **API aggregation** — when extension apiservers (like metrics-server, cluster-autoscaler) are served via the apiserver's `/apis/...` path. The apiserver acts as a front proxy.

The front-proxy CA signs:

* The apiserver's front-proxy-client cert.
* Extension apiservers' certs (e.g. metrics-server's).

The front-proxy CA is separate from the cluster CA. They have different trust chains.

### 2.3 The ServiceAccount Signing Key

The **SA signing key** is a **private key, not a CA**. The apiserver uses it to **sign** SA JWTs (bound tokens, k8s 1.21+).

The key is in `/etc/kubernetes/pki/sa.key` (private, only on control plane nodes). The public key (`sa.pub`) is also distributed — it's the **verification key** for SA tokens.

The SA signing key is **rotated separately** from the cluster CA. Rotation is via the `--service-account-key-file` and `--service-account-signing-key-file` apiserver flags.

### 2.4 The CSI / Webhook CAs

Some components have their own CAs:

* **CSI driver** — the csi-sock has its own cert. CSI drivers (e.g. EBS, GCE PD) have their own CA hierarchy.
* **Admission webhooks** — each webhook has its own cert. The apiserver has the CA bundle in the `ValidatingWebhookConfiguration` / `MutatingWebhookConfiguration`.

These are **application-level CAs**, not part of the cluster PKI. The cluster PKI signs the components; the application CAs sign the application-level integrations.

## 3. The Control Plane Certs

### 3.1 kube-apiserver certs

The apiserver has **multiple certs**:

* **`apiserver.crt`** — the serving cert for `:6443`. Signed by the cluster CA. SAN includes `kubernetes`, `kubernetes.default`, `kubernetes.default.svc`, `kubernetes.default.svc.cluster.local`, and the apiserver's IPs / DNS names.
* **`apiserver-etcd-client.crt`** — client cert for talking to etcd. Signed by the cluster CA.
* **`apiserver-kubelet-client.crt`** — client cert for talking to kubelets. Signed by the cluster CA.
* **`apiserver-front-proxy-client.crt`** — client cert for API aggregation. Signed by the front-proxy CA.

The serving cert's **SANs** are critical. The apiserver is reached by multiple names:

* `kubernetes` (the in-cluster Service IP's name)
* `kubernetes.default`, `kubernetes.default.svc`, `kubernetes.default.svc.cluster.local`
* The apiserver's IP addresses
* The DNS names (e.g. `ip-10-0-0-1.ec2.internal`)

A client connecting to `https://kubernetes.default.svc:6443` validates the SAN. If the SAN doesn't include `kubernetes.default.svc`, the connection fails.

### 3.2 etcd certs

etcd has:

* **`etcd-server.crt`** — the serving cert for `:2379`. Signed by the cluster CA. SAN includes the etcd member's DNS / IP.
* **`etcd-peer.crt`** — the peer cert for `:2380`. Signed by the cluster CA. SAN includes the member's DNS / IP.
* **`apiserver-etcd-client.crt`** — the apiserver's client cert (from the apiserver's side).

The etcd members form a **cluster** using the peer certs. The apiserver connects using the apiserver's client cert.

### 3.3 kube-controller-manager and kube-scheduler certs

Both have a single client cert:

* **`controller-manager.crt`** — for talking to the apiserver.
* **`scheduler.crt`** — for talking to the apiserver.

These are client certs (no serving role). They identify the component to the apiserver.

## 4. The kubelet Certs

Each kubelet has:

* **`kubelet.crt`** — the serving cert for `:10250`. Signed by the cluster CA (or rotated via CSR, see section 11).
* **`kubelet-client.crt`** — the client cert for talking to the apiserver.

The serving cert's **SAN** includes the node's DNS / IP. The client cert identifies the kubelet to the apiserver (via the `system:nodes` group, by convention).

In HA, each node's kubelet certs are unique to that node. They include the node's hostname in the SAN.

## 5. The Front-Proxy CA

Used for **API aggregation** — when an extension apiserver (e.g. metrics-server) is served via the main apiserver.

```
client → apiserver (/apis/metrics.k8s.io/v1beta1/...)
              ↓ (apiserver is a "front proxy" for the extension apiserver)
              ↓ uses apiserver-front-proxy-client.crt
              ↓
   extension-apiserver (e.g. metrics-server)
              ↑ (verifies apiserver's cert against the front-proxy CA)
              ↑ uses extension-apiserver.crt (signed by front-proxy CA)
```

The front-proxy CA's cert is mounted in the extension apiserver's trust store. The apiserver's front-proxy-client cert is verified against this CA.

## 6. The ServiceAccount Signing Key

*"https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#service-account-token-volume-projection"*

The apiserver uses the **SA signing key** to sign SA JWTs. The key is in:

* `/etc/kubernetes/pki/sa.key` — the **private** key. Only on control plane nodes.
* `/etc/kubernetes/pki/sa.pub` — the **public** key. Distributed to consumers (e.g. the apiserver, API aggregators).

The apiserver signs SA tokens with `sa.key`. Consumers verify with `sa.pub`.

For **bound tokens** (k8s 1.21+), the signing is part of the **OIDC discovery** flow:

* The apiserver publishes an OIDC discovery doc at `https://<apiserver>/.well-known/openid-configuration`.
* The JWKS endpoint is at `https://<apiserver>/openid/v1/jwks`.
* The `sa.pub` is the key in the JWKS.

A consumer (Vault, an external service) verifies the token by:

1. Fetching the OIDC discovery doc.
2. Fetching the JWKS.
3. Verifying the token's signature against the JWKS.

The SA signing key is **rotated separately** from the cluster CA. To rotate:

1. Generate a new key.
2. Update `--service-account-key-file` (the public key, for verifiers).
3. Update `--service-account-signing-key-file` (the private key, for signing).
4. Restart the apiserver.

After rotation, the apiserver signs new tokens with the new key. Old tokens (signed with the old key) are still valid (their lifetime is short, ~1h), and the apiserver publishes both keys in the JWKS.

## 7. The kube-apiserver's `--client-ca-file`

The **`--client-ca-file`** is the CA that signs **client certs** for X.509 auth. When a client presents a client cert, the apiserver validates it against this CA.

```
--client-ca-file=/etc/kubernetes/pki/ca.crt
```

This is the **cluster CA**. The apiserver trusts client certs signed by this CA.

The authn flow:

```
client → apiserver (with client cert)
              ↓
        apiserver validates the cert's chain against --client-ca-file
              ↓
        if valid, the client is identified by the cert's CN
              ↓
        CN = "kubernetes-admin" → user "kubernetes-admin"
        CN = "system:node:<node>" → user "system:node:<node>" (kubelet)
```

The CN becomes the user. The Organization (O) becomes the group. RBAC matches on these.

## 8. The kube-apiserver's `--tls-cert-file`

The **`--tls-cert-file`** is the apiserver's **serving cert**. Combined with `--tls-private-key-file`:

```
--tls-cert-file=/etc/kubernetes/pki/apiserver.crt
--tls-private-key-file=/etc/kubernetes/pki/apiserver.key
```

The cert is a **leaf cert** signed by the cluster CA. The SAN includes the apiserver's DNS / IP names.

Clients (kubectl, kubelets, controllers) trust the cert because they have the cluster CA in their trust store:

* **`/var/run/secrets/kubernetes.io/serviceaccount/ca.crt`** — for in-cluster clients.
* **`~/.kube/config`** — for `kubectl` (the `certificate-authority-data` field).

The TLS handshake:

```
client → apiserver (TLS ClientHello)
              ↓
        apiserver presents apiserver.crt
              ↓
        client validates the chain against ca.crt
              ↓
        if valid, the client trusts the apiserver
              ↓
        encrypted session established
```

## 9. The kube-apiserver's `--requestheader-client-ca-file`

The **`--requestheader-client-ca-file`** is the CA for the **front proxy** (API aggregation). The apiserver, when acting as a front proxy, uses its **front-proxy-client cert** to authenticate to the extension apiserver.

```
--requestheader-client-ca-file=/etc/kubernetes/pki/front-proxy-ca.crt
```

The extension apiserver has this CA in its trust store. When the apiserver (as front proxy) presents its front-proxy-client.crt, the extension apiserver validates against the front-proxy CA.

If `--requestheader-client-ca-file` is misconfigured:

* API aggregation fails.
* Extension apiservers (metrics-server, etc.) don't work.

The flag is distinct from `--client-ca-file`. They have different trust chains.

## 10. Cert Lifetimes and Rotation

### 10.1 The defaults

`kubeadm` sets:

* **CA certs** — 10 years.
* **Leaf certs (apiserver, etcd, kubelet)** — 1 year.
* **SA signing key** — long-lived (rotated manually).

A 1-year leaf cert is **rotated automatically** by `kubeadm` 30 days before expiry (configurable via `--feature-gates=RotateKubeletServerCertificate=true` and the `--rotate-certificates` flag on the kubelet).

### 10.2 The rotation flow

For a control plane cert:

1. The cert is about to expire (within 30 days).
2. `kubeadm certs check-expiration` reports it.
3. `kubeadm certs renew all` rotates:
   * Generates a new cert with the same SAN, same key size.
   * Writes the new cert/key to `/etc/kubernetes/pki/`.
   * Updates the static pod manifest (for control plane components).
4. The kubelet sees the new manifest and restarts the apiserver.
5. The new cert is in use.

For **kubelet certs** (rotated automatically):

1. The kubelet's serving cert is about to expire.
2. The kubelet generates a new key and CSR.
3. The kubelet submits the CSR to the apiserver.
4. The apiserver's `csr-approver` controller approves it.
5. The kubelet gets the new cert.

This is automatic if `rotateCertificates: true` and the apiserver has the `RotateKubeletServerCertificate` feature gate enabled.

### 10.3 Manual rotation

For a manual rotation (e.g. for a custom CA):

```bash
# generate a new cert
openssl genrsa -out new.key 2048
openssl req -new -key new.key -out new.csr -subj "/CN=..."
openssl x509 -req -in new.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out new.crt -days 365

# replace the old cert
cp new.crt /etc/kubernetes/pki/
systemctl restart kubelet
# or restart the control plane component
```

For zero-downtime rotation, ensure the new cert's SAN matches the old.

## 11. The kubelet's Cert Rotation

The kubelet can **auto-rotate** its serving cert. With:

```yaml
# /var/lib/kubelet/config.yaml
rotateCertificates: true
serverTLSBootstrap: true
```

The kubelet:

1. On startup, checks if it has a valid serving cert.
2. If not, generates a CSR and submits it to the apiserver.
3. The apiserver's `csr-approver` controller approves it.
4. The kubelet stores the new cert in `/var/lib/kubelet/pki/kubelet-server-<timestamp>.crt`.
5. The kubelet uses the new cert for `:10250`.
6. Before expiry, the kubelet repeats the process.

The certs are valid for **90 days** (default for kubelet-serving certs signed by the apiserver). Rotation is **transparent**.

The `csr-approver` controller is in `kube-controller-manager` and is enabled by default. For tighter control, you can disable it and use a custom controller.

## 12. External PKI (custom CA)

Some organizations use an **external CA** (e.g. HashiCorp Vault, cert-manager with an external issuer, a corporate CA). The workflow:

1. The external CA is the trust root.
2. `kubeadm` is run with `--discovery-token` (to skip the cert generation).
3. The certs are generated externally and provided to `kubeadm init`.
4. The external CA's cert is in the trust store.

For **kubeadm** with external PKI:

```bash
# generate the cluster CA
kubeadm init phase certs ca

# the certs are in /etc/kubernetes/pki/
# copy the ca.crt to all control plane nodes
# copy the leaf certs to the relevant components
```

For **Vault**:

* Vault is the CA.
* Vault issues certs to the cluster components.
* The certs are short-lived (e.g. 24h).
* The cert-manager-vault issuer issues them.

## 13. CSI Driver and Webhook Certs

### 13.1 CSI driver certs

CSI drivers have their own certs. The driver runs as a DaemonSet (typically), exposing a Unix socket for the kubelet to communicate with.

The driver has:

* A **server cert** (for the gRPC server over the Unix socket or a TCP port).
* A **client cert** (for the driver to call the apiserver, if needed).

The certs are typically **self-signed** and rotated by the CSI driver. The kubelet trusts the cert via the `csiDriver` registration.

For **TCP-listening CSI drivers**, the cert must be valid for the driver's DNS / IP. The kubelet validates it.

### 13.2 Admission webhook certs

*"https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/"*

Admission webhooks (OPA, Kyverno, Vault agent, etc.) have their own certs. The apiserver calls the webhook over HTTPS.

The webhook has:

* A **server cert** (for the webhook's HTTPS endpoint).
* A **CA bundle** in the webhook config (so the apiserver trusts the webhook).

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata: { name: my-policy }
webhooks:
- name: validate.example.com
  clientConfig:
    service:
      name: my-webhook
      namespace: my-ns
      path: /validate
    caBundle: <base64-encoded CA cert>
```

The `caBundle` is the CA that signed the webhook's serving cert. The apiserver uses it to validate the TLS handshake.

The certs are typically managed by **cert-manager** (which can issue certs from Let's Encrypt, Vault, the cluster CA, etc.).

## 14. Ingress and Service Certs

Ingresses need **TLS certs** for HTTPS. The cert is stored in a Secret and referenced by the Ingress.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: my-ingress }
spec:
  tls:
  - hosts:
    - my-app.example.com
    secretName: my-app-tls   # the Secret with the cert
  rules:
  - host: my-app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port: { number: 80 }
```

The Secret has:

```yaml
apiVersion: v1
kind: Secret
metadata: { name: my-app-tls }
type: kubernetes.io/tls
data:
  tls.crt: <base64>
  tls.key: <base64>
```

The cert is for the public hostname (`my-app.example.com`). It's signed by a **public CA** (Let's Encrypt, DigiCert, etc.) or a private CA.

For automation: **cert-manager** (with Let's Encrypt or another ACME provider).

## 15. Cert Files on Disk

A `kubeadm`-built cluster has the following files in `/etc/kubernetes/pki/`:

```
/etc/kubernetes/pki/
├── ca.crt                      # cluster CA cert
├── ca.key                      # cluster CA key (first node only)
├── sa.pub                      # SA public key (verifier)
├── sa.key                      # SA private key (signer)
├── front-proxy-ca.crt          # front-proxy CA cert
├── front-proxy-ca.key          # front-proxy CA key (first node only)
├── apiserver.crt               # apiserver serving cert
├── apiserver.key               # apiserver key
├── apiserver-etcd-client.crt   # apiserver's etcd client cert
├── apiserver-etcd-client.key
├── apiserver-kubelet-client.crt   # apiserver's kubelet client cert
├── apiserver-kubelet-client.key
├── apiserver-front-proxy-client.crt   # apiserver's front-proxy client cert
├── apiserver-front-proxy-client.key
├── etcd/
│   ├── ca.crt                  # etcd's CA (often the same as cluster CA)
│   ├── ca.key
│   ├── server.crt              # etcd's serving cert
│   ├── server.key
│   ├── peer.crt                # etcd's peer cert
│   └── peer.key
└── (no kubelet certs — those are on the worker nodes)
```

The worker node has:

```
/var/lib/kubelet/
├── pki/
│   ├── kubelet.crt             # kubelet's serving cert
│   ├── kubelet.key
│   ├── kubelet-client.crt      # kubelet's client cert
│   └── kubelet-client.key
└── (config.yaml is also here)
```

## 16. The OpenSSL Debug Toolkit

OpenSSL is the standard CLI for cert inspection. Useful commands:

```bash
# inspect a cert
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout

# check a cert's expiry
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -dates
# notBefore=Jan 15 00:00:00 2024 GMT
# notAfter=Jan 15 00:00:00 2025 GMT

# check a cert's SAN
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -ext subjectAltName

# check a cert's issuer
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -issuer

# test a TLS connection
openssl s_client -connect apiserver:6443 -showcerts

# test a TLS connection with a specific SNI
openssl s_client -connect apiserver:6443 -servername kubernetes.default.svc

# test a TLS connection with a specific CA
openssl s_client -connect apiserver:6443 -CAfile /etc/kubernetes/pki/ca.crt

# verify a cert chain
openssl verify -CAfile ca.crt apiserver.crt
```

## 17. Common Cert Errors and Fixes

### 17.1 `x509: certificate signed by unknown authority`

The cert's CA is not in the client's trust store.

**Fix**: add the CA to the trust store. For in-cluster clients, mount `ca.crt` to the Pod.

### 17.2 `x509: certificate is valid for X, not Y`

The cert's SAN doesn't match the hostname.

**Fix**: regenerate the cert with the correct SAN. For the apiserver, the SAN must include all reachable names.

### 17.3 `x509: certificate has expired or is not yet valid`

The cert is past its `notAfter` or before its `notBefore`.

**Fix**: rotate the cert. For kubelet, `kubeadm certs renew` or the kubelet's auto-rotation. For the apiserver, `kubeadm certs renew all`.

### 17.4 `tls: handshake failure`

The client and server don't share a TLS version or cipher.

**Fix**: check the apiserver's `--tls-min-version` and `--tls-cipher-suites`. Make sure the client supports them.

### 17.5 `connection refused`

Not a TLS error. The server isn't listening.

**Fix**: check the apiserver's status, the network, the port.

### 17.6 Time skew

If the client's clock is off, all certs look expired.

**Fix**: NTP / chrony on every node. Check `timedatectl status`.

## 18. Operations and Debugging

### 18.1 Common commands

```bash
# check what's about to expire
kubeadm certs check-expiration

# rotate all control plane certs
kubeadm certs renew all

# check a specific cert
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout

# check the kubelet's serving cert
echo | openssl s_client -connect <node>:10250 -servername <node> 2>/dev/null \
  | openssl x509 -noout -dates

# check the in-cluster CA
kubectl exec <pod> -- cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt | \
  openssl x509 -noout -subject -issuer

# check the apiserver's log for cert errors
kubectl -n kube-system logs kube-apiserver-<node> | grep -i "tls\|cert\|x509"
```

### 18.2 The "cert expired, kubelet is broken" case

```bash
# 1. Check what's expired
kubeadm certs check-expiration

# 2. Renew
kubeadm certs renew all

# 3. The control plane restarts (kubelet sees the new static pod manifest)

# 4. Verify
kubeadm certs check-expiration
```

### 18.3 The "Pod can't reach apiserver" case

```bash
# 1. Check the Pod's CA bundle
kubectl exec <pod> -- cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt

# 2. Check the apiserver's cert
openssl s_client -connect apiserver:6443 -servername kubernetes.default.svc

# 3. Check the Pod's clock
kubectl exec <pod> -- date
```

## 19. Gotchas and Common Mistakes

### 19.1 The 30+ common mistakes

1. **The cluster CA is on the first control plane node only.** The other control plane nodes have the cert but not the key. Don't try to sign new certs on non-first nodes.

2. **The `--client-ca-file` and `--tls-cert-file` are different files.** `--client-ca-file` is for verifying client certs (the trust anchor for X.509 auth). `--tls-cert-file` is the apiserver's own serving cert.

3. **The `--requestheader-client-ca-file` is the front-proxy CA.** Different from the cluster CA.

4. **The apiserver's serving cert SAN must include all reachable names.** `kubernetes`, `kubernetes.default`, `kubernetes.default.svc`, `kubernetes.default.svc.cluster.local`, the apiserver's IPs and DNS names.

5. **The kubelet's serving cert SAN must include the node's hostname.** Otherwise, clients connecting to `<node>:10250` get a cert mismatch.

6. **The kubeadm-generated certs expire in 1 year.** kubeadm auto-rotates 30 days before. For non-kubeadm clusters, you need to rotate manually.

7. **The kubelet's cert rotation requires `serverTLSBootstrap: true` and `rotateCertificates: true`.** Without them, the kubelet keeps a single cert.

8. **The `csr-approver` controller must be enabled for kubelet cert rotation.** It's in `kube-controller-manager` by default.

9. **The SA signing key is a key, not a CA.** It signs JWTs, not certs. Rotation is separate from the cluster CA.

10. **The OIDC discovery doc is at `/.well-known/openid-configuration`** on the apiserver. The JWKS is at `/openid/v1/jwks`. Consumers fetch these to verify bound tokens.

11. **The front-proxy CA is separate from the cluster CA.** API aggregation uses a different trust chain.

12. **The cluster CA is for the cluster, not for public-facing certs.** Public-facing (Ingress) certs are signed by Let's Encrypt, DigiCert, etc.

13. **The cluster CA's cert is in `/var/run/secrets/kubernetes.io/serviceaccount/ca.crt`** for in-cluster clients. The full chain (root + intermediates) is in this file.

14. **The kubelet's client cert is in `/var/lib/kubelet/pki/kubelet-client.crt`.** It identifies the kubelet to the apiserver (CN = `system:node:<node>`, O = `system:nodes`).

15. **The webhook's `caBundle` is required for Service-type webhooks.** Without it, the apiserver can't verify the webhook's cert.

16. **`caBundle` is base64-encoded.** YAML's multiline string. Some tools require explicit base64.

17. **A CSI driver with a TCP-listening gRPC server needs a valid cert.** The kubelet validates it.

18. **etcd's cert SANs are the etcd member's DNS / IP.** If etcd's hostname changes, the cert must be regenerated.

19. **HA etcd uses peer certs.** The members authenticate each other via the peer certs. Misconfigured peer certs = cluster split.

20. **The apiserver-front-proxy-client cert is for the apiserver when it's a front proxy.** It authenticates the apiserver to the extension apiserver.

21. **The extension apiserver's cert is signed by the front-proxy CA.** Different trust chain from the cluster CA.

22. **The cluster CA's key should be backed up.** If lost, you can't issue new certs; you must rebuild the cluster.

23. **The SA signing key should also be backed up.** Lost = can't issue new SA tokens.

24. **A kubeconfig's `certificate-authority-data` is the cluster CA cert.** Base64-encoded. Decoding it shows the cert.

25. **A kubeconfig's `client-certificate-data` is the user's client cert.** Base64-encoded.

26. **A kubeconfig's `client-key-data` is the user's private key.** Base64-encoded. **Treat as a secret.**

27. **A `kubectl` user with a client-cert / client-key is "cluster-admin" by default.** Unless RBAC says otherwise. The CN of the cert becomes the user.

28. **The cluster CA cert is also in the kubeconfig.** So kubectl trusts the apiserver's cert.

29. **The `--service-account-issuer` flag sets the `iss` claim of bound tokens.** Consumers verify the `iss` to confirm the token is from this cluster.

30. **The `--api-audiences` flag (k8s 1.24+) sets the audiences that the apiserver will issue tokens for.** Default is the apiserver itself. Multiple audiences are comma-separated.

## See also

* [[Kubernetes/concepts/L07-security/08-tls-mtls|TLS / mTLS]] — the transport layer
* [[Kubernetes/concepts/L07-security/13-etcd-encryption|etcd Encryption]] — encrypting the data on disk
* [[Kubernetes/concepts/L07-security/20-cluster-hardening|Cluster Hardening]] — apiserver flags
* [[Kubernetes/concepts/L07-security/21-node-hardening|Node Hardening]] — kubelet config
* [[Kubernetes/concepts/L01-architecture/04-control-plane|Control Plane]] — the components
