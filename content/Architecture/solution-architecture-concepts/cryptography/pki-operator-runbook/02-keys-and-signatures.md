---
title: "PKI Operator Runbook 2 — Keys and Signatures"
tags: [architecture/cryptography, security/pki, security/tls, security/identity]
date: 2026-10-21
description: "Generate and inspect RSA, P-256, Ed25519 and X25519 keys; learn PEM/DER/PKCS; sign, verify, encrypt, and derive shared secrets with OpenSSL."
---

# PKI Operator Runbook 2 — Keys and Signatures

Parts 8–15: RSA keys, PEM/DER/PKCS formats, RSA signatures and OAEP encryption, P-256/ECDSA, Ed25519, and X25519. Part of the [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook|PKI Operator Runbook]] (2 of 6). Previous: [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook/01-foundations|Foundations]]. Next: [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook/03-pki-and-tls|PKI and TLS]].

Commands continue in `~/crypto-lab` from the earlier notes; reapply `umask 077` in each new terminal.

## Part 8 — RSA from scratch

```bash
cd ~/crypto-lab/04-rsa

openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:2048 \
  -out rsa-private.pem

openssl pkey -in rsa-private.pem -text -noout
```

You will see `modulus`, `publicExponent`, `privateExponent`, `prime1`, `prime2`, and other parameters. This inspection prints private material; use lab keys.

### What does RSA 2048 mean?

Simplifying, RSA starts with two large primes `p` and `q`, and computes the modulus `n = p × q`. RSA-2048 describes a 2048-bit modulus, typically from two primes of about 1024 bits each. It does not mean 2048-bit security. RSA-2048 is associated with roughly 112-bit classical security.

### 8.1 Public exponent

```bash
openssl pkey -in rsa-private.pem -text -noout | grep publicExponent
```

Usually `65537`, or `0x10001`. The RSA public key conceptually contains `(n, e)`:

```text
n = modulus
e = public exponent
```

The private key includes enough information for private operations, commonly `d`, `p`, `q`, and CRT parameters.

### 8.2 Extract public key

```bash
openssl pkey \
  -in rsa-private.pem \
  -pubout \
  -out rsa-public.pem

cat rsa-public.pem
```

