---
title: "PKI Operator Runbook 6 — Operator Connections and Review"
tags: [architecture/cryptography, security/pki, security/tls, security/identity]
date: 2026-10-21
description: "Connect the primitives to KMS/HSM, Kubernetes certificates, cert-manager, Istio mTLS, OIDC, IRSA and Pod Identity, then review the numbers and PKI ideas."
---

# PKI Operator Runbook 6 — Operator Connections and Review

Parts 71–101: fingerprints, KMS/HSM, Kubernetes certificates, cert-manager, Istio, Kubernetes OIDC, IRSA and Pod Identity, and a first-principles review. Part of the [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook|PKI Operator Runbook]] (6 of 6). Previous: [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook/05-openpgp|OpenPGP and GPG]].

Commands continue in `~/crypto-lab` from the earlier notes; reapply `umask 077` in each new terminal.

## Part 71 — Key fingerprints everywhere

```text
SSH fingerprint
GPG fingerprint
certificate fingerprint
container digest
Git object hash
```

The recurring idea is a compact digest representing larger data. Exact inputs, hash algorithms, and display encodings differ. A certificate fingerprint and its public-key fingerprint are different identifiers.

Instead of visually comparing a long public-key blob, compare an authenticated fingerprint. A fingerprint supplied by the same untrusted source as the key does not establish identity by itself.

## Part 72 — Hash versus signature versus certificate

Suppose you download `terraform-provider.zip`:

- **SHA-256:** checks that the file matches an expected hash, provided you trust that expected hash.
- **Digital signature:** checks that the file was signed by the corresponding private-key holder and has not changed, provided you have the correct public key.
- **Certificate/trust binding:** helps explain why that public key should be associated with the vendor.

## Part 73 — Secret-key protection

Files such as `rsa-private.pem`, `server.key`, `ed25519-private.pem`, and GPG secret-key exports are assets. Protection can include permissions, encrypted key files, passphrases, HSMs, TPMs, cloud KMS, Vault, access control, rotation, audit logs, and offline roots.

Generate an encrypted private key in your lab:

```bash
cd ~/crypto-lab

openssl genpkey \
  -algorithm RSA \
  -aes-256-cbc \
  -pkeyopt rsa_keygen_bits:2048 \
  -out protected-private.pem
```

You need its passphrase to use it. Encryption at rest does not replace controlling access while the key is in use.

## Part 74 — KMS/HSM mental model

```text
Application → "sign this message/digest" → KMS/HSM
                                          ├── protects private key
                                          └── returns signature
```

With non-exportable keys, applications request operations rather than receiving private-key bytes. The caller still needs correct authorization and algorithm/message-format choices.

## Part 75 — Where AWS KMS fits

```text
Local file: application reads server.key
Managed key: application requests an authorized cryptographic operation
```

Operations depend on the key's type and purpose: encrypt, decrypt, sign, verify, or generate a data key. The underlying primitives should now feel familiar. For service-specific behavior, see [[AWS/security/kms/README|AWS KMS]].

## Part 76 — Certificate authority systems you already know

```text
AWS ACM                 certificate management
AWS Private CA          private certificate authority
cert-manager            Kubernetes certificate automation
Let's Encrypt           public CA / ACME ecosystem
Vault PKI               private certificate issuance
AD Certificate Services enterprise PKI
SPIRE / Istio CA         workload identity and certificates
Kubernetes CA           cluster component/client identity
```

Across these systems you encounter key generation, CSRs, issuance, trust, renewal, rotation, revocation, and distribution, with responsibilities differing by product.

## Part 77 — Kubernetes certificates

A kube-apiserver serving certificate may include SANs such as:

```text
kubernetes
kubernetes.default
kubernetes.default.svc
kubernetes.default.svc.cluster.local
API server IP
control-plane DNS
```

On a kubeadm control-plane host, inspect its certificate:

```bash
sudo openssl x509 \
  -in /etc/kubernetes/pki/apiserver.crt \
  -text \
  -noout
```

No kubeadm host? kind runs kubeadm inside its node container, so the wiki's lab cluster (see [[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01 — Cluster Setup & Orientation]]) has the same file:

```bash
docker exec k8s-lab-control-plane \
  openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -ext subjectAltName
```

### Kubernetes client certificate

A kubeconfig may embed these fields:

```yaml
client-certificate-data: BASE64_ENCODED_CERTIFICATE
client-key-data: BASE64_ENCODED_PRIVATE_KEY
```

