---
title: "M08: SBOM Generation & Consumption"
tags: [devsecops, stage1, code, sbom, spdx, cyclonedx, sigstore, supply-chain]
date: 2026-06-16
description: Module 8 of 20 — Software Bill of Materials: what to put in it, which format (SPDX vs. CycloneDX), how to generate it in the build, and how to consume it downstream for vuln tracking and compliance.
---

# M08: SBOM Generation & Consumption

A Software Bill of Materials (SBOM) is a machine-readable inventory of every component in your software. It is the dependency manifest promoted from a build artifact to a first-class deliverable. After the Log4Shell and SolarWinds incidents, SBOMs went from "nice to have" to "required by US federal procurement and most enterprise customers." This module covers formats, generation, storage, consumption, and the cultural shift that comes with publishing your inventory.

## Learning Objectives

By the end of this module you should be able to:

  - Generate a CycloneDX and SPDX SBOM at build time
  - Pick the right tool for each language and build system
  - Store SBOMs as build artifacts with cryptographic integrity
  - Consume SBOMs for vuln tracking, license compliance, and customer disclosure
  - Implement the VEX (Vulnerability Exploitability eXchange) pattern for known-but-not-applicable CVEs
  - Map SBOM requirements to US Executive Order 14028 and EU CRA

## 1. Why SBOMs Now

Three drivers:

  - **Regulatory** — US Executive Order 14028 (2021) requires SBOMs for federal software procurement. EU Cyber Resilience Act (CRA, 2024) requires SBOMs for products with digital elements. Healthcare, finance, and defense customers are following.
  - **Incident response** — when a new CVE drops, the first question is "are we affected?" An SBOM lets you answer in minutes, not weeks.
  - **Customer transparency** — enterprise procurement asks for SBOMs as part of vendor security review. Having one ready is the difference between a 2-week security review and a 2-day one.

The SBOM is the artifact that turns "we think we're fine" into a verifiable claim.

## 2. The Two Formats

### SPDX (Software Package Data Exchange)

Linux Foundation project. ISO/IEC 5962:2024 standard. Best for legal / license compliance. Text-heavy.

```
SPDXVersion: SPDX-2.3
DataLicense: CC0-1.0
SPDXID: SPDXRef-DOCUMENT
DocumentName: my-app-1.2.3
Creator: Tool: trivy-0.50.0
...

Package: lodash
SPDXID: SPDXRef-Package-lodash
PackageVersion: 4.17.20
PackageSupplier: NOASSERTION
PackageDownloadLocation: npmjs:lodash
FilesAnalyzed: false
PackageLicenseConcluded: MIT
```

### CycloneDX

OWASP project. Designed for security use cases. Best for vuln tracking and supply-chain tooling. JSON-first, with XML and Protobuf variants.

```json
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.5",
  "version": 1,
  "components": [
    {
      "type": "library",
      "bom-ref": "pkg:npm/lodash@4.17.20",
      "name": "lodash",
      "version": "4.17.20",
      "purl": "pkg:npm/lodash@4.17.20",
      "licenses": [{"license": {"id": "MIT"}}]
    }
  ]
}
```

### Which to Pick

| Use case                                | Format     |
| --------------------------------------- | ---------- |
| US federal procurement                  | SPDX 2.3 (mandated) |
| EU CRA                                  | SPDX 2.3 or CycloneDX 1.5+ |
| Vuln scanning downstream (Trivy, Snyk)  | CycloneDX  |
| License compliance tooling (FOSSology)  | SPDX       |
| Internal inventory + diff tracking      | CycloneDX  |
| Customer-facing (machine-readable)      | Both — generate and publish both |

The good news: most generators produce both formats. Generate both by default; let consumers pick.

### PURL (Package URL)

A canonical identifier for a package. Critical for cross-tool correlation.

```
pkg:npm/lodash@4.17.20
pkg:pypi/django@4.2.7
pkg:golang/github.com/gin-gonic/gin@v1.9.1
pkg:oci/my-image@sha256:abc...?tag=v1.2.3
pkg:generic/[email protected]
```

When your SBOM uses PURLs and your vulnerability scanner uses PURLs, the join is trivial. Tools that use their own ID schemes (Debian package names, RPM names) need translation tables; PURLs sidestep that.

## 3. Generation Tools

### Syft (Anchore)

The default recommendation. Fast, broad language support, outputs both SPDX and CycloneDX.

