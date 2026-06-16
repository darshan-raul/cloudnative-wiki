---
title: "M12: Pipeline Identity & OIDC Federation"
tags: [devsecops, stage3, deploy, oidc, iam, irsa, wif, workload-identity, cicd-auth]
date: 2026-06-16
description: Module 12 of 20 — replacing long-lived cloud credentials in CI with short-lived OIDC tokens. GitHub Actions → AWS, GCP, Azure. IRSA, WIF, and the pattern of "no static keys anywhere."
---

# M12: Pipeline Identity & OIDC Federation

The single highest-leverage DevSecOps upgrade you can make this quarter: remove every static cloud credential from your CI/CD system. OIDC federation lets the pipeline assume a cloud role using a short-lived token (15min–1hr) derived from the build context. The credential expires; the leak window closes. This module covers the pattern across GitHub Actions → AWS, GCP, Azure, and on-prem.

## Learning Objectives

By the end of this module you should be able to:

  - Configure OIDC trust between GitHub Actions and AWS (IAM role)
  - Configure OIDC trust between GitHub Actions and GCP (Workload Identity Federation)
  - Configure OIDC trust between GitHub Actions and Azure (Workload Identity)
  - Scope the trust to specific repos, branches, and environments
  - Replace static cloud credentials across your pipeline
  - Audit the rotation drill for OIDC-only pipelines

## 1. The Problem with Static Keys in CI

The pattern that most teams inherit:

```
  Pipeline (GitHub Actions)
       |
       |--- $AWS_ACCESS_KEY_ID
       |--- $AWS_SECRET_ACCESS_KEY
       |
       v
  AWS APIs
```

The keys:
  - Live forever (until manually rotated)
  - Are visible in the CI provider's secret store
  - Are visible in every workflow that references them
  - Can be exfiltrated by a malicious action, dependency, or PR
  - Have admin-equivalent power if scoped carelessly

The blast radius of a single leak: an attacker can call any AWS API the key is scoped to, indefinitely, until the key is revoked.

The OIDC fix:

```
  Pipeline (GitHub Actions)
       |
       |--- OIDC JWT (signed by GitHub; ~15min TTL; not a secret)
       |
       v
  AWS IAM (verifies JWT, issues session credentials)
       |
       v
  AWS APIs (with short-lived session)
```

The JWT is not a secret. Anyone can read it. What makes it useful is that the IAM role trusts *only* JWTs from a specific repo + branch + workflow. The attacker cannot forge a JWT (they'd need GitHub's private key), and they cannot reuse an old JWT (it expires in 15 minutes).

## 2. The OIDC Flow (Generalized)

```
  +-----------------+        +-----------------+       +----------------+
  |   CI Provider   |        |  Cloud IAM      |       |  Cloud APIs    |
  |  (GitHub, GL)   |        |  (AWS, GCP, Az) |       |                |
  +--------+--------+        +--------+--------+       +-------+--------+
           |                          |                        |
           | 1. Job starts; build     |                        |
           |    identity token (JWT)  |                        |
           |                          |                        |
           | 2. AssumeRoleWithWebId-  |                        |
           |    entity (or equiv)     |                        |
           |------- JWT ------------> |                        |
           |                          | 3. Verify signature    |
           |                          |    Check repo/branch   |
           |                          |    Check expiration    |
           |                          |                        |
           |                          | 4. Issue session creds |
           |                          |    (15min - 12hr TTL)  |
           |                          |                        |
           | 5. Session credentials   |                        |
           |<----------------------- |                        |
           |                          |                        |
           | 6. Call S3, EC2, etc. with session creds          |
           |---------------------------------------->         |
           |                                                   |
```

The cloud IAM is the trust boundary. It decides which external identities can become which IAM roles, under what conditions.

## 3. GitHub Actions → AWS

### Step 1: Create the OIDC Provider in IAM

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### Step 2: Create the IAM Role with a Trust Policy

The trust policy is the critical security boundary. It defines *which* GitHub contexts can assume the role.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:your-org/your-repo:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

