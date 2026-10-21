---
title: "PKI Operator Runbook 3 — PKI and TLS"
tags: [architecture/cryptography, security/pki, security/tls, security/identity]
date: 2026-10-21
description: "Build a root, intermediate and server certificate with OpenSSL, verify the chain and hostname, serve TLS locally, and understand the TLS 1.3 handshake."
---

# PKI Operator Runbook 3 — PKI and TLS

Parts 16–40: a root → intermediate → leaf CA, chain and hostname verification, PKCS#12, a working TLS server, TLS 1.3, forward secrecy, mTLS, and revocation. Part of the [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook|PKI Operator Runbook]] (3 of 6). Previous: [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook/02-keys-and-signatures|Keys and Signatures]]. Next: [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook/04-ssh-jwt-and-oidc|SSH, JWT and OIDC]].

Commands continue in `~/crypto-lab` from the earlier notes; reapply `umask 077` in each new terminal.

## Part 16 — Certificates

A certificate is not a private key. A simplified X.509 certificate contains:

```text
Certificate
├── Subject (for example CN=server.example.com)
├── Subject public key (RSA / EC / etc.)
├── Issuer
├── Serial number
├── Valid from / valid until
├── Extensions
│   ├── SAN
│   ├── Key Usage
│   ├── Extended Key Usage
│   ├── Basic Constraints
│   ├── SKI
│   └── AKI
└── CA digital signature
```

The private key is not inside a normal public certificate.

## Part 17 — Build your own CA

```bash
cd ~/crypto-lab/07-ca
mkdir -p root intermediate server
```

Build:

```text
Darshan Root CA → Darshan Intermediate CA → api.lab.local
```

