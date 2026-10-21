---
title: "PKI Operator Runbook 4 — SSH, JWT and OIDC"
tags: [architecture/cryptography, security/pki, security/tls, security/identity]
date: 2026-10-21
description: "Create SSH keys, build and verify an RS256 JWT by hand, read JWKS and OIDC discovery documents, and learn what token validation must check."
---

# PKI Operator Runbook 4 — SSH, JWT and OIDC

Parts 41–59: SSH keys, a hand-built RS256 JWT, JWK/JWKS, OAuth 2.0 versus OIDC, discovery, and token validation. Part of the [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook|PKI Operator Runbook]] (4 of 6). Previous: [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook/03-pki-and-tls|PKI and TLS]]. Next: [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook/05-openpgp|OpenPGP and GPG]].

Commands continue in `~/crypto-lab` from the earlier notes; reapply `umask 077` in each new terminal.

## Part 41 — SSH keys

SSH is not normally X.509 PKI, but uses the same asymmetric concepts:

```bash
ssh-keygen \
  -t ed25519 \
  -f ~/crypto-lab/ssh-demo \
  -C "crypto-lab"

cat ~/crypto-lab/ssh-demo.pub
ssh-keygen -lf ~/crypto-lab/ssh-demo.pub
```

`ssh-demo` is the private key; `ssh-demo.pub` is the public key. In typical public-key authentication, the server stores the public key in `~/.ssh/authorized_keys`. The client signs protocol data to prove possession of the private key; it does not send the private key to the server.

## Part 42 — JWT

```bash
cd ~/crypto-lab/09-jwt
```

A signed JWT normally uses compact JWS serialization:

```text
HEADER.PAYLOAD.SIGNATURE
```