Expect a `-----BEGIN PUBLIC KEY-----` block. See [openssl-pkey](https://docs.openssl.org/3.5/man1/openssl-pkey/).

### 8.3 Compare private/public information

```bash
openssl pkey -in rsa-private.pem -text_pub -noout
openssl pkey -pubin -in rsa-public.pem -text -noout
```

The public components should match.

## Part 9 — PEM, DER, ASN.1 and PKCS formats

These are not competing algorithms.

- **ASN.1** describes structured data such as sequences, integers, object identifiers, and bit strings.
- **DER** is a binary encoding for ASN.1.
- **PEM** commonly wraps Base64-encoded DER in labeled text boundaries.

```text
X.509 certificate structure → ASN.1 → DER binary → Base64 → PEM text

-----BEGIN CERTIFICATE-----
MIID...
-----END CERTIFICATE-----
```

### Prove DER versus PEM

From `~/crypto-lab/04-rsa`:

```bash
openssl pkey \
  -in rsa-private.pem \
  -outform DER \
  -out rsa-private.der

xxd rsa-private.der | head
file rsa-private.pem
file rsa-private.der
```

### PKCS cheat sheet

```text
PKCS#1   RSA-specific key/signature/encryption definitions
PKCS#8   generic private-key container
PKCS#10  certificate signing request (CSR)
PKCS#12  private key + certificate + chain bundle; often .p12 or .pfx
```

You will use these formats without needing a raw PKCS#1 key file.

## Part 10 — Digital signatures with RSA

```bash
cd ~/crypto-lab/06-signatures
cp ../04-rsa/rsa-private.pem .
cp ../04-rsa/rsa-public.pem .
echo "deploy version 42" > release.txt

openssl dgst \
  -sha256 \
  -sign rsa-private.pem \
  -out release.sig \
  release.txt

xxd release.sig | head

openssl dgst \
  -sha256 \
  -verify rsa-public.pem \
  -signature release.sig \
  release.txt
```

Expect `Verified OK`. Now modify and verify again:

```bash
echo "attacker changed this" >> release.txt

openssl dgst \
  -sha256 \
  -verify rsa-public.pem \
  -signature release.sig \
  release.txt
```

Verification fails.

### What actually happened?

```text
Sign:    message → SHA-256 → digest + private-key signature scheme → signature
Verify:  message + signature + public key → verification result
```

Treat signatures as dedicated cryptographic algorithms. “Encrypting a hash with the private key” is not a general description of modern signing, especially ECDSA, EdDSA, or RSA-PSS.

## Part 11 — RSA encryption

Still in `06-signatures`:

```bash
echo 'the launch code is 1234' > plaintext.txt

openssl pkeyutl \
  -encrypt \
  -pubin \
  -inkey rsa-public.pem \
  -in plaintext.txt \
  -out ciphertext.bin \
  -pkeyopt rsa_padding_mode:oaep \
  -pkeyopt rsa_oaep_md:sha256 \
  -pkeyopt rsa_mgf1_md:sha256

openssl pkeyutl \
  -decrypt \
  -inkey rsa-private.pem \
  -in ciphertext.bin \
  -out decrypted.txt \
  -pkeyopt rsa_padding_mode:oaep \
  -pkeyopt rsa_oaep_md:sha256 \
  -pkeyopt rsa_mgf1_md:sha256

cat decrypted.txt
```

### Important limitation

RSA encrypts only short inputs, not large files. Hybrid encryption uses asymmetric cryptography to protect or establish a symmetric session key, and AES/ChaCha to encrypt the bulk data. Modern TLS usually uses ephemeral Diffie-Hellman key agreement rather than RSA key transport. See [OpenSSL pkeyutl options](https://docs.openssl.org/3.5/man1/openssl-pkeyutl/) for the explicit OAEP and MGF1 digest settings used above.

## Part 12 — Elliptic-curve cryptography

```bash
cd ~/crypto-lab/05-ec

openssl genpkey \
  -algorithm EC \
  -pkeyopt ec_paramgen_curve:P-256 \
  -out p256-private.pem
```

If the alias is not accepted, use `prime256v1`:

```bash
openssl genpkey \
  -algorithm EC \
  -pkeyopt ec_paramgen_curve:prime256v1 \
  -out p256-private.pem

openssl pkey -in p256-private.pem -text -noout
openssl pkey -in p256-private.pem -pubout -out p256-public.pem
```

### What does P-256 mean?

A simplified short-Weierstrass elliptic curve over a prime field looks like:

```text
y² = x³ + ax + b  mod p

G = base point
d = secret scalar
Q = dG = public point
```

Scalar multiplication computes `Q` from `d` and `G`. Recovering `d` from `Q` and `G` is computationally infeasible for appropriately selected parameters.

P-256 uses a roughly 256-bit prime field and provides around 128-bit classical security. Generic elliptic-curve discrete-log attacks scale roughly with the square root of the group size.

```text
RSA-2048   ~112-bit security
P-256      ~128-bit security
Ed25519    ~128-bit security
AES-128     128-bit key
```

Comparing “2048” and “256” directly is misleading because the mathematical problems differ.

## Part 13 — ECDSA

Still in `05-ec`:

```bash
echo "deploy production" > data.txt

openssl dgst \
  -sha256 \
  -sign p256-private.pem \
  -out data.sig \
  data.txt

openssl dgst \
  -sha256 \
  -verify p256-public.pem \
  -signature data.sig \
  data.txt
```

This combines an EC key, ECDSA, and SHA-256: the primitives behind JWT `ES256`. The OpenSSL signature here is DER-encoded; JOSE ES256 uses fixed-width `R || S`, so the signature bytes cannot simply be reused as an ES256 JWS signature.

## Part 14 — Curve25519, Ed25519, X25519

These names are related, not synonymous. The field prime is `2^255 - 19`; “25519” does not mean a 25,519-bit key.

### Ed25519

Ed25519 is an EdDSA digital signature construction using Edwards25519. Its private seed is 32 bytes, public key is 32 bytes, and signature is 64 bytes. See [RFC 8032](https://www.rfc-editor.org/rfc/rfc8032).

```bash
openssl genpkey -algorithm ED25519 -out ed25519-private.pem
openssl pkey -in ed25519-private.pem -pubout -out ed25519-public.pem
openssl pkey -in ed25519-private.pem -text -noout
```

Ed25519 does not take a separately selected digest parameter like these RSA/ECDSA examples. See [OpenSSL key-type documentation](https://docs.openssl.org/3.5/man7/EVP_PKEY-X25519/).

### Sign using Ed25519

```bash
echo "hello ed25519" > ed-message.txt

openssl pkeyutl \
  -sign \
  -rawin \
  -inkey ed25519-private.pem \
  -in ed-message.txt \
  -out ed-message.sig

openssl pkeyutl \
  -verify \
  -rawin \
  -pubin \
  -inkey ed25519-public.pem \
  -in ed-message.txt \
  -sigfile ed-message.sig

wc -c ed-message.sig
```

Expect 64 signature bytes, regardless of the larger PEM key-container sizes.

### X25519

X25519 is key agreement, not signing. Generate Alice and Bob:

```bash
openssl genpkey -algorithm X25519 -out alice-x25519-private.pem
openssl pkey \
  -in alice-x25519-private.pem \
  -pubout \
  -out alice-x25519-public.pem

openssl genpkey -algorithm X25519 -out bob-x25519-private.pem
openssl pkey \
  -in bob-x25519-private.pem \
  -pubout \
  -out bob-x25519-public.pem
```

Derive from each side:

```bash
openssl pkeyutl \
  -derive \
  -inkey alice-x25519-private.pem \
  -peerkey bob-x25519-public.pem \
  -out alice-secret.bin

openssl pkeyutl \
  -derive \
  -inkey bob-x25519-private.pem \
  -peerkey alice-x25519-public.pem \
  -out bob-secret.bin

sha256sum alice-secret.bin
sha256sum bob-secret.bin
```

They should match. See [OpenSSL X25519 key exchange](https://docs.openssl.org/3.5/man7/EVP_KEYEXCH-X25519/).

### Understand what just happened

```text
Alice private + Bob public → shared secret
Bob private + Alice public → same shared secret
```

A passive observer with only the two public keys cannot feasibly derive the secret. This exchange alone does not authenticate either party; protocols add authentication to prevent an active man-in-the-middle.

```text
Ed25519 → Edwards signature construction → signatures
X25519  → Montgomery X-coordinate construction → key agreement
```

OpenSSL treats them as distinct key types.

## Part 15 — Encryption versus signing versus key agreement

| Operation         | Private key                 | Public key         |
| ----------------- | --------------------------- | ------------------ |
| RSA signature     | Sign                        | Verify             |
| RSA encryption    | Decrypt                     | Encrypt            |
| ECDSA signature   | Sign                        | Verify             |
| Ed25519 signature | Sign                        | Verify             |
| ECDH / X25519     | Derive with peer public key | Exchange with peer |

Modern protocols normally use this shape:

```text
X25519/ECDHE → shared secret → KDF → AES/ChaCha keys → bulk encrypted data
```

---

**Next:** [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook/03-pki-and-tls|PKI and TLS]].
