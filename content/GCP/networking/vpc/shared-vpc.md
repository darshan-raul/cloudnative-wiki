---
title: GCP Shared VPC Architecture & Cross-Project Networking
description: Shared VPC architecture — Host projects vs Service projects, subnet-level IAM delegation, cross-project service accounts, centralized hybrid connectivity, and enterprise governance.
tags:
  - gcp
  - networking
  - shared-vpc
  - vpc
  - governance
  - security
---

# GCP Shared VPC Architecture & Cross-Project Networking 🌐🏢

Shared VPC allows an enterprise to connect resources from multiple Google Cloud projects to a common Virtual Private Cloud (VPC) network. By centralizing network administration into a **Host Project**, an organization separates network security and hybrid connectivity (owned by Network/Security teams) from application infrastructure (owned by product DevOps teams in **Service Projects**).

---

## Architecture & Mental Model

### Host Project vs. Service Project Topology

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        Host Project: prod-networking-hub                               │
│                   Managed by: Central Network & Security Teams                         │
│                                                                                        │
│   VPC: shared-prod-vpc                                                                 │
│   ├── Cloud Interconnect (Dedicated 10 Gbps to On-Prem)                                │
│   ├── Cloud NAT Gateway (Centralized Outbound Egress)                                  │
│   ├── Global Firewall Policies & Central Route Tables                                  │
│   │                                                                                    │
│   ├── Subnet 1: 10.10.0.0/20 (us-central1-frontend) ──► Shared with Service Project A │
│   └── Subnet 2: 10.20.0.0/20 (us-central1-backend)  ──► Shared with Service Project B │
└───────────────────────────┬────────────────────────────────────────┬───────────────────┘
                            │ Subnet IAM Delegation                  │ Subnet IAM Delegation
                            │ (roles/compute.networkUser)            │ (roles/compute.networkUser)
                            ▼                                        ▼
┌──────────────────────────────────────────┐ ┌──────────────────────────────────────────┐
│     Service Project A: app-payments      │ │      Service Project B: app-analytics    │
│        Managed by: Payments Team         │ │        Managed by: Data Engineering      │
│                                          │ │                                          │
│  Deploys:                                │ │  Deploys:                                │
│  • Compute Engine VMs                    │ │  • GKE Production Cluster                │
│  • GKE Microservice Pods                 │ │  • Cloud SQL with Private IP             │
│  (VMs obtain internal IPs from Subnet 1) │ │  (Pods obtain internal IPs from Subnet 2)│
└──────────────────────────────────────────┘ └──────────────────────────────────────────┘
```

* **Internal Routing Without Peering:** A VM in Service Project A communicates directly with a GKE Pod in Service Project B over internal RFC 1918 addresses at zero latency, because they reside on the **exact same VPC routing domain** inside the Host Project.

---

## Core Concepts

### 1. Separation of Concerns (NetOps vs. DevOps)

* **Host Project Admins (`roles/compute.xpnAdmin` at Org/Folder level):**
  * Enable the Shared VPC host project.
  * Define IP CIDR blocks, create subnets, provision Cloud NAT gateways, and manage Cloud Interconnect circuits.
  * Associate Service Projects to the Host Project.
* **Service Project Admins (DevOps/SRE):**
  * Hold `Owner` or `Editor` rights inside their specific Service Project.
  * Cannot create, alter, or delete subnets or firewall rules.
  * Can only consume the subnets explicitly delegated to them by the network team.

### 2. Subnet-Level IAM Delegation

Permissions to attach instances to a Shared VPC must **never** be granted at the project level:
* **Anti-Pattern:** Granting `roles/compute.networkUser` on the entire Host Project allows developers in Project A to attach VMs to confidential database subnets reserved for Project B.
* **Best Practice:** Grant `roles/compute.networkUser` strictly on individual **Subnet resources**:
  * Payments team gets `roles/compute.networkUser` on `projects/host-proj/regions/us-central1/subnetworks/snet-payments`.

### 3. GKE in a Shared VPC (Service Agent Requirements)

When provisioning a GKE cluster inside a Service Project connected to a Shared VPC, the GKE control plane requires specialized cross-project permissions:
* The **GKE Service Agent** of the Service Project (`service-<service-project-number>@container-engine-robot.iam.gserviceaccount.com`) must be granted:
  * `roles/container.hostServiceAgentUser` at the **Host Project level**.
  * `roles/compute.networkUser` on the specific host subnets (including primary, pod secondary, and service secondary ranges).

---

## Production `gcloud` CLI Commands

### 1. Enabling Shared VPC on the Host Project

```bash
# Executed by an Organization Admin with roles/compute.xpnAdmin:
gcloud compute shared-vpc enable prod-networking-hub
```

### 2. Attaching a Service Project to the Host Project

```bash
gcloud compute shared-vpc associated-projects add app-payments-prod \
  --host-project=prod-networking-hub
```

### 3. Delegating Subnet Access to a Service Project Team

```bash
# Grant the Payments team developer group access to only their designated subnet:
gcloud compute networks subnets add-iam-policy-binding snet-payments \
  --project=prod-networking-hub \
  --region=us-central1 \
  --member="group:payments-devops@company.com" \
  --role="roles/compute.networkUser"