```bash
# Install
brew install syft

# Scan a directory
syft scan dir:. -o cyclonedx-json=sbom.cdx.json -o spdx-json=sbom.spdx.json

# Scan a container image
syft scan registry:my-registry.example.com/my-app:v1.2.3 -o cyclonedx-json

# Scan a tarball
syft scan tar:./app.tar -o spdx-json
```

### Trivy (built-in)

Trivy generates SBOMs in addition to scanning them. Convenient if you already have Trivy in the pipeline.

```bash
trivy image --format cyclonedx --output sbom.cdx.json my-app:v1.2.3
```

### Language-Specific Generators

  - **npm**: `cyclonedx-npm`, `spdx-satisfies`
  - **Python**: `cyclonedx-python`, `syft`
  - **Go**: `cyclonedx-gomod`
  - **Java**: `cyclonedx-maven-plugin`, `spdx-maven-plugin`
  - **Rust**: `cargo-cyclonedx`
  - **.NET**: `CycloneDX.CSharp`

For multi-language builds, prefer Syft over language-specific tools — it handles the polyglot case and the container case in one tool.

## 4. SBOM in the Build Pipeline

The right place to generate an SBOM is at the build, not at deploy. Reasons:

  - The build has the full source and lockfile context
  - The SBOM is reproducible given the same source
  - Attaching the SBOM to the build artifact (image, binary) is a single step

```
Source + Lockfile
       |
       v
   [Build]
       |
       +-- Image (signed)
       +-- SBOM (signed)
       +-- Provenance (SLSA)
       |
       v
   [Registry]
       |
       +-- tag → image
       +-- tag.sbom → SBOM
       +-- tag.att → provenance
```

The SBOM is uploaded as a separate artifact; it is *not* embedded in the image. Embedding bloats the image; separating keeps the SBOM in version control of the build history.

### Storage

  - **OCI registry** (Harbor, ECR, GHCR) — store as an OCI artifact alongside the image
  - **Build artifact store** (GitHub Actions artifacts, GitLab artifacts) — store as a build output, retained 24+ months
  - **SBOM-only store** (e.g., `guac`, Trustify, an S3 bucket with a manifest) — for cross-system correlation

For most teams, OCI registry is enough. Attach the SBOM as a referrer artifact (ORAS, cosign attach sbom).

### Example: cosign attach

```bash
# Build the image
docker build -t my-app:v1.2.3 .

# Generate SBOM
syft scan registry:my-app:v1.2.3 -o cyclonedx-json > sbom.cdx.json

# Attach SBOM to image
cosign attach sbom --sbom sbom.cdx.json my-app:v1.2.3
```

The SBOM is now cryptographically associated with the image digest. Anyone with the SBOM can verify it was emitted for that specific image.

## 5. The SBOM Lifecycle

```
   Build              Store              Distribute        Consume
   -----              -----              ----------        --------
   Source + lockfile  OCI registry       Customer asks     Vuln scanning
        |                  |                  |                  |
        v                  v                  v                  v
   Syft/Trivy       Tag + digest      SBOM + signature    Trivy / Snyk
   (per build)      (per release)     (per disclosure)    (per CVE)
```

The lifecycle has four handoffs. Each must be auditable.

  1. **Build** — SBOM is generated, signed, attached. Provenance links the SBOM to the source commit.
  2. **Store** — SBOM lives in the OCI registry as a referrer artifact. Retained 24+ months.
  3. **Distribute** — customer asks for SBOM; you provide it with the signature for verification.
  4. **Consume** — internal vuln scanners re-scan the SBOM daily; customer scanners do the same.

## 6. Consuming SBOMs

### Internal: Continuous Re-Scanning

The SBOM is not a one-time artifact. New CVEs are disclosed daily. The SBOM lets you re-scan the *same* artifact against new vuln data without rebuilding.

```bash
# Trivy: scan an SBOM for new vulns (no rebuild needed)
trivy sbom sbom.cdx.json
```

This is the operational payoff of an SBOM. When Log4Shell dropped, orgs with SBOMs answered "are we affected?" in minutes by re-scanning SBOMs. Orgs without SBOMs took weeks of grep and lockfile archaeology.

### Customer-Facing: VEX

The opposite problem: an SBOM shows a vulnerable dep, but the vuln is not reachable in your code. You do not want the customer flagging it as a finding.

VEX (Vulnerability Exploitability eXchange) is the format for saying "this CVE exists in this dep, but it is not exploitable in this product, and here is why."

