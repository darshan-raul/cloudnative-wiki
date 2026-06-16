---
title: "M15: Policy-as-Code"
tags: [devsecops, stage3, deploy, opa, kyverno, rego, cel, policy-as-code, admission-control]
date: 2026-06-16
description: Module 15 of 20 — policy-as-code with OPA, Kyverno, and CEL. Writing admission-control policies, RBAC policies, and CI gate policies in code. Version-controlled, testable, auditable policy.
---

# M15: Policy-as-Code

Policy-as-code is the discipline of writing security and operational rules in a programming language, not a ticketing system. It applies to every layer: admission control, CI gates, cloud config, network policy. This module covers the major policy engines (OPA, Kyverno, CEL), the pattern of writing testable policies, and the operational discipline that makes policy work at scale.

## Learning Objectives

By the end of this module you should be able to:

  - Write a Kyverno policy for Kubernetes admission control
  - Write an OPA/Rego policy for arbitrary structured data
  - Write a CEL policy for Kubernetes-native use cases
  - Test a policy in isolation
  - Version-control, review, and roll out policy changes
  - Map policy-as-code to compliance controls

## 1. Why Policy-as-Code

The opposite: policy in a wiki page, enforced by humans. The failure modes are well known:

  - The wiki is out of date
  - Two engineers interpret the wiki differently
  - The exception process is by email
  - Audit is a quarterly scramble

Policy-as-code fixes each:

  - The policy is in git; "out of date" means "not committed"
  - The policy is code; interpretation is deterministic
  - Exceptions are coded (waiver, expiry)
  - Audit is a git log + a CI history

```
  Policy in wiki            Policy as code
  -----------              --------------
  "All images must         kyverno:
   be from approved          - name: only-approved-registries
   registries"               spec:
                               validationFailureAction: Enforce
                               rules:
                                 - match:
                                     resources:
                                       kinds: ["Pod"]
                                   validate:
                                     message: "Image not from approved registry"
                                     pattern:
                                       spec:
                                         containers:
                                           - image: "registry.example.com/*"
```

The right side is reviewable, testable, version-controlled, and enforced by a machine.

## 2. The Engines

### OPA (Open Policy Agent)

The most general-purpose engine. Policy is written in Rego. Input is any structured JSON/YAML. Output is a decision (allow/deny + reason).

Used for:
  - Kubernetes admission (via Gatekeeper)
  - Terraform plan validation
  - CI gate policies
  - API authorization
  - Anywhere you can express input as JSON

### Kyverno

Kubernetes-native. Policy is YAML; no new language to learn. Specifically designed for K8s admission control. Best for K8s-only shops.

### CEL (Common Expression Language)

Google's policy expression language. Built into Kubernetes as an admission alternative. Best for simple, focused policies on K8s resources.

### Comparison

| Aspect | OPA/Rego | Kyverno | CEL |
| ------ | -------- | ------- | --- |
| Learning curve | Steep (Rego) | Gentle (YAML) | Medium (expressions) |
| Scope | Anything JSON | K8s only | K8s only |
| Background generation | Yes (OPA bundle) | Yes (background scans) | Limited |
| Testing | `opa test` | `kyverno test` | Embedded |
| Mutation | Yes | Yes (more ergonomic) | Limited |
| Validation | Yes | Yes | Yes |
| Best for | Multi-system policy | K8s admission | K8s simple policies |

For most teams starting policy-as-code in a K8s environment, **Kyverno is the default** — the YAML syntax is more accessible to engineers who do not want to learn Rego. For multi-system policy (K8s + Terraform + API), OPA is the better fit.

## 3. Kyverno: The K8s-Native Engine

### Install

```bash
helm repo add kyverno https://kyverno.github.io/kyverno
helm install kyverno kyverno/kyverno --namespace kyverno --create-namespace
```

### Policy Structure

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-non-root
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: check-security-context
      match:
        resources:
          kinds: ["Pod"]
      validate:
        message: "Pods must run as non-root user"
        pattern:
          spec:
            containers:
              - securityContext:
                  runAsNonRoot: true
                  runAsUser: "> 0"
                  allowPrivilegeEscalation: false
                  capabilities:
                    drop: ["ALL"]
                  readOnlyRootFilesystem: true
```

`validationFailureAction: Enforce` blocks non-compliant pods. `Audit` logs but allows; useful for rollout.

### Mutation Policies

Kyverno can mutate resources on the fly:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-default-network-policy
spec:
  rules:
    - name: add-default-deny
      match:
        resources:
          kinds: ["Namespace"]
      mutate:
        patchStrategicMerge:
          metadata:
            labels:
              network-policy: "default-deny"
```

### Image Verification

