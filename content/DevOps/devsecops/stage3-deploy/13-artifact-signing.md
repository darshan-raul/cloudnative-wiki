---
title: "M13: Artifact Signing"
tags: [devsecops, stage3, deploy, signing, cosign, sigstore, sigstore-fulcio, rekor, slsa]
date: 2026-06-16
description: "Module 13 of 20 — signing build artifacts (container images, binaries, SBOMs) with cosign/Sigstore. Keyless signing with OIDC, key management with KMS, and verification at deploy."
---

# M13: Artifact Signing

An unsigned artifact is an unsigned promise. The pipeline built it, but how does the deployment target know? Artifact signing creates a cryptographic link between an artifact and the identity that built it. This module covers cosign, Sigstore, keyless signing, key management, and the verification flow at deploy time.

## Learning Objectives

By the end of this module you should be able to:

  - Sign a container image with cosign using keyless OIDC
  - Sign with a KMS-backed key for higher assurance
  - Verify signatures at deploy time
  - Sign SBOMs and provenance
  - Integrate signing into the build pipeline
  - Choose between keyless and key-based signing for your threat model

## 1. Why Sign

The attack: an attacker compromises your registry, or a man-in-the-middle swaps the artifact between registry and node, or a malicious insider pushes a "hotfix" that bypasses CI. The deploy target pulls an image it cannot verify came from your build.

Signing fixes this. The deploy target verifies the signature against a trusted public key. If the signature is valid, the artifact came from whoever holds the private key (you, your CI, your KMS).

```
  Build                  Registry                Deploy
  -----                  --------                ------
  Source + lockfile
        |
        v
  [Build]
        |
        +-- Image
        +-- Signature  --->  stored alongside image (referrer)
        +-- Public key
                                |
                                v
                          [Admission Controller]
                                |
                                +-- Pull image
                                +-- Pull signature
                                +-- Verify signature
                                |
                                v
                            Allow / Deny
```

## 2. Sigstore: The Modern Stack

Sigstore is a Linux Foundation project that provides signing infrastructure designed for software supply chains. Three components:

  - **cosign** — the CLI; signs and verifies artifacts
  - **Fulcio** — a free CA that issues short-lived certificates bound to OIDC identities
  - **Rekor** — a transparency log; every signature is publicly recorded, immutable, auditable

The killer feature: **keyless signing**. With Fulcio, you sign an artifact using an OIDC identity (your GitHub Actions workflow, your AWS role, your Google account). Fulcio issues a certificate binding your OIDC identity to a public key. The signature + certificate + transparency log entry together prove the artifact was signed by that OIDC identity.

No long-lived private key. The signing material is generated per-signing, used once, discarded. The OIDC identity is the trust anchor.

```
  cosign sign
       |
       |--- Generate ephemeral keypair
       |--- Request certificate from Fulcio (binds key to OIDC identity)
       |--- Sign image digest with private key
       |--- Submit signature + cert to Rekor
       |
       v
  Signature stored in registry as referrer
  Transparency log entry created
```

## 3. cosign: The Default

### Keyless Signing (GitHub Actions)

```yaml
- name: Install cosign
  uses: sigstore/cosign-installer@v3

- name: Login to registry
  uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}

- name: Build and push
  uses: docker/build-push-action@v5
  with:
    push: true
    tags: ghcr.io/${{ github.repository }}:${{ github.sha }}

- name: Sign image (keyless)
  env:
    COSIGN_EXPERIMENTAL: 1
  run: |
    cosign sign --yes \
      ghcr.io/${{ github.repository }}@${{ env.IMAGE_DIGEST }}
```

The `COSIGN_EXPERIMENTAL: 1` (now stable in cosign v2.x) enables OIDC auth. cosign uses the GitHub Actions OIDC token to authenticate to Fulcio. Fulcio issues a cert binding the workflow's identity. The signature is recorded in Rekor.

### Key-Based Signing (KMS-Backed)

For higher-assurance signing, use a KMS-backed key. The private key never leaves the KMS.