The `sub` condition scopes the trust:
  - `repo:your-org/your-repo` — only this repo
  - `:ref:refs/heads/main` — only the main branch
  - `:ref:refs/heads/*` — all branches (looser)
  - `:environment:production` — only when running in the `production` environment
  - `:pull_request` — only from PRs (separate role recommended)

### Step 3: Attach a Least-Privilege Policy

The role gets a policy with the minimum permissions needed. Common patterns:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "arn:aws:ecr:us-east-1:123456789012:repository/my-app"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecs:UpdateService",
        "ecs:DescribeServices"
      ],
      "Resource": "arn:aws:ecs:us-east-1:123456789012:service/my-cluster/my-app"
    }
  ]
}
```

This role can push to ECR and update one ECS service. It cannot do anything else. If the token is compromised, the blast radius is contained.

### Step 4: Use the Role in the Workflow

```yaml
# .github/workflows/deploy.yml
name: deploy
on:
  push:
    branches: [main]

permissions:
  id-token: write   # required for OIDC
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-actions-deploy
          aws-region: us-east-1
      - name: Push to ECR
        run: |
          aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_REGISTRY
          docker push $ECR_REGISTRY/my-app:${{ github.sha }}
      - name: Deploy to ECS
        run: |
          aws ecs update-service --cluster my-cluster --service my-app --force-new-deployment
```

No `AWS_ACCESS_KEY_ID` in the workflow. No secret in the repo. The `id-token: write` permission is the only thing that enables the OIDC flow; without it, the JWT cannot be obtained.

## 4. GitHub Actions → GCP (Workload Identity Federation)

GCP's pattern is called Workload Identity Federation (WIF). The flow is similar but uses a different trust mechanism.

### Step 1: Create the Workload Identity Pool and Provider

```bash
# Pool
gcloud iam workload-identity-pools create github-pool \
  --location global \
  --display-name "GitHub Actions Pool"

# Provider
gcloud iam workload-identity-pools providers create github-provider \
  --location global \
  --workload-identity-pool github-pool \
  --display-name "GitHub Actions Provider" \
  --attribute-condition "assertion.repository=='your-org/your-repo'" \
  --attribute-mapping "google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
  --issuer-uri "https://token.actions.githubusercontent.com"
```

### Step 2: Bind to a GCP Service Account

```bash
gcloud iam service-accounts add-iam-policy-binding \
  [email protected] \
  --role roles/iam.workloadIdentityUser \
  --member "principalSet://iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/github-pool/attribute.repository/your-org/your-repo"
```

### Step 3: Use in the Workflow

```yaml
- id: auth
  uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: projects/123456789012/locations/global/workloadIdentityPools/github-pool/providers/github-provider
    service_account: [email protected]
```

The same pattern: no static keys, short-lived creds, scoped to one repo.

## 5. GitHub Actions → Azure (Workload Identity)

Azure's OIDC story is called Workload Identity Federation. Pattern:

```yaml
- uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
    enable-oidc-authentication: true
```

The federation setup is in Entra ID; once configured, the workflow authenticates as the federated identity.

## 6. The Trust Boundary: What to Lock Down

The OIDC trust policy is your attack surface. If it is too loose, an attacker can pivot. Three rules:

### Rule 1: Scope to a Specific Repo + Branch

```
"sub": "repo:your-org/your-repo:ref:refs/heads/main"
```

Not:
```
"sub": "*"
```

The latter means "any repo in any org can assume this role." Never.

### Rule 2: Scope to an Environment

For prod, use GitHub Environments with required reviewers:

```yaml
on:
  push:
    branches: [main]
jobs:
  deploy-prod:
    environment: production  # requires approval