Decode only the certificate for inspection, straight from your current kubeconfig:

```bash
kubectl config view --raw --minify \
  -o jsonpath='{.users[0].user.client-certificate-data}' |
base64 -d |
openssl x509 -text -noout
```

`--minify` limits the output to the current context's user.

Inspect subject, issuer, EKU, and validity. The key field is secret; Base64 does not protect it. Continue with [[Kubernetes/concepts/L07-security/01-api-access/04-certificates|Kubernetes Certificates]].

## Part 78 — cert-manager mental model

```text
Private key → CSR → Issuer / ClusterIssuer → CA / ACME
                                                 │
                                                 ▼
                                            certificate
                                                 │
                                                 ▼
                                          Kubernetes Secret
```

A typical TLS Secret has:

```yaml
data:
  tls.crt: BASE64_ENCODED_CERTIFICATE_CHAIN
  tls.key: BASE64_ENCODED_PRIVATE_KEY
```

`tls.crt` holds the certificate/chain; `tls.key` holds the corresponding private key. Kubernetes Secret data encoding is not encryption.

## Part 79 — Istio mTLS

```text
Workload A: private key + certificate + trusted CA
Workload B: private key + certificate + trusted CA
                  ⇅ mutual TLS
```

Each proves possession of a private key bound to its certificate identity. Automated rotation enables short-lived workload certificates. Authentication identifies the peer; authorization policy decides what that peer may do. See [[Kubernetes/concepts/L07-security/03-encryption-identity/08-tls-mtls|TLS and mTLS]].

## Part 80 — OIDC in Kubernetes

```text
User → Identity Provider → signed ID token → kubectl
                                              │ bearer token
                                              ▼
                                        kube-apiserver
                                         ├── trusted issuer/keys
                                         ├── signature + claims validation
                                         └── identity mapping → authorization
```

The same JWT/JWKS concepts apply. See [[Kubernetes/guides/non-functional/oidc-integration|Kubernetes OIDC Integration]] for configuration details.

## Part 81 — AWS IAM OIDC

IRSA conceptually works like this:

```text
Pod → projected ServiceAccount JWT
       ├── iss
       ├── sub
       ├── aud
       └── signature
              │
              ▼
           AWS STS
            ├── configured OIDC provider and public keys
            ├── token and trust-policy claim checks
            └── temporary AWS credentials
```

This is JWT signatures plus configured identity trust and authorization. See [[Kubernetes/eks/security/README|EKS Security]] for the surrounding AWS integration.

EKS Pod Identity is the newer alternative. The pod still presents a projected ServiceAccount token, but to the EKS Pod Identity Agent on the node rather than to STS. Roles trust the `pods.eks.amazonaws.com` service principal, so there is no per-cluster OIDC provider to register. See [[Kubernetes/eks/security/pod-identity|EKS Pod Identity]].

## Part 82 — What `kid` solves

```text
Week 1: private A / public A / kid=A
Week 2: private B / public B / kid=B

JWT header.kid=B → trusted JWKS → eligible B → verify signature
```

The key identifier allows selection during rotation. Overlap and cache-refresh policy matter because old tokens may remain valid. `kid` alone does not tell the verifier which issuer or network location to trust.

## Part 83 — `x5c`, `x5t`, JWK and certificates

Some JWKs contain `x5c`, an X.509 certificate chain. This connects JOSE keys and PKI:

```text
JWT/JWS → JWK → x5c → X.509 certificate chain
```

`x5c` entries are ordinary Base64-encoded DER certificates, not Base64url. `x5t` is a SHA-1 certificate thumbprint; `x5t#S256` is its SHA-256 counterpart. These are identifiers, not signature algorithms. An included certificate chain still needs the consumer's trust policy; its presence does not make the key trusted. See [RFC 7517, Section 4](https://www.rfc-editor.org/rfc/rfc7517#section-4).

## Part 84 — Signing algorithm comparison

The table includes encryption, agreement, and hashing for comparison; they serve different purposes. Approximate strengths below describe classical attacks.

