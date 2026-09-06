---
title: GKE Binary Authorization, Container Attestations, and Supply Chain Security
description: Exhaustive engineering guide to Google Cloud Binary Authorization on GKE — Deploy-time security policies, Sigstore / Cosign image signing, Grafeas vulnerability attestations, admission controller enforcement, and SRE Break-Glass incident procedures.
tags:
  - gcp
  - gke
  - security
  - binary-authorization
  - devsecops
  - sigstore
---

# GKE Binary Authorization, Container Attestations, and Supply Chain Security 🔐🛡️

Container supply chain attacks represent one of the most critical threats to modern enterprise infrastructure: malicious or vulnerable container images can be injected into registries and deployed directly to production. **Google Cloud Binary Authorization** is a deploy-time security control for Google Kubernetes Engine. Acting as a managed Kubernetes **Validating Admission Webhook**, Binary Authorization intercepts all Pod creation requests (`kubectl`, CI/CD pipelines, Helm charts) and validates that the container image has been cryptographically signed by authorized build authorities (**Attestors**) and scanned for vulnerabilities before allowing the container to run on GKE worker nodes.

---

## 1. Architecture & The Attestation Verification Pipeline

Binary Authorization decouples image building and security scanning in the CI/CD pipeline from deploy-time enforcement inside the GKE control plane.