```json
{
  "vulnerabilities": [
    {
      "id": "CVE-2024-12345",
      "analysis": {
        "state": "not_affected",
        "justification": "code_not_present",
        "response": "will_not_fix"
      },
      "affects": [
        {"ref": "pkg:npm/lodash@4.17.20"}
      ]
    }
  ]
}
```

VEX documents the *negative* claim, with reason and evidence. Customers can ingest it and clear the finding on their side.

## 7. SBOM in the Audit

A 2026 SOC2 / ISO 27001 audit will ask for evidence of:

  - SBOM generation at every build (the artifact, not just a claim)
  - SBOM retention policy
  - Process for re-scanning SBOMs on new CVE disclosures
  - Customer SBOM distribution process
  - VEX statements for disputed findings

Modules M14 (supply chain attestations) and M18 (compliance evidence) cover the audit trail.

## 8. SBOM Hygiene

The SBOM has its own quality concerns. Watch for:

  - **Incomplete transitive coverage** — a generator that only sees direct deps misses the real attack surface
  - **Hash mismatches** — the SBOM says package X@version Y, but the actual binary has Y+1; integrity check fails
  - **License noise** — every dep is listed, including dev-only deps; downstream consumer does not know which are runtime
  - **PURL drift** — the SBOM uses one PURL form, the scanner uses another; reconciliation fails

The fix for all of these: generate the SBOM at build time (where the lockfile is canonical), validate it (parse, check counts, check hashes), and re-scan the resulting image (M09) to confirm.

## 9. CycloneDX + VEX + Sigstore: The Modern Stack

The current best practice:

  1. Build → Syft produces CycloneDX SBOM
  2. Build → cosign signs the image and attaches SBOM
  3. Build → in-toto attestation links SBOM to source commit
  4. Deploy → admission controller verifies SBOM exists, signature valid
  5. Operate → Trivy re-scans SBOM against fresh vuln DB daily
  6. Operate → VEX statements issued for non-applicable findings
  7. Customer → receives SBOM + VEX bundle on request

This is the flow you will converge on. Modules M13, M14, M15 cover the signing and policy pieces.

## 10. SBOM Anti-Patterns

| Anti-pattern | Symptom | Fix |
| ------------ | ------- | --- |
| Generate at deploy, not build | SBOM does not match image | Generate at build, attach |
| Generate only direct deps | Misses 80% of vulns | Use Syft, which captures transitives |
| Store without signature | Customer cannot verify | cosign sign + attach |
| No VEX process | False positives alarm customers | VEX workflow for disputed findings |
| One-time SBOM | Stale within days | Continuous re-scan |
| Hand-curated SBOM | Out of date in a sprint | Generate, don't write |

## 11. Self-Check

  1. Can you answer, in under 5 minutes, "are we affected by CVE-2024-XXXX?" If not, you need SBOMs.
  2. Where in your pipeline do you generate the SBOM? Is it signed? Is it attached to the image?
  3. When was the last time a customer asked for your SBOM? How long did it take to produce?

## 12. SBOM Beyond Containers

The SBOM concept generalizes. Any artifact can have an SBOM:

| Artifact type | SBOM contents | Generator |
| ------------- | ------------- | --------- |
| Container image | OS packages + language packages | Syft, Trivy |
| Compiled binary | Linked libraries + transitive deps | Syft, dependency-track |
| npm package | npm deps tree | `cyclonedx-npm` |
| Python wheel | pip deps tree | `cyclonedx-python` |
| Java JAR | Maven deps tree | `cyclonedx-maven-plugin` |
| Go binary | Go modules + cgo libs | `cyclonedx-gomod` |
| Rust crate | Cargo deps + system libs | `cargo-cyclonedx` |
| VM image (AMI, VHD) | OS packages, installed services | AWS Inspector, Azure Defender |
| Firmware | OS + apps + crypto libs | Vendored, internal tools |

The discipline is the same: declare the inventory, sign the SBOM, attach it to the artifact. The customer-facing transparency is the same.

## 13. SBOM and Customer Trust

Customers increasingly require SBOMs as part of procurement. The patterns:

### Pattern 1: On-Demand Download

A public endpoint where the customer can download the SBOM for any release:

```
GET /api/v1/sbom?product=myapp&version=1.2.3
```

Returns: SBOM + signature. The customer can verify the signature.

### Pattern 2: Public S3 / GitHub Release

SBOMs uploaded as release assets. Customers can browse and download. Lower operational cost, less control over access.