| Algorithm | Type                       | Typical purpose       | Approximate strength / size                 |
| --------- | -------------------------- | --------------------- | ------------------------------------------- |
| RSA-2048  | RSA                        | Signatures/encryption | ~112-bit security                           |
| RSA-3072  | RSA                        | Signatures/encryption | ~128-bit security                           |
| P-256     | Elliptic curve             | ECDSA/ECDH            | ~128-bit security                           |
| Ed25519   | Edwards-curve signature    | Signatures            | ~128-bit security                           |
| X25519    | Montgomery-curve agreement | Key agreement         | ~128-bit security                           |
| AES-128   | Symmetric cipher           | Encryption            | 128-bit key                                 |
| AES-256   | Symmetric cipher           | Encryption            | 256-bit key                                 |
| SHA-256   | Hash                       | Digest                | 256-bit output; ~128-bit collision strength |

Do not confuse key length, digest length, field size, and security strength.

## Part 85 — Decode the numbers once and for all

### SHA-256

256-bit digest = 32 bytes = 64 hex characters.

### AES-256

256-bit key = 32 bytes. AES block size remains 128 bits.

### RSA-2048

2048-bit modulus; primes typically about 1024 bits each; about 112-bit classical security.

### RSA-3072

3072-bit modulus; about 128-bit classical security.

### P-256

Roughly 256-bit field; about 128-bit classical security.

### SHA-384

384-bit digest = 48 bytes = 96 hex characters.

### SHA-512

512-bit digest = 64 bytes = 128 hex characters.

### Ed25519

