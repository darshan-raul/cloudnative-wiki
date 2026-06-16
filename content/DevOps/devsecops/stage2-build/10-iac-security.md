---
title: "M10: Infrastructure-as-Code Security"
tags: [devsecops, stage2, build, iac, terraform, checkov, tfsec, terrascan, pulumi, cdk]
date: 2026-06-16
description: Module 10 of 20 — securing Infrastructure-as-Code before it applies. Checkov, tfsec, Trivy IaC, OPA, policy-as-code for Terraform/CloudFormation/Pulumi/CDK. The build-time gate for cloud misconfigurations.
---

# M10: Infrastructure-as-Code Security

A misconfigured S3 bucket or an open security group does not look like a vulnerability to SAST, but it is the single largest source of cloud breaches (per Verizon DBIR, year after year). IaC security catches these *before* they apply — at PR time, on the diff, in code review. This module covers the tools, the rule sets, and the operational pattern of shifting cloud-misconfig defense to the build.

## Learning Objectives

By the end of this module you should be able to:

  - Run Checkov / tfsec / Trivy IaC on every Terraform PR
  - Distinguish a *misconfiguration* from a *vulnerability* and route findings to the right owner
  - Set a baseline + override pattern that scales across teams
  - Use OPA / Conftest for cross-tool policy-as-code
  - Run pre-deploy diff scans (cfn-nag, kics, cloudformation-guard)
  - Map IaC findings to CIS, NIST, and PCI controls

## 1. Why IaC Security Is a Separate Discipline

IaC is code, but it is not application code. The failure modes are different:

  - **SAST** looks for code-level bugs (injection, weak crypto). IaC misconfigurations are not bugs in the usual sense — the Terraform is syntactically and semantically correct.
  - **SCA** looks at third-party packages. IaC has packages (providers, modules), but the bigger issue is the cloud resource graph, not the provider code.
  - **DAST** tests a running app. IaC defines what *will* be running, before it is.

A dedicated scanner understands cloud resource models: "this S3 bucket has `public_read` ACL," "this security group allows 0.0.0.0/0:22," "this IAM policy grants `*:*`." The mapping from rule to misconfiguration is the value-add.

```
  Static                       | Pre-deploy           | Runtime
  -----------------------------+----------------------+--------------
  [checkov on .tf PR]          | [cfn-nag on stack]   | [cloud Custodian]
  [tfsec on .tf PR]            | [plan scan]          | [AWS Config]
  [Trivy IaC scan]             | [terraform plan      | [Prowler]
                                |  diff vs. baseline] |
```

## 2. The Tool Landscape

### Checkov (Bridgecrew / Prisma Cloud)

Open-source, broad, best general-purpose IaC scanner. 1000+ built-in policies. Supports Terraform, CloudFormation, Kubernetes, Helm, Dockerfile, ARM, Bicep, Pulumi.

```bash
# Install
pip install checkov

# Scan a directory
checkov -d ./terraform

# Output JSON for CI
checkov -d ./terraform -o json --output-file-path ./reports

# Fail on severity threshold
checkov -d ./terraform --check HIGH,CRITICAL

# Skip a specific check with justification
# resource "aws_s3_bucket" "x" {
#   # checkov:skip=CKV_AWS_18:Access logging is handled at org level
#   bucket = "x"
# }
```

### tfsec (Aqua Security)

Terraform-focused, fast, opinionated. Good for Terraform-only shops.

```bash
# Install
brew install tfsec

# Scan
tfsec ./terraform

# Format SARIF
tfsec ./terraform --format sarif --out tfsec.sarif

# Skip a check
# resource "aws_s3_bucket" "x" {
#   # tfsec:ignore:aws-s3-enable-bucket-logging
#   bucket = "x"
# }
```

### Trivy IaC

Built into Trivy (M07, M09). Less deep than Checkov but convenient if Trivy is already in your pipeline.

```bash
trivy config ./terraform
trivy config --severity HIGH,CRITICAL ./terraform
```

### Terrascan (Accurics / Tenable)