```bash
cosign sign --key awskms:///alias/my-signing-key \
  ghcr.io/my-org/my-app@sha256:abc123
```

Supported KMS providers: AWS KMS, GCP KMS, Azure Key Vault, HashiCorp Vault Transit. The signing operation happens in the KMS; cosign never sees the private key.

### Verify

```bash
# Keyless verification — checks the OIDC identity in the cert
cosign verify \
  --certificate-identity [email protected] \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/my-org/my-app@sha256:abc123
```

The verify command:
  1. Downloads the signature from the registry
  2. Fetches the cert from Rekor
  3. Verifies the cert chain to Fulcio's root
  4. Verifies the cert's OIDC identity matches the expected identity
  5. Verifies the signature against the image digest
  6. Optionally checks the Rekor inclusion proof

If all pass, the image was signed by the expected OIDC identity, and the signature is publicly recorded.

## 4. Where Signatures Live

cosign stores signatures as **OCI referrers** — separate artifacts in the registry, linked to the original image by digest. The original image is not modified.

```
  registry.example.com/my-org/my-app@sha256:abc...
    ├── (image)
    ├── sha256-abc....sig       (signature)
    ├── sha256-abc....att       (attestation, e.g., SBOM)
    └── sha256-abc....pem       (signing certificate)
```

The deployment target can pull the image + signature by digest. The image's identity is the digest; the signature is a separate artifact.

## 5. Sign SBOMs and Provenance

cosign can sign anything, not just images. The most valuable things to sign:

  - **SBOM** — proves this SBOM was emitted for this specific image
  - **SLSA provenance** — proves the build was performed by this specific CI run
  - **VEX statements** — proves the VEX was issued by the vendor

```bash
# Sign an SBOM
cosign sign --yes --key awskms:///alias/sbom-key \
  sbom.cdx.json

# Attach SBOM to image (signed together)
cosign attach sbom --sbom sbom.cdx.json ghcr.io/my-org/my-app@sha256:abc...
cosign sign --yes --key awskms:///alias/sbom-key \
  ghcr.io/my-org/my-app:sha256-abc....sbom
```

Module M14 covers provenance in depth.

## 6. Verification at Deploy

The signature is only useful if something verifies it. Three deploy-time verification patterns:

### Pattern 1: Admission Controller (Kubernetes)

  - **Kyverno** with the `verifyImages` rule
  - **Connaisseur** (deprecated; use Kyverno or Ratify)
  - **Ratify** (Microsoft) — generic policy engine
  - **Cosigned** (deprecated; use Kyverno)

Kyverno example:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signature
spec:
  validationFailureAction: Enforce
  rules:
    - name: verify-signature
      match:
        resources:
          kinds: ["Pod"]
      verifyImages:
        - imageReferences:
            - "ghcr.io/my-org/*"
          attestors:
            - entries:
                - keys:
                    publicKeys: |-
                      -----BEGIN PUBLIC KEY-----
                      MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...
                      -----END PUBLIC KEY-----
```

The policy rejects any pod that uses an unsigned image.

### Pattern 2: Init Container

A sidecar or init container pulls the image, verifies the signature, and refuses to start if invalid. Used in non-Kubernetes environments.

### Pattern 3: Deploy Script

A pre-deploy script that calls `cosign verify` and aborts on failure. Simplest, least reliable (depends on script being run).

## 7. Keyless vs. Key-Based

| Aspect | Keyless (Fulcio) | Key-Based (KMS) |
| ------ | ----------------- | --------------- |
| Private key management | None; ephemeral | KMS or HSM |
| Trust anchor | OIDC issuer | Public key (or KMS) |
| Replay protection | Rekor transparency log | Registry-side or external |
| Recovery | Re-issue from same OIDC identity | Recover from KMS |
| Compromise window | ~15 min (cert TTL) | Until key rotated |
| Audit | Rekor (public) | KMS audit log (private) |
| Compliance | May not satisfy all auditors | Generally accepted |
| Cost | Free | KMS cost per sign op |

**When to use keyless**:
  - Open source projects
  - Internal artifacts with high trust in the OIDC issuer
  - When the operator is willing to trust the transparency log

**When to use key-based**:
  - Compliance requires a managed signing key (FedRAMP, PCI)
  - High-value artifacts that warrant HSM protection
  - When the OIDC issuer cannot be trusted to be a root of trust

**Common pattern**: keyless for non-prod, key-based (KMS) for prod.

## 8. Signing in the Pipeline

### Where in the Pipeline

```
  Build → Test → [SAST/SCA/secrets scan] → [Image build] → Sign → Push → [Admission verify] → Deploy
