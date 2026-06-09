# TLS and mTLS in Kubernetes

*"https://kubernetes.io/docs/tasks/tls/managing-tls-in-a-cluster/"*

TLS (Transport Layer Security) is what makes "HTTPS" work — it encrypts the bytes on the wire, verifies the server's identity, and (optionally) verifies the client's identity. **mTLS (mutual TLS)** is TLS where **both** sides verify each other. Kubernetes uses TLS everywhere by default — apiserver↔etcd, apiserver↔kubelet, kubelet↔apiserver, ingress↔client, pod-to-pod in service meshes. This note covers the concepts: how TLS works in the cluster, what mTLS adds, and how to operate it.

### Table of Contents

1. [TLS Recap (the handshake)](#1-tls-recap-the-handshake)
2. [The Certificate Authority Model](#2-the-certificate-authority-model)
3. [mTLS: Client Authentication](#3-mtls-client-authentication)
4. [Where k8s Uses TLS](#4-where-k8s-uses-tls)
5. [The Cluster's CA Bundle](#5-the-clusters-ca-bundle)
6. [Certificate Rotation](#6-certificate-rotation)
7. [In-Cluster mTLS (Service Mesh)](#7-in-cluster-mtls-service-mesh)
8. [mTLS Without a Service Mesh](#8-mtls-without-a-service-mesh)
9. [TLS Versions and Cipher Suites](#9-tls-versions-and-cipher-suites)
10. [The cert-manager Tool](#10-the-cert-manager-tool)
11. [Troubleshooting TLS](#11-troubleshooting-tls)
12. [Operations and Debugging](#12-operations-and-debugging)
13. [Gotchas and Common Mistakes](#13-gotchas-and-common-mistakes)

---

## 1. TLS Recap (the handshake)

Every TLS connection starts with a **handshake** — a back-and-forth that establishes:

1. **TLS version** (TLS 1.2 or 1.3)
2. **Cipher suite** (the algorithm to use)
3. **The server's identity** (the server presents a certificate)
4. **(Optionally) the client's identity** (the client also presents a cert)
5. **A shared symmetric key** for the rest of the session

```
Client                                  Server
  │  ─── ClientHello ───────────────────►  │   (TLS version, ciphers, random)
  │                                       │
  │  ◄── ServerHello ─────────────────    │   (chosen version, cipher, random)
  │  ◄── ServerCertificate ──────────     │   (server's X.509 cert + chain)
  │  ◄── ServerKeyExchange ───────────    │   (for ECDHE, the DH params)
  │  ◄── ServerHelloDone ────────────     │
  │                                       │
  │  ─── ClientKeyExchange ─────────────► │   (pre-master secret, encrypted)
  │  ─── ChangeCipherSpec ──────────────► │
  │  ─── Finished ──────────────────────► │
  │                                       │
  │  ◄── ChangeCipherSpec ─────────────   │
  │  ◄── Finished ─────────────────────   │
  │                                       │
  │  ━━━ encrypted traffic ━━━━━━━━━━━━━  │
```

After the handshake, both sides have the same symmetric key. They use it (with AES-GCM or ChaCha20) for the rest of the session. The handshake itself is asymmetric (slow) but encrypts only a small amount of data; the bulk session is symmetric (fast).

### 1.1 The three checks a TLS client does

When the client connects to a server:

1. **Is the cert valid?** (Not expired, not revoked — checked via CRL or OCSP.)
2. **Is the cert signed by a trusted CA?** (The client has a list of trusted CAs.)
3. **Does the cert's `Subject Alternative Name` (SAN) match the hostname I'm connecting to?** (E.g. `kubernetes.default.svc` must be in the cert's SAN.)

If all three pass, TLS is established. If any fail, the connection is rejected (or a warning is shown for self-signed).

## 2. The Certificate Authority Model

TLS needs a way to verify that a certificate is **trusted**. The model:

* **Certificate Authority (CA)** — a trusted entity that signs certificates.
* **Root CA** — the top of the trust chain. Its certificate is in the client's trust store.
* **Intermediate CA** — signed by the root, can sign other certs.
* **Leaf certificate** — the actual server (or client) cert, signed by an intermediate.

The chain: leaf → intermediate → root. The client trusts the root, validates the chain to the root, and trusts the leaf.

```
Leaf cert (kube-apiserver server cert)
   │ signed by
   ▼
Intermediate CA (cluster CA, can sign)
   │ signed by
   ▼
Root CA (the cluster root, in the trust store)
```

A standard cluster has one CA for control plane (signs apiserver, etcd, kubelet certs) and often a separate one for service accounts.

### 2.1 The trust store

The client has a "trust store" — a set of CA certificates it trusts. When validating a server cert, the client walks the chain to a trusted CA.

In Linux, the system trust store is `/etc/ssl/certs/ca-certificates.crt` (Debian/Ubuntu) or `/etc/pki/tls/certs/ca-bundle.crt` (RHEL). Most tools (curl, wget, Go's `crypto/tls`, Python's `ssl`) use this.

For container images, the trust store is what the base image ships. `debian`, `alpine`, `ubuntu` ship with a reasonable set of public CAs (Let's Encrypt, DigiCert, etc.). `distroless` ships with `ca-certificates` package or nothing — you have to add it.

## 3. mTLS: Client Authentication

In **regular TLS**, only the server presents a certificate. The client is anonymous (or authenticated at a higher layer, e.g. via a password or token).

In **mTLS**, the **client also presents a certificate**. The server validates it against its trust store. Now both sides know who the other is.

```
Client                                  Server
  │  ─── ClientHello ───────────────────►  │
  │  ◄── ServerHello + ServerCert ────    │
  │                                       │
  │  ─── ClientCert ────────────────────► │   ← mTLS adds this
  │  ─── ClientKeyExchange ─────────────► │
  │  ...                                  │
```

### 3.1 When mTLS matters

mTLS is the right answer when:

* **Both sides need to know who's calling.** Example: apiserver verifying that a request is from a valid kubelet (and not an attacker who can reach the network).
* **No passwords or tokens.** mTLS replaces bearer tokens for service-to-service auth.
* **Zero-trust network.** Don't trust the network, verify identity.

mTLS is **not** the right answer when:

* **Browsers are involved.** Browsers don't ship per-client certs (most don't). Use cookies / OAuth for browsers.
* **The client is human.** Humans don't manage certs.

For Pod-to-Pod traffic in k8s, mTLS is the standard. Service meshes (Istio, Linkerd, Cilium) make it transparent.

## 4. Where k8s Uses TLS

Kubernetes uses TLS in **at least** these places:

| Connection | Direction | Who certifies whom |
|---|---|---|
| `kubectl` → apiserver | outbound (from user) | Server only (mTLS if you have a client cert) |
| apiserver → etcd | outbound (from apiserver) | mTLS (both sides) |
| apiserver → kubelet | outbound | mTLS (both sides) |
| kubelet → apiserver | outbound (from kubelet) | mTLS (both sides) |
| apiserver → webhook | outbound | Server (or mTLS) |
| apiserver ↔ apiserver (HA) | both | mTLS |
| Pod → apiserver (in-cluster) | outbound | mTLS (if using SA token w/ cert, otherwise server-only) |
| Pod → Pod (in-cluster) | both | Plaintext by default, mTLS via service mesh |
| Ingress → Pod | inbound (from user) | Server (the ingress) |
| NodePort / LB → Pod | inbound (from user) | Server (or no TLS) |

**The control plane is mTLS by default.** **Pod-to-pod is plaintext by default** (until you add a service mesh or app-level mTLS).

### 4.1 The cluster's TLS architecture

```
┌─────────────────────────────────────────┐
│  Control Plane (mTLS)                    │
│                                          │
│  apiserver ←──→ etcd (mTLS)             │
│  apiserver ←──→ kubelet (mTLS)          │
│  apiserver ←──→ webhook (mTLS or TLS)   │
│  apiserver ←──→ apiserver (mTLS, HA)    │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│  Data Plane                              │
│                                          │
│  Pod ↔ Pod: plaintext by default        │
│  Pod → apiserver: mTLS via SA token      │
│  Ingress → Pod: TLS (or no TLS)         │
│  User → Ingress: TLS (the ingress)      │
└─────────────────────────────────────────┘
```

The control plane is locked down by default. The data plane needs work (NetworkPolicy, mTLS via mesh, or app-level mTLS).

## 5. The Cluster's CA Bundle

Every k8s cluster has a **CA bundle** — the set of CAs the cluster trusts. It's distributed to Pods in two places:

1. **`/var/run/secrets/kubernetes.io/serviceaccount/ca.crt`** — the CA cert, used by the in-cluster client to verify the apiserver's cert.
2. **ConfigMap `kube-root-ca.crt`** (k8s 1.20+) — same content, available to Pods that need it.

The Pods trust the apiserver's cert because they have the cluster's CA cert.

### 5.1 The two CAs in a cluster

A standard cluster has:

* **Cluster CA** — signs apiserver, kubelet, controller-manager, scheduler, etcd certs.
* **Service Account CA** — signs ServiceAccount tokens (the JWT signing key).

Some clusters (especially EKS, GKE) have additional CAs for front-proxy, OIDC, etc.

The `ca.crt` in the ServiceAccount mount is the **Cluster CA** (for the apiserver). The **SA CA** is internal to the apiserver and not exposed.

## 6. Certificate Rotation

Certificates expire. A standard cluster's certs are valid for 1 year. The cluster must rotate them before expiry.

### 6.1 kubeadm's auto-rotation

`kubeadm` rotates control plane certs **automatically** 30 days before expiry. It writes the new cert, restarts the affected component, and the cluster continues with new certs.

For self-managed clusters: check `kubeadm certs check-expiration`. For cloud-managed clusters (EKS, GKE, AKS): the cloud provider rotates.

### 6.2 Manual rotation

```bash
# check what's about to expire
kubeadm certs check-expiration

# rotate everything that's expiring in the next 30 days
kubeadm certs renew all

# the cluster components restart with the new certs
```

For each component, kubeadm writes a new cert/key to `/etc/kubernetes/pki/`, then triggers a restart of the control plane Pod (in kubeadm-managed clusters, this is the static Pod manifest).

### 6.3 kubelet cert rotation

The kubelet can **auto-rotate its serving cert**. Enable with:

```yaml
# /var/lib/kubelet/config.yaml
rotateCertificates: true
```

The kubelet generates a new key, requests a new cert from the apiserver's CSR API, and uses the new cert. The old cert is valid until it expires (the apiserver can grant a 90-day cert, so rotation is natural).

## 7. In-Cluster mTLS (Service Mesh)

The default k8s data plane is plaintext Pod-to-Pod. To encrypt that traffic, you have three options:

1. **Service mesh** (Istio, Linkerd, Cilium service mesh) — transparent mTLS. The mesh's sidecar proxies handle cert issuance, rotation, and identity.
2. **App-level mTLS** (e.g. gRPC with TLS, custom certs in the app) — the application does the TLS handshake.
3. **Network-level encryption** (WireGuard, IPsec) — encrypts at the network layer, not the application layer.

For most production clusters, **service mesh is the default**. The tradeoff is operational complexity (a sidecar per Pod) and the mesh's own attack surface.

### 7.1 How Istio / Linkerd do mTLS

* Each Pod gets a sidecar proxy.
* The proxy has an identity (a SPIFFE ID).
* When Pod A calls Pod B, the traffic goes through both sidecars.
* The sidecars establish mTLS. The application is unaware.
* Certs are issued by the mesh's control plane (Istiod for Istio, linkerd-identity for Linkerd).
* Certs are short-lived (24h for Istio, 24h for Linkerd) and auto-rotated.

This is the **zero-trust networking** model. See [[Kubernetes/concepts/L07-security/09-spiffe-spire|SPIFFE / SPIRE]] for the underlying identity model.

### 7.2 STRICT vs PERMISSIVE mTLS

Istio has two modes:

* **PERMISSIVE** — accept both plaintext and mTLS. Lets you roll out mTLS without breaking existing services.
* **STRICT** — only accept mTLS. Plaintext is rejected.

The standard rollout: PERMISSIVE in the namespace, then STRICT after all services are mesh-enabled.

## 8. mTLS Without a Service Mesh

You can do mTLS at the application layer:

* **gRPC with TLS** — the gRPC framework supports TLS natively. The server presents a cert, the client verifies.
* **HTTPS with mutual auth** — the HTTP server requires a client cert. The client presents one.
* **Database connections** — Postgres, MySQL support TLS. Some support client cert auth.

For each, you need:

1. **A CA** for the service (often the cluster CA, or a dedicated service CA).
2. **Certs per service** (or per instance) — issued by cert-manager.
3. **The app configured** to use the certs (paths, formats).

cert-manager (the de-facto k8s cert tool) automates this. See [[Kubernetes/concepts/L07-security/10-cert-manager-deprecated|the cert-manager section]].

### 8.1 cert-manager's place in the L07 cluster

cert-manager is a **practitioner tool** for issuing and rotating certs in k8s. It integrates with Let's Encrypt, HashiCorp Vault, Venafi, and the cluster CA.

For L07 (concepts), the takeaway: cert-manager is the standard way to manage in-cluster certs. For L07's purpose, the concepts (cert rotation, mTLS, etc.) are what matter; the cert-manager details are in `/guides/`.

## 9. TLS Versions and Cipher Suites

### 9.1 The current state

* **TLS 1.0, 1.1** — deprecated, do not use.
* **TLS 1.2** — the minimum acceptable. Most tools support it.
* **TLS 1.3** — the current best. Faster handshake, removes weak ciphers, mandatory forward secrecy.

For new clusters, configure TLS 1.2+ on the apiserver, kubelet, etcd. TLS 1.3 is preferred.

### 9.2 Cipher suites

TLS 1.2 lets you pick cipher suites. The recommended set (k8s, modern):

```
TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305
TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305
```

All use **ECDHE** (forward secrecy) and **AEAD ciphers** (AES-GCM, ChaCha20-Poly1305). No CBC, no RC4, no 3DES, no MD5.

TLS 1.3 doesn't let you pick ciphers — the spec mandates a small set of secure ones.

### 9.3 The k8s apiserver flags

```bash
# apiserver flags
--tls-min-version=VersionTLS12
--tls-cipher-suites=TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,...
```

These apply to connections the apiserver accepts. For TLS 1.3, the `--tls-cipher-suites` flag is ignored (TLS 1.3 has its own cipher selection).

## 10. The cert-manager Tool

*"https://cert-manager.io/"*

cert-manager is the de-facto tool for managing TLS certs in k8s. It automates:

* **Issuance** — request certs from Let's Encrypt, Vault, your own CA, etc.
* **Renewal** — renew certs before they expire.
* **Distribution** — store certs as Secrets, expose to Pods.

It uses **Issuer** and **ClusterIssuer** resources (CRDs):

```yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata: { name: letsencrypt }
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ops@example.com
    privateKeySecretRef: { name: letsencrypt-account-key }
    solvers:
    - http01: { ingress: { class: nginx } }
```

A cert is requested via an annotation on an Ingress, or by creating a `Certificate` resource:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: { name: my-cert }
spec:
  secretName: my-cert-tls
  dnsNames: [my-app.example.com]
  issuerRef: { name: letsencrypt }
```

cert-manager handles the rest: ACME challenge, cert issuance, storage in a Secret, and renewal.

For L07's purposes, cert-manager is a **practitioner tool** covered in `/guides/`. The **concept** is automated cert rotation; the implementation is cert-manager.

## 11. Troubleshooting TLS

### 11.1 Common errors

| Error | Cause |
|---|---|
| `x509: certificate signed by unknown authority` | The server's CA is not in the client's trust store |
| `x509: certificate is valid for X, not Y` | The cert's SAN doesn't match the hostname being requested |
| `x509: certificate has expired or is not yet valid` | The cert is past its `notAfter` or before its `notBefore` |
| `tls: handshake failure` | The client and server don't share a TLS version or cipher |
| `tls: bad certificate` | The client cert is invalid (e.g. expired) |
| `connection refused` | Not a TLS error — the server isn't listening |

### 11.2 The `openssl s_client` debug

```bash
# test a TLS connection
openssl s_client -connect apiserver:6443 -showcerts

# test with a specific SNI
openssl s_client -connect apiserver:6443 -servername kubernetes.default.svc

# check a cert's chain
openssl s_client -connect apiserver:6443 -CAfile /path/to/ca.crt

# inspect a cert file
openssl x509 -in /etc/ssl/certs/server.crt -text -noout
```

### 11.3 The "in-cluster TLS issue" case

A Pod can't reach the apiserver via TLS.

```bash
# 1. Is the apiserver reachable at all?
kubectl exec <pod> -- wget -O- https://kubernetes.default.svc
# (this fails if DNS or routing is wrong, regardless of TLS)

# 2. Does the Pod have the CA cert?
kubectl exec <pod> -- ls /var/run/secrets/kubernetes.io/serviceaccount/
# should show ca.crt, token, namespace

# 3. Is the cert's SAN correct?
# (from the apiserver, in the debug output)
openssl s_client -connect apiserver:6443 -servername kubernetes.default.svc

# 4. Is the time on the Pod correct?
kubectl exec <pod> -- date
# if the Pod's clock is way off, all certs look expired
```

## 12. Operations and Debugging

### 12.1 Common commands

```bash
# check what's about to expire
kubeadm certs check-expiration

# check the kubelet cert
echo | openssl s_client -connect <node>:10250 -servername <node> 2>/dev/null | openssl x509 -noout -dates

# check the apiserver cert
kubectl exec <pod> -- openssl s_client -connect apiserver:6443 -servername kubernetes.default.svc </dev/null 2>&1 | grep "subject\|issuer\|dates"

# check the etcd cert
etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/ssl/etcd/ca.crt \
        --cert=/etc/ssl/etcd/peer.crt --key=/etc/ssl/etcd/peer.key endpoint status

# check the in-cluster client trust
kubectl exec <pod> -- cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt | openssl x509 -text -noout
```

### 12.2 The "cert about to expire" checklist

```bash
# 1. Check what kubeadm-managed certs are about to expire
kubeadm certs check-expiration

# 2. Renew
kubeadm certs renew all

# 3. The static Pods for the control plane restart
# (kubeadm writes a new manifest, kubelet sees it, restarts the pod)

# 4. Verify
kubeadm certs check-expiration

# 5. Check the apiserver's log
journalctl -u kubelet | grep apiserver
# (or kubectl -n kube-system logs kube-apiserver-<node>)
```

## 13. Gotchas and Common Mistakes

### 13.1 The 25+ common mistakes

1. **TLS handshake failures are not "connection refused".** `connection refused` = the server isn't listening. `tls: handshake failure` = the server is there but doesn't accept the TLS version / cipher / cert.

2. **The cert's SAN must match the hostname being requested.** A cert for `apiserver.internal` won't be valid for `kubernetes.default.svc`. The SAN is checked.

3. **Time skew breaks TLS.** If the client's clock is 5 minutes off, all certs look expired or not-yet-valid. NTP / chrony on every node.

4. **Self-signed certs in production are a smell.** The cluster CA exists for a reason — use it (or a public CA for external certs).

5. **TLS 1.0 and 1.1 are deprecated.** Don't accept them. Configure `--tls-min-version=VersionTLS12` on the apiserver.

6. **`insecureSkipVerify: true` is a security footgun.** It bypasses cert validation. Use only for testing.

7. **mTLS isn't free.** The TLS handshake is CPU-intensive. With many short-lived connections, mTLS can become a bottleneck. Use TLS 1.3 (faster handshake) or persistent connections (HTTP/2, gRPC streaming).

8. **`--tls-cipher-suites` doesn't apply to TLS 1.3.** TLS 1.3 has its own cipher set. The flag is for TLS 1.2 only.

9. **In-cluster mTLS via service mesh adds a sidecar to every Pod.** This uses memory (default 50-100 MB per sidecar) and adds latency (one network hop per call). For high-RPS services, the cost is real.

10. **`PERMISSIVE` mTLS mode is for migration, not production.** It accepts both plaintext and mTLS. Production should be `STRICT`.

11. **The cluster CA bundle in `/var/run/secrets/kubernetes.io/serviceaccount/ca.crt` is the cluster's CA, not the world's CAs.** A Pod can verify the apiserver's cert (cluster CA) but can't verify a public CA (no public roots in the bundle).

12. **`ca.crt` in older k8s versions was at `/var/run/secrets/kubernetes.io/serviceaccount/ca.crt`.** Some tools still hardcode the path. ConfigMap `kube-root-ca.crt` (k8s 1.20+) is the new way.

13. **The apiserver's cert includes `kubernetes.default.svc` and `kubernetes.default.svc.cluster.local` in its SAN.** Clients connecting to the apiserver from inside the cluster use these names.

14. **ServiceAccount tokens are JWT, not X.509.** They're a different auth mechanism. Bound SA tokens (k8s 1.21+) have an audience claim and an expiry.

15. **TLS 1.3's 0-RTT is dangerous for non-idempotent requests.** k8s doesn't use 0-RTT, but be aware of it in any custom client.

16. **The kubelet's serving cert is different from the kubelet's client cert.** Two separate certs, two different roles.

17. **HA apiservers all need a cert that includes `kubernetes.default.svc` in the SAN.** Behind a load balancer, the LB's cert is what the client sees; the LB terminates TLS and re-encrypts to a backend.

18. **Mutual TLS in apps requires a CA that both sides trust.** If the server's CA is the cluster CA, the client must have the cluster CA. The easiest is to mount `ca.crt` to both.

19. **The `etcd` server's cert must be valid for the etcd client's hostname.** The etcd client (apiserver) connects to `https://127.0.0.1:2379` or similar — the cert's SAN must include the right hostname.

20. **OCSP stapling is rarely used in k8s.** Cert revocation is mostly via short cert lifetimes (90 days for kubelet, 1 year for control plane) rather than OCSP. CRLs and OCSP are heavier.

21. **ECDSA certs are smaller and faster than RSA.** For new certs, prefer ECDSA. RSA is more compatible with old clients.

22. **`Subject Alternative Name` (SAN) replaced `Common Name` (CN) in 2017.** A cert with only CN is invalid by modern TLS clients. Most CAs issue SAN certs by default.

23. **The `kube-apiserver` flag `--client-ca-file`** is the CA used to verify client certs (for X.509 authentication). A separate flag from `--tls-cert-file` (the apiserver's serving cert).

24. **The `--requestheader-client-ca-file` is the CA for the front proxy.** Used for aggregations (e.g. metrics-server). A different CA from the cluster CA.

25. **The ServiceAccount signing key (`--service-account-key-file`)** is used to sign SA JWTs. Rotation requires updating the apiserver flag and re-issuing tokens. The apiserver publishes the public key for verifiers.

26. **etcd's client cert is for the apiserver's auth to etcd.** Different from the apiserver's serving cert. Two certs, two roles.

27. **The cluster's CA bundle in `ConfigMap kube-root-ca.crt` is what Pods should use to verify the apiserver.** Older clients hardcode the path `/var/run/secrets/...`.

28. **In a service mesh, the workload's cert is issued by the mesh, not the cluster CA.** The cert is short-lived (24h) and rotated by the sidecar.

29. **The CN (Common Name) of a server cert is what the SAN overrides.** Modern TLS checks SAN, not CN. A cert with no SAN is rejected by most clients.

30. **TLS doesn't protect against DoS.** An attacker can flood the TLS handshake (which is CPU-intensive). Use rate limiting, a WAF, or DDoS protection at the network edge.

## See also

* [[Kubernetes/concepts/L07-security/04-certificates|Certificates]] — the cluster PKI
* [[Kubernetes/concepts/L07-security/09-spiffe-spire|SPIFFE / SPIRE]] — workload identity for service-mesh mTLS
* [[Kubernetes/concepts/L07-security/13-etcd-encryption|etcd Encryption]] — encrypting data at rest
* [[Kubernetes/concepts/L07-security/14-secret-encryption|Secret Encryption]] — encrypting Secrets in etcd
* [[Kubernetes/concepts/L04-services-networking/05-network-policy|NetworkPolicy]] — encrypting network traffic (with mTLS)