OPA-based. Policies are Rego (the OPA language), giving you full custom policy power. Steeper learning curve.

### KICS (Keeping Infrastructure as Code Secure)

Multi-IaC, broad rule library. Less popular than Checkov but solid.

### OPA / Conftest

Not a scanner — a policy engine. Write Rego policies; run them against any structured data (Terraform plan JSON, K8s manifests, etc.). Most flexible, least batteries-included.

## 3. What IaC Scanners Catch

A representative Checkov finding:

```
Check: CKV_AWS_18: "Ensure the S3 bucket has access logging"
File: /terraform/main.tf:10-30
Guide: https://docs.bridgecrew.io/aws/s3_bucket-enable-access-logging
Severity: LOW

 10 | resource "aws_s3_bucket" "data" {
 11 |   bucket = "company-data-prod"
 12 | }
```

This is a real misconfiguration that an attacker can leverage to exfiltrate data without a log trail.

### Common Findings (Top 20)

| Resource | Misconfig | Severity |
| -------- | --------- | -------- |
| S3 bucket | Public read ACL | Critical |
| S3 bucket | No access logging | Low |
| S3 bucket | No versioning | Medium |
| S3 bucket | No encryption at rest | High |
| Security group | 0.0.0.0/0 ingress on 22, 3389 | Critical |
| Security group | 0.0.0.0/0 egress | Medium |
| IAM policy | `Action: "*"` with `Resource: "*"` | Critical |
| IAM policy | Inline policy (vs. managed) | Low |
| RDS | Publicly accessible | High |
| RDS | No encryption at rest | High |
| RDS | No automated backups | Medium |
| Lambda | No DLQ configured | Medium |
| Lambda | Env var with `*password*` pattern | Critical |
| API Gateway | No WAF attached | Medium |
| CloudFront | No WAF, no logging | Medium |
| KMS | Key policy grants `*` | High |
| SQS | No encryption | Medium |
| DynamoDB | No encryption at rest | High |
| EKS | Public endpoint | Critical |
| EKS | No audit logging | Medium |

A real org will see the same 5–10 issues repeat. The fix is to ship a hardened module library and forbid raw resources (more on this below).

## 4. The Module Library Pattern

The single highest-leverage IaC control: **ship a vetted module library and forbid raw resources**.

Instead of engineers writing:

```hcl
resource "aws_s3_bucket" "data" {
  bucket = "company-data"
}
```

They use your module:

```hcl
module "data_bucket" {
  source  = "git::https://github.com/your-org/terraform-modules//s3-secure"
  version = "v2.3.1"
  name    = "company-data"
}
```

The module encodes all the safe defaults: encryption, logging, versioning, public access block, IAM policy. The engineer cannot accidentally create a misconfigured bucket because the module does not expose those knobs.

```hcl
# modules/s3-secure/main.tf
resource "aws_s3_bucket" "this" {
  bucket = var.name
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "this" {
  bucket        = aws_s3_bucket.this.id
  target_bucket = var.log_bucket
  target_prefix = "log/${var.name}/"
}
```

This is the "paved road" approach. Engineers who stay on the paved road cannot create an insecure resource. The IaC scanner exists to catch the ones who go off-road.

## 5. The Baseline Pattern

Not every finding needs a fix in the PR that introduced it. Most orgs have legacy resources that predate the policy. The baseline pattern:

```
  baseline.json
  ------------
  {
    "checkov": {
      "CKV_AWS_18": ["aws_s3_bucket.legacy_logs_2019"],
      "CKV_AWS_53": ["aws_s3_bucket.legacy_archive"]
    }
  }
```

New resources are gated by the policy. Existing resources in the baseline are tracked separately, with a ticket and an SLA to remediate.

```bash
checkov -d ./terraform --skip-download
# Baseline applied: pre-existing findings suppressed
# New findings: full report
```

## 6. Custom Policies with OPA / Rego

When Checkov's built-in rules don't cover your org-specific concerns, write custom policies in Rego.

### Example: S3 Bucket Names Must Match Org Prefix