```

The `sub` condition can then reference `:environment:production`, which means the role can only be assumed by jobs that are running in the `production` environment, which requires manual approval.

### Rule 3: Use a Separate Role for PR Builds

PRs from forks run untrusted code. They should assume a role that can *read* (to run scans) but not *write* (to push images or update infra).

```json
{
  "Condition": {
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:your-org/your-repo:pull_request"
    }
  }
}
```

This role: read-only ECR, read-only IAM, no deploy permissions. PRs cannot deploy even if the code is malicious.

## 7. Beyond GitHub: GitLab, CircleCI, Buildkite

The same pattern exists for other CI providers:

  - **GitLab CI** — `id_tokens` keyword; cloud federation via JWT
  - **CircleCI** — OIDC token in context; AWS/GCP federation works similarly
  - **Buildkite** — OIDC token; AWS, GCP federation
  - **Jenkins** — `withCredentials` + OIDC plugin; or use Vault to issue short-lived AWS creds

For each, the pattern is the same: short-lived OIDC token, trust policy scoped to specific jobs/environments, no static keys.

## 8. Self-Hosted Runners and OIDC

Self-hosted runners can use OIDC, but the trust is anchored to the runner, not to GitHub's OIDC provider. Two patterns:

### Pattern 1: GitHub-Hosted OIDC + Self-Hosted Runner

The self-hosted runner executes the job, but the OIDC JWT still comes from GitHub. The cloud IAM trusts the JWT, not the runner. This works as long as the runner can reach the cloud API.

### Pattern 2: SPIFFE/SPIRE for Self-Hosted

For air-gapped or non-cloud environments, use SPIFFE/SPIRE to issue workload identities. The pipeline runner has a SPIFFE ID; the workload API trusts that ID. M14 covers SPIFFE.

## 9. The Migration Plan

Migrating from static keys to OIDC is a quarter-long project. Stages:

### Stage A: Inventory (Week 1)

  - List every workflow that uses static cloud credentials
  - For each, document the scope of the credential
  - Identify high-value credentials first (prod-deploy, signing keys)

### Stage B: Pilot (Weeks 2–3)

  - Pick one non-critical workflow
  - Configure OIDC for that workflow
  - Verify it works end-to-end
  - Document the steps for the team

### Stage C: Rollout (Weeks 4–10)

  - For each workflow in priority order:
    - Create the IAM role with trust policy
    - Update the workflow to use OIDC
    - Test in a non-prod environment
    - Cut over; remove the static secret
  - Update the rotation drill to reflect that there are no static keys to rotate

### Stage D: Cleanup (Weeks 11–12)

  - Audit: any workflow still using static keys?
  - Delete the static keys
  - Document the new model in the security policy

## 10. Common Pitfalls

| Pitfall | Consequence | Fix |
| ------- | ----------- | --- |
| `sub: "*"` in trust policy | Any repo can assume the role | Scope to repo + branch |
| Same role for PR and main | PR code can deploy to prod | Separate roles, prod via environment |
| `id-token: write` on all jobs | Larger blast radius if a job is compromised | `id-token: write` only on jobs that need it |
| Role with `AdministratorAccess` | OIDC + admin = same risk as static key | Least privilege per role |
| No condition on `aud` | Confused-deputy risk | Always check `aud` |
| Stale trust policy | Old repos/branches retain access | Audit trust policies quarterly |

## 11. Self-Check

  1. List every workflow that uses a static cloud credential. Pick the highest-value one and migrate it to OIDC this week.
  2. For your prod-deploy role, what is the trust policy? Is it scoped to a specific branch + environment? If not, fix it.
  3. Can your pipeline run from a fork PR? If yes, what role does it assume? Does that role have write permissions?

## 12. The OIDC Migration Story

The migration from static keys to OIDC is not a one-day project. It is a 1–2 quarter effort that touches every workflow. The pattern:

### Phase 1: Setup (Week 1)

  - Create the OIDC provider in each cloud
  - Define the trust policy template (with placeholders for repo, branch, env)
  - Document the pattern in your security wiki

### Phase 2: Pilot (Week 2)

  - Pick one non-critical workflow
  - Migrate it to OIDC
  - Verify the end-to-end flow
  - Document the steps; create a checklist for other workflows

### Phase 3: Wave 1 — Read-Only (Weeks 3–6)

  - All workflows that only *read* (scans, queries)
  - Lowest risk; biggest volume
  - OIDC role has read-only access
  - Static keys removed after cutover

### Phase 4: Wave 2 — Write, Non-Prod (Weeks 7–10)

  - All workflows that *write* to non-prod
  - Higher risk; OIDC role scoped to non-prod
  - Static keys removed after cutover

### Phase 5: Wave 3 — Write, Prod (Weeks 11–14)

  - All workflows that *write* to prod
  - Highest risk; OIDC role scoped to prod
  - Static keys removed; manual approval for prod deploys

### Phase 6: Cleanup (Week 15)

  - Audit: any workflow still using static keys?
  - Delete the static keys
  - Document the new model
  - Update the rotation drill

After 15 weeks, the org has no static cloud credentials in CI. The blast radius of a runner compromise is contained.

## 13. The Per-Environment Trust Boundary

Different environments get different OIDC trust policies:

| Environment | Trust policy | Role |
| ----------- | ------------ | ---- |
| dev | `repo:org/*:ref:refs/heads/*` | read-write to dev only |
| staging | `repo:org/*:ref:refs/heads/main` + `:environment:staging` | read-write to staging |
| prod | `repo:org/app:ref:refs/tags/v*` + `:environment:prod` | limited, with manual approval |
| fork PRs | `repo:org/*:pull_request` | read-only across the org |

The dev trust policy is loose because dev is cheap. The prod trust policy is tight because prod is expensive. The fork PR policy is read-only because fork PRs run untrusted code.

## 14. OIDC and Per-User Attribution

A subtle but important property: OIDC tokens include the user identity (the developer who triggered the workflow). This means every cloud API call from CI is attributed to a specific human. CloudTrail logs the OIDC subject; the audit trail is per-user.

With static keys, every API call is attributed to "the IAM user" — no individual accountability. With OIDC, the individual is named.

## 15. OIDC and Cross-Cloud Federation

For multi-cloud orgs, OIDC federation chains. A GitHub Actions workflow can:
  1. Assume an AWS role via OIDC
  2. From AWS, call a Lambda that assumes a GCP service account via WIF
  3. From GCP, call the cloud API

Each step in the chain is short-lived and audited. The chain is auditable end-to-end.

```
  GitHub Actions
       |
       | OIDC → AWS IAM role
       v
  AWS Lambda
       |
       | WIF → GCP service account
       v
  GCP API
```

The pattern is rare in practice (most orgs are single-cloud) but powerful when needed.

## 16. OIDC and SLSA

OIDC is a prerequisite for SLSA L2+. The provenance generator (slsa-github-generator) requires the workflow to authenticate to the OIDC issuer. Without OIDC, the provenance is unsigned; with OIDC, it's signed and verifiable.

M14 covers SLSA in depth. This module is the OIDC foundation.

## 17. OIDC and the Audit Trail

| Control | OIDC evidence |
| ------- | ------------- |
| SOC 2 CC6.1 (logical access) | Trust policy, OIDC subject in CloudTrail |
| SOC 2 CC6.6 (boundary) | Per-env trust policy |
| SOC 2 CC8.1 (change management) | CloudTrail attribution to commit + user |
| ISO A.8.16 (monitoring) | CloudTrail logs with OIDC subject |
| FedRAMP AC-2 (account management) | Trust policy = explicit allow list |
| FedRAMP IA-2 (identification) | OIDC subject = unique user identity |

The audit asks "who did what?" The OIDC subject is the answer. The trust policy is the rule. The CloudTrail log is the evidence.

## Related

  - [[DevOps/devsecops/stage1-code/06-secrets-detection|M06: Secrets Detection]]
  - [[DevOps/devsecops/stage2-build/11-cicd-pipeline-hardening|M11: CI/CD Pipeline Hardening]]
  - [[DevOps/devsecops/stage3-deploy/13-artifact-signing|M13: Artifact Signing]]
  - [[DevOps/devsecops/stage3-deploy/14-supply-chain-attestations|M14: Supply Chain Attestations]]
  - [[DevOps/devsecops/stage3-deploy/README|Stage 3 — Deploy]]
