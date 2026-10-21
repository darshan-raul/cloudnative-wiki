---
title: "PKI Operator Runbook 1 — Foundations"
tags: [architecture/cryptography, security/pki, security/tls, security/identity]
date: 2026-10-21
description: "Set up the lab, then work through bytes, Base64, randomness, SHA-256, HMAC, password KDFs, AES, and the asymmetric-crypto overview."
---

# PKI Operator Runbook 1 — Foundations

Lab 0 and Parts 1–7: bytes, encodings, randomness, hashes, HMAC, password KDFs, and symmetric and asymmetric encryption. Part of the [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook|PKI Operator Runbook]] (1 of 6). Next: [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook/02-keys-and-signatures|Keys and Signatures]].

## Lab 0 — Build your playground

Use a disposable directory. Restrict newly created private files before generating keys:

```bash
mkdir -p ~/crypto-lab
cd ~/crypto-lab
umask 077

sudo apt update
sudo apt install -y \
  openssl \
  gnupg \
  jq \
  curl \
  xxd \
  python3 \
  openssh-client
```

Check everything:

```bash
openssl version -a
gpg --version
jq --version
curl --version
```

Create directories:

```bash
mkdir -p \
  01-encoding \
  02-hashing \
  03-symmetric \
  04-rsa \
  05-ec \
  06-signatures \
  07-ca \
  08-tls \
  09-jwt \
  10-oidc \
  11-gpg
```

In new terminals, reapply `umask 077`. For GPG, use a separate keyring so test keys stay isolated:

```bash
export GNUPGHOME="$HOME/crypto-lab/11-gpg/gnupg"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"
```

## Part 1 — Bits, bytes, hex, Base64

Do not skip this. A lot of crypto confusion is actually **encoding confusion**.

### 1.1 Bit versus byte

```text
bit = 0 or 1
byte = 8 bits

256 bits = 32 bytes
128 bits = 16 bytes
512 bits = 64 bytes
2048 bits = 256 bytes
```

A 2048-bit RSA key does not mean a 2048-byte key. It describes the RSA modulus bit length, not the serialized file size.

### 1.2 ASCII/UTF-8 bytes

```bash
cd ~/crypto-lab/01-encoding
printf 'hello' > hello.txt
xxd hello.txt
```

The bytes are:

```text
68 65 6c 6c 6f

h = 0x68
e = 0x65
l = 0x6c
l = 0x6c
o = 0x6f
```

Hex is a way of displaying bytes. One hex digit represents four bits, so **two hex characters represent one byte**.

### 1.3 Base64

```bash
printf 'hello' | base64
printf 'aGVsbG8=' | base64 -d
```

The first prints `aGVsbG8=`; the second prints `hello`. Base64 is encoding, not encryption, hashing, or compression. Anyone can reverse it.

### 1.4 Why Base64 exists

Binary bytes do not always travel conveniently through JSON, XML, HTTP headers, email, text files, or URLs:

```text
binary bytes → Base64 encoding → printable characters
```

### 1.5 Base64url

JWT uses **Base64url**, with these differences from ordinary Base64:

```text
Base64       Base64url
+            -
/            _
= padding    omitted in compact JWS segments
```

See it on bytes that produce `+`, `/` and padding:

```bash
printf '\xfb\xff\xbf' | base64                                  # +/+/
printf '\xfb\xff\xbf' | base64 | tr '+/' '-_'                   # -_-_
printf '\xfb\xff' | base64                                      # +/8=
printf '\xfb\xff' | base64 | tr '+/' '-_' | tr -d '='           # -_8
```

The JWT labs use the same `tr` pipeline as a Base64url helper.

## Part 2 — Randomness and entropy

Before keys, understand where keys come from.

```bash
# Raw bytes, piped through xxd so the terminal stays readable
openssl rand 32 | xxd

# Same number of random bytes, displayed as hex
openssl rand -hex 32
openssl rand -hex 32 | wc -c
```

The count is 65: 32 bytes × two hex characters = 64 characters, plus a newline. The random value contains 256 bits, assuming good cryptographic randomness.

A private value such as `00000000000000000000000000000001` may fit some mathematical structures but is easy to guess. Security depends on unpredictability:

```text
key security = algorithm + key size + correct implementation
             + good randomness + safe storage
```

## Part 3 — Hashing

```bash
cd ~/crypto-lab/02-hashing
printf 'hello' > message.txt
```

### 3.1 SHA-256

```bash
sha256sum message.txt
sha256sum message.txt | awk '{print $1}' | wc -c
```

The digest starts with `2cf24dba5fb0a30e26e83b2ac5b9e29e`. The character count is 65 including the newline:

```text
SHA-256 → 256 bits output → 32 bytes → 64 hexadecimal characters
```

The 256 means digest output length, not a key size, round count, or character count.