Kyverno can verify image signatures (M13) inline:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signature
spec:
  validationFailureAction: Enforce
  rules:
    - name: verify-cosign
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
                      ...
                      -----END PUBLIC KEY-----
```

The pod is rejected if the image is not signed by the expected key.

## 4. OPA/Rego: The General-Purpose Engine

### A Terraform Plan Policy

```rego
package terraform.s3

deny[msg] {
  resource := input.resource.aws_s3_bucket[name]
  resource.acl == "public-read"
  msg := sprintf("S3 bucket '%s' has public-read ACL; use 'private' or a CloudFront OAC", [name])
}

deny[msg] {
  resource := input.resource.aws_s3_bucket[name]
  not resource.server_side_encryption_configuration
  msg := sprintf("S3 bucket '%s' is missing server-side encryption", [name])
}
```

Run with Conftest:

```bash
terraform show -json | conftest verify --policy ./policy
```

The Terraform plan JSON is the input; the Rego policy emits deny messages; Conftest reports.

### A Kubernetes Admission Policy

```rego
package kubernetes.admission

deny[msg] {
  input.request.kind.kind == "Pod"
  container := input.request.object.spec.containers[_]
  container.securityContext.runAsNonRoot != true
  msg := sprintf("Container '%s' in pod must set runAsNonRoot: true", [container.name])
}
```

Run via Gatekeeper.

### Test the Policy

```rego
# policy_test.rego
package terraform.s3

test_public_read_denied {
  deny["S3 bucket 'x' has public-read ACL"] with input as {
    "resource": {
      "aws_s3_bucket": {
        "x": {"acl": "public-read"}
      }
    }
  }
}

test_private_allowed {
  count(deny) == 0 with input as {
    "resource": {
      "aws_s3_bucket": {
        "x": {"acl": "private", "server_side_encryption_configuration": {"a": "b"}}
      }
    }
  }
}
```

```bash
opa test ./policy
```

The test suite is part of the policy repo. Policy changes require test changes; PR review catches both.

## 5. CEL: Simple K8s Policies

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: require-image-from-approved-registry
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
  validations:
    - expression: "object.spec.containers.all(c, c.image.startsWith('registry.example.com/'))"
      message: "All containers must use registry.example.com/*"
```

CEL is built into K8s; no admission controller to install. Limited to K8s, but lightweight.

## 6. Policy Tests Are Non-Negotiable

A policy without tests is a bug waiting to ship. Required tests:

  - **Positive test** — the policy allows what should be allowed
  - **Negative test** — the policy denies what should be denied
  - **Boundary test** — edge cases (null values, missing fields, empty arrays)
  - **Regression test** — a real production incident, captured as a test case

For Kyverno:

```yaml
# kyverno-test.yaml
name: require-non-root
policies:
  - policy.yaml
tests:
  - name: should-pass-non-root
    resources:
      - pod.yaml
    result: pass
  - name: should-fail-root
    resources:
      - pod-root.yaml
    result: fail
```

```bash
kyverno test ./policies
```

For OPA:

```bash
opa test ./policy -v
```

## 7. Policy Versioning and Rollout

### The Pattern

  - Policy lives in a git repo (e.g., `org/policies`)
  - Changes go through PR review (two approvers for production policies)
  - CI runs the test suite
  - Deploy: `kubectl apply -f policies/` (or Argo CD / Flux for GitOps)

### Rollout Strategy

  - **Audit mode** — `validationFailureAction: Audit` — log but allow
  - **Monitor** — wait 1–2 weeks; collect the audit logs
  - **Fix** — fix the workloads that violate (usually <10%)
  - **Enforce** — change to `Enforce`; violations now block

The same pattern for OPA: `dryRun: true` initially, then remove.

### Exceptions

Every policy has exceptions. Two patterns:

#### Pattern 1: Waivers in Code

```yaml
apiVersion: kyverno.io/v1
kind: PolicyException
metadata:
  name: legacy-app-waiver
  namespace: kyverno
spec:
  exceptions:
    - policyName: require-non-root
      ruleNames: ["check-security-context"]
  match:
    resources:
      kinds: ["Pod"]
      names: ["legacy-app"]
      namespaces: ["legacy"]
  ttl: 90  # waiver expires
```

The exception has an expiration. The exception is in git, not in someone's head.

#### Pattern 2: Namespace-Based Exemptions

```yaml
rules:
  - name: require-non-root
    match:
      resources:
        kinds: ["Pod"]
      exclude:
        resources:
          namespaces: ["kube-system", "monitoring"]
```

## 8. Policy in CI