```
                           CONTINUOUS INTEGRATION (CI) PIPELINE
                                            │
                                            ▼ 1. Build & Push Image
       ┌────────────────────────────────────────────────────────────────────────┐
       │                GOOGLE ARTIFACT REGISTRY / CONTAINER REGISTRY           │
       │                `pkg.dev/core-prod/apps/order-api:v2.0`                 │
       └────────────────────────────────────┬───────────────────────────────────┘
                                            │ 2. Trigger Container Analysis
                                            ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                 ARTIFACT ANALYSIS / VULNERABILITY SCANNER              │
       │   - CVE scan completes: ZERO Critical / High vulnerabilities           │
       │   - Automated signing tool (KMS + Attestor Key) creates Attestation    │
       │   - Signed note stored in Grafeas metadata service                     │
       └────────────────────────────────────┬───────────────────────────────────┘
                                            │
       ═════════════════════════════════════╪═══════════════════════════════════
       DEPLOYMENT PHASE                     │ 3. `kubectl apply -f deployment.yaml`
                                            ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                   GKE KUBERNETES CONTROL PLANE                         │
       │                                                                        │
       │  ┌──────────────────────────────────────────────────────────────────┐  │
       │  │             BINARY AUTHORIZATION ADMISSION CONTROLLER            │  │
       │  │                                                                  │  │
       │  │  Evaluates Cluster Policy:                                       │  │
       │  │  1. Check image whitelist (e.g., allow `gke.gcr.io/*`)           │  │
       │  │  2. Verify Cryptographic Signature via Cloud KMS                │  │
       │  │  3. Verify Vulnerability Attestation in Grafeas API              │  │
       │  └──────────────────────────────────┬───────────────────────────────┘  │
       └─────────────────────────────────────┼──────────────────────────────────┘
                                             │
             ┌───────────────────────────────┴───────────────────────────────┐
             │ Attestation Valid                                             │ Attestation Missing / Failed
             ▼                                                               ▼
  ┌─────────────────────────────────────┐                         ┌─────────────────────────────────────┐
  │         ADMISSION APPROVED          │                         │         ADMISSION REJECTED          │
  │ Pod scheduled & executed on nodes   │                         │ HTTP 403 Forbidden: "Image was      │
  └─────────────────────────────────────┘                         │ denied by Binary Authorization"     │
                                                                  └─────────────────────────────────────┘
```

### Core Architecture Constructs

1. **Policy:** A cluster-wide or project-wide rule set defining enforcement modes (`ENFORCING` or `DRYRUN_AUDIT_LOG_ONLY`), whitelisted container registries (e.g., Google system images), and required Attestors.
2. **Attestor:** A named authority (such as a CI/CD build pipeline or security gate) that asserts a container image is verified. Attestors use public/private key pairs stored in **Google Cloud KMS** or PGP keys.
3. **Grafeas Metadata / Artifact Analysis:** The open-source metadata store where cryptographic attestations are recorded as structured notes bound to the container's SHA256 digest (`image@sha256:...`).
4. **Break-Glass Emergency Procedure:** In a severe production outage where a hotfix must be applied immediately without waiting for standard CI attestations, SREs can bypass the admission webhook using a specialized pod annotation. Every break-glass invocation triggers high-priority alerts in Cloud Audit Logs.

---

## 2. Sigstore / Cosign vs KMS-Based Attestations

Binary Authorization natively supports both Google Cloud KMS-backed attestations and **Sigstore / Cosign** open-source signatures:
- **Cloud KMS Asymmetric Signing:** Uses enterprise hardware HSM keys (`rsa-sign-pss-4096-sha512` or `ec-sign-p256-sha256`) managed inside Cloud KMS. Keys cannot be extracted from Google Cloud.
- **Sigstore Integration:** Allows developers and open-source projects to sign container images using OIDC identity tokens and Cosign, verifying signatures directly against public transparency logs (Rekor).

---

## 3. Production Deployment & CLI Operations (`gcloud` & `kubectl`)

### 1. Enable Binary Authorization on a Production GKE Cluster

```bash
gcloud container clusters update prod-regional-cluster \
    --region=us-central1 \
    --enable-binauthz \
    --project=core-infrastructure-prod
```

### 2. Create Asymmetric Signing Key in Cloud KMS

```bash
# Create key ring and asymmetric signing key
gcloud kms keyrings create binauthz-ring \
    --location=us-central1 \
    --project=secops-kms-prod

gcloud kms keys create qa-signer-key \
    --keyring=binauthz-ring \
    --location=us-central1 \
    --purpose=asymmetric-signing \
    --default-algorithm=ec-sign-p256-sha256 \
    --project=secops-kms-prod
```

### 3. Register a Binary Authorization Attestor

```bash
# Create the Grafeas Note for the Attestor
cat > note_payload.json <<EOF
{
  "name": "projects/secops-kms-prod/notes/qa-attestor-note",
  "attestation": {
    "hint": {
      "human_readable_name": "QA and Vulnerability Scan Attestor"
    }
  }
}
EOF

curl -X POST \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "Content-Type: application/json" \
    --data-binary @note_payload.json \
    "https://containeranalysis.googleapis.com/v1/projects/secops-kms-prod/notes/?noteId=qa-attestor-note"

# Create the Attestor bound to the Grafeas note
gcloud container binauthz attestors create prod-qa-attestor \
    --attestation-authority-note=projects/secops-kms-prod/notes/qa-attestor-note \
    --project=secops-kms-prod

# Bind the Cloud KMS public key to the Attestor
gcloud container binauthz attestors public-keys add \
    --attestor=prod-qa-attestor \
    --keyversion-project=secops-kms-prod \
    --keyversion-location=us-central1 \
    --keyversion-keyring=binauthz-ring \
    --keyversion-key=qa-signer-key \
    --keyversion=1 \
    --project=secops-kms-prod
```

### 4. Configure Cluster Binary Authorization Policy

Create `binauthz-policy.yaml`:

```yaml
defaultAdmissionRule:
  evaluationMode: REQUIRE_ATTESTATION
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
  requireAttestationsBy:
  - projects/secops-kms-prod/attestors/prod-qa-attestor
globalPolicyEvaluationMode: ENABLE
clusterAdmissionRules:
  us-central1.prod-regional-cluster:
    evaluationMode: REQUIRE_ATTESTATION
    enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
    requireAttestationsBy:
    - projects/secops-kms-prod/attestors/prod-qa-attestor
# Whitelist critical infrastructure components
admissionWhitelistPatterns:
- matchedPattern: "gke.gcr.io/*"
- matchedPattern: "k8s.gcr.io/*"
- matchedPattern: "registry.k8s.io/*"
- matchedPattern: "us-central1-docker.pkg.dev/core-infrastructure-prod/system/*"
```

Apply Policy to GCP:

```bash
gcloud container binauthz policy import binauthz-policy.yaml \
    --project=core-infrastructure-prod
```

### 5. Sign an Image in CI/CD Pipeline (Create Attestation)

```bash
# Obtain image SHA256 digest
IMAGE_PATH="us-central1-docker.pkg.dev/core-infrastructure-prod/apps/order-api@sha256:4a8b79f6e5..."

# Sign the image digest using Cloud KMS key and store attestation
gcloud beta container binauthz attestations sign-and-create \
    --artifact-url="${IMAGE_PATH}" \
    --attestor=projects/secops-kms-prod/attestors/prod-qa-attestor \
    --keyversion-project=secops-kms-prod \
    --keyversion-location=us-central1 \
    --keyversion-keyring=binauthz-ring \
    --keyversion-key=qa-signer-key \
    --keyversion=1
```

### 6. Emergency Break-Glass Hotfix Procedure

If a critical zero-day requires deploying an unsigned hotfix immediately, annotate the pod spec to bypass the admission webhook:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: emergency-payment-patch
  namespace: finance
  annotations:
    # Triggers emergency Break-Glass bypass
    imagepolicy.k8s.io/break-glass: "true"
spec:
  containers:
  - name: patch
    image: us-central1-docker.pkg.dev/core-infrastructure-prod/apps/order-api:hotfix-v1
```

---

## 4. Quotas, Performance, and Configuration Limits

| Parameter / Dimension | Standard Quota / Limit | Engineering Guidance |
| :--- | :--- | :--- |
| **Admission Webhook Latency** | ~50 to 150 milliseconds | Cached KMS public keys prevent admission timeouts |
| **Max Attestors per Policy** | Up to 100 attestors | Enforce multi-signature gates (QA + Security + CI) |
| **Whitelisted Pattern Limit** | 500 regex patterns | Use registry wildcards (`pkg.dev/my-project/*`) |
| **Audit Log Latency** | Instantaneous | Emitted to Cloud Logging on every check |
| **Fail-Open vs Fail-Closed** | Configurable | Fail-closed guarantees security; fail-open prioritizes uptime |

---

## 5. Official References & Documentation

- [GKE Binary Authorization Documentation](https://cloud.google.com/binary-authorization/docs)
- [How to Create Attestors Using Cloud KMS](https://cloud.google.com/binary-authorization/docs/creating-attestors-cli)
- [Sigstore / Cosign Image Verification in GKE](https://cloud.google.com/binary-authorization/docs/sigstore-cosign)
- [Break-Glass Emergency Response Procedures](https://cloud.google.com/binary-authorization/docs/viewing-audit-logs#break-glass)
- [Binary Authorization Pricing](https://cloud.google.com/binary-authorization/pricing)

---

## 6. Realistic Pricing Scenarios

Pricing structure:
1. **Binary Authorization Enforcement:** **Free** (Included with GKE Standard and Autopilot).
2. **Cloud KMS Cryptographic Signing:** $0.06 per key version / month + $0.03 per 10,000 signing operations in CI/CD.
3. **Artifact Analysis (Vulnerability Scanning):** $0.26 per scanned container image in Artifact Registry.

### Scenario A: Enterprise Microservices Fleet (100 Builds / Day)

- **Workload Profile:**
  - 50 microservices running on a 20-node GKE cluster.
  - CI/CD builds and signs 100 container images daily ($3{,}000 \text{ images / month}$).
  - Every image scanned for CVEs and signed with Cloud KMS.
  - GKE evaluates 500 pod admission requests daily against Binary Authorization policy.
- **Monthly Cost Calculation:**
  - Binary Authorization Webhook: **$0.00**
  - Cloud KMS Asymmetric Key (1 key): **$0.06**
  - Cloud KMS Signing Ops (3,000 ops): Negligible ($0.01)
  - Artifact Analysis Vulnerability Scans: 3,000 images × $0.26/image = **$780.00**
- **Total Monthly Cost:** **$780.07 / month**

### Scenario B: Massive Multi-Cluster Regulated Financial Estate (10 Clusters)

- **Workload Profile:**
  - 10 GKE clusters across 3 regions enforcing multi-attestor policies (Security + Compliance + CI).
  - 10,000 monthly image builds.
  - High-availability Cloud HSM signing keys ($1.00/key version).
- **Monthly Cost Calculation:**
  - Binary Authorization: **$0.00**
  - Cloud HSM Keys (3 keys): 3 × $1.00 = **$3.00**
  - Artifact Analysis Scans: 10,000 images × $0.26 = **$2,600.00**
- **Total Monthly Cost:** **$2,603.00 / month**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **Tag Mutability Vulnerability (Always Sign by Digest):** If your CI pipeline signs `order-api:latest` by tag, an attacker with registry write access could push a malicious image with the exact same tag `:latest`. Binary Authorization verifies cryptographic signatures **strictly against the SHA256 image digest** (`image@sha256:...`). If your Kubernetes manifests reference mutable tags (`image:v2.0`) instead of immutable digests, Binary Authorization admission checks can produce unpredictable evaluation results. Always deploy images by digest in production.
2. **Missing System Whitelist Breaks GKE Node Addons:** If you configure a Binary Authorization policy with `defaultAdmissionRule: REQUIRE_ATTESTATION` and fail to whitelist Google's system registries (`gke.gcr.io/*`, `k8s.gcr.io/*`), **GKE cannot schedule its own internal system pods** (CoreDNS, metrics-server, Calico/Cilium daemons, CSI drivers). During node upgrades or pod restarts, nodes will enter `NotReady` state, taking down the entire cluster. Always whitelist `gke.gcr.io/*` and `k8s.gcr.io/*`.
3. **Dry-Run Audit Mode (`DRYRUN_AUDIT_LOG_ONLY`) Before Enforcing:** Flipping a Binary Authorization policy directly from disabled to `ENFORCED_BLOCK_AND_AUDIT_LOG` in an active production cluster will immediately block all automated rolling deployments, cronjobs, and horizontal autoscaling if any image lacks an attestation. Always operate in `DRYRUN_AUDIT_LOG_ONLY` mode for at least two weeks, querying Cloud Audit Logs (`protoPayload.status.message:"Image denied by Binary Authorization"`) to identify missing signatures before enforcing.
4. **Cloud KMS IAM Service Agent Permissions:** The Binary Authorization service agent (`service-<PROJECT_NUMBER>@gcp-sa-binaryauthorization.iam.gserviceaccount.com`) must possess `roles/cloudkms.viewer` and `roles/cloudkms.verifier` on the KMS key. If an infrastructure engineer rotates or restricts IAM bindings on the KMS key ring, the admission controller can no longer verify signatures, causing **every single pod deployment in the cluster to fail with HTTP 500 admission errors**.
5. **Break-Glass Audit Alarm Automation:** The `imagepolicy.k8s.io/break-glass: "true"` annotation allows emergency deployments to bypass all security gates. Attackers with `kubectl edit` privileges can use this annotation to deploy backdoor containers undetected. Create an automated high-severity alert in Cloud Logging / Sentinel monitoring for `protoPayload.response.admissionResponse.auditAnnotations."imagepolicy.k8s.io/break-glass" = "true"` that pages the security on-call team within 60 seconds of invocation.
6. **Cosign Rekor Transparency Log Network Outage:** If your Binary Authorization policy uses Sigstore/Cosign with keyless signatures that rely on public Rekor transparency log lookups, an external internet disruption or firewall rule blocking outbound traffic from GKE masters to `rekor.sigstore.dev` will cause admission evaluations to time out and fail. For high-availability private clusters, use Cloud KMS asymmetric key attestations stored in Google Artifact Analysis.