The name relates to the field prime `2^255 - 19`. It is an Edwards-curve signing construction with a 32-byte private seed, 32-byte public key, and 64-byte signature, and about 128-bit classical security. See [RFC 8032](https://www.rfc-editor.org/rfc/rfc8032).

### X25519

Related field family; Diffie-Hellman key agreement, not digital signatures.

### ES256

ECDSA with P-256 and SHA-256. It does not mean a 256-bit signature: JOSE represents its signature as 64 bytes of `R || S`.

### RS256

RSA PKCS#1 v1.5 signing with SHA-256. The RSA key could be 2048, 3072, or 4096 bits. “256” is not the RSA modulus size.

### PS256

RSA-PSS with SHA-256, with the JOSE-specified parameters. Again, 256 is not the RSA key size. See [RFC 7518](https://www.rfc-editor.org/rfc/rfc7518).

### HS256

HMAC with SHA-256. [JWA](https://www.rfc-editor.org/rfc/rfc7518#section-3.2) requires an HS256 key at least as large as the hash output: 256 bits.

## Part 86 — Diffie-Hellman deserves one mental picture

```text
Alice                         Bob
private a                     private b
public A                      public B

A ───────────────────────────>
  <─────────────────────────── B

f(a, B) = S                   f(b, A) = S
```

Both derive `S`; a passive observer with only `A` and `B` cannot feasibly do so. Modern TLS commonly uses ephemeral elliptic-curve Diffie-Hellman, **ECDHE**. “Ephemeral” means temporary key-agreement keys. Authentication is needed to prevent active substitution of the exchanged keys.

## Part 87 — KDFs

Raw shared secret `S` is normally processed through a **Key Derivation Function**:

```text
S → KDF
     ├── client encryption key
     ├── server encryption key
     ├── IV material
     ├── handshake secrets
     └── application secrets
```

TLS 1.3 uses HKDF with transcript/context information and distinct labels. Password KDFs and protocol key-schedule KDFs solve different problems; “KDF” does not always mean an intentionally slow password hash.

## Part 88 — Salts, IVs and nonces

### Salt

Common in password hashing and KDFs. A salt can separate derived results for equal passwords. It is usually public; exact requirements depend on the construction.

### IV

An Initialization Vector is used by certain cipher modes. It is usually public but must satisfy mode-specific randomness or uniqueness requirements.

### Nonce

A number used once, particularly important in AEAD algorithms such as AES-GCM and ChaCha20-Poly1305. Reusing a nonce with the same key can be catastrophic. “Public” does not mean “safe to repeat.”

## Part 89 — Encoding vs hashing vs encryption

| Item                  | Who can undo or check it?               | Secret involved?        | Purpose                    |
| --------------------- | --------------------------------------- | ----------------------- | -------------------------- |
| Base64                | Anyone can decode                       | No                      | Encoding                   |
| SHA-256               | Nobody can invert; anyone can recompute | No                      | Hashing                    |
| AES                   | Only a key holder can decrypt           | Yes                     | Symmetric encryption       |
| RSA/Ed25519 signature | Anyone with the public key can verify   | Private key for signing | Authenticity and integrity |

## Part 90 — Signatures do not necessarily identify a human

If a signature verifies with PublicKey-X, it establishes signing capability for the corresponding private key. It does not automatically establish that this key belongs to Darshan, or that Darshan personally approved the operation.

Identity binding comes from a certificate, OpenPGP certification, manually verified fingerprint, cloud IAM configuration, trusted OIDC issuer configuration, or another trust mechanism.

## Part 91 — The deepest PKI idea

Cryptography can establish “this signature corresponds to this public key.” It does not inherently establish “this public key belongs to amazon.com.” PKI adds identity binding, trust anchors, and policy:

```text
Public key → certificate → CA signature → CA certificate
                    → root certificate → configured trust store
```

## Part 92 — Chain validation

A browser validating a leaf and intermediate conceptually checks:

1. Leaf signature against intermediate public key.
2. Intermediate path signatures toward a trusted anchor.
3. Trust-anchor policy.
4. Hostname against SAN.
5. Validity periods.
6. Basic Constraints and path-length constraints.
7. Key Usage/EKU compatibility.
8. Algorithm acceptability.
9. Revocation according to client policy.
10. Other applicable policies and constraints.

Successful certificate validation is one part of a successful authenticated TLS connection. A chain-only `openssl verify` invocation is not automatically equivalent to every browser check.

## Part 93 — Why server doesn't send root certificate

```text
Server sends: leaf + intermediate(s)
Client has:   configured trust anchors
```

Receiving a root from an untrusted server does not make it trusted. Otherwise an attacker could supply a fake website certificate and the fake root that signed it.

## Part 94 — Self-signed does not mean insecure

A self-signed certificate is not intrinsically cryptographically weak. The question is how to establish trust. A company can securely distribute a private root and use private PKI; a public website generally needs a CA chain recognized by its clients.

## Part 95 — Certificate expiry

Expiry limits the time that compromised keys, stale identities, outdated algorithms, or incorrect attributes remain acceptable under that certificate. Short-lived workload certificates reduce the window of exposure and reliance on revocation, but still require reliable renewal and key handling.

## Part 96 — Root versus intermediate CA

```text
ROOT         offline / highly protected
  │
INTERMEDIATE operational issuance
  │
LEAF         service/client identity
```

Keeping the root out of routine issuance reduces exposure. If an intermediate is compromised, an operator can revoke/distrust and replace it while retaining the root, subject to effective trust and revocation distribution.

## Part 97 — Private key versus secret key

Symmetric cryptography commonly says **secret key**, because parties share the secret. Asymmetric cryptography distinguishes **private key** from **public key**. A private key is secret, and some ecosystems such as GPG also call it a secret key; interpret the terminology in context.

## Part 98 — Certificate versus public key

You can have a public key without an X.509 certificate; SSH frequently does this.

```text
certificate ≈ signed public-key identity document
            = public key + identity/metadata + issuer signature
```

## Part 99 — CSR versus certificate

```text
CSR:         "Please issue a certificate for this key/requested identity."
Certificate: "The issuer has signed this approved binding and metadata."
```

The CA creates and signs a certificate rather than appending approval to the CSR. Browsers consume the issued certificate, not the CSR.

## Part 100 — Root certificate contains a public key

```text
Root CA private key → extremely secret
Root CA certificate → public key + metadata + self-signature; distributable
```

A laptop's trust store contains root certificates/public information, not CA private keys. Trust comes from how the anchor was installed and configured, not merely from its self-signature.

## Part 101 — Final PKI hierarchy from first principles

```text
                         RANDOMNESS
                             │
              ┌──────────────┴─────────────┐
              │                            │
           secrets                      keys
              │                            │
              ▼                            ▼
            AES                      asymmetric keys
                                       │
                           ┌───────────┴───────────┐
                           │                       │
                       signatures            key agreement
                           │                       │
                  RSA/ECDSA/Ed25519              X25519
                           │                       │
                           │                       ▼
                           │                  shared secret
                           │                       │
                           │                      KDF
                           │                       │
                           │                       ▼
                           │                 AES/ChaCha
                           ▼
                     certificates
                           │
                          CA
                           │
                      trust chains
                           │
                          TLS

Hashes
├── fingerprints
├── integrity checks
├── HMAC
├── signature constructions
└── KDF constructions

Signatures
├── X.509 certificates
├── package signatures
├── Git/GPG
└── JWS/JWT → OIDC
```

---

**Finish:** go back to the [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook|PKI Operator Runbook]] for the cheat sheet and the 20 review questions.
