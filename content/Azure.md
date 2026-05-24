---
title: Azure
tags: [azure, cloud, microsoft]
date: 2025-05-24
description: Microsoft Azure cloud platform - compute, networking, identity, security, and Azure-native tooling
---

# Azure ☁️

Microsoft Azure cloud platform covering compute, networking, storage, identity, and security services.

## Sections

### Core Services
- [[Azure/resource-group|Resource Groups]] — Logical containers for Azure resources
- [[Azure/security-groups|Security Groups]] — NSGs and ASGs for network filtering
- [[Azure/network-routing|Network Routing]] — VNet routing, UDR, peering

### Identity & Access
- [[Azure/identity/entraid|Entra ID]] — Azure AD / Microsoft Entra ID (IAM, SSO, MFA)
- [[Azure/identity/README|Identity Hub]]

### Compute
- [[Azure/compute|Compute]] — VMs, VMSS, Azure Functions, App Service

### Database
- [[Azure/databases|Databases]] — Azure SQL, Cosmos DB, Azure Database for PostgreSQL

### Networking
- [[Azure/networking|Networking]] — VNet, VPN, ExpressRoute, Load Balancer, Application Gateway

### Security
- [[Azure/security|Azure Security]] — Defender for Cloud, Microsoft Sentinel, Entra ID protection

## Azure vs AWS

| Concept | Azure | AWS |
|---------|-------|-----|
| Virtual network | VNet | VPC |
| IAM | Entra ID | IAM |
| Object storage | Blob Storage | S3 |
| Managed K8s | AKS | EKS |
| Serverless | Azure Functions | Lambda |
| CDN | Azure CDN | CloudFront |

## Related

- [[AWS]] — AWS equivalents and comparison
- [[GCP]] — Google Cloud Platform
- [[Security/cloud-security/azure/README|Azure Security Hub]]