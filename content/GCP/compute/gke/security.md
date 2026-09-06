---
title: GKE Security & Hardening — Workload Identity & Binary Authorization
description: GKE security architecture — Workload Identity, Shielded Nodes, Binary Authorization deploy-time image validation, Network Policies, and Master Authorized Networks.
tags:
  - gcp
  - compute
  - gke
  - kubernetes
  - security
  - supply-chain
---

# GKE Security & Hardening — Workload Identity & Binary Authorization 🛡️☸️

Securing Google Kubernetes Engine (GKE) requires defense-in-depth across the entire stack: from the Linux host kernel and container supply chain up to the Kubernetes API and cloud IAM control plane. 

Google Cloud provides three flagship security capabilities built directly into the GKE control plane: **GKE Workload Identity** (eliminating static service account keys), **Binary Authorization** (cryptographically enforcing that only signed, verified container images can deploy), and **Shielded GKE Nodes** (hardware-rooted hypervisor integrity).

---

## Architecture & Mental Model

### GKE Supply Chain & Runtime Defense Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Build & Supply Chain Plane                      │
│                                                                        │
│   CI/CD (Cloud Build / GitHub Actions)                                 │
│   ├── 1. Builds container image: us-docker.pkg.dev/app:v1.0            │
│   ├── 2. Runs vulnerability scan (Trivy / Container Analysis)          │
│   └── 3. Signs image with Cloud KMS Key via Cosign / Grafeas Attestor  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                       Deploy-Time Admission Control                    │
│                                                                        │
│   GKE Kubernetes API Server                                            │
│   ├── 4. Intercepts Deployment request via Admission Webhook           │
│   └── 5. Binary Authorization Evaluator:                               │
│          Checks image signature against Cloud KMS Public Key           │
│          ├── Signature Valid & Vulnerabilities Clean ──► ALLOW DEPLOY  │
│          └── Unsigned Image or Vulnerable ──────────► REJECT (HTTP 403)│
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                          Runtime Execution Plane                       │
│                                                                        │
│   Worker Node (Shielded VM: Secure Boot + vTPM)                        │
│   ├── GKE Metadata Server: Intercepts IMDS tokens for Workload Identity│
│   └── Datapath V2 (eBPF): Enforces default-deny NetworkPolicies        │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Core Concepts

### 1. Workload Identity Hardening

* **The Node Service Account Vulnerability:** By default, if Workload Identity is disabled, all pods on a GKE node inherit the broad Google Service Account attached to the underlying VM (historically the default Compute Engine SA with primitive `Editor` permissions!). A compromised pod can curl the metadata server and steal project-wide credentials.
* **Workload Identity Protection:**
  * Maps a Kubernetes ServiceAccount (`KSA`) in a specific namespace to a Google Cloud ServiceAccount (`GSA`).
  * The **GKE Metadata Server** intercepts pod requests to `http://metadata.google.internal/` and validates the calling Pod's projected identity token before issuing a short-lived GCP OAuth2 access token.
  * Completely strips the underlying VM's credentials from the Pod network namespace.

### 2. Binary Authorization (Deploy-Time Supply Chain Enforcement)

Binary Authorization is a deploy-time security control that ensures only trusted container images are launched in your GKE cluster:
* **Attestor:** An identity (backed by a Cloud KMS asymmetric signing key) that certifies an image has passed required checks (e.g. security scanning, QA testing).
* **Policy:** A rule configured at the project level specifying which attestors are mandatory.
* **Admission Controller:** When `kubectl apply` or Helm submits a pod spec to the cluster, the Binary Authorization admission controller checks the image against the policy. Unsigned images are blocked before they ever pull to a node.
* **Breakglass Mode:** In a high-priority production incident, operators can bypass the policy by annotating the pod with `image-policy.k8s.io/break-glass: "true"`. All breakglass actions trigger an immediate high-severity Cloud Audit Log event.

### 3. Shielded GKE Nodes

Shielded GKE nodes protect the host operating system against rootkits and boot-level malware:
* **Secure Boot:** Verifies the cryptographic signature of every bootloader component, kernel, and driver against trusted certificates.
* **Virtual Trusted Platform Module (vTPM):** Provides hardware-level measured boot by measuring kernel state during startup.
* **Integrity Monitoring:** Continuously compares current host measurements against baseline measurements, alerting Security Command Center if integrity is breached.

### 4. Master Authorized Networks

Restricts access to the GKE control plane API server (`kube-apiserver`):
* Even if a cluster is public or uses a public master endpoint, Master Authorized Networks enforces firewall-level IP allowlisting.
* Blocks unauthorized internet port scanners from reaching port 443 on the Kubernetes API server.

---

## Production `gcloud` CLI & YAML Configurations

### 1. Enabling Binary Authorization on a Cluster

```bash
# 1. Enable Binary Authorization API
gcloud services enable binaryauthorization.googleapis.com

# 2. Update GKE cluster to enforce Binary Authorization
gcloud container clusters update prod-cluster \
  --region=us-central1 \
  --binauthz-evaluation-mode=PROJECT_SINGLETON_POLICY_ENFORCE
```