```rego
# policy/s3_naming.rego
package terraform.s3

deny[msg] {
  resource := input.resource.aws_s3_bucket[name]
  not startswith(resource.bucket, "acme-")
  msg := sprintf("S3 bucket '%s' must start with 'acme-'", [name])
}
```

Run with Conftest:

```bash
terraform show -json | conftest verify --policy ./policy
```

The `terraform show -json` output (the plan) is the structured data; Conftest applies the policy. Same approach works for Kubernetes manifests (`conftest verify --policy ./policy kustomize.yaml`).

### When to Write Custom Policies

  - Org-specific naming conventions
  - Mandated tags (`owner`, `cost-center`, `data-class`)
  - Region restrictions (only deploy to `us-east-1`, `us-west-2`)
  - Resource-type restrictions (no Lambda in prod, only EKS)
  - Cost limits (no instance larger than `r5.4xlarge`)

## 7. CI Integration

### GitHub Actions: Checkov + tfsec in parallel

```yaml
name: iac-scan
on: [pull_request]

jobs:
  checkov:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Checkov
        uses: bridgecrewio/checkov-action@master
        with:
          directory: ./terraform
          framework: terraform
          output_format: sarif
          output_file_path: checkov.sarif
          quiet: true
      - uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: checkov.sarif

  tfsec:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: tfsec
        uses: aquasecurity/tfsec-action@v1
        with:
          working_directory: ./terraform
          format: sarif
          soft_fail: false
```

### Pre-Deploy: `terraform plan` Diff

In addition to scanning the source, scan the *plan* — the diff between current and proposed state. This catches issues that only become visible at apply time.

```bash
# In CI
terraform init
terraform plan -out=plan.tfplan
terraform show -json plan.tfplan > plan.json
checkov -f plan.json
```

Checkov can scan the plan JSON. tfsec has a similar `tfsec tfplan` mode. Both detect "this PR would create a public S3 bucket" — even if the source code is fine and the misconfiguration is in a variable.

## 8. Mapping to Compliance Frameworks

| Framework | Control | IaC rule |
| --------- | ------- | -------- |
| CIS AWS 2.1.1 | S3 bucket policy disallows public read | CKV_AWS_53, CKV_AWS_54, CKV_AWS_55, CKV_AWS_56 |
| CIS AWS 2.1.5 | S3 access logging enabled | CKV_AWS_18 |
| CIS AWS 3.1 | CloudTrail enabled in all regions | CKV_AWS_35 |
| CIS AWS 4.1 | No security groups allow 0.0.0.0/0:22 | CKV_AWS_24 |
| CIS AWS 4.2 | VPC flow logs enabled | CKV_AWS_91 |
| PCI-DSS 1.2.1 | NSCs configured between trusted/untrusted | CKV_AWS_24, CKV_AWS_260 |
| PCI-DSS 1.3.4 | PAN cannot be stored in public-facing services | CKV_AWS_53 |
| SOC2 CC6.1 | Logical access controls | All IAM, S3, KMS rules |

Checkov, tfsec, and Terrascan all support framework-mapping output:

```bash
checkov -d ./terraform --framework terraform --output json --check CKV_AWS_18
tfsec ./terraform --include-uuid  # maps to CIS controls
```

## 9. Kubernetes as IaC

Kubernetes manifests are IaC. The same scanners apply:

  - **Checkov** with `framework: kubernetes`
  - **KubeLinter** (Stackrox) — k8s-specific
  - **Trivy** with `trivy config k8s/`
  - **Kyverno** — policy engine (covered in M15)

A KubeLinter finding:

```
KubeLinter
---------
Check: no-read-only-root-fs
Object: Deployment/my-app
Message: Containers must set securityContext.readOnlyRootFilesystem to true
Severity: warning
```

Same pattern: scan on PR, baseline known issues, fix in the diff.

## 10. The Pulumi / CDK Case

Pulumi and CDK generate IaC, but in a programming language. The scanners work:

  - **Checkov** has CDK support; runs against the synthesized CloudFormation
  - **tfsec** has some Terraform-Cloud-Translation (TCT) for non-Terraform
  - **Trivy** with `trivy config` works on synthesized output