```

### 4. Configuring GKE Cross-Project Service Agent Permissions

```bash
# 1. Retrieve Service Project Number
SERVICE_PROJECT_NUM=$(gcloud projects describe app-payments-prod --format="value(projectNumber)")

# 2. Grant GKE Service Agent the Host Service Agent User role on the Host Project
gcloud projects add-iam-policy-binding prod-networking-hub \
  --member="serviceAccount:service-${SERVICE_PROJECT_NUM}@container-engine-robot.iam.gserviceaccount.com" \
  --role="roles/container.hostServiceAgentUser"

# 3. Grant GKE Service Agent Network User on the host subnet
gcloud compute networks subnets add-iam-policy-binding snet-payments \
  --project=prod-networking-hub \
  --region=us-central1 \
  --member="serviceAccount:service-${SERVICE_PROJECT_NUM}@container-engine-robot.iam.gserviceaccount.com" \
  --role="roles/compute.networkUser"
```

### 5. Launching a VM in the Service Project Using the Host Subnet

```bash
gcloud compute instances create payment-api-01 \
  --project=app-payments-prod \
  --zone=us-central1-a \
  --machine-type=e2-standard-4 \
  --network=projects/prod-networking-hub/global/networks/shared-prod-vpc \
  --subnet=projects/prod-networking-hub/regions/us-central1/subnetworks/snet-payments \
  --no-address
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Service Projects per Host Project** | 1,000 projects | Scalable for massive enterprise environments |
| **Host Projects per Organization** | 100 host projects | Can maintain separate Prod, Non-Prod, and Sandbox hubs |
| **Max Network User bindings per subnet** | Standard IAM policy limits (250 KB) | Assign roles to Google Groups, not individual users |
| **Cross-project peering** | Not permitted within same VPC | Shared VPC eliminates the need for peering |

---

## References

* **Shared VPC Overview:** https://cloud.google.com/vpc/docs/shared-vpc
* **Provisioning Shared VPC Guide:** https://cloud.google.com/vpc/docs/provisioning-shared-vpc
* **GKE with Shared VPC:** https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-shared-vpc
* **Pricing:** Free (Shared VPC is a core networking feature; pay standard inter-zone/inter-region egress rates)

---

## Pricing Examples

### Scenario 1: Enterprise Multi-Team Cloud Migration
* 25 Service Projects (Payments, Logistics, Catalog, User Services) running 300 VMs connected to a single Host Project in `us-central1`.
* Cross-project communication between microservices within the same zone: **$0.00** (Free).
* Cross-zone internal communication: 20 TB / month ($0.01 / GB = **$200.00 / month**).
* Shared VPC Admin & Host infrastructure: **$0.00**.
* **Total Network Infrastructure Overhead:** **$0.00** (Eliminates the cost of 25 separate NAT gateways, VPN tunnels, and complex transit peering).

### Scenario 2: Centralized Egress via Shared VPC Cloud NAT
* Instead of running 25 separate NAT gateways across 25 standalone projects, the Host Project operates **1 centralized Cloud NAT Gateway** in `us-central1`.
* Fixed gateway fee: 1 gateway × $0.045 / hr × 730 hrs = **$32.85 / month**.
* Total egress processed across all 25 teams: 15 TB ($0.045 / GB = $675.00).
* **Cost Savings:** Operating 25 separate NAT gateways would cost ~$821/month in base hourly fees alone. Shared VPC reduces base NAT gateway fees by **96%**.

---

## Nuggets & Gotchas

1. **The Missing `container.hostServiceAgentUser` GKE Failure:** When launching a GKE cluster in a Service Project, if the Service Project's GKE service agent is missing `roles/container.hostServiceAgentUser` on the **Host Project**, cluster creation will fail after 20 minutes with a cryptic error: `Google Compute Engine: Required 'compute.firewalls.create' permission`. GKE requires this role on the host to manage internal firewall rules for Pod health checks.
2. **Project Billing Separation:** Even though compute instances in a Service Project consume IP addresses and network bandwidth belonging to the Host Project's VPC, **all compute, storage, and egress bandwidth charges are billed directly to the Service Project**! Network engineers managing the Host Project do not have to worry about cross-charging compute egress back to business units.
3. **A Service Project Can Attach to Only ONE Host Project:** A single Google Cloud project cannot be attached to two different Shared VPC Host Projects simultaneously. If an application needs to bridge between a Legacy Host VPC and a Modern Host VPC, it must use **Private Service Connect** or **Cloud VPN** rather than multiple Shared VPC memberships.
4. **Compute Engine Default Service Account Needs Subnet Access:** When developers launch instances in a Service Project without specifying a custom service account, the VM attempts to use the Service Project's default Compute Engine SA (`<service-proj-num>-compute@developer.gserviceaccount.com`). This service account **must also be granted `roles/compute.networkUser` on the host subnet**, otherwise instance creation fails with `PermissionDenied`.
5. **Shared VPC Cannot Be Disabled While Resources Are Attached:** If you attempt to disable a Host Project or disassociate a Service Project while active VMs or GKE clusters are attached to host subnets, the operation will fail immediately with `ProjectHasActiveResources`. You must migrate or destroy all attached instances in all service projects before disassociating.