JWS defines the protected header, payload, and signature/MAC structure, using Base64url. See [RFC 7515](https://www.rfc-editor.org/rfc/rfc7515). JWTs can also use encrypted JWE representations; the following labs use signed, readable tokens.

## Part 43 — JWT isn't encryption

A payload such as this is readable by anyone who receives a signed token:

```json
{
  "sub": "darshan",
  "role": "admin"
}
```

Signing provides integrity/authenticity, not confidentiality. JOSE encryption is **JWE**. Do not put secrets in a signed JWT expecting the signature to hide them.

## Part 44 — Create JWT manually

Generate RSA keys:

```bash
openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:2048 \
  -out jwt-private.pem

openssl pkey -in jwt-private.pem -pubout -out jwt-public.pem

cat > header.json <<'EOF'
{"alg":"RS256","typ":"JWT","kid":"lab-key-1"}
EOF

NOW=$(date +%s)
EXP=$((NOW + 3600))

cat > payload.json <<EOF
{
  "iss":"https://issuer.lab",
  "sub":"darshan",
  "aud":"crypto-lab",
  "iat":$NOW,
  "exp":$EXP,
  "role":"admin"
}
EOF
```

## Part 45 — Base64url helper

```bash
b64url() {
    openssl base64 -A |
    tr '+/' '-_' |
    tr -d '='
}

HEADER=$(jq -cj . header.json | b64url)
PAYLOAD=$(jq -cj . payload.json | b64url)

printf '%s\n' "$HEADER"
printf '%s\n' "$PAYLOAD"

SIGNING_INPUT="${HEADER}.${PAYLOAD}"
printf '%s' "$SIGNING_INPUT" > signing-input.txt
```

The signature covers these exact encoded bytes. Reformatting JSON and re-encoding it produces a different signing input.

## Part 46 — Create RS256 signature

RS256 is **RSASSA-PKCS1-v1_5 with SHA-256**, defined in [RFC 7518](https://www.rfc-editor.org/rfc/rfc7518).

```bash
openssl dgst \
  -sha256 \
  -sign jwt-private.pem \
  -out signature.bin \
  signing-input.txt

SIGNATURE=$(b64url < signature.bin)
JWT="${HEADER}.${PAYLOAD}.${SIGNATURE}"
printf '%s\n' "$JWT"
```

You just built a signed JWT manually. These shell variables must stay in the same terminal through Part 48.

## Part 47 — Decode your JWT

Header:

```bash
printf '%s\n' "$JWT" |
cut -d. -f1 |
python3 -c '
import sys,base64
x=sys.stdin.read().strip()
x += "="*((4-len(x)%4)%4)
print(base64.urlsafe_b64decode(x).decode())
'
```

Payload:

```bash
printf '%s\n' "$JWT" |
cut -d. -f2 |
python3 -c '
import sys,base64
x=sys.stdin.read().strip()
x += "="*((4-len(x)%4)%4)
print(base64.urlsafe_b64decode(x).decode())
'
```

No key is required. Decoding is not validation.

## Part 48 — Verify JWT signature manually

Decode the signature:

```bash
printf '%s\n' "$JWT" |
cut -d. -f3 |
python3 -c '
import sys,base64
x=sys.stdin.read().strip()
x += "="*((4-len(x)%4)%4)
sys.stdout.buffer.write(base64.urlsafe_b64decode(x))
' > received-signature.bin
```

Reconstruct the exact signing input and verify:

```bash
printf '%s\n' "$JWT" |
awk -F. '{print $1"."$2}' |
tr -d '\n' \
> received-input.txt

openssl dgst \
  -sha256 \
  -verify jwt-public.pem \
  -signature received-signature.bin \
  received-input.txt
```

Expect `Verified OK`. This proves the signature against your selected key. It does not check issuer, audience, expiry, or application authorization. Production consumers should use a maintained JOSE/OIDC library with explicit validation policy.

## Part 49 — JWT algorithm names

```text
HS256  HMAC + SHA-256
RS256  RSA PKCS#1 v1.5 signature + SHA-256
PS256  RSA-PSS + SHA-256
ES256  ECDSA using P-256 + SHA-256
EdDSA  Edwards-curve digital signature identifier, commonly Ed25519
```

The HMAC, RSA, PSS, and ECDSA families are specified in [JWA, RFC 7518](https://www.rfc-editor.org/rfc/rfc7518).

### Crucial HS256 distinction

```text
HS256: issuer and verifier share a secret; both can mint tokens
RS256: issuer signs with private key; verifier holds only public key
```

For example, Keycloak can hold a signing private key while 100 services verify using its public key. Those services cannot mint valid tokens just by possessing the public key.

## Part 50 — JWT claims

```text
iss  issuer
sub  subject
aud  audience: intended recipient
exp  expiration timestamp
nbf  not valid before
iat  issued at
jti  token identifier
```

A secure consumer validates more than the signature: trusted issuer, expected audience, expiry, not-before where present, allowed algorithm, token purpose/type, and context-specific requirements such as OIDC nonce or authorized party. An untrusted token must not choose your validation policy.

## Part 51 — JWK

A **JSON Web Key** represents a cryptographic key as JSON. See [RFC 7517](https://www.rfc-editor.org/rfc/rfc7517).

Illustrative RSA public JWK; the placeholders below are not usable key values:

```json
{
  "kty": "RSA",
  "kid": "abc123",
  "use": "sig",
  "alg": "RS256",
  "n": "...",
  "e": "AQAB"
}
```

```text
kty = key type
kid = key identifier
use = intended key use
alg = intended algorithm
n   = RSA modulus, Base64url-encoded unsigned integer
e   = RSA exponent, Base64url-encoded unsigned integer
```

`AQAB` represents 65537. Recall `RSA public key = (n, e)`. A JWK can also represent private or symmetric keys; a public JWKS endpoint must not publish private material.

## Part 52 — JWKS

A **JSON Web Key Set** contains a `keys` array. Multiple public keys allow rotation:

```json
{
  "keys": [
    { "kid": "key-2026-10", "kty": "RSA", "n": "...", "e": "AQAB" },
    { "kid": "key-2026-09", "kty": "RSA", "n": "...", "e": "AQAB" }
  ]
}
```

This is illustrative, with placeholder moduli.

### Key rotation flow

```text
Issuer: private A + private B
JWKS:   public A + public B while old tokens can remain valid
JWT:    header.kid = B
Client: find eligible B in the trusted issuer's JWKS, then verify
```

`kid` is a selection hint, not proof of trust. [JWS](https://www.rfc-editor.org/rfc/rfc7515) defines it as a key identifier hint. The consumer must obtain keys from its configured trusted source and check key/algorithm compatibility.

## Part 53 — OAuth 2.0 vs OIDC

OAuth 2.0 is an authorization framework: “Is this application allowed to access resource X?”

OIDC is an identity layer on OAuth 2.0: “Who authenticated, and what can the client learn about that authentication?” See [OpenID Connect Core](https://openid.net/specs/openid-connect-core-1_0.html).

## Part 54 — Typical actors

```text
User → Client / Relying Party
                 │
                 ├── authorization request → Authorization Server / OpenID Provider
                 │                            authenticates user
                 │← authorization code ──────┘
                 │
                 ├── code + PKCE verifier → token endpoint
                 │← ID token + access token + possibly refresh token
                 │
                 └── access token → Resource Server / API
```

```text
OIDC:  Relying Party = client; OpenID Provider = identity provider
OAuth: Resource Owner, Client, Authorization Server, Resource Server
```

## Part 55 — ID token vs access token

An **ID token** conveys information about authentication and the user/session to the client/Relying Party. Its audience includes that client.

An **access token** authorizes access to a resource/API and is intended for a resource server. It may be a JWT or opaque. Do not substitute ID tokens for access tokens in API authorization.

## Part 56 — OIDC discovery

```bash
cd ~/crypto-lab/10-oidc

curl -fsS \
  https://accounts.google.com/.well-known/openid-configuration |
jq
```

Look for `issuer`, `authorization_endpoint`, `token_endpoint`, `jwks_uri`, `userinfo_endpoint`, `scopes_supported`, `response_types_supported`, and `id_token_signing_alg_values_supported`.

[OIDC Core](https://openid.net/specs/openid-connect-core-1_0.html) defines authentication/claims semantics; [OIDC Discovery](https://openid.net/specs/openid-connect-discovery-1_0.html) defines provider metadata discovery.

### Retrieve Google's JWKS

```bash
JWKS_URI=$(
  curl -fsS \
    https://accounts.google.com/.well-known/openid-configuration |
  jq -er '.jwks_uri'
)

printf '%s\n' "$JWKS_URI"
curl -fsS "$JWKS_URI" | jq
curl -fsS "$JWKS_URI" | jq '.keys[] | {kid,kty,alg,use}'
```

Key IDs and metadata can change. This exercise inspects a provider's discovery document and public keys; it does not obtain or validate a user token.

```text
Provider: holds private signing keys → issues JWT with header.kid
Provider: publishes JWKS → public keys
Application: configured issuer → trusted JWKS → matching key → verify JWT
```

## Part 57 — `iss`, `aud`, `sub`

Example Keycloak-issued claims:

```json
{
  "iss": "https://sso.example.com/realms/platform",
  "sub": "749217...",
  "aud": "vyom-api"
}
```

The API must establish that the issuer is trusted, `iss` matches the expected issuer, `aud` includes this API, the token has not expired, and it is appropriate for this purpose. `sub` identifies the subject within an issuer's context; do not assume it is globally unique by itself.

A valid signature establishes that the signed bytes were produced by a holder of the corresponding signing key. It does not answer every authentication or authorization question.

## Part 58 — What TLS and OIDC are each protecting

```text
Browser ──HTTPS──> Keycloak
                    │ signs JWT
Browser/client <────┘
      │ bearer token over HTTPS
      ▼
     API
      ├── TLS protects the connection
      └── JWT verification checks token integrity/origin and claims policy
```

TLS authenticates the peer and protects the connection. JWT signing protects the token's signed contents independently of a particular connection. Both layers matter.

## Part 59 — Certificates versus JWT signatures

```text
Certificate: CA private key → signs identity + public key + metadata
JWT:         IdP private key → signs claims
```

The fundamental primitive is private-key signing and public-key verification. The signed data and trust systems differ.

---

**Next:** [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook/05-openpgp|OpenPGP and GPG]].
