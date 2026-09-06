---
title: GCP Firewalls & Hierarchical Policies
description: GCP Firewall architecture — stateful inspection, rule priority (0-65535), Hierarchical Policies (Org/Folder), target tags vs Service Accounts, and rule logging.
tags:
  - gcp
  - networking
  - firewall
  - security
  - vpc
  - governance
---

# GCP Firewalls & Hierarchical Policies 🛡️🧱

Google Cloud firewalls operate directly within Google's software-defined hypervisor network (**Andromeda**). Unlike traditional hardware appliances that create network bottlenecks, GCP firewalls provide **distributed, stateful packet filtering** enforced directly at the virtual network interface (NIC) of every Compute Engine instance and GKE node.

To enforce immutable enterprise security baselines across thousands of projects, GCP provides **Hierarchical Firewall Policies**, allowing organization and folder administrators to enforce global firewall rules that project owners cannot modify or bypass.

---

## Architecture & Mental Model

### Multi-Tiered Packet Evaluation Pipeline

```
Incoming Network Packet (Ingress)
               │
               ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Organization-Level Hierarchical Firewall Policy                        │
│ Priority: 0 – 65,535                                                   │
│ ├── MATCH: DENY  ────────────────────────────────► Drop Packet         │
│ ├── MATCH: ALLOW ────────────────────────────────► Allow Packet        │
│ └── MATCH: GOTO_NEXT or NO_MATCH                                       │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Folder-Level Hierarchical Firewall Policy                              │
│ Priority: 0 – 65,535                                                   │
│ ├── MATCH: DENY  ────────────────────────────────► Drop Packet         │
│ ├── MATCH: ALLOW ────────────────────────────────► Allow Packet        │
│ └── MATCH: GOTO_NEXT or NO_MATCH                                       │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Project-Level VPC Firewall Rules                                       │
│ Priority: 0 – 65,535                                                   │
│ ├── Custom Rules: Evaluated lowest priority number first               │
│ └── Implicit Rules:                                                    │
│     • Priority 65535: Default Ingress DENY ─────► Drop Packet          │
│     • Priority 65535: Default Egress ALLOW ─────► Allow Packet         │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
                                   ▼
                      Virtual Machine / GKE Pod NIC
```

---

## Core Concepts

### 1. Rule Priority (0 to 65,535)

* Evaluated strictly in ascending order: **Priority 0 is evaluated first; priority 65,535 is evaluated last**.
* The **first rule that matches** the packet's attributes terminates evaluation.
* **Best Practice:** Leave numerical gaps (e.g. 1000, 1100, 1200) to allow inserting emergency rules during active security incidents.

### 2. Hierarchical Policies & `goto_next`

* **Immutable Guardrails:** Policies defined at the Organization root or Folder cannot be deleted, altered, or overridden by Project Owners.
* **The `goto_next` Action:** A hierarchical rule can match a packet and explicitly delegate further evaluation to child folders or project-level VPC rules. This allows security teams to inspect or log traffic globally without prematurely terminating rule evaluation.

### 3. Targeting Workloads: Network Tags vs. Service Accounts

GCP provides two mechanisms to apply firewall rules to specific VMs within a VPC:

| Dimension | Network Tags | Service Accounts (Recommended) |
| :--- | :--- | :--- |
| **Identifier Type** | Arbitrary text string (e.g. `web-backend`) | Cryptographically verified IAM email |
| **Security Risk** | **High:** Any user with `compute.instances.setTags` can add a tag to their VM and instantly inherit sensitive firewall access | **Zero Identity Drift:** Governed strictly by `iam.serviceAccounts.actAs` permissions |
| **Cross-Subnet Enforcement** | Matches tags regardless of IP | Matches verified service account identity |
| **Production Guidance** | Legacy / rapid prototyping | **Enterprise Zero-Trust Standard** |

```
Secure Ingress Rule Using Service Accounts:
Source SA:      serviceAccount:api-worker@my-project.iam.gserviceaccount.com
Target SA:      serviceAccount:db-worker@my-project.iam.gserviceaccount.com
Allowed Port:   TCP 5432 (PostgreSQL)
Result:         Only VMs authorized to run as api-worker can reach db-worker!
```

### 4. Stateful Connection Tracking

GCP firewalls are stateful:
* If an incoming connection is permitted on port 443, the outbound response traffic is **automatically allowed**, regardless of any egress firewall rules.
* Similarly, if an outgoing connection is permitted, the incoming response packets are automatically allowed.

---

## Production `gcloud` CLI Commands

### 1. Enforcing an Organization-Level Hierarchical Firewall Policy

```bash
# 1. Create the hierarchical firewall policy at the Organization level
gcloud compute firewall-policies create \
  --organization=123456789012 \
  --description="Global Enterprise Security Perimeter" \
  --short-name="org-security-policy"

# 2. Add rule: Block inbound SSH (port 22) from the public internet across ALL projects
gcloud compute firewall-policies rules create 100 \
  --firewall-policy=org-security-policy \
  --organization=123456789012 \
  --action=deny \
  --direction=INGRESS \
  --layer4-configs=tcp:22 \
  --src-ip-ranges="0.0.0.0/0" \
  --description="Global Deny: Public SSH Port 22"

# 3. Associate policy with the Organization root
gcloud compute firewall-policies associations create \
  --firewall-policy=org-security-policy \
  --organization=123456789012
```

