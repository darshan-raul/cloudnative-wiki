---
title: AKS Governance — Azure Policy for Kubernetes and OPA Gatekeeper Guardrails
description: Exhaustive engineering guide to declarative governance on AKS — Azure Policy add-on, Open Policy Agent (OPA) Gatekeeper, CIS Kubernetes benchmarks, custom Rego constraint templates, and audit vs deny enforcement modes.
tags:
  - azure
  - aks
  - governance
  - azure-policy
  - gatekeeper
  - opa
  - security
  - compliance
---

# AKS Governance — Azure Policy for Kubernetes and OPA Gatekeeper Guardrails 🏛️📜

In large enterprise organizations, development teams deploy thousands of container manifests daily across multiple AKS clusters. Without centralized policy enforcement, clusters inevitably suffer from **security drift: developers run unhardened privileged containers, omit mandatory resource requests, expose internal databases via public LoadBalancers, or pull unvetted container images from public Docker Hub**. AKS solves this through the **Azure Policy Add-on for Kubernetes**, which operationalizes **Open Policy Agent (OPA) Gatekeeper** directly within the Kubernetes admission control pipeline.

---

## 1. Architecture: The Admission Interception Loop

```
       DEVELOPER / CI/CD PIPELINE (`kubectl apply -f deployment.yaml`)
                                  │
                                  ▼ Sends AdmissionReview API Request
       ┌────────────────────────────────────────────────────────────────────────┐
       │                      KUBERNETES API SERVER                             │
       └──────────────────────────────────┬─────────────────────────────────────┘
                                          │ Webhook Interception Call (HTTPS 8443)
                                          ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                OPA GATEKEEPER VALIDATING ADMISSION WEBHOOK             │
       │                (`gatekeeper-controller-manager` Pods)                  │
       │                                                                        │
       │  Step 1: Intercepts Pod / Deployment manifest                          │
       │  Step 2: Evaluates constraints against in-memory Rego policy engine    │
       │  Step 3: Checks:                                                       │
       │          - Is container privileged? -> DENY                            │
       │          - Are required tags present? -> DENY                          │
       │          - Is root filesystem read-only? -> ALLOW                      │
       └───────────────────┬────────────────────────────────┬───────────────────┘
                           │                                │
        Violation (DENY)   ▼                                ▼ Passes Evaluation (ALLOW)
       ┌───────────────────────────────┐        ┌───────────────────────────────┐
       │ BLOCKS DEPLOYMENT (403 Error) │        │ ADMITS WORKLOAD TO ETCD       │
       │ - Detailed error returned to  │        │ - Kubelet schedules container │
       │   CI/CD terminal console      │        │ - Workload runs securely      │
       └───────────────────────────────┘        └───────────────────────────────┘
                           │ Continuous Compliance Reporting
                           ▼
       ┌────────────────────────────────────────────────────────────────────────┐
       │                      AZURE POLICY ENGINE (CLOUD)                       │
       │  - Centralized compliance dashboard across all enterprise clusters     │
       │  - Compliance audit logs synced to Microsoft Defender for Cloud        │
       └────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Policy Enforcement Modes: Audit vs. Deny

| Policy Mode | Operational Behavior | Impact on Production CI/CD | Recommended Phase |
| :--- | :--- | :--- | :--- |
| **Audit** | Flags non-compliant resources in Azure Policy compliance dashboard; allows pods to deploy | **Zero disruption to running applications** | Day 0–30: Discovery & Baselining |
| **Deny** | Intercepts admission requests; immediately blocks non-compliant resources with HTTP 403 | **Blocks breaking deployments at deploy-time**| Day 31+: Production Enforcement |
| **Disabled** | Completely turns off rule evaluation for targeted namespaces | Skips evaluation | Emergency Break-Glass |

---

## 3. Built-in Security Initiatives for AKS

Microsoft packages hundreds of OPA Gatekeeper constraints into curated **Azure Policy Initiatives**:
1. **Kubernetes cluster pod security baseline standards:** Restricts privilege escalation, host networking, host ports, and capabilities.
2. **Kubernetes cluster pod security restricted standards:** Enforces rootless execution (`runAsNonRoot: true`), read-only root filesystems, and drops all Linux capabilities.
3. **CIS Microsoft Azure Kubernetes Service (AKS) Benchmark:** Audits and enforces CIS Foundation security baselines.

---

## 4. Production Deployment & CLI Operations (`az` CLI & `kubectl`)

### 1. Enable Azure Policy Add-on on AKS

```bash
# Enable Azure Policy add-on for Kubernetes
az aks enable-addons \
    --resource-group rg-prod-governance \
    --name aks-core-prod \
    --addons azure-policy

# Verify Gatekeeper and Azure Policy pods are operational in gatekeeper-system
kubectl get pods -n gatekeeper-system
```

### 2. Assign Built-in Initiative (Pod Security Restricted) via Azure CLI

Assign the Pod Security Restricted initiative in `Deny` mode across the cluster:

```bash
export CLUSTER_ID=$(az aks show \
    --resource-group rg-prod-governance \
    --name aks-core-prod \
    --query "id" -o tsv)

# Assign built-in policy initiative (Disallow Privileged Containers)
az policy assignment create \
    --name "aks-block-privileged-containers" \
    --display-name "Kubernetes clusters should not allow privileged containers" \
    --scope "${CLUSTER_ID}" \
    --policy "95ecb845-22e3-4ba6-ac66-bc373b8ca732" \
    --params '{"effect":{"value":"Deny"}}'