CI is the second enforcement layer. Even before admission control, the CI pipeline can enforce:

  - SAST/SCA policy: "fail the build on critical"
  - IaC policy: "fail the PR on public S3"
  - Image policy: "fail on unsigned image"

OPA + Conftest in CI:

```yaml
- name: OPA Policy Check
  run: |
    terraform show -json > plan.json
    conftest verify --policy ./policy plan.json
```

Kyverno CLI in CI:

```yaml
- name: Kyverno Policy Check
  run: |
    kyverno apply ./policies --resource ./manifests/
```

The same policy runs in two places: CI (catch early) and admission (catch everything). The CI run is faster; the admission run is comprehensive.

## 9. Common Policies to Ship First

| Policy | Why |
| ------ | --- |
| No privileged containers | Single most common K8s misconfiguration |
| No root user | Blast-radius reducer |
| Read-only root filesystem | Defense in depth |
| Drop all capabilities | Principle of least privilege |
| Image from approved registry | Supply chain |
| Image signature verified | Supply chain |
| Resource limits set | QoS, scheduling |
| Network policy exists | Lateral movement prevention |
| No hostNetwork / hostPID | Container isolation |
| Labels required (owner, env, data-class) | Operational hygiene |

Ship the first five in week 1; the rest in the first quarter.

## 10. Policy-as-Code Anti-Patterns

| Anti-pattern | Symptom | Fix |
| ------------ | ------- | --- |
| Policy in a wiki | Drift, no enforcement | Move to code |
| Policy without tests | Surprise blocks in prod | `opa test` / `kyverno test` in CI |
| Direct `kubectl apply` of policies | No review, no audit | GitOps (Argo CD / Flux) |
| No exception expiry | Waivers live forever | `ttl: 90` on exceptions |
| One policy for all clusters | Too strict or too loose | Per-cluster overlays + org floor |
| `Enforce` on day 1 | Everything breaks | `Audit` first, then `Enforce` |

## 11. Policy Governance

For a mid-size org (50+ engineers):

  - **Policy author** — security team or platform team
  - **Policy reviewer** — anyone affected by the policy; two reviewers for prod
  - **Policy owner** — the team that owns the policy
  - **Policy steward** — overall responsibility; usually the security lead

Quarterly review: which policies have exceptions? Which have no audit hits? Which are bypassed? Adjust accordingly.

## 12. Mapping to Compliance

| Framework | Control | Policy |
| --------- | ------- | ------ |
| SOC2 CC6.6 | Logical access controls | RBAC + admission policy |
| SOC2 CC7.2 | System monitoring | Audit mode for all policies |
| CIS K8s 5.1.1 | No privileged containers | Kyverno no-privileged |
| CIS K8s 5.2.1 | Minimize admin containers | Kyverno no-root |
| PCI-DSS 1.2.1 | NSCs | Network policy required |
| ISO 27001 A.8.32 | Change management | GitOps for policy changes |
| FedRAMP AC-6 | Least privilege | Kyverno drop-capabilities |

The policy is the *implementation* of the control. The audit evidence is the git log + the admission logs.

## 13. Self-Check

  1. Pick one policy from section 9. Write it in Kyverno or Rego. Test it. Apply in audit mode.
  2. How many of your current policies have exceptions? Do those exceptions have expiry dates?
  3. If you flipped all your policies from `Audit` to `Enforce` today, what would break? The list is your remediation backlog.

## 14. The Policy-as-Code Library Pattern

A paved-road policy library follows the same pattern as the paved-road module library (M10):

```
  policies/
  ├── k8s/
  │   ├── baseline/
  │   │   ├── require-non-root.yaml
  │   │   ├── read-only-root-fs.yaml
  │   │   ├── drop-capabilities.yaml
  │   │   └── no-privileged.yaml
  │   ├── networking/
  │   │   ├── default-deny.yaml
  │   │   └── no-host-network.yaml
  │   └── supply-chain/
  │       ├── signed-images-only.yaml
  │       └── approved-registries.yaml
  ├── terraform/
  │   ├── s3-no-public.yaml
  │   ├── iam-least-privilege.yaml
  │   └── kms-key-policies.yaml
  └── ci/
      ├── block-on-critical.yaml
      └── require-approval-prod.yaml
```

A library is versioned, tested, and consumed via GitOps (Argo CD / Flux for K8s, Atlantis for Terraform).

## 15. Policy Composition

Real-world policies compose. A common pattern:

```yaml
# base-pod-security.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: base-pod-security
spec:
  rules:
    - name: no-privileged
      ...
    - name: non-root
      ...
    - name: read-only-fs
      ...
    - name: drop-caps
      ...
```

```yaml
# prod-overlay.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: prod-overlay
spec:
  rules:
    - name: prod-extra-network-isolation
      match:
        resources:
          namespaces: ["prod"]
      ...
```

