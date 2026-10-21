---
title: "PKI Operator Runbook — Cryptography, Certificates, TLS, JWT, OIDC, and GPG"
tags: [architecture/cryptography, security/pki, security/tls, security/identity]
date: 2026-10-21
description: "A hands-on operator learning runbook from bytes and hashes through RSA, elliptic curves, a root/intermediate CA, TLS, JWT/JWKS, OIDC, GPG, and Kubernetes identity."
aliases: [PKI Operator Runbook, Cryptography Operator Lab]
---

# PKI Operator Runbook

For a cloud/Kubernetes background, learn this as an operator rather than as a cryptography course. By the end, when you encounter these terms, you should know what each represents, where it sits in the stack, and which command can inspect or prove it:

```text
-----BEGIN PRIVATE KEY-----
-----BEGIN CERTIFICATE-----
SHA256
RSA 2048
prime256v1 / P-256
Ed25519
X25519
RS256
ES256
PS256
kid
JWKS
x5c
iss
aud
OIDC discovery
CSR
SAN
EKU
PKCS#8
PKCS#12
PEM
DER
GPG fingerprint
TLS_AES_256_GCM_SHA384
```

The commands target OpenSSL 3 on a Debian/Ubuntu-style Linux system. See the [OpenSSL 3 documentation](https://docs.openssl.org/3.5/man7/).

## How to use this runbook

Work through the six notes in order; later labs reuse files from earlier ones. Commands run in a disposable `~/crypto-lab` directory, not in this wiki repository. The CA is a learning setup, not a production CA service. Part numbers run continuously across the notes.

1. [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook/01-foundations|Foundations]] — Lab 0 and Parts 1–7: bytes, encodings, randomness, hashes, HMAC, password KDFs, and symmetric and asymmetric encryption.
2. [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook/02-keys-and-signatures|Keys and Signatures]] — Parts 8–15: RSA keys, PEM/DER/PKCS formats, RSA signatures and OAEP encryption, P-256/ECDSA, Ed25519, and X25519.
3. [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook/03-pki-and-tls|PKI and TLS]] — Parts 16–40: a root → intermediate → leaf CA, chain and hostname verification, PKCS#12, a working TLS server, TLS 1.3, forward secrecy, mTLS, and revocation.
4. [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook/04-ssh-jwt-and-oidc|SSH, JWT and OIDC]] — Parts 41–59: SSH keys, a hand-built RS256 JWT, JWK/JWKS, OAuth 2.0 versus OIDC, discovery, and token validation.
5. [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook/05-openpgp|OpenPGP and GPG]] — Parts 60–70: GPG keys, fingerprints, detached and clear signatures, encryption, subkeys, and web-of-trust versus X.509.
6. [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook/06-operator-connections|Operator Connections and Review]] — Parts 71–101: fingerprints, KMS/HSM, Kubernetes certificates, cert-manager, Istio, Kubernetes OIDC, IRSA and Pod Identity, and a first-principles review.

Come back here at the end for the cheat sheet and the review questions.

**Run status:** run on 2026-10-21 with OpenSSL 3.6.3 and GnuPG 2.4.9 on Linux. Run: Lab 0's tools, Parts 1–34, 41, 44–48, 62–67 and 73, with passphrase prompts replaced by `-pass`/`--batch` flags and the Part 60 key made with `gpg --quick-gen-key` instead of the interactive `--full-generate-key`. Not run: Parts 36 and 56 (they contact Google) and Part 77 (it needs a kubeadm or kind control plane). The remaining parts are explanation.

Related notes: [[Architecture/solution-architecture-concepts/cryptography/README|Cryptography]], [[Architecture/solution-architecture-concepts/cryptography/pki|PKI]], and [[Architecture/solution-architecture-concepts/authentication/README|Identity & Auth Curriculum]].

## The entire map first

Keep this diagram beside you for the whole session.

```text
                         CRYPTOGRAPHY
                              │
           ┌──────────────────┼──────────────────┐
           │                  │                  │
        HASHING           SYMMETRIC          ASYMMETRIC
           │              ENCRYPTION          CRYPTO
           │                  │                  │
       SHA-256              AES            public/private
       SHA-384              ChaCha20           keys
       SHA-512                                  │
           │                         ┌───────────┴───────────┐
         HMAC                        │                       │
           │                     SIGNATURE              KEY AGREEMENT
     shared secret                   │                       │
                               RSA / ECDSA              DH / ECDH
                                Ed25519                  X25519
                                     │
                              identity problem
                                     │
                                     ▼
                              CERTIFICATES
                               X.509 / PKI
                                     │
                     ┌───────────────┼───────────────┐
                     │               │               │
                    CA              CSR           trust chain
                                                     │
                                               Root → Int → Leaf
                                                     │
                                                     ▼
                                                    TLS

Another branch using the same primitives:

asymmetric signing (or a MAC)
       │
       ▼
      JWS
       │
       ▼
  signed JWT
       │
       ▼
 OAuth2 + identity semantics
       │
       ▼
      OIDC
       ├── discovery
       ├── ID token
       ├── access token (not necessarily a JWT)
       └── JWKS

Another ecosystem:

public/private keys → OpenPGP → GPG
```

