---
title: "PKI Operator Runbook 5 — OpenPGP and GPG"
tags: [architecture/cryptography, security/pki, security/tls, security/identity]
date: 2026-10-21
description: "Generate an isolated GPG key, sign, clear-sign and encrypt with it, and compare OpenPGP trust with X.509 PKI."
---

# PKI Operator Runbook 5 — OpenPGP and GPG

Parts 60–70: GPG keys, fingerprints, detached and clear signatures, encryption, subkeys, and web-of-trust versus X.509. Part of the [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook|PKI Operator Runbook]] (5 of 6). Previous: [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook/04-ssh-jwt-and-oidc|SSH, JWT and OIDC]]. Next: [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook/06-operator-connections|Operator Connections and Review]].

Commands continue in `~/crypto-lab` from the earlier notes; reapply `umask 077` in each new terminal.

## Part 60 — GPG / OpenPGP

```bash
cd ~/crypto-lab/11-gpg
export GNUPGHOME="$HOME/crypto-lab/11-gpg/gnupg"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"

gpg --full-generate-key
```

Choose a modern/default setup supported by your installed GnuPG version, a lab passphrase, and an expiration date. Use:

```text
Name: Darshan Crypto Lab
Email: lab@example.com
```

Inspect:

```bash
gpg --list-keys
gpg --list-keys --keyid-format LONG
gpg --list-secret-keys
```

The [GnuPG manual](https://gnupg.org/documentation/manuals/gnupg/) covers generation, signatures, encryption, subordinate keys, trust, and revocation. Keep using this isolated `GNUPGHOME` for Parts 61–69.

## Part 61 — Fingerprints

```bash
gpg --fingerprint lab@example.com
```

Distinguish the fingerprint, key ID, and public key. A fingerprint is a digest-based identifier for key material, not the key itself. Compare full fingerprints over a trusted channel when establishing key identity.

## Part 62 — GPG detached signature

```bash
echo "release artifact version 1" > artifact.txt

gpg --local-user lab@example.com --detach-sign artifact.txt
gpg --verify artifact.txt.sig artifact.txt

echo attacker >> artifact.txt
gpg --verify artifact.txt.sig artifact.txt
```

The second verification fails. GnuPG supports detached signatures through `--detach-sign`; see [operational GPG commands](https://gnupg.org/documentation/manuals/gnupg/Operational-GPG-Commands.html).

## Part 63 — ASCII-armored signatures

Restore the artifact, then sign:

```bash
echo "release artifact version 1" > artifact.txt

gpg \
  --local-user lab@example.com \
  --armor \
  --detach-sign \
  artifact.txt

cat artifact.txt.asc
```

Expect a `-----BEGIN PGP SIGNATURE-----` block. ASCII armor is a text encoding representation.

## Part 64 — Clear-sign

```bash
echo "I approve deployment" > approval.txt
gpg --local-user lab@example.com --clearsign approval.txt
cat approval.txt.asc
```

The message stays readable alongside the signature. GnuPG distinguishes normal signing, clear-signing, and detached signing in its [operational commands](https://gnupg.org/documentation/manuals/gnupg/Operational-GPG-Commands.html).

## Part 65 — Export public key

```bash
gpg --list-keys

gpg \
  --armor \
  --export lab@example.com \
  > darshan-public.asc

cat darshan-public.asc
```

The public key can be shared. Recipients still need to authenticate its binding to you.

## Part 66 — Export private key

For this isolated demonstration key:

```bash
gpg \
  --armor \
  --export-secret-keys lab@example.com \
  > darshan-private.asc

chmod 600 darshan-private.asc
```

The export contains secret material. Do not casually export real operational keys or add the resulting file to this repository. Private-key handling is the security boundary.

## Part 67 — OpenPGP encryption

Encrypt to the recipient's public key; here, your lab key:

```bash
echo "secret message" > private-message.txt

gpg \
  --encrypt \
  --recipient lab@example.com \
  private-message.txt

gpg --decrypt private-message.txt.gpg
```

GnuPG uses public-key encryption to protect session-key material and symmetric encryption for the message. The corresponding secret key enables decryption. See [GPG operational commands](https://gnupg.org/documentation/manuals/gnupg/Operational-GPG-Commands.html).

## Part 68 — GPG primary key and subkeys

```text
Primary key
├── certifies identities/subkeys
├── signing subkey
└── encryption subkey
```

Responsibilities can be isolated: an offline primary certification key, and signing/encryption subkeys on a laptop. A compromised subkey can be revoked and replaced without necessarily replacing the primary identity. The exact subkeys created by default depend on your selected configuration. See the [GnuPG manual](https://gnupg.org/documentation/manuals/gnupg/).

## Part 69 — GPG trust versus X.509 trust

```text
X.509: Root CA → Intermediate CA → leaf certificate
OpenPGP: identities and keys can be certified by other keys
```

OpenPGP historically supports a web of trust: if Darshan trusts Alice as an introducer and Alice certifies Bob's key, that can contribute to confidence in Bob's identity/key binding. Trust policy is distinct from whether a signature mathematically verifies.

## Part 70 — Certificates versus PGP keys

```text
X.509:   issuer-signed identity ↔ public-key binding
OpenPGP: public keys + user identities + self-signatures
         + subkey bindings + certifications from other keys
```

They solve related identity/key-distribution problems with different formats and trust models. “Certificate” needs context: an OpenPGP transferable public key can also be described as an OpenPGP certificate; it is not an X.509 certificate.

---

**Next:** [[Architecture/solution-architecture-concepts/cryptography/pki-operator-runbook/06-operator-connections|Operator Connections and Review]].