### 2. Creating a Zero-Trust Rule Using Service Accounts

```bash
gcloud compute firewall-rules create allow-api-to-db \
  --network=prod-vpc \
  --priority=1000 \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:5432 \
  --source-service-accounts=api-runner@my-prod-project.iam.gserviceaccount.com \
  --target-service-accounts=db-server@my-prod-project.iam.gserviceaccount.com \
  --enable-logging
```

### 3. Whitelisting Google Load Balancer Health Check Probes

```bash
gcloud compute firewall-rules create allow-gcp-health-checks \
  --network=prod-vpc \
  --priority=900 \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:80,tcp:443,tcp:8080 \
  --source-ranges=35.191.0.0/16,130.211.0.0/22 \
  --target-service-accounts=api-runner@my-prod-project.iam.gserviceaccount.com
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **VPC Firewall rules per network** | 500 rules (default) | Can request increase up to 1,000 |
| **Hierarchical policy rules** | Up to 1,000 rules per policy | Enforced at Org/Folder level |
| **IP addresses in source/target** | Up to 256 CIDRs per rule | Aggregate CIDR blocks |
| **Target Service Accounts per rule** | Up to 10 Service Accounts | Define roles by application tiers |

---

## References

* **Firewall Rules Overview:** https://cloud.google.com/vpc/docs/firewalls
* **Hierarchical Firewall Policies:** https://cloud.google.com/vpc/docs/hierarchical-firewall-policies
* **Service Account Firewalls Guide:** https://cloud.google.com/vpc/docs/firewalls#service-accounts
* **Firewall Rules Logging:** https://cloud.google.com/vpc/docs/firewall-rules-logging
* **Pricing:** Free (GCP Firewall rule evaluation is free; Firewall Rule Logging incurs standard Cloud Logging ingestion charges)

---

## Pricing Examples

### Scenario 1: Enterprise Perimeter Protection (Zero Ingress Fees)
* 100 projects running 1,500 VMs across 10 VPC networks.
* Enforcing 50 Hierarchical Firewall rules and 200 project VPC rules.
* Total rule evaluations: Tens of billions of packets processed by Andromeda hypervisors.
* **Monthly Firewall Engine Cost:** **$0.00 / month** (Included free with Google Cloud compute networking).

### Scenario 2: Security Auditing with Firewall Rule Logging
* Firewall Rule Logging enabled on 5 high-traffic edge ingress rules to capture dropped malicious packets.
* Dropped packet log volume: 100 GB / month.
* Cloud Logging ingestion pricing ($0.50 / GiB after first 50 GiB free):
  * 50 billable GiB × $0.50 = **$25.00 / month**.
* Exporting logs via Log Sink to BigQuery for SIEM threat analysis: ~$5.00 / month.
* **Total Monthly Observability Cost:** **~$30.00 / month**.

---

## Nuggets & Gotchas

1. **Tag Spoofing Privilege Escalation:** If you write firewall rules targeting **Network Tags** (e.g. `allow-database-access`), any developer with the standard IAM role `roles/compute.instanceAdmin` or permission `compute.instances.setTags` can add the tag `allow-database-access` to their untrusted test VM! They will immediately gain direct access to your internal database. **Always target Service Accounts in production.**
2. **Implicit Ingress Deny vs. Implicit Egress Allow:** The default implicit rules (priority 65,535) **DENY all inbound traffic** and **ALLOW all outbound traffic**. If you deploy a new VM and cannot connect to it via SSH, it is because of the implicit ingress deny. However, if that same VM is compromised by malware, it can initiate outbound connections to arbitrary command-and-control servers on the internet because of the implicit egress allow!
3. **`0.0.0.0/0` Ingress Rule With Broad Priority Overwrites Defaults:** If a junior engineer creates an allow rule with `--source-ranges=0.0.0.0/0` and priority 1000 without specifying ports, it opens **all 65,535 TCP and UDP ports to the entire public internet** for every VM in that VPC. Always mandate that firewall rules specify explicit `--rules=tcp:<port>` and narrow source ranges.
4. **Hierarchical Policy Inheritance Terminations:** If a packet matches a rule in an Organization-level hierarchical policy with action `ALLOW`, evaluation stops immediately. The packet is admitted to the VM **even if a project-level VPC rule explicitly attempts to DENY it**! Use `goto_next` if you want lower-level project rules to have the final say.
5. **Firewall Rule Logging Sampling Overhead:** Enabling Firewall Rules Logging on a rule that matches 100,000 packets per second with `--sample-rate=1.0` (100% logging) will generate terabytes of logs in Cloud Logging within hours, resulting in massive surprise bills. In high-traffic environments, configure sampling rates between `0.01` (1%) and `0.1` (10%) or use log metadata exclusions.