```

### 3. Deploy Custom Rego Constraint Template

Enforce that all pods must define explicit CPU and memory resource limits to prevent noisy neighbors:

Create `k8s-require-resources-template.yaml`:

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequireresources
spec:
  crd:
    spec:
      names:
        kind: K8sRequireResources
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequireresources
        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          not container.resources.limits.cpu
          msg := sprintf("Container <%v> does not define required cpu limit!", [container.name])
        }
        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          not container.resources.limits.memory
          msg := sprintf("Container <%v> does not define required memory limit!", [container.name])
        }
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireResources
metadata:
  name: require-cpu-and-memory-limits
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    excludedNamespaces: ["kube-system", "gatekeeper-system"]
```

Apply template and constraint:

```bash
kubectl apply -f k8s-require-resources-template.yaml
```

### 4. Test Policy Violation Rejection

Attempt to deploy a non-compliant pod without resource limits:

```bash
kubectl run test-rogue-pod --image=nginx:alpine
# Expected Error Output:
# Error from server (Forbidden): admission webhook "validation.gatekeeper.sh" denied the request:
# [require-cpu-and-memory-limits] Container <test-rogue-pod> does not define required cpu limit!
```

---

## 5. Quotas, Performance & Configuration Limits

| Dimension | Metric / Platform Limit | Production Rule |
| :--- | :--- | :--- |
| **Admission Webhook Latency** | **< 30 milliseconds** | In-memory Rego evaluation minimizes deploy overhead |
| **Webhook Timeout Setting** | **3 to 5 seconds** | Webhooks time out if Gatekeeper is unresponsive |
| **Audit Sync Interval** | **15 minutes** | Azure Policy reconciles compliance state periodically |
| **Max Custom Constraints** | Up to **500 Constraints** | High rule counts consume node memory |
| **Failure Policy** | `Ignore` (Fail-Open) / `Fail` (Fail-Closed) | Set `Ignore` in non-prod to avoid locking cluster |

---

## 6. Official References

- [Understand Azure Policy for Kubernetes](https://learn.microsoft.com/en-us/azure/governance/policy/concepts/policy-for-kubernetes)
- [Secure AKS Clusters with Azure Policy](https://learn.microsoft.com/en-us/azure/aks/use-azure-policy)
- [Open Policy Agent (OPA) Gatekeeper Documentation](https://open-policy-agent.github.io/gatekeeper/website/docs/)
- [Azure Policy Built-in Definitions for AKS](https://learn.microsoft.com/en-us/azure/aks/policy-reference)

---

## 7. Realistic Pricing Scenarios

### Scenario A: Enterprise FinOps & Security Baseline (10 AKS Clusters)

- **Architecture:** 10 AKS clusters (500 worker nodes) running Azure Policy for Kubernetes.
- **Enforcement Scope:** CIS benchmarks, rootless execution, mandatory cost-center labels.
- **Monthly Cost Breakdown:**
  - Azure Policy Add-on for AKS: **$0.00 (Completely Free Platform Service)**.
  - Gatekeeper Pod Resource Overhead (2 pods per cluster): 2 × 0.5 vCPU, 1 GiB RAM = **$0.00 extra cloud bill** (Absorbed by existing system node pool).
  - Azure Policy Compliance State Storage: **$0.00**.
- **Total Monthly Governance Cost:** **$0.00 / month** *(Delivering 100% compliance automation without third-party licensing fees).*

### Scenario B: Regulatory Compliance Reporting via Microsoft Defender for Cloud

- **Architecture:** Regulatory audit integration with Defender for Cloud for real-time compliance dashboards.
- **Monthly Cost Breakdown:**
  - Defender for Containers: 500 nodes × $7.00/node/month = **$3,500.00**
  - Azure Policy Add-on Integration: **$0.00**
- **Total Monthly Cost:** **$3,500.00 / month**

---

## 8. Battle-Tested Nuggets & Production Gotchas

1. **The Fail-Closed Webhook API Server Lockout:** Gatekeeper's ValidatingWebhookConfiguration defaults to `failurePolicy: Fail` on certain built-in initiatives. If all Gatekeeper controller pods crash or experience CPU starvation during an incident, the Kubernetes API server will reject **ALL future pod creation requests, autoscaling deployments, and Helm releases cluster-wide** with `failed calling webhook: context deadline exceeded`. In non-prod clusters, configure `failurePolicy: Ignore`.
2. **Missing System Namespace Exclusions:** When writing custom Gatekeeper constraints, **always explicitly exclude system namespaces** (`kube-system`, `gatekeeper-system`, `calico-system`). If a policy mandates that all pods must define a specific organizational label (`cost-center`), critical system pods (like `coredns` or `azure-cni`) scaling during an outage will be blocked, causing complete cluster failure.
3. **Audit Mode First: Never Deploy Direct to Deny:** Never apply a new security policy directly in `Deny` mode to a running production cluster. Even if existing pods remain running, subsequent rolling deployments, autoscaling events, or emergency bug fixes will be abruptly blocked. Always run in `Audit` mode for at least two weeks to identify and remediate non-compliant workloads.
4. **Policy Sync Latency between Azure and AKS:** When you assign an Azure Policy via the Azure Portal or ARM template, it takes **15 to 30 minutes** for the Azure Policy pod in the cluster to pull the new policy definition and compile the Gatekeeper CRD. Do not expect instantaneous enforcement after creating an Azure Policy assignment.
5. **Rego Memory Leaks on High-Churn Object Auditing:** Rego rules that use unbounded cross-object references (`data.inventory.namespace[_]`) force Gatekeeper to replicate large portions of the Kubernetes API state into RAM. In clusters with rapid pod churn, the `gatekeeper-controller-manager` pod will exhaust memory and be killed with **`OOMKilled (Exit Code 137)`**. Avoid `data.inventory` queries unless strictly necessary.
