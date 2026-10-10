---
title: Policy Management on EKS
tags: [eks, security, policy, kyverno, gatekeeper, admission]
date: 2026-05-17
description: Enforcing custom policy on EKS — choosing between ValidatingAdmissionPolicy, Kyverno and OPA Gatekeeper, the webhook failure modes specific to EKS, and a starter policy set.
---

# Policy Management on EKS

[[Kubernetes/eks/security/pod-security-standards|Pod Security Admission]] covers pod hardening. Everything else an organisation wants to require — images only from its own registry, resource requests on every container, no `latest` tags, a cost-centre label — needs a policy engine that hooks into [[Kubernetes/concepts/L07-security/04-admission-policy/10-admission-controllers|admission control]].

## The options

| Engine                        | Language   | Runs where                  | Validate | Mutate | Generate | Background scan |
| :---------------------------- | :--------- | :-------------------------- | :------- | :----- | :------- | :-------------- |
| **ValidatingAdmissionPolicy** | CEL        | Inside the API server       | Yes      | No     | No       | No              |
| **Kyverno**                   | YAML + CEL | Webhook pods in the cluster | Yes      | Yes    | Yes      | Yes             |
| **OPA Gatekeeper**            | Rego       | Webhook pods in the cluster | Yes      | Yes    | No       | Yes (audit)     |

- **ValidatingAdmissionPolicy (VAP)** is built into Kubernetes. No webhook, no pods, no extra latency, and it cannot be taken down by a node failure. It only validates, and CEL cannot call out to external data.
- **[[Kubernetes/concepts/L07-security/04-admission-policy/12-kyverno|Kyverno]]** writes policies as Kubernetes resources, which most teams find easiest. It can also add defaults, create companion resources (a default NetworkPolicy for every new namespace) and verify image signatures.
- **[[Kubernetes/concepts/L07-security/04-admission-policy/11-opa-gatekeeper|OPA Gatekeeper]]** is the choice when policy is already written in Rego or shared with systems outside Kubernetes, such as Terraform plan checks.

A reasonable default on EKS: VAP for the handful of rules that must never be bypassed, Kyverno for everything that needs mutation, generation or reporting.

## A built-in policy with no moving parts

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: require-ecr-images
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
  validations:
    - expression: >-
        object.spec.containers.all(c,
          c.image.startsWith('111122223333.dkr.ecr.eu-west-1.amazonaws.com/'))
      message: "Images must come from the organisation's ECR registry."
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: require-ecr-images
spec:
  policyName: require-ecr-images
  validationActions: ["Deny"]
  matchResources:
    namespaceSelector:
      matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: NotIn
          values: ["kube-system"]
```

Start a new policy with `validationActions: ["Warn", "Audit"]` and switch to `Deny` once the audit log is clean.

## The same idea in Kyverno, with a mutation

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-requests
spec:
  validationFailureAction: Audit
  background: true
  rules:
    - name: containers-must-set-requests
      match:
        any:
          - resources:
              kinds: ["Pod"]
      exclude:
        any:
          - resources:
              namespaces: ["kube-system", "kyverno"]
      validate:
        message: "CPU and memory requests are required."
        pattern:
          spec:
            containers:
              - resources:
                  requests:
                    cpu: "?*"
                    memory: "?*"
```

`background: true` makes Kyverno evaluate resources that already exist and write `PolicyReport` objects, so you can measure compliance before enforcing.

## EKS-specific failure modes

Webhook-based engines sit in the request path of the API server. On EKS the control plane is in an AWS-managed VPC and reaches your webhook pods through ENIs in your subnets, which creates failure modes that do not exist on a self-managed control plane.

| Symptom                                                          | Cause                                                                                                                   | Fix                                                                                                                      |
| :--------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------- |
| Every `kubectl apply` times out with `context deadline exceeded` | The control plane cannot reach the webhook: node security group blocks the webhook port from the cluster security group | Allow the webhook's target port (often 9443 or 8443) from the control plane                                              |
| Cluster cannot recover after all nodes were replaced             | Webhook has `failurePolicy: Fail` and matches the pods needed to bring the webhook back                                 | Exclude `kube-system` and the engine's own namespace; run 3 replicas across zones                                        |
| Webhook unreachable with a custom CNI                            | Pods have overlay IPs the control plane cannot route to                                                                 | Run the webhook with `hostNetwork: true`                                                                                 |
| Node scale-up stalls                                             | Webhook pods were evicted and nothing can be admitted                                                                   | [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget\|PDB]], priority class, and keep the engine off Spot |

Rules of thumb: always exclude `kube-system`; give the engine a high `priorityClassName`; set webhook timeouts low (a few seconds); and think hard before using `failurePolicy: Fail` on a rule that matches every pod.

## A starter policy set

| Policy                                                        | Mode to start | Engine  |
| :------------------------------------------------------------ | :------------ | :------ |
| Images only from approved registries                          | Enforce       | VAP     |
| No `:latest` tag; digest pinning for production               | Audit         | Kyverno |
| CPU and memory requests required                              | Audit         | Kyverno |
| Required labels: `app`, `team`, `cost-centre`                 | Audit         | Kyverno |
| Block `LoadBalancer` Services without the internal annotation | Enforce       | VAP     |
| Default-deny NetworkPolicy generated for each new namespace   | Generate      | Kyverno |
| Namespaces must carry Pod Security labels                     | Enforce       | VAP     |
| Verify image signatures (cosign / AWS Signer)                 | Audit         | Kyverno |

Keep policies in Git and test them in CI with the engine's CLI (`kyverno test`, `gator test`) so a broken policy is caught before it reaches a cluster.

## Related

- [[Kubernetes/eks/security/README|EKS security overview]]
- [[Kubernetes/concepts/L07-security/04-admission-policy/23-sboms|SBOMs and supply chain]]
- [[DevOps/devsecops/README|DevSecOps curriculum]] — policy as code earlier in the pipeline
- [[Kubernetes/guides/non-functional/multi-tenancy|Multi-tenancy]] — where policy carries the most weight
- [EKS best practices: policy as code](https://docs.aws.amazon.com/eks/latest/best-practices/pod-security.html#_policy_as_code_pac)

## Across the wiki

- [[Azure/governance/policy|Azure Governance — Management Groups, Policy & Locks]] — policy and governance (Azure)
- [[GCP/compute/gke/binary-authorization|GKE Binary Authorization, Container Attestations, and Supply Chain Security]] — policy and governance (GCP)
- [[AWS/management-governance/organizations/README|AWS Organizations]] — policy and governance (AWS)
- [[Azure/compute/aks/governance-azure-policy|AKS Governance — Azure Policy for Kubernetes and OPA Gatekeeper Guardrails]] — policy and governance (Azure)
