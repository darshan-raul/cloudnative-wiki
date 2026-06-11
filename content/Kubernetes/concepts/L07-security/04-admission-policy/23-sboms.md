# SBOMs (Software Bill of Materials)

*"https://www.cisa.gov/sbom | https://cyclonedx.org/ | https://spdx.dev/"*

A **Software Bill of Materials (SBOM)** is a **machine-readable inventory of every component** that makes up a piece of software — the image, the libraries, the transitive dependencies, the licenses, the versions. If you've ever read a nutrition label on food, an SBOM is the same idea: when something turns out to be harmful, you need to know what you actually consumed so you can act on it. In k8s, the "something harmful" is usually a **CVE in a base image layer or a transitive dependency**, and the "act on it" is identifying which workloads are affected before a vulnerability is exploited. This note covers the formats, generation, signing, consumption, and the regulatory context.

### Table of Contents

1. [Why SBOMs Exist](#1-why-sboms-exist)
2. [The Two SBOM Formats (SPDX, CycloneDX)](#2-the-two-sbom-formats-spdx-cyclonedx)
3. [The SBOM Fields](#3-the-sbom-fields)
4. [SBOM Generation (build-time)](#4-sbom-generation-build-time)
5. [SBOM Generation (image-time)](#5-sbom-generation-image-time)
6. [The "where does the SBOM live?" question](#6-the-where-does-the-sbom-live-question)
7. [SBOM Storage and Distribution](#7-sbom-storage-and-distribution)
8. [SBOM Signing (cosign / Sigstore)](#8-sbom-signing-cosign--sigstore)
9. [SBOM Consumption — vulnerability scanning](#9-sbom-consumption--vulnerability-scanning)
10. [SBOM Consumption — license compliance](#10-sbom-consumption--license-compliance)
11. [The SBOM + VEX Workflow](#11-the-sbom--vex-workflow)
12. [SBOM in the Cluster (Kyverno, Connaisseur, k8s)](#12-sbom-in-the-cluster-kyverno-connaisseur-k8s)
13. [The SLSA / SLSA-provenance Link](#13-the-slsa--slsa-provenance-link)
14. [The Regulatory Context (US EO 14028, EU CRA, PCI-DSS)](#14-the-regulatory-context-us-eo-14028-eu-cra-pci-dss)
15. [The k8s-Specific Use Case (VEX, runtime)](#15-the-k8s-specific-use-case-vex-runtime)
16. [Common Tools and Their Output](#16-common-tools-and-their-output)
17. [Common Patterns](#17-common-patterns)
18. [Operations and Debugging](#18-operations-and-debugging)
19. [Gotchas and Common Mistakes](#19-gotchas-and-common-mistakes)

---

## 1. Why SBOMs Exist

A typical container image is a stack:

```
Your Go app (1.0)
  └─ gin v1.9.1
       └─ go-validator v10
            └─ ... (50 more transitive deps)
  └─ prometheus/client_golang v1.18.0
       └─ protobuf v1.32.0
            └─ ... (200 more transitive deps)
A Debian 12 base image
  └─ glibc 2.36
  └─ openssl 3.0.x
  └─ openssh-server 9.6
  └─ ... (200 OS packages)
```

When a CVE drops in **openssl 3.0.x**, you need to know **which images contain that exact version**, and **which workloads in your cluster are running those images**. Without an SBOM, this is guesswork. With an SBOM, it's a query: "show me all workloads running images that contain openssl < 3.0.13".

Three reasons SBOMs matter:

* **Vulnerability management** — "which of my workloads are affected by CVE-2024-XXXX?"
* **License compliance** — "are we shipping GPL-licensed code in a proprietary product?"
* **Supply chain assurance** — "is this image what it claims to be?" (combined with signing)

The first one is the **killer use case** for k8s. A new CVE drops weekly; an SBOM lets you go from "we have 800 images" to "3 images are affected, in 2 namespaces, 17 pods" in seconds.

## 2. The Two SBOM Formats (SPDX, CycloneDX)

There are **two dominant formats** plus a third niche one:

* **SPDX** (Linux Foundation) — the **broadest** format. Designed for license compliance; extended for security. Used by the Linux kernel, major distros, and most enterprise compliance tools.
* **CycloneDX** (OWASP / CycloneDX working group) — the **security-focused** format. Designed for vulnerability management; lighter than SPDX. Used by most security / SCA tools.
* **in-toto** (in-toto project) — less common; focused on supply chain attestation. Used by some Sigstore tooling.

Both are **standardized at ISO** (SPDX ISO/IEC 5962:2024, CycloneDX ISO/IEC 5925:2024). Either is a reasonable choice. **Pick one and be consistent** — tools support both, but switching is a hassle.

| | SPDX | CycloneDX |
|---|---|---|
| **Origin** | Linux Foundation | OWASP |
| **Primary use** | License + security | Security + license |
| **ISO standard** | ISO/IEC 5962:2024 | ISO/IEC 5925:2024 |
| **Complexity** | Heavier (more fields) | Lighter (fewer fields) |
| **Adoption** | Red Hat, SUSE, Microsoft, etc. | Anchore, Sonatype, Snyk, OWASP Dep-Check |
| **JSON / XML / YAML** | Tag-value (text), JSON, YAML, RDF | JSON, XML, Protobuf |
| **Best for** | Compliance-heavy orgs | Security-heavy orgs |

For **k8s / cloud-native**, **CycloneDX** is more common (most security tools default to it). For **enterprise / regulated / compliance-heavy**, **SPDX** is more common.

## 3. The SBOM Fields

A typical SBOM has these fields:

### 3.1 Top-level

* **`bomFormat`** / **`spdxVersion`** — the format version.
* **`serialNumber`** / **`SPDXID`** — a unique ID for the SBOM itself.
* **`metadata`** — when generated, by what tool, the document's purpose.
* **`creationInfo`** (SPDX) / **`metadata.timestamp`** (CycloneDX) — timestamp.

### 3.2 Components (the actual bill of materials)

For SPDX:

* **`name`** — package name.
* **`versionInfo`** — version.
* **`downloadLocation`** — where the package was downloaded from.
* **`filesAnalyzed`** — whether the source was inspected (true for source SBOMs, false for binary / known-good).
* **`licenseConcluded`** — the license (SPDX identifier: `MIT`, `Apache-2.0`, `GPL-3.0-only`).
* **`copyrightText`** — copyright notices.
* **`checksums`** — SHA1 / SHA256 of the package.
* **`externalRefs`** — PURL (Package URL), CPE (Common Platform Enumeration), SWHID (Software Heritage ID) — for cross-tool matching.

For CycloneDX:

* **`type`** — `library`, `application`, `operating-system`, `device`, etc.
* **`name`** — package name.
* **`version`** — version.
* **`purl`** — Package URL (mandatory for tools that match vulnerabilities).
* **`licenses`** — list of licenses.
* **`hashes`** — SHA1 / SHA256 / etc.
* **`externalReferences`** — vendor, security advisories, etc.

### 3.3 Relationships

For SPDX:

* **`Relationship: SPDXRef-Package-A DEPENDS_ON SPDXRef-Package-B`** — the dependency graph.

For CycloneDX:

* `"dependencies": [{"ref": "pkg:maven/...", "dependsOn": ["pkg:maven/..."]}]` — the dependency graph.

The **dependency graph** is what makes an SBOM **more than a package list**. With the graph, you can answer "is this vulnerable package reachable from this entry point?".

### 3.4 PURL (Package URL)

*"https://github.com/package-url/purl-spec"*

The **Package URL (PURL)** is the de-facto standard identifier:

```
pkg:<type>/<namespace>/<name>@<version>?<qualifiers>#<subpath>
```

Examples:

```
pkg:npm/%40angular/animation@4.0.0
pkg:pypi/django@1.11.1
pkg:maven/org.apache.commons/commons-lang3@3.5
pkg:apk/alpine/openssl@1.0.2k-r1?distro=alpine-3.5
pkg:golang/github.com/gorilla/mux@v1.7.4
pkg:oci/alpine@3.5?tag=alpine%3Av3.5
```

A PURL is the **key** for matching vulnerabilities. The CVE database is keyed by PURL (and CPE). The scanner maps the SBOM's PURLs to the CVE database.

## 4. SBOM Generation (build-time)

**Build-time generation** is the **right place to do it**: the build knows the source. There are three common approaches:

### 4.1 From the package manager

The **language ecosystem** has its own SBOM generators:

* **Go** — `cyclonedx-gomod` (CycloneDX), `sigs.k8s.io/bom` (SPDX), `go mod why`.
* **JavaScript / TypeScript** — `cyclonedx-node-npm`, `@cyclonedx/cyclonedx-npm`.
* **Python** — `cyclonedx-python`, `pip-licenses`.
* **Java / Maven** — `cyclonedx-maven-plugin`, `spdx-maven-plugin`.
* **Rust** — `cargo-cyclonedx`.
* **.NET** — `dotnet-CycloneDX`.

The plugin is added to the build; on each build, an SBOM is generated for the source-level deps.

### 4.2 From the build system

Build systems like **Bazel**, **Pants**, **Buck** can produce SBOMs as a build artifact. The SBOM is **first-class**: the build system knows every dependency, every version, every target.

### 4.3 From a CI step

A CI step (GitHub Actions, GitLab CI, Tekton) runs the generator after the build. The SBOM is **separate from the image** — it's a CI artifact, uploaded to an artifact store.

The **standard pattern** is:

1. Build the source.
2. Generate the SBOM (from the package manager).
3. Build the image.
4. Sign both the image and the SBOM.
5. Push to registry.
6. Upload SBOM to artifact store.

The SBOM is generated at **the same step as the image build**, so the SBOM and image are **guaranteed to match**.

## 5. SBOM Generation (image-time)

**Image-time generation** is the **fallback**: the build didn't produce an SBOM, or you don't trust the build's SBOM. Tools scan the image's filesystem.

### 5.1 The image scan

* **Trivy** — `trivy image --format cyclonedx <image>`. Generates CycloneDX JSON. Most popular.
* **Grype** — `grype <image> -o cyclonedx-json`. Generates CycloneDX JSON.
* **Syft** — `syft <image> -o cyclonedx-json` or `syft -o spdx-json`. Generators only (no scanning).
* **Bomber** — generates from various inputs.
* **docker sbom** — `docker sbom <image>`. Uses Syft under the hood; official Docker tool.

The scanner inspects the image's filesystem (the layers, the package managers' files like `dpkg/status`, `apk/installed`, `pip freeze`, etc.) and produces an SBOM.

### 5.2 The accuracy trade-off

Image-time SBOMs are **less accurate** than build-time:

* **Language deps** — image-time sees the installed packages. If the build did `npm prune --production`, only prod deps are in the image. The SBOM is correct.
* **OS packages** — image-time sees the installed packages. Correct.
* **Source-level deps that aren't in the image** — image-time can't see them. Build-time can.
* **VCS / git deps** — image-time can't see them. Build-time can (if the tool is configured).
* **License info** — image-time can usually get this from the package metadata. Less accurate for source-only deps.

For **most use cases**, image-time is good enough. For **strict supply chain assurance**, build-time is required.

## 6. The "where does the SBOM live?" question

Three common patterns:

### 6.1 Attached to the image (OCI artifact)

The SBOM is an **OCI artifact** pushed alongside the image:

```
myregistry/myapp:1.0.0
myregistry/myapp:1.0.0.sbom                # the SBOM
myregistry/myapp:1.0.0.att                 # the signature
myregistry/myapp:1.0.0.sbom.att            # the SBOM signature
```

The SBOM is **referenced** from the image's `org.opencontainers.image.documentation` or `application/vnd.cyclonedx+json` media type. Tools fetch it as a separate blob.

This is the **modern, correct way**. OCI registries are designed for this; Sigstore / cosign makes it standard.

### 6.2 In a separate artifact store

The SBOM is **outside the registry** — in S3, GCS, an artifact store (GitHub Packages, GitLab Container Registry, JFrog), or a dedicated SBOM store (Anchore, Dependency-Track).

Pros: easy to query, easy to scan, separate from the image lifecycle.
Cons: must be kept in sync; the registry's image and the SBOM store's SBOM are separate.

### 6.3 In a vulnerability scanner's database

The scanner (Snyk, Anchore, Dependency-Track) consumes the SBOM and stores it in its own database. The original SBOM is discarded.

Pros: the scanner is the source of truth for vulnerability data.
Cons: the SBOM itself is lost; you can't share it with auditors.

The **best practice** is **6.1** (OCI artifact) + a **6.3** scanner. The SBOM is **portable** (anyone can fetch it from the registry) and the scanner is **queryable**.

## 7. SBOM Storage and Distribution

### 7.1 The OCI artifact model

*"https://github.com/opencontainers/image-spec/blob/main/artifact.md"*

The OCI artifact model lets you push **arbitrary blobs** to a registry. The blob has a `mediaType` that says what it is:

* `application/vnd.oci.image.manifest.v1+json` — image manifest.
* `application/vnd.oci.image.layer.v1.tar+gzip` — image layer.
* `application/vnd.cyclonedx+json` — CycloneDX SBOM.
* `application/spdx+json` — SPDX SBOM.
* `application/vnd.sigstore.cosign.signature.v1+json` — cosign signature.

The image manifest can **reference** the SBOM via the `manifests` field, using a "referrer list":

```bash
# push the SBOM as a referrer
oras attach --artifact-type application/vnd.cyclonedx+json \
  myregistry/myapp:1.0.0 \
  ./sbom.cdx.json

# the SBOM is now linked to the image
```

`oras` is the standard tool for this. `cosign attach sbom` does the same with cosign.

### 7.2 The vendor-specific paths

* **GitHub** — `oci://ghcr.io/owner/repo:sbom-<digest>`.
* **GitLab** — `oci://registry.gitlab.com/owner/project:sbom-<digest>`.
* **Docker Hub** — supports OCI artifacts since 2022.
* **AWS ECR** — supports OCI artifacts.
* **GCP Artifact Registry** — supports OCI artifacts.
* **Azure ACR** — supports OCI artifacts.

All major registries support the OCI artifact model. Pick one and use it.

## 8. SBOM Signing (cosign / Sigstore)

*"https://docs.sigstore.dev/"*

The SBOM is **only useful if you trust it**. An unsigned SBOM can be **tampered with**: an attacker can replace the SBOM with one that says "no vulnerabilities" (to bypass a policy that consumes the SBOM).

**Sign the SBOM** with cosign (or any Sigstore tool):

```bash
# generate the SBOM
syft myregistry/myapp:1.0.0 -o cyclonedx-json > sbom.cdx.json

# sign the SBOM
cosign sign-blob --bundle sbom.bundle \
  myregistry/myapp:1.0.0 \
  --output sbom.cdx.json.sig
```

Or, the more common approach, sign the SBOM **as an OCI artifact**:

```bash
# push the SBOM as a referrer + sign it
cosign attach sbom --sbom sbom.cdx.json myregistry/myapp:1.0.0
cosign sign myregistry/myapp:1.0.0.sbom
```

Verification:

```bash
# verify the SBOM signature
cosign verify myregistry/myapp:1.0.0.sbom \
  --certificate-identity user@example.com \
  --certificate-oidc-issuer https://github.com/login/oauth
```

The SBOM signature is verified. The SBOM is trusted.

### 8.1 Keyless signing (Sigstore Fulcio)

*"https://github.com/sigstore/fulcio"*

With **keyless signing**, you don't need a key pair. You authenticate to Fulcio (Sigstore's CA) via OIDC, and Fulcio issues a short-lived certificate tied to your OIDC identity.

```bash
# keyless sign the SBOM
cosign sign-blob --output sbom.cdx.json.sig \
  --bundle sbom.bundle \
  myregistry/myapp:1.0.0 \
  < sbom.cdx.json
```

The `cosign.bundle` contains the certificate (from Fulcio) and the signature. Verification:

```bash
cosign verify-blob --bundle sbom.bundle \
  --certificate-identity user@example.com \
  --certificate-oidc-issuer https://github.com/login/oauth \
  myregistry/myapp:1.0.0 \
  < sbom.cdx.json
```

The certificate is **short-lived** (10 min). The OIDC issuer is the trust anchor. **No long-lived keys to manage.**

## 9. SBOM Consumption — vulnerability scanning

The primary use case: **map the SBOM to CVE databases** and identify vulnerable packages.

### 9.1 The flow

```
SBOM (list of packages)
  ↓
  VEX (vulnerability exploitability exchange) - "is this vuln relevant?"
  ↓
  CVE database (NVD, GHSA, OSV, vendor advisories)
  ↓
  Output: "this image has 3 known CVEs, 1 of which is exploitable in our usage"
```

### 9.2 The tools

* **Trivy** — `trivy image <image>`. Scans the image (generates SBOM internally, scans it).
* **Grype** — `grype <image>`. Scans the image.
* **Snyk** — `snyk container test <image>`. Scans the image.
* **Anchore** — `anchore-cli image add <image> && anchore-cli image wait <image> && anchore-cli image vuln <image> all`.
* **Dependency-Track** — consumes SBOMs, runs continuous monitoring.
* **OSV-Scanner** — Google's tool, uses the OSV database.

The tools all do the same thing:

1. Generate an SBOM (or accept one).
2. Compare the packages to the CVE database.
3. Report CVEs.

### 9.3 The continuous monitoring problem

A CVE can drop **any time** — including 6 months after the image was built. The SBOM must be **continuously monitored** against the latest CVE database.

Tools for continuous monitoring:

* **Snyk** — re-scans periodically.
* **Anchore** — re-scans periodically.
* **Dependency-Track** — continuous monitoring.
* **Trivy + cron** — periodic re-scans.
* **kubeclarity / chainsaw** — k8s-specific continuous monitoring.

The standard pattern: a daily or weekly cron that re-scans all images. The result is a "vulnerability report" that's updated regularly.

## 10. SBOM Consumption — license compliance

The second use case: **license compliance**. Some companies can't ship GPL-licensed code, or have specific license obligations (attribution, source disclosure).

The SBOM has the licenses of every package. Tools:

* **ScanCode** — `scancode-toolkit`. Scans the source for license expressions.
* **FOSSology** — `fossology`. License scanning, with a web UI.
* **ORT (OSS Review Toolkit)** — license + security review.
* **Snyk License Compliance** — checks licenses against a policy.
* **pip-licenses** — for Python.

The flow:

```
SBOM (with licenses)
  ↓
  Policy: "no GPL, no AGPL, no SSPL"
  ↓
  Output: "this image has 3 GPL packages — should not be deployed to production"
```

The policy is enforced **at CI** (fail the build) or **at admission** (fail the deploy). The k8s layer is the second one.

## 11. The SBOM + VEX Workflow

*"https://www.cisa.gov/sites/default/files/2024-01/VEX-Use-Cases-508c.pdf"*

**VEX (Vulnerability Exploitability eXchange)** is a **statement about a CVE in the context of a specific product**: "this CVE in openssl 3.0.x does NOT affect us because we don't use the vulnerable function". The VEX status is one of:

* **Not affected** — the vuln is in the code, but we don't use it.
* **Affected** — the vuln is in the code and we do use it.
* **Fixed** — the vuln is in the code, but we've patched it.
* **Under investigation** — we don't know yet.

The VEX document is **linked to the SBOM** (or to a specific package version). The scanner consumes both: the SBOM says "this openssl is in the image", the VEX says "this openssl vuln doesn't affect us".

### 11.1 The CycloneDX VEX

CycloneDX has a **VEX extension** (`vulnerabilities` field in CycloneDX 1.4+):

```json
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.5",
  "version": 1,
  "components": [...],
  "vulnerabilities": [
    {
      "id": "CVE-2024-1234",
      "analysis": {
        "state": "not_affected",
        "justification": "code_not_present",
        "response": ["will_not_fix"]
      },
      "affects": [
        {"ref": "pkg:apk/alpine/openssl@3.0.13-r0"}
      ]
    }
  ]
}
```

The VEX says: "CVE-2024-1234 in openssl 3.0.13-r0: not affected, the code isn't present in our usage, will not fix".

### 11.2 The SPDX VEX

SPDX has a similar concept in the `annotations` field, with the security profile.

### 11.3 The flow

```
1. Image is built.
2. SBOM is generated.
3. CVE drops (e.g. openssl 3.0.x).
4. Scanner says: "this image has the vulnerable openssl".
5. Engineer investigates: "do we use the affected function?"
6. VEX is generated: "not_affected" (or "affected" + patch plan).
7. The next scan consumes the VEX: "this CVE is not_affected, skip".
8. The next audit shows the VEX: "we have a documented decision for this CVE".
```

The VEX is the **engineer's knowledge** captured in a machine-readable format. The scanner + VEX + SBOM is the **closed loop** for vulnerability management.

## 12. SBOM in the Cluster (Kyverno, Connaisseur, k8s)

Several k8s admission controllers consume SBOMs.

### 12.1 Kyverno + cosign

Kyverno can **verify SBOM signatures** at admission:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: verify-sbom }
spec:
  validationFailureAction: Enforce
  rules:
  - name: verify-image-sbom
    match:
      any:
      - resources:
          kinds: ["Pod"]
    verifyImages:
    - imageReferences:
      - "myregistry/*"
      attestations:
      - predicateType: https://cyclonedx.org/bom
        conditions:
        - all:
          - key: "{{images.{{...}}.attestations.{{...}}.predicateType}}"
            operator: Equals
            value: https://cyclonedx.org/bom
```

The Pod is rejected if the image doesn't have a **signed SBOM** (signed by the configured cosign identity).

### 12.2 Connaisseur

*"https://github.com/sse-secure-systems/connaisseur"*

Connaisseur verifies image signatures and SBOMs at admission. It's the **defense-in-depth layer**: only images with a valid signature + SBOM are deployed.

### 12.3 The OCI referrer list (k8s 1.30+)

K8s 1.30 added the **`ImagePullPolicy` for OCI referrers** — the kubelet can fetch the SBOM and other artifacts alongside the image. This is **alpha** in 1.30; it lets the kubelet verify the SBOM at image pull.

For the **runtime use case** (a Pod is running, a CVE drops), see [[Kubernetes/concepts/L07-security/02-workload-sandboxing/18-runtime-detection|Runtime Detection]] (Falco / Tetragon) and the new **kubeclarity** tools that scan running images against the CVE database.

## 13. The SLSA / SLSA-provenance Link

*"https://slsa.dev/"*

**SLSA (Supply chain Levels for Secure Artifacts)** is a framework for **provenance** — proof that an artifact was built as claimed. The provenance includes:

* **Who** built it (the build system, the identity).
* **How** it was built (the build steps, the source repo, the commit).
* **What** was built (the artifact hash, the dependencies).

The **SBOM is part of the provenance**. The provenance is a separate artifact (e.g. an in-toto attestation) signed by the build system. A consumer verifies:

1. The image signature (proves the image wasn't tampered with).
2. The SBOM signature (proves the SBOM wasn't tampered with).
3. The provenance (proves the build was as claimed).

The **full chain** is:

```
source → (build) → image + SBOM + provenance
                          ↓
                  (sign each with cosign)
                          ↓
                  (push to registry)
                          ↓
                  (consumer verifies all three)
```

The SBOM is **one link in the chain**. Without the SBOM, you know the image is what was built, but you don't know what's in it. With the SBOM, you know the image is what was built **and what's in it**.

## 14. The Regulatory Context (US EO 14028, EU CRA, PCI-DSS)

The **regulatory landscape** has shifted. SBOMs are no longer optional in many industries.

### 14.1 US Executive Order 14028 (2021)

*"https://www.whitehouse.gov/briefing-room/presidential-actions/2021/05/12/executive-order-on-improving-the-nations-cybersecurity/"*

EO 14028 requires federal agencies to:

* Require SBOMs from software vendors.
* Use the NIST SSDF (Secure Software Development Framework).
* Adopt SLSA-style provenance.

The **NTIA's "minimum elements"** (now part of CISA) define what an SBOM should contain. Most SBOM generators follow this.

### 14.2 EU Cyber Resilience Act (CRA)

*"https://digital-strategy.ec.europa.eu/en/policies/cyber-resilience-act"*

The CRA (effective 2027) requires:

* SBOMs for products with digital elements.
* Timely security updates.
* Vulnerability handling.

For **k8s operators and software vendors**, this is direct: any software you ship to EU customers needs an SBOM.

### 14.3 PCI-DSS 4.0

*"https://www.pcisecuritystandards.org/"*

PCI-DSS 4.0 (effective 2025) requires:

* Inventory of all software components.
* Patch management.
- Vulnerability scanning.

The **SBOM is the inventory**. Without it, the inventory is incomplete.

### 14.4 SOC 2 / ISO 27001 / FedRAMP

These frameworks require:

* Asset inventory.
* Change management.
* Vulnerability management.

The **SBOM supports all three** — it's a structured inventory with version tracking and a queryable vulnerability surface.

## 15. The k8s-Specific Use Case (VEX, runtime)

The **killer k8s use case** is: "an image we deployed 3 months ago has a new CVE — which of our running workloads are affected?"

The flow:

1. Image was built. SBOM was generated + signed.
2. Image was deployed to the cluster.
3. CVE drops (e.g. CVE-2024-1234 in openssl 3.0.13).
4. A scanner (kubeclarity, Chainsaw, Anchore) is configured to monitor the cluster.
5. The scanner fetches the SBOMs of all running images (from the registry or a local store).
6. The scanner compares the SBOM packages to the CVE database.
7. The scanner reports: "3 deployments in the cluster are running an image with openssl 3.0.13 — affected".
8. The on-call engineer pages, patches the image, redeploys.

Without SBOMs, the engineer would **scan the running images** (slow, requires a scanner to be in the cluster) or **manually look up packages** (error-prone).

With SBOMs, the scanner **just queries**: "show me all images with package X". It's a database query.

### 15.1 The kubeclarity / chainsaw model

**kubeclarity** and **chainsaw** are k8s-specific tools that:

1. Scan all running images in the cluster.
2. Generate SBOMs (if missing).
3. Compare to the CVE database.
4. Report vulnerabilities per-namespace, per-deployment, per-image.

The output is a **vulnerability report** tied to the cluster's actual state.

### 15.2 The "vulnerability report per cluster" pattern

```bash
# generate the report
kubeclarity-cli analyze --namespace all --output json > report.json

# the report says:
#   deployment/prod/api-gateway uses image X
#   image X has openssl 3.0.13 (from the SBOM)
#   openssl 3.0.13 has CVE-2024-1234 (high severity)
#   result: deployment/prod/api-gateway is vulnerable
```

The report is **actionable**: you know exactly what to fix.

## 16. Common Tools and Their Output

| Tool | What it does | Output format |
|---|---|---|
| **syft** | Generates SBOMs (no scanning) | SPDX, CycloneDX, GitHub |
| **trivy** | Scans images (generates SBOM internally) | CycloneDX, SPDX, table, JSON |
| **grype** | Scans images | CycloneDX JSON (vulns + SBOM) |
| **snyk** | Scans images (proprietary) | Snyk's format, integrates with GitHub |
| **anchore** | Scans + stores SBOMs | Anchore's format, has UI |
| **bomber** | Scans SBOMs (input) | Reports vulns |
| **osv-scanner** | Scans images, uses OSV DB | OSV format |
| **dependency-track** | Stores + monitors SBOMs | Has a web UI |
| **scancode-toolkit** | License scanning | SPDX |
| **ort** | License + security review | SPDX + CycloneDX |
| **kubeclarity** | k8s cluster scanning | CycloneDX + report |
| **chainsaw** | k8s cluster scanning (CNCF Sandbox) | CycloneDX + report |
| **cyclonedx-* tooling** | Language-specific SBOM generators | CycloneDX |
| **spdx-* tooling** | Language-specific SBOM generators | SPDX |
| **oras** | OCI artifact push/pull | Anything |
| **cosign** | Signing (incl. SBOMs) | Signature bundle |

## 17. Common Patterns

### 17.1 "Generate + sign + push in CI"

```bash
# in CI, after the build
syft myregistry/myapp:$GIT_SHA -o cyclonedx-json > sbom.cdx.json
cosign sign-blob --bundle sbom.bundle myregistry/myapp:$GIT_SHA < sbom.cdx.json
cosign attach sbom --sbom sbom.cdx.json myregistry/myapp:$GIT_SHA
cosign sign myregistry/myapp:$GIT_SHA
cosign sign myregistry/myapp:$GIT_SHA.sbom
```

The image, the SBOM, and the signatures are all in the registry. The next stage (deployment, admission) can verify them.

### 17.2 "Cluster-wide continuous monitoring"

```bash
# daily scan of all images
kubeclarity-cli analyze --namespace all --output json > /var/log/kubeclarity/report-$(date +%Y%m%d).json
```

The report is shipped to a SIEM / dashboard. The on-call gets paged for high-severity vulns.

### 17.3 "Block deployments of vulnerable images"

```yaml
# Kyverno policy: block if the image has a high CVE
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: block-vulnerable }
spec:
  validationFailureAction: Enforce
  rules:
  - name: block-high-cve
    match:
      any:
      - resources:
          kinds: ["Pod"]
    verifyImages:
    - imageReferences:
      - "myregistry/*"
      attestations:
      - predicateType: https://cyclonedx.org/bom
        conditions:
        - all:
          - key: "{{images.{{...}}.attestations.{{...}}.vulnerabilities[?(@.ratings[?(@.severity=='high')])].id}}"
            operator: NotEquals
            value: ""
```

The Kyverno policy is the **admission-level enforcement** of the SBOM. Vulnerable images are rejected before they're deployed.

### 17.4 "License compliance at build time"

```bash
# in CI, after the build
syft myregistry/myapp:$GIT_SHA -o spdx-json > sbom.spdx.json
scancode-toolkit -clipeu sbom.spdx.json
# fail the build if a GPL / AGPL / SSPL license is found
```

The CI fails the build. The image is never deployed.

## 18. Operations and Debugging

### 18.1 Common commands

```bash
# generate an SBOM from an image
syft myregistry/myapp:1.0.0 -o cyclonedx-json > sbom.cdx.json

# scan an image for vulns (and generate SBOM)
trivy image myregistry/myapp:1.0.0

# attach an SBOM to an image in the registry
cosign attach sbom --sbom sbom.cdx.json myregistry/myapp:1.0.0

# verify the SBOM signature
cosign verify myregistry/myapp:1.0.0.sbom \
  --certificate-identity user@example.com \
  --certificate-oidc-issuer https://github.com/login/oauth

# scan a running cluster
kubeclarity-cli analyze --namespace all

# list the SBOM components (jq)
cat sbom.cdx.json | jq '.components[] | {name, version, purl}'

# find a specific package in an SBOM
cat sbom.cdx.json | jq '.components[] | select(.name == "openssl")'
```

### 18.2 The "SBOM doesn't match the image" case

The SBOM and the image are **out of sync**. The image was rebuilt, the SBOM wasn't.

```bash
# 1. Compare the image's SHA to the SBOM's
docker inspect myregistry/myapp:1.0.0 | jq '.[0].Id'
cat sbom.cdx.json | jq '.components[] | select(.purl | startswith("pkg:oci/"))'

# 2. If they don't match, regenerate the SBOM
syft myregistry/myapp:1.0.0 -o cyclonedx-json > sbom.cdx.json
```

### 18.3 The "Kyverno is rejecting my image" case

The Kyverno policy is rejecting the image. The image doesn't have a valid SBOM signature.

```bash
# 1. Check the Kyverno logs
kubectl -n kyverno logs -l app=kyverno | grep -A 5 "verify-sbom"

# 2. Check the SBOM signature
cosign verify myregistry/myapp:1.0.0.sbom \
  --certificate-identity user@example.com \
  --certificate-oidc-issuer https://github.com/login/oauth

# 3. Re-sign if needed
cosign sign myregistry/myapp:1.0.0.sbom
```

## 19. Gotchas and Common Mistakes

### 19.1 The 30+ common mistakes

1. **Generating an SBOM and not using it.** The SBOM is **only useful if something consumes it**. Generate, store, and monitor.

2. **Generating the SBOM from the image, not the build.** Build-time is more accurate (sees source-level deps, VCS info). Image-time is the fallback.

3. **Storing the SBOM outside the registry.** The SBOM **next to the image** (OCI artifact) is the standard. External stores are a fallback.

4. **Not signing the SBOM.** An unsigned SBOM can be tampered with. Sign it (cosign or similar).

5. **Using the wrong format for the use case.** SPDX for compliance, CycloneDX for security. Pick one, be consistent.

6. **Not including the dependency graph.** A flat list of packages is **not enough**. The graph lets you query "is this package reachable?".

7. **Missing the OS packages.** Base image packages (glibc, openssl) are often the most vulnerable. Make sure the SBOM includes them.

8. **Missing the language packages.** Python wheels, npm modules, Go binaries. The image-time SBOM tools catch these if they look at the right files.

9. **Not updating the SBOM when the image is rebuilt.** The image is rebuilt; the SBOM is stale. Regenerate.

10. **Not running continuous monitoring.** A CVE drops weekly. The SBOM must be **continuously re-scanned** against the CVE database.

11. **Storing the SBOM only in the scanner's database.** The scanner is the **consumer**; the SBOM should be **portable** (OCI artifact or external store).

12. **Forgetting the VEX.** The SBOM says "openssl 3.0.13 is in the image". The VEX says "we don't use the vulnerable function, no action needed". Without the VEX, every CVE is a panic.

13. **Generating the SBOM with the wrong namespace.** PURLs need the right namespace (`pkg:npm/%40angular/animation@...` not `pkg:npm/angular/animation@...`). Wrong namespace = no vuln match.

14. **Generating the SBOM in the wrong format for the scanner.** Some scanners only consume SPDX, some only CycloneDX. Match the format to the scanner.

15. **Not using PURLs.** PURLs are the standard identifier. Some SBOMs use names + versions only. CVE matching requires PURLs (or CPEs).

16. **Generating the SBOM post-build, after pushing.** The image is already in the registry; the SBOM should be generated **at build time**, not after.

17. **Trusting the SBOM from an untrusted source.** If the SBOM comes from a registry you don't control, sign it (or don't trust it).

18. **Not versioning the SBOM.** The SBOM itself is an artifact; it should be versioned (along with the image).

19. **Not storing the SBOM for the lifecycle of the image.** The image is deployed for years; the SBOM must be available for years.

20. **Not using the SBOM for license compliance.** The SBOM has the licenses. Run a license scanner against it.

21. **Not using the SBOM for the cluster's running images.** The killer use case. Don't just generate and store — query against running images.

22. **The scanner is not in the cluster.** Continuous monitoring **requires** the scanner to have access to the running images (or to a recent SBOM store).

23. **The SBOM is one-time, not on every build.** A CI pipeline that generates an SBOM once and never re-generates is a liability.

24. **The SBOM is per-image, not per-workload.** A single image may run in 100 workloads. The SBOM should be per-image; the **vulnerability report** is per-workload (a join of SBOM + cluster state).

25. **The SBOM doesn't include the base image's components.** Many scanners only look at the app's deps. The base image's OS packages are the **biggest** attack surface.

26. **The SBOM is from a base image scan, not the full image.** Layer-by-layer scans are needed for full coverage.

27. **The SBOM includes packages that aren't actually used.** The "CVE in openssl" might be in the image, but the app doesn't use openssl. **VEX** is the answer, not a flat SBOM.

28. **The SBOM is huge and slow to scan.** A large image (1 GB+) can have 10,000+ components. The scanner is slow. Use **incremental scanning** or **SBOM-level scanning** (don't re-parse the image).

29. **The SBOM is not consumed by anything.** Generating and storing an SBOM is a waste if nothing reads it. Hook up a scanner, a SIEM, or a dashboard.

30. **The SBOM is the "compliance checkbox", not the "operational tool".** The value of an SBOM is in the **continuous query** (vulnerability monitoring, license compliance), not the artifact itself.

## See also

* [[Kubernetes/concepts/L07-security/02-workload-sandboxing/19-image-hardening|Image Hardening]] — the broader image context
* [[Kubernetes/concepts/L07-security/04-admission-policy/11-opa-gatekeeper|OPA / Gatekeeper]] — for admission-level enforcement
* [[Kubernetes/concepts/L07-security/04-admission-policy/12-kyverno|Kyverno]] — for admission-level enforcement (YAML)
* [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/22-compliance-frameworks|Compliance Frameworks]] — the regulatory context
* [[Kubernetes/guides/delivery/ci-cd-integration|security-scanning]] — image scanning in practice
* [[Kubernetes/guides/delivery/ci-cd-integration|image-signing]] — image signing in practice
* See [[Kubernetes/guides/delivery/ci-cd-integration]] (Cosign, Notary) and [[Kubernetes/guides/delivery/ci-cd-integration]] (image scanning) for the supply-chain tooling layer.