```text
Hashing      = fingerprint data
Encryption   = hide data
Signature    = prove signing-key possession + detect modification
Certificate  = CA signs a public-key/identity binding
TLS          = authenticate peer + establish encrypted channel
JWT          = format containing claims
JWS          = way to sign or MAC data such as JWTs
OIDC         = identity protocol on OAuth 2.0 using signed ID tokens
GPG          = OpenPGP implementation for signing/encryption/key trust
```

## Your final practical cheat sheet

These are command templates from the six notes. Supply the files from the relevant lab directory; names such as `file` and `private.pem` are placeholders.

```bash
# Randomness
openssl rand -hex 32

# Hash
sha256sum file

# HMAC
openssl dgst -sha256 -hmac "$SECRET" file

# RSA private key
openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:2048 \
  -out private.pem

# Extract public key
openssl pkey -in private.pem -pubout -out public.pem

# Inspect key (prints private material)
openssl pkey -in private.pem -text -noout

# Sign
openssl dgst -sha256 -sign private.pem -out file.sig file

# Verify
openssl dgst -sha256 -verify public.pem -signature file.sig file

# Ed25519
openssl genpkey -algorithm ED25519 -out ed25519.pem

# X25519
openssl genpkey -algorithm X25519 -out x25519.pem

# CSR (interactive identity prompts)
openssl req -new -key private.pem -out request.csr

# Inspect and verify CSR
openssl req -in request.csr -text -noout
openssl req -in request.csr -verify -noout

# Inspect certificate
openssl x509 -in cert.pem -text -noout

# Certificate fingerprint
openssl x509 -in cert.pem -fingerprint -sha256 -noout

# Verify chain, server purpose, and hostname
openssl verify \
  -CAfile root.crt \
  -untrusted intermediate.crt \
  -purpose sslserver \
  -verify_hostname example.com \
  leaf.crt

# Inspect and validate real TLS
openssl s_client \
  -connect example.com:443 \
  -servername example.com \
  -verify_hostname example.com \
  -verify_return_error \
  -showcerts

# GPG keys (use the isolated lab GNUPGHOME)
gpg --list-keys
gpg --list-secret-keys
gpg --fingerprint

# GPG sign and verify
gpg --detach-sign file
gpg --verify file.sig file

# OIDC discovery
curl -fsS \
  https://accounts.google.com/.well-known/openid-configuration |
jq

# JWKS (set JWKS_URI from trusted discovery first)
curl -fsS "$JWKS_URI" | jq
```

## The 20 questions you should be able to answer afterward

Use these as your exam. Do the commands before reviewing the explanations.

1. Why is a SHA-256 hash 64 hexadecimal characters?
2. Why does SHA-256 have roughly 128-bit collision resistance?
3. Why is Base64 not encryption?
4. What is the difference between hashing and HMAC?
5. Why can an HMAC verifier also forge a valid HMAC?
6. What exactly does `2048` mean in RSA-2048?
7. Why is RSA-2048 not “2048-bit security”?
8. What are `n` and `e` in an RSA public key?
9. Why can P-256 provide stronger classical security than RSA-2048 despite its smaller key representation?
10. Where does the `25519` in Ed25519/X25519 come from?
11. Why can't you use an X25519 key to create an Ed25519 signature just because the names look related?
12. What is the difference between a public key and a certificate?
13. What is inside a CSR?
14. Why does a root certificate contain public information while the root CA has an extremely sensitive private key?
15. Why doesn't a TLS server normally send its root CA?
16. What is SAN and why does the browser care?
17. Why doesn't `RS256` mean “256-bit RSA”?
18. Why isn't a signed JWT encrypted by default?
19. What is `kid`, and how does it interact with JWKS during rotation?
20. What does OIDC provide beyond OAuth 2.0?

If you can answer these and reproduce the RSA → CSR → CA → TLS and JWT → JWKS paths, you have the foundation to understand Kubernetes certificates, cert-manager, Istio mTLS, private CAs, ACM, Keycloak/OIDC, IRSA, JWT validation, SSH, GPG, KMS/HSM signing, and certificate incidents.

## Across the wiki

- [[Architecture/solution-architecture-concepts/cryptography/pki|PKI]] and [[Architecture/solution-architecture-concepts/cryptography/signing-and-verifying|Signing and Verifying]] — shorter concept notes on the same ground.
- [[Architecture/solution-architecture-concepts/authentication/README|Identity & Auth Curriculum]] — OAuth 2.0, OIDC and token handling in depth.
- [[Kubernetes/concepts/L07-security/01-api-access/04-certificates|Kubernetes Certificates]], [[Kubernetes/concepts/L07-security/03-encryption-identity/08-tls-mtls|TLS and mTLS]] and [[Kubernetes/concepts/L07-security/03-encryption-identity/09-spiffe-spire|SPIFFE and SPIRE]] — the same PKI inside a cluster.
- [[Kubernetes/guides/non-functional/oidc-integration|Kubernetes OIDC Integration]] — wiring an OIDC issuer into the API server.
- [[Kubernetes/eks/security/README|EKS Security]] and [[Kubernetes/eks/security/pod-identity|EKS Pod Identity]] — IRSA and Pod Identity on AWS.
- [[AWS/security/kms/README|AWS KMS]] — managed keys and signing.
- [[Security/network-security/README|Network Security]] — where TLS sits in the wider security picture.