### Pattern 3: CycloneDX/SPDX Server

A dedicated SBOM distribution server with role-based access. Used by larger orgs with many customers.

### Pattern 4: Attestation Registry

A service that stores SBOMs and serves them to verifiers (e.g., the customer's admission controller). Sigstore's `rekor` is a public version of this pattern.

The choice depends on the customer base and the regulatory environment. For most orgs, Pattern 1 or 2 is sufficient.

## 14. The SBOM in Incident Response

The "are we affected by CVE-X?" question is the test of the SBOM pipeline. Walk-through:

```
00:00  CVE-X is disclosed; critical; in library Y
00:01  Trivy / Snyk re-scans all SBOMs against the new vuln DB
00:02  The re-scan flags 3 images: my-app:v1.0, my-app:v1.1, my-app:v1.2
00:03  Engineer pulls each image; checks reachability
00:05  2 of 3 are reachable; 1 is not (function not called)
00:06  PRs opened for the 2 reachable images; bypass Renovate/Dependabot if needed
00:10  Patched images: my-app:v1.0.1, my-app:v1.1.1
00:15  Deploys expedited (out-of-band; emergency change)
00:30  Service restored
00:45  Postmortem: the 1 unaffected image gets a VEX statement
```

This is the 30-minute response to a critical CVE. Without SBOMs, it is a 30-day response. The 60× speedup is the value.

## 15. SBOM and Customer Audits

When a customer audits your supply chain, the SBOM is the *first* artifact they ask for. The audit pattern:

  - "Show us your SBOM for product X" → download the SBOM
  - "Is this SBOM authentic?" → verify the cosign signature
  - "Is the SBOM complete?" → compare to the image (syft + diff)
  - "What is the vuln status of this SBOM?" → re-scan with the customer's preferred tool
  - "What is your process for new CVEs?" → describe the SCA + SBOM + re-scan loop

A clean SBOM story answers all of these. A broken one — missing SBOM, no signature, incomplete inventory — raises the customer's risk rating, and may cost the deal.

## 16. SBOM in Different Industries

| Industry | SBOM requirement | Source |
| -------- | ----------------- | ------ |
| US Federal | Mandatory for software procurement | EO 14028 (2021) |
| Healthcare | Required for medical devices | FDA pre-market guidance (2023) |
| EU | Mandatory for products with digital elements | EU Cyber Resilience Act (CRA) (2024) |
| Automotive | Required for new vehicle types | ISO/SAE 21434 |
| Financial | Required for vendor risk management | NYDFS, PCI-DSS |
| Energy | Required for critical infrastructure | TSA pipeline directives |

The trajectory is clear: SBOMs are moving from "best practice" to "regulatory mandate" across industries. The pipeline that produces them is a compliance control, not a nice-to-have.

## 17. SBOM Anti-Patterns (Extended)

| Anti-pattern | Symptom | Fix |
| ------------ | ------- | --- |
| SBOM generated, not signed | Customer cannot verify | cosign sign + attach |
| SBOM with no PURL | Hard to correlate with vuln DB | Use PURL for every component |
| SBOM with hashes missing | Cannot verify dep integrity | Include SHA-256 / SHA-512 |
| SBOM with version ranges (">=1.0,<3.0") | Ambiguous, breaks re-scan | Lock to exact version |
| SBOM not retained | Cannot answer "are we affected" for old versions | Retain in OCI registry, 24+ months |
| SBOM in image layers | Bloats image, hard to extract | Attach as OCI referrer |

## 18. SBOM and Supply Chain Attestations Together

SBOM is one attestation. The full attestation stack:

  - **SBOM** — what's in it
  - **SLSA Provenance** — how it was built
  - **VEX** — what is and is not exploitable
  - **Test Results** — what tests passed
  - **Code Review** — what review was done
  - **License Compliance** — what licenses apply

The customer verifies all of them. Module M14 covers attestations; this module is one of the attestations.

## Related

  - [[DevOps/devsecops/stage1-code/07-sca-dependency-scanning|M07: SCA & Dependency Scanning]]
  - [[DevOps/devsecops/stage2-build/09-container-image-scanning|M09: Container Image Scanning]]
  - [[DevOps/devsecops/stage3-deploy/13-artifact-signing|M13: Artifact Signing]]
  - [[DevOps/devsecops/stage3-deploy/14-supply-chain-attestations|M14: Supply Chain Attestations]]
  - [[DevOps/devsecops/stage1-code/README|Stage 1 — Code]]