```

Signing happens *after* the build, *before* the push. The signing identity (OIDC or KMS) is bound to the build, not the registry.

### What to Sign

  - The image (always)
  - The SBOM (recommended; proves the SBOM is for this image)
  - The provenance attestation (recommended; SLSA L2+)
  - The VEX statement (optional)

### What to *Not* Sign

  - The build log (use a separate audit pipeline)
  - The artifact's test report (not security-critical)
  - Anything ephemeral

## 9. Key Rotation

Even with KMS, keys rotate. The pattern:

  - **Cosign key rotation** — sign with both old and new key for a transition period; verifiers accept either; cut over; revoke the old key
  - **KMS key rotation** — automatic for most KMS providers; verifiers use the public key, not the private
  - **OIDC cert rotation** — handled by Fulcio; no action needed

The Rekor transparency log is append-only and permanent. Old signatures are still verifiable. Key rotation does not invalidate history.

## 10. Common Mistakes

| Mistake | Consequence | Fix |
| ------- | ----------- | --- |
| Sign but never verify | Pointless; signature is not checked | Add admission controller |
| Sign with a long-lived local key | Key compromise = total loss | Use KMS or keyless |
| Pin to a tag, not a digest | Image can mutate; signature becomes ambiguous | Sign the digest, not the tag |
| Verify only in prod | Dev/staging pull unverified images | Verify at every deploy |
| Trust any OIDC identity | Open signing surface | Constrain to specific issuers/repos |
| No transparency log | Cannot detect replay | Use Rekor (default for keyless) |

## 11. Self-Check

  1. Pick a production image. Is it signed? If not, sign it this week. If yes, is the signature verified at deploy?
  2. What is your signing key? Where is it stored? What is the rotation policy?
  3. Can you prove, today, that the image running in production is the one your CI built? If not, you need signing + verification.

## 12. The Signature Lifecycle

A signature has a lifecycle. The stages:

  1. **Generation** — at build time, after the image is built and scanned
  2. **Storage** — as an OCI referrer in the registry, alongside the image
  3. **Distribution** — implicitly via the registry; no separate distribution channel
  4. **Verification** — at deploy time, by the admission controller
  5. **Retention** — the signature lives as long as the image; verify-ability persists
  6. **Expiry / Rotation** — for KMS keys, rotate; for keyless, no action needed

Each stage is automated. The signature is a *byproduct* of the build, not a separate process.

## 13. The Threat Model: What Signing Defeats

A signature defeats specific attacks. Knowing which is important:

| Attack | Defeated by signature? | Why |
| ------ | ---------------------- | --- |
| Registry compromise (malicious image pushed) | Yes (if signed) | The signature would not match |
| Man-in-the-middle (image swapped in transit) | Yes | The swap invalidates the digest, hence the signature |
| Compromised CI pushing a backdoor | Conditional | If the CI is the signer, no. If a separate identity signs, yes. |
| Compromised build dependencies (XZ-style) | No | The signature is on the result, not the inputs |
| Insider with signing key access | No | The insider signs; the signature is valid |

Signing is a *layer*, not a *panacea*. It pairs with M11 (CI hardening), M14 (provenance), and M15 (policy) for defense in depth.

## 14. Signature in Different Ecosystems

### Kubernetes

  - **Kyverno** with `verifyImages` — image signature verification
  - **Ratify** (Microsoft) — generic policy engine, supports signatures
  - **Connaisseur** — deprecated, replaced by Kyverno/Ratify
  - **Cosigned** — deprecated, replaced by policy engines

### Docker / containerd

  - **Docker Content Trust** (DCT) — built into Docker, uses Notary
  - **containerd image verification** — experimental, configurable

### Serverless / Lambda

  - **Code signing for AWS Lambda** — signs the deployment package
  - **Function signing for GCP** — verifies the source

### Package Registries

  - **npm** — supports signed provenance (Sigstore)
  - **PyPI** — supports signed provenance (Sigstore)
  - **RubyGems** — supports signed gems
  - **Maven Central** — supports PGP-signed artifacts
  - **Go modules** — uses `go.sum` for integrity, not signing per se

For each ecosystem, the pattern is the same: sign at publish, verify at consume. The tool differs.

## 15. The Fulcio and Rekor Public Infrastructure

Fulcio and Rekor are public, free services. They are not the only way to do keyless signing (you can run your own Fulcio), but they are the most common.

### Fulcio: The Certificate Authority

  - Issues short-lived certificates (15 min) bound to OIDC identities
  - Logs every certificate issuance to Rekor (transparency)
  - Free, open source, run by the Sigstore project
  - You can run your own if you don't want to depend on the public instance

### Rekor: The Transparency Log

  - Append-only public log
  - Every signature (with keyless) is recorded
  - Cryptographic proof of inclusion (Merkle tree)
  - Auditors can verify the log
  - Free, open source, run by the Sigstore project

### The Trust Root

The trust root for keyless signing is the Fulcio root certificate + the OIDC issuer. The OIDC issuer is the actual trust anchor; Fulcio is the bridge from OIDC to certificate.

The chain:
  1. OIDC issuer (e.g., GitHub) signs a JWT
  2. Fulcio verifies the JWT, issues a cert bound to the JWT's subject
  3. cosign uses the cert to sign
  4. Rekor records the cert + signature
  5. Verifier checks: cert chain to Fulcio root, OIDC subject matches expected, signature valid, Rekor inclusion proof valid

If any step fails, the signature is rejected.

## 16. The Cost of Signing

A few cost dimensions:

| Dimension | Cost | Notes |
| --------- | ---- | ----- |
| Storage | OCI referrer per image | Negligible |
| Build time | <1s per sign | Free for keyless; pennies for KMS |
| Verify time | <100ms per verify | Negligible |
| KMS | Per-sign op ($0.03 per 10k for AWS KMS) | Materially free |
| Rekor | Free | Public, sustained by Linux Foundation |
| Fulcio | Free | Public, sustained by Linux Foundation |

The total cost: pennies per build. The benefit: cryptographic proof of artifact integrity.

## 17. Signing and the Audit Trail

| Control | Signature evidence |
| ------- | ------------------ |
| SOC 2 CC8.1 (change management) | Signature is part of the change record |
| ISO A.8.32 (change management) | Signed artifacts in registry |
| FedRAMP SI-7 (software/firmware integrity) | Signature verification at deploy |
| FedRAMP CM-5 (access restrictions) | KMS access logs for signing keys |
| SLSA L2 / L3 | Provenance + signature is the implementation |

The audit asks "how do you know the deployed artifact is the one you built?" The answer is the signature verification log.

## Related

  - [[DevOps/devsecops/stage2-build/09-container-image-scanning|M09: Container Image Scanning]]
  - [[DevOps/devsecops/stage2-build/11-cicd-pipeline-hardening|M11: CI/CD Pipeline Hardening]]
  - [[DevOps/devsecops/stage3-deploy/12-pipeline-identity-oidc|M12: Pipeline Identity & OIDC]]
  - [[DevOps/devsecops/stage3-deploy/14-supply-chain-attestations|M14: Supply Chain Attestations]]
  - [[DevOps/devsecops/stage3-deploy/15-policy-as-code|M15: Policy-as-Code]]
  - [[DevOps/devsecops/stage3-deploy/README|Stage 3 — Deploy]]