This is the same hierarchy shape as a public root → intermediate → website. [RFC 5280](https://www.rfc-editor.org/rfc/rfc5280) defines the X.509 certification-path model. We will prove it with commands.

## Part 18 — Root CA private key

```bash
openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:4096 \
  -out root/root.key

chmod 600 root/root.key
```

Production root CA private keys are extremely sensitive and commonly kept offline or in carefully controlled HSM-backed systems.

## Part 19 — Root certificate

```bash
cat > root/root.cnf <<'EOF'
[req]
prompt = no
distinguished_name = dn
x509_extensions = v3_ca

[dn]
C = IN
ST = Maharashtra
O = Darshan Crypto Lab
CN = Darshan Root CA

[v3_ca]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF

openssl req \
  -x509 \
  -new \
  -key root/root.key \
  -sha256 \
  -days 3650 \
  -config root/root.cnf \
  -out root/root.crt

openssl x509 -in root/root.crt -text -noout
```

Inspect issuer, subject, validity, public key, Basic Constraints, Key Usage, and signature algorithm. The subject and issuer names match, and the certificate is signed using its own corresponding private key: it is self-signed. Matching names alone describe a self-issued certificate and are not proof of self-signing.

## Part 20 — Certificate fingerprint

```bash
openssl x509 \
  -in root/root.crt \
  -noout \
  -fingerprint \
  -sha256
```

This computes `SHA256(DER-encoded certificate bytes)`. It is a compact identifier, not the certificate's encryption algorithm or a hash of the PEM text file.

## Part 21 — Intermediate CA

```bash
openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:3072 \
  -out intermediate/intermediate.key

cat > intermediate/intermediate.cnf <<'EOF'
[req]
prompt = no
distinguished_name = dn

[dn]
C = IN
ST = Maharashtra
O = Darshan Crypto Lab
CN = Darshan Intermediate CA
EOF

openssl req \
  -new \
  -key intermediate/intermediate.key \
  -config intermediate/intermediate.cnf \
  -out intermediate/intermediate.csr

openssl req -in intermediate/intermediate.csr -text -noout
```

## Part 22 — What is a CSR?

A **Certificate Signing Request** broadly contains subject information, a public key, requested attributes/extensions, and a signature made using the applicant's private key. It contains the public key, not the private key.

A valid CSR signature establishes possession of the corresponding private key at signing time; it does not validate the requested identity. The CA must decide which identity and extensions to approve.

```bash
openssl req -in intermediate/intermediate.csr -verify -noout
```

## Part 23 — Root signs intermediate

```bash
cat > intermediate/intermediate-ext.cnf <<'EOF'
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

openssl x509 \
  -req \
  -in intermediate/intermediate.csr \
  -CA root/root.crt \
  -CAkey root/root.key \
  -CAcreateserial \
  -days 1825 \
  -sha256 \
  -extfile intermediate/intermediate-ext.cnf \
  -out intermediate/intermediate.crt

openssl x509 -in intermediate/intermediate.crt -text -noout
```

Look for `CA:TRUE` and `pathlen:0`: the intermediate can issue leaf certificates, but a valid path cannot normally put another non-self-issued intermediate CA beneath it.

The CA signs the new certificate's `TBSCertificate` structure, not the CSR itself.

## Part 24 — Verify intermediate

```bash
openssl verify \
  -CAfile root/root.crt \
  intermediate/intermediate.crt
```

Expect `intermediate/intermediate.crt: OK`. You explicitly trust the root, and verification checks the intermediate's path to it.

## Part 25 — Create server private key

```bash
openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:2048 \
  -out server/server.key
```

Many deployments can use an EC key instead; this lab uses RSA.

## Part 26 — Server CSR

```bash
cat > server/server.cnf <<'EOF'
[req]
prompt = no
distinguished_name = dn
req_extensions = req_ext

[dn]
C = IN
ST = Maharashtra
O = Darshan Crypto Lab
CN = api.lab.local

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = api.lab.local
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF

openssl req \
  -new \
  -key server/server.key \
  -config server/server.cnf \
  -out server/server.csr

openssl req -in server/server.csr -text -noout
```

Find the requested **Subject Alternative Name** extension. Modern hostname verification uses SAN entries such as `DNS:api.example.com`, `DNS:*.example.com`, and `IP:10.0.1.10`. A Common Name alone is not a substitute for SAN.

## Part 27 — Issue server certificate

```bash
cat > server/server-ext.cnf <<'EOF'
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer

[alt_names]
DNS.1 = api.lab.local
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF

openssl x509 \
  -req \
  -in server/server.csr \
  -CA intermediate/intermediate.crt \
  -CAkey intermediate/intermediate.key \
  -CAcreateserial \
  -days 365 \
  -sha256 \
  -extfile server/server-ext.cnf \
  -out server/server.crt

openssl x509 -in server/server.crt -text -noout
```

The explicit extension file determines what the CA puts in the certificate; requested CSR extensions are not automatically trusted.

## Part 28 — Understand major X.509 extensions

### Basic Constraints

`CA:TRUE` permits CA use subject to path-validation rules; `CA:FALSE` is appropriate for this leaf certificate.

### Key Usage

Examples: `digitalSignature`, `keyEncipherment`, `keyCertSign`, `cRLSign`. A CA normally needs `keyCertSign`; a TLS server performing handshake signatures needs `digitalSignature`. `keyEncipherment` relates to uses such as older RSA key transport.

### Extended Key Usage

More specific purposes: `serverAuth`, `clientAuth`, `codeSigning`, `emailProtection`. An mTLS client certificate uses `clientAuth`.

### Subject Key Identifier — SKI

Identifies the subject key, commonly derived from the public key: “This is my key identifier.”

### Authority Key Identifier — AKI

Identifies the issuer key: “The key that signed me has this identifier.” It helps chain building; actual signatures still need verification.

## Part 29 — Verify full chain

This is expected to fail in this lab because the intermediate is missing:

```bash
openssl verify -CAfile root/root.crt server/server.crt
```

Supply it separately:

```bash
openssl verify \
  -CAfile root/root.crt \
  -untrusted intermediate/intermediate.crt \
  server/server.crt
```

Expect `server/server.crt: OK`. Now explicitly check the TLS server purpose and hostname as well:

```bash
openssl verify \
  -CAfile root/root.crt \
  -untrusted intermediate/intermediate.crt \
  -purpose sslserver \
  -verify_hostname api.lab.local \
  server/server.crt
```

```text
api.lab.local → Intermediate CA → Root CA → explicitly trusted locally
```

## Part 30 — Why root trust is special

An attacker can create a root and sign a certificate for somebody else's domain. The signature may be mathematically valid, but the root is not trusted by the client.

```text
cryptographic validity ≠ trust
PKI = cryptography + identity + policy + trust distribution
```

## Part 31 — Prove private key matches certificate

```bash
openssl x509 \
  -in server/server.crt \
  -pubkey \
  -noout \
  > server/cert-public.pem

openssl pkey \
  -in server/server.key \
  -pubout \
  > server/key-public.pem

diff server/cert-public.pem server/key-public.pem
```

No output means the certificate's public key matches the public component derived from the private key. This works across key types and is useful during certificate incident troubleshooting.

## Part 32 — PKCS#12 / PFX

```bash
openssl pkcs12 \
  -export \
  -out server/server.p12 \
  -inkey server/server.key \
  -in server/server.crt \
  -certfile intermediate/intermediate.crt

openssl pkcs12 -in server/server.p12 -info -noout
```

Choose a lab export password. A `.p12`/`.pfx` can carry a private key, leaf certificate, and certificate chain. These bundles are common in Windows/IIS, Java integrations, and enterprise PKI.

OpenSSL 3 protects a new `.p12` with PBKDF2 and AES-256-CBC by default; `-info` shows `PBES2, PBKDF2, AES-256-CBC`. Older importers, such as Windows Server 2016 and earlier or old Java releases, reject that. If one does, re-export with `-legacy` (RC2/3DES and SHA-1), and only for that consumer.

## Part 33 — Certificate chain file

```bash
cat server/server.crt \
    intermediate/intermediate.crt \
    > server/fullchain.pem
```

A server normally presents leaf first, then intermediate(s). Clients already hold the trusted roots; sending a root does not establish trust in it.

## Part 34 — Start your own TLS server

From `~/crypto-lab/07-ca`:

```bash
openssl s_server \
  -accept 127.0.0.1:8443 \
  -cert server/server.crt \
  -key server/server.key \
  -cert_chain intermediate/intermediate.crt \
  -www
```

Leave it running. In a new terminal:

```bash
cd ~/crypto-lab/07-ca
umask 077

openssl s_client \
  -connect 127.0.0.1:8443 \
  -servername api.lab.local \
  -verify_hostname api.lab.local \
  -verify_return_error \
  -CAfile root/root.crt
```

Expect `Verify return code: 0 (ok)`. `-servername` sets SNI; `-verify_hostname` performs the separate identity check. `-verify_return_error` makes certificate verification failures fatal. See [OpenSSL s_client verification options](https://docs.openssl.org/3.5/man1/openssl-s_client/).

You can also make an HTTPS request without editing `/etc/hosts`:

```bash
curl \
  --cacert root/root.crt \
  --resolve api.lab.local:8443:127.0.0.1 \
  https://api.lab.local:8443/
```

Stop `s_client` and the server with Ctrl-C when finished. You have built a PKI and used it in TLS.

## Part 35 — TLS mental model

An RSA server certificate does not mean HTTP requests are RSA-encrypted. A simplified TLS 1.3 certificate-authenticated handshake is:

```text
Client                                      Server
ClientHello
  versions, cipher suites, key share ───────>
                                    <─────── ServerHello + key share
                                    <─────── encrypted handshake:
                                              certificate
                                              CertificateVerify
                                              Finished
client verifies certificate and handshake
client Finished ───────────────────────────>

ephemeral DH/ECDH → shared secret → HKDF → handshake/application keys
HTTP records → AES-GCM or ChaCha20-Poly1305
```

The CA signature on the certificate and the server's handshake signature are separate. The certificate authenticates a public key; the handshake proves possession of its private key. Bulk traffic uses symmetric encryption.

## Part 36 — Inspect a real internet TLS connection

```bash
openssl s_client \
  -connect google.com:443 \
  -servername google.com \
  -verify_hostname google.com \
  -verify_return_error \
  -showcerts
```

Inspect protocol, cipher, certificate chain, issuer, subject, and verification result. This relies on your OpenSSL installation's default trust configuration.

Extract and inspect the leaf:

```bash
openssl s_client \
  -connect google.com:443 \
  -servername google.com \
  -showcerts \
  </dev/null 2>/dev/null |
openssl x509 -text -noout
```

This second pipeline is an inspection exercise; its exit status alone does not establish successful peer verification. Look at subject, issuer, public-key algorithm, signature algorithm, SAN, validity, Key Usage, and EKU.

## Part 37 — TLS cipher-suite naming

```text
TLS_AES_256_GCM_SHA384
    │       │     │
    │       │     └── key schedule / transcript hash
    │       └──────── authenticated-encryption mode
    └──────────────── 256-bit symmetric AES key
```

In TLS 1.3 the suite name does not contain RSA, ECDSA, or ECDHE. Certificate authentication and key-exchange choices are negotiated separately from the cipher suite.

## Part 38 — Perfect Forward Secrecy

If the certificate private key is stolen tomorrow, recorded traffic from yesterday should remain protected when the sessions used ephemeral Diffie-Hellman and the ephemeral secrets were erased.

```text
server certificate private key ≠ ephemeral session secret
```

That property is forward secrecy. It does not protect a session whose ephemeral secrets were captured.

## Part 39 — mTLS

```text
Normal TLS: client verifies server
mTLS:       client verifies server AND server verifies client
```

Each authenticated peer presents a certificate and proves possession of the corresponding private key. This is common in service meshes, Kubernetes, SPIFFE deployments, internal APIs, and zero-trust architectures. Issuing a `clientAuth` certificate and configuring server-side client verification are additional steps beyond this server-only TLS lab.

## Part 40 — Revocation

A private key can be compromised before its certificate expires.

- **CRL — Certificate Revocation List:** a CA publishes revoked certificate serial numbers.
- **OCSP — Online Certificate Status Protocol:** a responder returns certificate status, such as good, revoked, or unknown.

Client behavior and revocation policy matter; checks are not automatic in every tool or deployment. The `openssl verify` commands above do not perform a complete online revocation check by default. OpenSSL provides [CRL and OCSP tooling](https://docs.openssl.org/3.5/man1/).

---

**Next:** [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook/04-ssh-jwt-and-oidc|SSH, JWT and OIDC]].