The discipline is the same: scan the synthesized output, not the source. The source can be clean; the synthesized output is what gets applied.

## 11. IaC Scan Anti-Patterns

| Anti-pattern | Symptom | Fix |
| ------------ | ------- | --- |
| Scan only `terraform plan` in prod | Catch issues too late | Scan source on PR + plan on merge |
| Suppress with no comment | "Why is this allowed?" | Required: `// checkov:skip=ID: reason` |
| Baseline with no remediation | Findings age out indefinitely | Ticket per baselined finding with SLA |
| One rule set for all teams | Either too strict (block) or too loose (no signal) | Per-team baselines + org-wide floor |
| No paved-road modules | Every team reinvents S3 | Org-owned module library |

## 12. The IaC Hardening Plan (1 Quarter)

  - **Week 1** — Run Checkov on every Terraform repo. Sort findings by severity × resource count.
  - **Week 2** — Set the org floor: every repo must pass HIGH+CRITICAL. Create baselines.
  - **Week 3** — Publish the paved-road module library (S3, IAM, SG, RDS, EKS).
  - **Week 4** — Wire Checkov + tfsec into PR CI for every repo.
  - **Week 5–8** — Triage and fix the baselined findings. SLA: critical 14 days, high 30 days, medium 90 days.
  - **Week 9–12** — Audit: which repos have bypassed the CI gate? Which paved-road modules are not used?

## 12. Self-Check

  1. Pick a recent module of Terraform. Run Checkov on it. How many findings? How many would have been prevented by a module library?
  2. Does your CI scan the source, the plan, or both? Which catches more?
  3. Do you have a paved-road module library? If not, what would the first 5 modules be?

## 13. The Module Library Lifecycle

A paved-road module library is a long-term investment. The lifecycle:

### Stage 1: First Three Modules (Week 1)

  - S3 (most common, most misconfigured)
  - IAM role (high blast radius, easy to harden)
  - Security group (most public-S3-like mistakes)

These three cover 60% of common misconfigurations. Ship them, document them, drive adoption.

### Stage 2: Core Library (Month 1)

  - S3, IAM, SG, RDS, KMS, EKS, Lambda
  - Each module: tested, documented, with examples
  - CI: every module is Checkov-clean by construction

### Stage 3: Coverage (Quarter 1)

  - All common AWS resources
  - Multi-cloud (GCP, Azure) if applicable
  - Internal: paved-road modules are the default; off-paved-road requires approval

### Stage 4: Governance (Quarter 2+)

  - Module versioning policy
  - Deprecation policy (modules evolve; old versions retire)
  - Adoption metrics (% of resources using paved-road)
  - Per-team paved-road overlays (org floor + team custom)

The library is never "done." It grows with the org.

## 14. Cost of a Paved-Road Module

The cost of building one paved-road module:

  - **Initial**: 2–5 engineer-days (write, test, document)
  - **Maintenance**: 0.5 engineer-day per quarter (updates, bug fixes)
  - **Adoption cost**: per-team onboarding, 0.5 day per team

The benefit: every resource using the module is hardened by default. For an org with 100 resources of a given type, the paved-road module prevents 100 potential misconfigurations.

The ROI: ~10× over 1 year, conservatively.

## 15. The Off-Paved-Road Process

What happens when an engineer needs a resource that is not in the library?

  - **Step 1** — Check the library. Most use cases are covered.
  - **Step 2** — If not, check the team's paved-road overlay. Some teams have specialized modules.
  - **Step 3** — If still not, write a one-off. CI checks pass; Checkov flags known issues. Engineer files a follow-up to add the resource to the library.
  - **Step 4** — The security champion reviews the off-paved-road usage in PR.

The off-paved-road process is *not* a prohibition. It is a feedback loop: every off-paved-road use is a candidate for a new library module.

## 16. The Terraform-Specific Threat Model

IaC introduces a new threat: the *plan*. A plan is the diff between current and proposed state. A plan can introduce a misconfiguration that the source code does not have.