### 2. Creating a Cloud KMS Key & Binary Authorization Attestor

```bash
# 1. Create a Cloud KMS key ring and asymmetric signing key
gcloud kms keyrings create binauth-keyring --location=us-central1

gcloud kms keys create prod-attestor-key \
  --location=us-central1 \
  --keyring=binauth-keyring \
  --purpose=asymmetric-signing \
  --default-algorithm=rsa-sign-pkcs1-4096-sha512

# 2. Create the Container Analysis Attestation Note
cat <<EOF > note.json
{
  "name": "projects/my-prod-project/notes/prod-attestor-note",
  "attestation": {
    "hint": {
      "human_readable_name": "Production Deploy Attestor"
    }
  }
}
EOF

curl -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  --data-binary @note.json \
  "https://containeranalysis.googleapis.com/v1/projects/my-prod-project/notes/?noteId=prod-attestor-note"

# 3. Create the Attestor linked to the Note and KMS Key
gcloud container binauthz attestors create prod-attestor \
  --attestation-authority-note=prod-attestor-note \
  --attestation-authority-note-project=my-prod-project

gcloud container binauthz attestors public-keys add \
  --attestor=prod-attestor \
  --keyversion-project=my-prod-project \
  --keyversion-location=us-central1 \
  --keyversion-keyring=binauth-keyring \
  --keyversion-key=prod-attestor-key \
  --keyversion=1
```

### 3. Deploying a Default-Deny Ingress/Egress NetworkPolicy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {} # Matches all pods in namespace
  policyTypes:
    - Ingress
    - Egress
---
# Explicitly permit DNS lookup to CoreDNS / Datapath V2
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Attestors per project** | 100 attestors | Multiple signing stages in CI/CD |
| **Master Authorized Networks CIDRs** | Up to 50 CIDR blocks | Include corporate VPN & CI/CD runners |
| **Workload Identity token lifetime** | 1 hour | Automatically renewed by Google SDKs |
| **Shielded Node reboot verification** | Continuous | Monitored by Cloud Logging |

---

## References

* **GKE Security Overview:** https://cloud.google.com/kubernetes-engine/docs/concepts/security-overview
* **GKE Hardening Guide:** https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster-infrastructure
* **Binary Authorization Documentation:** https://cloud.google.com/binary-authorization/docs
* **Pricing:** https://cloud.google.com/binary-authorization/pricing (Binary Authorization is billed at ~$0.026 per million evaluations; GKE Workload Identity is free)

---

## Pricing Examples

### Scenario 1: Enterprise GKE Hardening Suite
* 5 Production GKE clusters running 200 nodes and 2,500 pods in `us-central1`.
* Workload Identity: **$0.00** (Free).
* Shielded GKE Nodes (Secure Boot & vTPM): **$0.00** (Free).
* Master Authorized Networks: **$0.00** (Free).
* Cloud KMS Key for signing container images: 1 Asymmetric Key = **$0.06 / month**.
* Binary Authorization Evaluation: 10,000 deployments / month = **negligible (< $0.01)**.
* **Total Monthly Security Hardening Cost:** **~$0.06 / month**.

### Scenario 2: Container Vulnerability Scanning via Artifact Analysis
* 50 active container repositories building 500 images per month.
* Automatic vulnerability scanning on push: ~$0.26 per scanned image.
* Monthly cost: 500 × $0.26 = **$130.00 / month** (Feeds CVE findings directly into Binary Authorization).

---

## Nuggets & Gotchas

1. **Breakglass Auditing Alerts:** In an emergency outage where an unsigned hotfix container must be deployed, adding `image-policy.k8s.io/break-glass: "true"` allows the pod to run despite Binary Authorization restrictions. However, this triggers an immutable `ALERT` finding in Cloud Audit Logs. Configure a Cloud Monitoring alert that sends a PagerDuty notification whenever a breakglass event occurs.
2. **Missing `allow-dns-egress` Drops Pods Instantly:** Applying a default-deny egress NetworkPolicy without explicitly whitelisting UDP/TCP port 53 to `kube-dns` breaks DNS resolution for every pod in that namespace. Pods will fail health checks, database lookups, and API calls within seconds. Always deploy the DNS allow policy simultaneously.
3. **Master Authorized Networks CIDR Lockout:** If an administrator enables Master Authorized Networks and provides their home office dynamic IP address (e.g. `203.0.113.5/32`), their ISP may rotate their IP the next day. The administrator will be completely locked out of running `kubectl` against the cluster API server until they update the authorized CIDR via `gcloud container clusters update`.
4. **Binary Authorization System Image Whitelisting:** When configuring a custom Binary Authorization policy, ensure you enable the option **"Allow Google-maintained system images"**. Disabling this will block GKE system pods (like `kube-dns`, metrics-server, and the CSI driver) from booting, bricking the cluster on its next upgrade.
5. **Node Service Account Privilege Revocation:** When Workload Identity is enabled, remember to remove the `Editor` role from the node's underlying Compute Engine service account. If the node VM retains `Editor`, an attacker who escapes a container or compromises a `hostNetwork: true` pod can still access the node's elevated credentials.