### 3.2 Same input = same output

```bash
sha256sum message.txt
sha256sum message.txt
sha256sum message.txt
```

Hashing is deterministic.

### 3.3 Tiny input difference, huge output difference

```bash
printf 'hello' | sha256sum
printf 'Hello' | sha256sum
```

The avalanche effect means one changed input bit tends to change roughly half the output bits.

### 3.4 Fixed-size output

```bash
printf 'a' | sha256sum
head -c 1000000 /dev/zero | sha256sum
```

Both digests are 256 bits. Hash functions map arbitrary-sized messages to fixed-sized digests:

```text
1 byte / 1 KB / 1 GB / an entire ISO → SHA-256 → 256 bits
```

### 3.5 SHA-512

```bash
printf 'hello' | sha512sum
printf 'hello' | sha512sum | awk '{print $1}' | wc -c
```

Expect 129 including the newline: 512 bits = 64 bytes = 128 hex characters.

### 3.6 Hashing is not encryption

There is no decryption key for SHA-256. Hashing is designed to be one-way; low-entropy inputs can still be guessed and hashed for comparison.

### 3.7 Preimage versus collision

**Preimage attack:** given `H(x)`, find an input mapping to that digest. An ideal 256-bit hash requires about `2^256` generic work.

**Collision attack:** find any `x != y` with `H(x) = H(y)`. The birthday bound gives about `2^128` generic work for an ideal 256-bit hash. Its output remains 256 bits; this does not make it a “128-bit hash.”

### 3.8 Checksum use case

```bash
echo 'package version 1' > package.tar
sha256sum package.tar > package.sha256
sha256sum -c package.sha256

echo attacker >> package.tar
sha256sum -c package.sha256
```

The second verification fails. But an attacker who replaces the file might also replace its checksum. A checksum establishes integrity relative to an expected digest; authenticity depends on trusting that expected digest. This is why signatures exist.

## Part 4 — MACs and HMAC

One step between hashes and digital signatures:

```bash
SECRET=$(openssl rand -hex 32)
echo "transfer INR 100" > payment.txt
openssl dgst -sha256 -hmac "$SECRET" payment.txt

echo "transfer INR 100000" > payment.txt
openssl dgst -sha256 -hmac "$SECRET" payment.txt
```

The MAC changes. Here `-hmac` uses the generated hex string as a text key.

```text
Hash:  message → SHA-256 → digest             anyone can calculate
HMAC:  message + secret → HMAC-SHA256 → MAC   requires the secret
```

HMAC uses a shared secret. Alice and Bob can both create a MAC, so Bob cannot use it to prove to a third party that only Alice could have produced it.

With a digital signature, Alice signs using her private key and Bob verifies using her public key. Verification does not give Bob the ability to sign. This explains the later distinction between `HS256` and `RS256`.

## Part 5 — Password hashing and KDFs

Do not normally store `SHA256(password)`. SHA-256 is fast, which helps attackers test guesses.

Password hashing intentionally makes guesses expensive. Families include PBKDF2, bcrypt, scrypt, and Argon2:

```text
password + salt + cost parameters → expensive computation → derived value
```

A unique salt prevents equal passwords from producing equal stored values and defeats simple precomputed rainbow tables. Salts are normally public; they do not replace a strong password or appropriate cost parameters.

## Part 6 — Symmetric encryption

```bash
cd ~/crypto-lab/03-symmetric
echo "production database password" > secret.txt

openssl enc \
  -aes-256-cbc \
  -salt \
  -pbkdf2 \
  -in secret.txt \
  -out secret.enc

xxd secret.enc | head

openssl enc \
  -d \
  -aes-256-cbc \
  -pbkdf2 \
  -in secret.enc \
  -out recovered.txt

cat recovered.txt
```

Enter the same lab password for encryption and decryption.

### What AES-256 means

AES supports 128-, 192-, and 256-bit keys. AES-256 uses a 256-bit/32-byte key. **AES always has a 128-bit block size**, including AES-256.

### CBC versus modern authenticated encryption

This CBC exercise demonstrates encryption and decryption; it does not authenticate the ciphertext. Modern protocols use authenticated encryption with associated data (**AEAD**), such as AES-GCM or ChaCha20-Poly1305, for confidentiality and integrity/authenticity. TLS 1.3 uses AEAD cipher suites.

## Part 7 — Asymmetric cryptography

```text
PRIVATE KEY — secret
     │ mathematically related
PUBLIC KEY  — distributable
```

Do not assume every keypair can do everything:

```text
RSA      → signatures or encryption, using appropriate schemes
ECDSA    → signatures
Ed25519  → signatures
ECDH     → key agreement
X25519   → key agreement
```

---

**Next:** [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook/02-keys-and-signatures|Keys and Signatures]].