The base policy applies to all clusters; the overlay applies to specific environments. Teams consume the base; their overlays add environment-specific rules.

## 16. Policy as a CI Gate

Some policies run in CI, not in admission control:

  - **Terraform plan validation** — conftest, OPA, tfsec, Checkov
  - **K8s manifest validation** — kubeconform, kubectl --dry-run, Kyverno CLI
  - **Helm chart validation** — conftest on the rendered output
  - **OPA on arbitrary JSON** — anything structured

The CI gate is *faster* than admission control (it runs before the PR is merged). The admission control is *comprehensive* (it runs against the final manifest at deploy).

Run the policy in both. The CI gate catches issues during development; admission control catches issues that slipped through.

```yaml
# CI gate for Terraform
- name: OPA Policy Check
  run: |
    terraform plan -out=tfplan
    terraform show -json tfplan > plan.json
    conftest verify --policy ./policy plan.json
```

```yaml
# Admission control
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: enforce-s3-no-public
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-s3-acl
      match:
        resources:
          kinds: ["S3Bucket"]  # CRD or similar
      validate:
        message: "S3 buckets cannot have public-read ACL"
        pattern:
          spec:
            forProvider:
              acl: "private"
```

Same policy, two enforcement points.

## 17. Policy and Compliance

| Framework | Control | Policy |
| --------- | ------- | ------ |
| SOC 2 CC6.1 | Logical access | RBAC, network policies |
| SOC 2 CC6.6 | Boundary | K8s NetworkPolicy, AWS SG |
| SOC 2 CC7.2 | Monitoring | Audit mode for all policies |
| SOC 2 CC8.1 | Change management | GitOps for policy changes |
| ISO A.8.16 | Monitoring | Audit logs of policy decisions |
| ISO A.8.32 | Change management | Policy PR history |
| PCI 1.2 | NSCs | Network policies |
| PCI 6.4 | Change control | GitOps for policy |
| CIS K8s 5.x | Container security | Kyverno/Kyverno equivalents |
| FedRAMP AC-6 | Least privilege | Drop capabilities, runAsNonRoot |

The policy is the *implementation*. The audit evidence is the policy PR history + admission logs.

## 18. Policy Authoring Anti-Patterns (Extended)

| Anti-pattern | Symptom | Fix |
| ------------ | ------- | --- |
| Copy-pasted policy from the internet | Doesn't fit your environment | Customize; test in audit mode |
| Policy in a different repo from the app | Drift, no review | Policy in app repo, or co-located |
| No tests | Surprises in prod | `opa test`, `kyverno test` in CI |
| No exceptions allowed | Engineers find workarounds | Document exception process, with TTL |
| Exceptions are permanent | Tech debt accumulates | Expiry on every exception |
| Policy without a metric | Can't tell if it's working | Count admissions, denials, exceptions |
| Policy with no owner | Drift, no review | Every policy has an owner and a review date |

## 19. The Policy Lifecycle

A policy has a lifecycle similar to code:

```
  1. Authoring — write the policy, add tests
  2. PR review — security + affected team
  3. CI — test the policy
  4. Apply in audit mode — collect evidence
  5. Switch to enforce — for real
  6. Operate — monitor denials, exceptions
  7. Tune — adjust based on production data
  8. Deprecate — when the threat is no longer relevant
```

A policy that sits in audit mode forever is a policy that does not work. The lifecycle enforces accountability.

## 20. Policies Across the Stack

The same pattern applies at every layer:

  - **Application** — OPA on request (e.g., authorization)
  - **CI/CD** — conftest on Terraform plan
  - **K8s admission** — Kyverno / OPA Gatekeeper
  - **Cloud** — AWS Config, Azure Policy, GCP Org Policy
  - **Network** — VPC flow logs, NACLs
  - **Identity** — IAM policies, RBAC

The discipline is the same: policy in code, test, version, review, deploy, monitor. The tool differs by layer.

A unified policy story:
  - Author in OPA Rego
  - Test with `opa test`
  - Deploy to multiple enforcement points (CI, admission, runtime)
  - Monitor across all points

## Related

  - [[DevOps/devsecops/stage0-foundations/03-secure-sdlc|M03: Secure SDLC]]
  - [[DevOps/devsecops/stage2-build/10-iac-security|M10: IaC Security]]
  - [[DevOps/devsecops/stage3-deploy/13-artifact-signing|M13: Artifact Signing]]
  - [[DevOps/devsecops/stage3-deploy/14-supply-chain-attestations|M14: Supply Chain Attestations]]
  - [[DevOps/devsecops/stage3-deploy/README|Stage 3 — Deploy]]
