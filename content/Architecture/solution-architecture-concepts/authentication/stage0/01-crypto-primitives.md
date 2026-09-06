---
title: "0.1 — Cryptographic Building Blocks for Identity"
author: darshan
tags: [authentication, stage-0, cryptography, hmac, rsa, ecdsa, eddsa, hashing]
date: 2026-06-13
description: Symmetric vs asymmetric, hashing, HMAC, RSA, ECDSA, EdDSA — the cryptographic alphabet every auth engineer needs
---

# 0.1 — Cryptographic Building Blocks for Identity

> **Goal:** Before you can read a JWT spec, debug a "signature invalid" error, or pick between RS256 and EdDSA, you need the cryptographic alphabet. This module covers the minimum viable cryptography for identity work — enough to *understand* what's happening, not enough to design a new cipher (don't do that anyway).

> **Prerequisites:** basic Linux CLI, comfortable reading JSON. No crypto background required.

---

## Table of Contents

1. [The Big Picture: Three Things Crypto Does](#1-the-big-picture-three-things-crypto-does)
2. [Hashing — One-Way Fingerprints](#2-hashing--one-way-fingerprints)
3. [Symmetric Crypto — Same Key, Both Sides](#3-symmetric-crypto--same-key-both-sides)
4. [Asymmetric Crypto — Public Key Goes Out, Private Key Stays Home](#4-asymmetric-crypto--public-key-goes-out-private-key-stays-home)
5. [HMAC — Hashing With a Secret](#5-hmac--hashing-with-a-secret)
6. [Digital Signatures — Asymmetric HMAC](#6-digital-signatures--asymmetric-hmac)
7. [Algorithm Comparison: HS256 / RS256 / ES256 / EdDSA](#7-algorithm-comparison-hs256--rs256--es256--eddsa)
8. [Key Sizes, Security Levels, and "alg=none"](#8-key-sizes-security-levels-and-algnone)
9. [DevOps Analogy: The Mailbox](#9-devops-analogy-the-mailbox)
10. [Attacks & Pitfalls](#10-attacks--pitfalls)
11. [Exercises](#11-exercises)
12. [Next Step](#12-next-step)

---

## 1. The Big Picture: Three Things Crypto Does

Cryptography in identity systems does exactly **three jobs**:

| Job | What it answers | Example |
|-----|-----------------|---------|
| **Integrity** | "Has this message been tampered with?" | JWT signature, TLS MAC |
| **Authenticity** | "Did this message really come from who it claims?" | JWT signature, TLS cert |
| **Confidentiality** | "Can anyone else read this?" | TLS encryption, JWE |

**Hashing** is the foundation for integrity. **HMAC** adds a shared secret. **Digital signatures** swap the shared secret for a public/private key pair. **Encryption** (which we cover only briefly here) is the confidentiality layer.

> **The single most important thing to internalize early:** *encoding is not encryption*. Base64 is encoding — it's a public, reversible representation. AES is encryption — it requires a key. JWTs are **signed**, not encrypted, by default (we'll cover JWE in [[../stage1/05-jose-family|Stage 1.5]]).

```
What JWT actually gives you:
  ✅ Integrity      — the payload hasn't been tampered with
  ✅ Authenticity   — the issuer is who they claim to be
  ❌ Confidentiality — anyone with the token can READ the payload

If you need confidentiality, you need JWE (encrypted JWT), not just JWS.
A signed JWT is a postcard, not a sealed letter.
```

---

## 2. Hashing — One-Way Fingerprints

A **hash function** takes any input and produces a fixed-size output. The output is called a *digest* or *fingerprint*. Good hash functions have three properties:

1. **Deterministic** — same input always produces the same output
2. **Avalanche** — changing one bit of input changes ~50% of output bits
3. **One-way** — given an output, you cannot find the input (within reason)

```
Input: "hello"
SHA-256: 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824

Input: "hellp"  ← one character changed
SHA-256: 98a3a1d4b8c4e0e8c0e8c0e8c0e8c0e8c0e8c0e8c0e8c0e8c0e8c0e8c0e8c0e8
                     ^ completely different output

Input: "the entire works of Shakespeare"
SHA-256: 7d38b5cd25c91e8a4c4e0e8c0e8c0e8c0e8c0e8c0e8c0e8c0e8c0e8c0e8c0e8
                  ← still 64 hex chars (256 bits)
```

**Common hash functions you'll see in auth:**

| Algorithm | Output size | Status | Use in auth |
|-----------|-------------|--------|-------------|
| MD5 | 128 bits | **Broken** | Don't use. Ever. (Legacy certs, file checksums only) |
| SHA-1 | 160 bits | **Broken** | Don't use. (Git still uses SHA-1 for object IDs, but it shouldn't) |
| SHA-256 | 256 bits | **Standard** | JWT (none of the JWS algorithms use bare SHA-256 — they wrap it) |
| SHA-384 | 384 bits | **Standard** | JWT (HS384, RS384) |
| SHA-512 | 512 bits | **Standard** | JWT (HS512, RS512) |
| SHA-3 (Keccak) | 224/256/384/512 | **Standard** | Emerging — preferred for new designs |
| BLAKE2 / BLAKE3 | 256/512 | **Fast, secure** | Used in some modern protocols |

**Why MD5 and SHA-1 are dead for security:**
- **MD5 collisions** (two different inputs producing the same hash) can be generated in seconds on a laptop. It's been broken since 2004.
- **SHA-1 collisions** (SHAttered attack, 2017) cost ~$110K in compute. Theoretically broken, practically still expensive — but the writing's on the wall.

```
Bad:  storing passwords as MD5("hunter2")
      ↓
      attacker with the rainbow table: "hunter2"

Good: storing passwords as bcrypt("hunter2", cost=12)
      ↓
      attacker gets a slow-to-check hash that requires brute force
```

> **Hashing vs encryption, one more time:** hashing is **one-way**. There's no "decrypt" step. If you ever see a product offering "MD5 decryption" — they're either brute-forcing small inputs or running a rainbow table. They haven't broken the math.

### Quick check: does this make sense?

```
Q: I have a SHA-256 hash. Can I recover the original input?
A: No, in general. The only way is to guess inputs and check
   if they produce the same hash. For password storage this is
   why we use slow hashes (bcrypt, scrypt, Argon2) — they make
   each guess expensive.
```

---

## 3. Symmetric Crypto — Same Key, Both Sides

**Symmetric** = both sides use the **same secret key**. The key is shared ahead of time and must be kept secret by everyone who has it.

```
Alice  ────[encrypt with key K]────►  ciphertext  ────[decrypt with key K]────►  Bob
        ◄────[encrypt with key K]────              ◄────[decrypt with key K]────

Both Alice and Bob know K. Eve knows nothing.
```

**Common symmetric algorithms:**

| Algorithm | Key size | Block size | Notes |
|-----------|----------|------------|-------|
| AES-128 | 128 bits | 128 bits | Fast, secure, ubiquitous |
| AES-256 | 256 bits | 128 bits | Higher security margin, slightly slower |
| ChaCha20 | 256 bits | stream cipher | Faster than AES on CPUs without AES-NI |
| 3DES | 168 bits | 64 bits | **Deprecated** — slow, 64-bit block is too small |

**The key distribution problem:** if Alice and Bob need to talk, they need a shared key. But how do they get it to each other securely? This is the problem asymmetric crypto solves (Section 4), and the reason TLS uses *both* — asymmetric to exchange a symmetric key, symmetric for the bulk of the traffic.

**For identity/auth specifically:** symmetric crypto is used inside **HMAC** (Section 5) and inside **TLS** (after the handshake). You almost never see raw symmetric encryption in identity protocols — that's the asymmetric layer's job.

```
TLS handshake in 30 seconds:
  1. Client says hello, lists cipher suites
  2. Server replies with cert (asymmetric public key)
  3. Client verifies cert against trusted CA
  4. Client generates a random "pre-master secret"
  5. Client encrypts pre-master secret with server's public key
  6. Server decrypts with private key
  7. Both sides derive the same symmetric session keys from pre-master
  8. All further traffic uses symmetric crypto (AES-GCM, ChaCha20)
  
  Asymmetric crypto is expensive. Symmetric crypto is cheap.
  TLS uses both, for exactly this reason.
```

---

## 4. Asymmetric Crypto — Public Key Goes Out, Private Key Stays Home

**Asymmetric** = a **key pair** — a public key (shared freely) and a private key (kept secret). What one key does, only the other can undo.

```
Two things you can do with a key pair:
  ENCRYPTION:    public key encrypts, private key decrypts
                 (anyone can send you a secret; only you can read it)
  
  SIGNING:       private key signs, public key verifies
                 (only you can sign; anyone can verify)
```

Notice the symmetry: encryption uses the *other person's* public key; signing uses *your own* private key. This trips up a lot of beginners. Memorize it:

```
To encrypt FOR Alice:  use Alice's PUBLIC key
To sign AS Alice:      use Alice's PRIVATE key

To decrypt as Alice:   use Alice's PRIVATE key
To verify Alice's sig: use Alice's PUBLIC key
```

### The three asymmetric families you'll meet

| Family | Key sizes (security equivalent) | Speed | Key/sig size | Notes |
|--------|--------------------------------|-------|--------------|-------|
| **RSA** | 2048, 3072, 4096 bits | Slow keygen, fast sign/verify | Big keys, big signatures | The old workhorse. Compatible with everything. |
| **ECDSA** | 256, 384, 521 bits | Fast | Small keys, small signatures | P-256, P-384, P-521 curves. NIST standardized. |
| **EdDSA** | 256, 456 bits | Very fast | Tiny keys, tiny signatures | Ed25519 (signing), Ed448. No random nonce needed. **Modern default.** |
| **Post-quantum** | varies | varies | large | Kyber, Dilithium, Falcon. New (2024+), early adoption. |

**For identity/auth in 2026:** EdDSA (Ed25519) is the modern default for new systems. RS256 is still the universal fallback because every library on Earth supports it. ES256 is in between.

```
Why you should care about key/sig size:
  
  RS256:  2048-bit key, 256-byte signature
  ES256:  256-bit key,  64-byte signature
  EdDSA:  256-bit key,  64-byte signature
  
  If you're verifying 10,000 JWTs/sec at the edge, the size matters.
  If you're verifying 10/sec on a backend, it doesn't.
  
  ES256 and EdDSA give you 32x smaller keys than RS256 with
  the same security level. That's why they're winning.
```

### How RSA works (the 2-minute version)

You don't need to know the math. You need to know:
- **Key generation** picks two large primes, multiplies them, derives the public/private pair from the result
- **Signing** = compute `signature = message^d mod n` (with private exponent `d`)
- **Verification** = check if `signature^e mod n == message_hash` (with public exponent `e`)
- **Security** depends on the difficulty of factoring the product of the two primes
- 2048-bit RSA = ~112 bits of symmetric security (per NIST 2020 guidelines)
- 3072-bit RSA = ~128 bits
- 4096-bit RSA = ~150 bits

### How ECDSA works (the 2-minute version)

- A curve is defined (e.g., `secp256r1` aka P-256)
- Private key = random integer in the curve's order
- Public key = a point on the curve, derived by multiplying a base point by the private key
- Signing = compute a point `(r, s)` based on the message hash, private key, and a **random nonce**
- Verification = check that `(r, s)` is consistent with the public key and the message hash

**Critical ECDSA gotcha:** the **random nonce** in ECDSA signing must be truly random. Reusing a nonce across two signatures leaks the private key. Sony PS3 learned this the hard way (their code signing key was extracted this way in 2010).

```
ECDSA nonce reuse → private key leak

This is why EdDSA exists. EdDSA derives the nonce deterministically
from the private key and the message — no random number generator
needed, no nonce-reuse attack possible.
```

### How EdDSA works (the 2-minute version)

- Uses a twisted Edwards curve (Ed25519 = specific curve)
- Private key = 32 random bytes
- Public key = 32 bytes, derived from private key via scalar multiplication
- Signature = 64 bytes (R, s) computed deterministically
- Verification = one scalar multiplication + one point addition

EdDSA is what you should reach for in new systems unless you have a hard compatibility constraint.

---

## 5. HMAC — Hashing With a Secret

**HMAC (Hash-based Message Authentication Code)** = hash a message with a secret key. Produces a tag that proves the message came from someone who knew the key.

```
HMAC-SHA256(message, key) → 32-byte tag

Properties:
  - Only someone with the key can produce a valid tag
  - Anyone with the key can verify a tag
  - The tag is NOT recoverable from the message alone (one-way)
```

**This is what JWT's HS256/HS384/HS512 use.**

```python
import hmac, hashlib

key = b"super-secret-shared-key"
msg = b"hello world"

# Compute HMAC
tag = hmac.new(key, msg, hashlib.sha256).hexdigest()
print(tag)
# Output: 9307b3b915efb5171ff14d8cb55fbcc798c6aabdcebec45e210b811cb0b48271

# Verify HMAC
expected = hmac.new(key, msg, hashlib.sha256).hexdigest()
if hmac.compare_digest(tag, expected):
    print("valid")
```

**Why HMAC and not just `hash(key + message)`?** Because of **length extension attacks**. If you compute `SHA256(key || message)`, an attacker who knows `SHA256(key || message)` (but not the key) can compute `SHA256(key || message || extra)` for any `extra`. HMAC's construction (two rounds of hashing with the key in different positions) defeats this.

```
NEVER do this:  signature = SHA256(key || message)   # length extension
DO this:         signature = HMAC-SHA256(key, message)  # constant-time, no extension
```

**Constant-time comparison:** use `hmac.compare_digest(a, b)`, not `a == b`. The latter short-circuits on the first byte mismatch, which leaks information about the signature via timing. This is a real attack against poorly-implemented validators.

---

## 6. Digital Signatures — Asymmetric HMAC

A **digital signature** is HMAC's asymmetric cousin. Instead of a shared secret, you use a key pair:

```
SIGN:
  signature = sign(private_key, message)
  
VERIFY:
  valid = verify(public_key, message, signature)
```

This is what JWT's RS256, ES256, EdDSA use.

**The asymmetry of trust:**

```
Symmetric (HMAC):
  - Issuer and verifier MUST share the same secret
  - If the secret leaks at the verifier, attacker can forge tokens
  - Cheaper, smaller signatures
  
Asymmetric (signatures):
  - Issuer signs with private key (only they have it)
  - Verifier needs ONLY the public key
  - Public key can be distributed freely — no leak risk
  - Bigger keys, bigger signatures, more CPU
```

**This is why OIDC's JWKS exists:** the IdP publishes its public key(s) at a well-known URL. Verifiers fetch them. The IdP never has to share a secret with anyone. If you rotate the key, you publish the new public key, the verifiers refresh, the old key gets retired. Done.

```
HS256 flow (symmetric):
  IdP ──[sign with shared secret]──► token
  Verifier ──[verify with SAME shared secret]──► valid
  Problem: verifier has the secret. If verifier is compromised, attacker forges.

RS256 flow (asymmetric):
  IdP ──[sign with private key]──► token
  Verifier ──[verify with public key]──► valid
  IdP publishes public key at /.well-known/jwks.json
  Verifier fetches, caches, uses. Never sees private key.
```

---

## 7. Algorithm Comparison: HS256 / RS256 / ES256 / EdDSA

This is the matrix you'll reference every time you choose a JWT algorithm. Memorize it.

| Algorithm | Type | Key size | Signature size | Sign speed | Verify speed | Use it when |
|-----------|------|----------|----------------|------------|--------------|-------------|
| **HS256** | HMAC + SHA-256 | 256+ bits | 32 bytes | Fast | Fast | Single service, never crosses a trust boundary |
| **HS384** | HMAC + SHA-384 | 384+ bits | 48 bytes | Fast | Fast | Same as HS256, paranoia mode |
| **HS512** | HMAC + SHA-512 | 512+ bits | 64 bytes | Fast | Fast | Same as HS256, more paranoia |
| **RS256** | RSA + SHA-256 | 2048+ bits | 256 bytes | Slow | Slow | Universal compatibility, legacy interop |
| **RS384** | RSA + SHA-384 | 2048+ bits | 256 bytes | Slow | Slow | Same as RS256, paranoia mode |
| **RS512** | RSA + SHA-512 | 2048+ bits | 256 bytes | Slow | Slow | Same as RS256, more paranoia |
| **ES256** | ECDSA + SHA-256 (P-256) | 256 bits | 64 bytes | Fast | Fast | Modern default, smaller than RS256 |
| **ES384** | ECDSA + SHA-384 (P-384) | 384 bits | 96 bytes | Fast | Fast | Same as ES256, paranoia mode |
| **ES512** | ECDSA + SHA-512 (P-521) | 521 bits | 132 bytes | Fast | Fast | Same as ES256, more paranoia |
| **PS256** | RSA-PSS + SHA-256 | 2048+ bits | 256 bytes | Slow | Slow | When you need RSA + better padding than PKCS#1 v1.5 |
| **EdDSA** | Ed25519 | 256 bits | 64 bytes | Very fast | Very fast | **New systems. This is the default for 2026.** |
| **none** | (no signature) | N/A | N/A | N/A | N/A | **NEVER ACCEPT THIS. EVER.** |

### The "alg=none" attack — why this row exists

Older JWT libraries had a default that, if the token's `alg` header said `"none"`, the library would skip signature verification entirely. This was meant for debugging. It became the most catastrophic auth vulnerability of the 2010s.

```
Attack in 4 lines:

# Attacker takes a valid JWT
valid_jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhZG1pbiJ9.signature"

# Decodes the payload, changes "sub" to "admin"
import base64, json
header  = base64.urlsafe_b64encode(b'{"alg":"none","typ":"JWT"}').rstrip(b'=')
payload = base64.urlsafe_b64encode(b'{"sub":"admin"}').rstrip(b'=')

# Crafts a token with alg=none and NO signature
forged = f"{header.decode()}.{payload.decode()}."

# Server accepts it. Game over.
```

**The fix:** every JWT validator MUST enforce an algorithm allowlist. Never trust the `alg` header from the token. See [[../stage1/03-validation|Stage 1.3 — JWT Validation]] for the full check sequence.

### When to pick which

```
Just you, one service, no external verifiers?
  → HS256 with a 32-byte random secret. Stop overthinking.

Interop with third parties, public verifiers, OIDC?
  → RS256 (universal) or ES256 (modern) or EdDSA (cutting edge)

Building a new system in 2026, full control?
  → EdDSA. Modern libraries support it, key/sig are tiny, no nonce drama.

Regulated industry (finance, healthcare, gov)?
  → Check your compliance regime. FAPI 2.0 mandates PS256 or ES256.
     (See [[../stage6/04-emerging-standards|Stage 6.4]].)
```

### Performance reality check

```
Benchmark: 10,000 JWT verifications

  HS256:   0.12s   ← fastest
  EdDSA:   0.15s   ← tiny keys, fast verify
  ES256:   0.25s
  RS256:   2.5s    ← 10-20x slower than ES256/EdDSA
  
If you're verifying tokens in a hot path, this matters.
If you're verifying one token per user session, it doesn't.
```

---

## 8. Key Sizes, Security Levels, and "alg=none"

### NIST security levels (2020+ guidelines)

| Security level | Symmetric equivalent | RSA | ECDSA | EdDSA | Use when |
|----------------|---------------------|-----|-------|-------|----------|
| 112-bit | 3DES (legacy) | 2048 bits | P-224 (avoid) | Ed448 | Legacy interop, minimum bar |
| 128-bit | AES-128 | 3072 bits | P-256 | Ed25519 | **Standard for new systems** |
| 192-bit | AES-192 | 7680 bits | P-384 | (none standard) | High-value, long-term |
| 256-bit | AES-256 | 15360 bits | P-521 | (none standard) | Paranoid / classified |

**128-bit security is the right target for new systems in 2026.** That's P-256 (ES256) or Ed25519 (EdDSA) or RSA-3072. Anything weaker is below current best practice.

### Key generation: how strong is "strong enough"?

```python
# Python: generate a 256-bit (32-byte) random key for HS256
import secrets
hs256_key = secrets.token_bytes(32)
print(hs256_key.hex())
# Output: 8f3a2b1c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a
```

```bash
# OpenSSL: generate an RSA-2048 private key
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out rsa.pem

# OpenSSL: generate an EC P-256 private key
openssl ecparam -name prime256v1 -genkey -noout -out ec.pem

# OpenSSL: generate an Ed25519 private key
openssl genpkey -algorithm Ed25519 -out ed.pem
```

**The cardinal sin:** using a predictable "key" like `"secret"`, `"mycompanyname"`, or `"password123"`. JWT libraries will accept these. They are not secret. If your private key is a word from a dictionary, an attacker has already won.

---

## 9. DevOps Analogy: The Mailbox

Imagine an office building with a row of mailboxes. Each mailbox has:
- A **slot** anyone can drop mail into (this is your **public key**)
- A **lock** only the owner can open (this is your **private key**)

| Crypto operation | Mailbox equivalent |
|------------------|--------------------|
| **Hashing a message** | A unique tracking number printed on the envelope. Anyone can read it, no one can forge it. |
| **HMAC with shared secret** | A wax seal. The sender and receiver share the same seal stamp. If the seal is intact, it's from someone with the seal. |
| **Encryption with public key** | Anyone can drop a sealed letter into your slot. Only you can open it (private key). |
| **Signing with private key** | You put your unique wax seal on a letter. Anyone can verify the seal is yours, but only you can apply it. |
| **TLS handshake** | A courier shows ID, you verify it's really FedEx (cert chain), FedEx gives you a one-time combo for a lockbox, all future deliveries use the combo. |

**The TL;DR for sysadmins:**
- **Hashing** = checksum, but cryptographic
- **HMAC** = checksum + secret, both sides share the secret
- **Signing** = checksum + secret, but only one side has the secret (the signer)
- **Encryption** = lockbox, only the private key holder can open

If you understand `sha256sum file.iso` (integrity check) and `gpg --verify file.sig` (signature check), you already understand the concepts — these modules are just formalizing what your tools already do.

---

## 10. Attacks & Pitfalls

The cryptographic primitives are sound. The implementations are where things break. Here are the attacks you'll see in the wild.

### A1. `alg=none` (already covered)
Don't accept tokens where the `alg` header is `"none"`. Don't accept tokens where the `alg` is one your service didn't issue. **Allowlist, don't denylist.**

### A2. Algorithm confusion (HS256 vs RS256)

```
Scenario:
  - IdP issues RS256 tokens, publishes public key at JWKS
  - Your service verifies with that public key
  - Attacker crafts a token with alg=HS256
  - Attacker uses the IdP's PUBLIC KEY as the HMAC secret
  - Buggy validator sees alg=HS256, expects a shared secret,
    uses the public key (which it has!) as the secret
  - Signature verifies. Game over.
```

**Fix:** the validator pins the expected algorithm. RS256 means RSA verify with public key. HS256 means HMAC verify with shared secret. Never let the token's `alg` header change which path the validator takes.

### A3. ECDSA nonce reuse

```
If two ECDSA signatures use the same nonce (k):
  r1 == r2 (same R component)
  → attacker algebraically derives the private key
```

**Why EdDSA exists:** it derives the nonce deterministically from `(private_key, message)`. No randomness, no reuse possible. **Use EdDSA unless you have a reason not to.**

### A4. Weak random number generation

```
Bad:  nonce = int(time.time())              # predictable
Bad:  key = hashlib.md5(b"my-seed").digest() # brute-forceable
Good: key = secrets.token_bytes(32)         # cryptographically random
Good: nonce = os.urandom(32)                # cryptographically random
```

`random.random()` is a Mersenne Twister — fast, NOT cryptographically secure. Use `secrets` (Python) or `crypto.randomBytes` (Node) or `crypto/rand` (Go). For ECDSA, use a library that gets this right (e.g., `cryptography` in Python, `crypto/ecdsa` in Go).

### A5. Padding oracle (RSA-PKCS1-v1.5)

```
RSA-PKCS1-v1.5 (used by RS256) has a padding oracle attack
where an attacker can decrypt a ciphertext one byte at a time
by observing whether the server returns "decryption error" or
"padding error" with different timing.

RSA-PSS (used by PS256) is provably secure against this.
Use PS256 if you're starting fresh with RSA.
```

### A6. Side-channel timing attacks

```
signature1 = "abcdef..."  (correct first 6 bytes)
signature2 = "abcdez..."  (wrong at byte 6)

If your validator does `if token_sig == expected_sig`:
  - signature1 takes slightly longer to fail (matches 6 bytes)
  - signature2 fails faster (matches 5 bytes)
  - Attacker measures timing → recovers signature byte-by-byte

If your validator does `hmac.compare_digest(token_sig, expected_sig)`:
  - Both take the same time regardless of match length
  - No information leak
```

**Always use constant-time comparison.** This is built into every standard library, so you have to go out of your way to do it wrong. But people do.

### A7. Quantum threat (forward-looking)

```
Shor's algorithm (1994) breaks RSA, ECDSA, EdDSA in polynomial time
on a sufficiently large quantum computer.

Grover's algorithm halves the effective security of symmetric crypto
(AES-256 stays secure, AES-128 stays secure in practice, AES-256
becomes the new AES-128).

Status: no quantum computer large enough exists (as of 2026).
But: "harvest now, decrypt later" attacks mean data encrypted
today with RSA could be decrypted in 10-20 years.

NIST post-quantum standards (FIPS 203/204/205, 2024):
  - ML-KEM (Kyber)      → key exchange
  - ML-DSA (Dilithium)  → signatures
  - SLH-DSA (SPHINCS+)  → hash-based signatures (fallback)

For JWTs: hybrid signatures (classical + PQ) are emerging.
For your 2026 systems: stay on EdDSA, plan migration to ML-DSA
when your IdP supports it.
```

### A8. The "I implemented my own crypto" trap

```
DO NOT implement your own crypto. DO NOT.
Use vetted libraries:
  - Python:    cryptography, PyNaCl, josecrypto
  - Go:        crypto/* stdlib, golang.org/x/crypto
  - Node:      node:crypto (built-in), jose
  - Java:      javax.crypto, BouncyCastle
  - Rust:      ring, rustls, signature crate
```

Every year, a security firm publishes a "Don't Roll Your Own Crypto" paper full of CVEs from custom implementations. Don't be in that paper.

---

## 11. Exercises

These are ordered roughly easiest → hardest. Do them in order.

### Exercise 1: Hash a file
```bash
echo "hello world" > /tmp/hello.txt
sha256sum /tmp/hello.txt
```
Change one character, re-hash. Confirm the output is completely different. That's the avalanche property.

### Exercise 2: Generate a strong key
```python
import secrets
key = secrets.token_bytes(32)
print(f"HS256 key (hex): {key.hex()}")
print(f"HS256 key length: {len(key)*8} bits")
```
What happens if you change `32` to `16`? To `8`? What's the trade-off?

### Exercise 3: HMAC sign and verify
```python
import hmac, hashlib

key = b"my-very-secret-key-32-bytes-long-ok"
msg = b"user=alice&action=delete&resource=db"

# Sign
sig = hmac.new(key, msg, hashlib.sha256).hexdigest()
print(f"Signature: {sig}")

# Verify
expected = hmac.new(key, msg, hashlib.sha256).hexdigest()
print(f"Valid: {hmac.compare_digest(sig, expected)}")

# Tamper
msg_tampered = b"user=alice&action=delete&resource=ALL-DATA"
expected_tampered = hmac.new(key, msg_tampered, hashlib.sha256).hexdigest()
print(f"Tampered valid: {hmac.compare_digest(sig, expected_tampered)}")
```
Expected: last line prints `False`.

### Exercise 4: Generate all four key types
```bash
# RSA
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out rsa.pem
openssl rsa -in rsa.pem -pubout -out rsa.pub

# EC P-256
openssl ecparam -name prime256v1 -genkey -noout -out ec.pem
openssl ec -in ec.pem -pubout -out ec.pub

# Ed25519
openssl genpkey -algorithm Ed25519 -out ed.pem
openssl pkey -in ed.pem -pubout -out ed.pub

ls -la *.pem *.pub
# Notice: EC and Ed keys are TINY compared to RSA. That's the whole point.
```

### Exercise 5: The `alg=none` attack (and the fix)
```python
import base64, json, hmac, hashlib

key = b"my-secret"

def b64url(b):
    return base64.urlsafe_b64encode(b).rstrip(b'=').decode()

# Legitimate token
header = b64url(json.dumps({"alg":"HS256","typ":"JWT"}).encode())
payload = b64url(json.dumps({"sub":"alice","role":"user"}).encode())
sig = b64url(hmac.new(key, f"{header}.{payload}".encode(), hashlib.sha256).digest())
legit = f"{header}.{payload}.{sig}"
print(f"Legit: {legit}")

# Forged token with alg=none
forged_header = b64url(json.dumps({"alg":"none","typ":"JWT"}).encode())
forged_payload = b64url(json.dumps({"sub":"alice","role":"admin"}).encode())
forged = f"{forged_header}.{forged_payload}."

# Buggy validator (DO NOT USE)
def buggy_verify(token):
    h, p, s = token.split(".")
    algo = json.loads(base64.urlsafe_b64decode(h + "==").decode())["alg"]
    if algo == "none":
        return True  # ← THE BUG
    return hmac.compare_digest(s, b64url(hmac.new(key, f"{h}.{p}".encode(), hashlib.sha256).digest()))

# Safe validator
def safe_verify(token, allowed_algs={"HS256"}):
    h, p, s = token.split(".")
    algo = json.loads(base64.urlsafe_b64decode(h + "==").decode())["alg"]
    if algo not in allowed_algs:
        return False
    if algo == "HS256":
        return hmac.compare_digest(s, b64url(hmac.new(key, f"{h}.{p}".encode(), hashlib.sha256).digest()))
    return False

print(f"\nForged: {forged}")
print(f"Buggy validator accepts forged: {buggy_verify(forged)}")  # True
print(f"Safe validator accepts forged:  {safe_verify(forged)}")     # False
```

### Exercise 6: Read the source of one crypto library
Pick `python-jose` or `jose` (Node) or `golang-jwt/jwt`. Find the code that handles the `alg` header. Confirm it has an algorithm allowlist. (If it doesn't, find a better library — and submit a CVE.)

### Exercise 7: Calculate the security level of your current keys
Look at your production keys (if you have any — this is a thought exercise). What algorithm? What key size? Per NIST 2020, what's the effective symmetric security level? Is it >= 128 bits? If not, plan a migration.

### Exercise 8: Design a JWT algorithm choice for a new system
Pick one of these scenarios and justify your choice in 1-2 paragraphs:
- (a) Internal microservice auth, all services in your VPC, you control the issuer
- (b) Public API with 1000+ third-party developers verifying your tokens
- (c) Banking app, FAPI 2.0 compliance required
- (d) IoT device fleet, 10M devices, firmware-signed updates

---

## 12. Next Step

You now have the alphabet. Next we put it together into the most-used token format in identity: JWT.

→ [[../stage1/01-jwt-anatomy|Stage 1.1 — JWT Anatomy: Header.Payload.Signature]]

**Before you move on, verify you can answer these without looking back:**
1. What's the difference between HS256 and RS256? When do you pick each?
2. Why is `alg=none` dangerous? What's the fix?
3. What's ECDSA nonce reuse, and why does EdDSA not have this problem?
4. Why is `==` wrong for comparing signatures? What do you use instead?
5. What are the three things crypto gives you, and which one does JWT NOT give you by default?

If any of those are fuzzy, re-read that section. If they're solid, on to JWT.