### Example

```hcl
# Source: clean
resource "aws_s3_bucket" "x" {
  bucket = "my-bucket"
  acl    = var.acl  # variable, defaults to "private"
}
```

```hcl
# Variables file (overrides default)
acl = "public-read"  # uh oh
```

The source code is clean. The plan is not. Scanning the source misses it; scanning the plan catches it.

### The Pattern

```bash
# In CI
terraform plan -out=plan.tfplan
terraform show -json plan.tfplan > plan.json
checkov -f plan.json
```

Catch the issue at the plan step, before apply.

## 17. The Drift Problem

After `terraform apply`, the live infrastructure may drift from the declared state. Causes:
  - Manual changes in the cloud console
  - Other tools (CDK, CloudFormation) modifying the same resource
  - API calls from scripts
  - Auto-scaling or other dynamic resources

Drift is a security problem because the declared state (which Checkov scanned) does not match the live state (which is what runs). A misconfiguration introduced by drift is invisible to IaC scanning.

### Drift Detection

  - **`terraform plan`** (with no changes) shows drift
  - **Cloud Custodian** — continuous compliance scanning
  - **AWS Config** — rule-based config monitoring
  - **driftctl** — open-source Terraform-specific drift detection

The pattern: detect drift in CI, alert on it, fix the root cause (re-apply Terraform, remove the manual access path).

## 18. Common IaC Patterns for Regulated Industries

| Pattern | FedRAMP | PCI-DSS | HIPAA | SOC2 |
| ------- | ------- | ------- | ----- | ---- |
| No public S3 | Required | Required | Required | Required |
| CloudTrail in all regions | Required | Required | Required | Required |
| Encrypted at rest | Required | Required | Required | Required |
| VPC flow logs | Required | Required | Recommended | Required |
| No 0.0.0.0/0 ingress | Required | Required | Required | Required |
| IAM least privilege | Required | Required | Required | Required |
| KMS key policies | Required | Required | Required | Required |
| Audit logging | Required | Required | Required | Required |

The Checkov rule sets cover most of these. The paved-road modules enforce them by default. The compliance team consumes the scan reports.

## 19. The IaC Security Champion

The person who owns IaC security has a specific role:

  - Maintains the paved-road module library
  - Reviews Checkov rules; tunes for the org
  - Writes custom OPA policies (M15) for org-specific concerns
  - Onboards new teams to the paved road
  - Is the reviewer for off-paved-road PRs

The role is typically 0.5–1 FTE for a mid-size org. Without it, the library rots and the Checkov rule set becomes stale.

## 20. IaC and the Audit Trail

IaC scanning produces the evidence for compliance:

| Control | IaC evidence |
| ------- | ------------ |
| SOC 2 CC6.1 (logical access) | IAM resource scans |
| SOC 2 CC6.6 (boundary) | SG, NACL, K8s NetworkPolicy scans |
| SOC 2 CC8.1 (change management) | Terraform PR history |
| ISO A.8.9 (config management) | IaC scan reports |
| PCI 1.2 (NSCs) | SG, NACL scans |
| PCI 1.3 (DMZ) | Public ingress scans |
| PCI 6.4 (change control) | Terraform plan + apply history |
| FedRAMP AC-4 (info flow enforcement) | SG, NACL, NetworkPolicy scans |

The audit asks "how do you know your cloud config is correct?" The answer is the Checkov report, the terraform plan history, and the paved-road module library.

## Related

  - [[DevOps/devsecops/stage0-foundations/03-secure-sdlc|M03: Secure SDLC]]
  - [[DevOps/devsecops/stage2-build/09-container-image-scanning|M09: Container Image Scanning]]
  - [[DevOps/devsecops/stage2-build/11-cicd-pipeline-hardening|M11: CI/CD Pipeline Hardening]]
  - [[DevOps/devsecops/stage3-deploy/15-policy-as-code|M15: Policy-as-Code]]
  - [[DevOps/devsecops/stage2-build/README|Stage 2 — Build]]
