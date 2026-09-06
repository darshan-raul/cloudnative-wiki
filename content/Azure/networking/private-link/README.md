---
title: Azure Private Link, Private Endpoints, and Private DNS Architecture
description: Exhaustive engineering guide to Azure Private Link — Private Endpoints, Private Link Services, Private DNS Zones, split-horizon name resolution, Service Endpoints comparison, and data exfiltration prevention.
tags:
  - azure
  - networking
  - private-link
  - private-endpoint
  - security
---

# Azure Private Link, Private Endpoints, and Private DNS Architecture 🔒🔗

**Azure Private Link** is Microsoft's secure networking architecture for privately connecting Azure Virtual Networks to Azure PaaS services (e.g., Azure SQL, Storage Accounts, Key Vault, Cosmos DB), customer-owned services, or third-party SaaS providers without traversing the public internet. By projecting a PaaS resource directly into a private subnet via an **Azure Private Endpoint** (a dedicated virtual network interface with a private RFC 1918 IP), Private Link eliminates public IP exposure and natively protects against **data exfiltration**.

---

## 1. Architecture & DNS Resolution Topology

Private Link decouples the physical hosting of the PaaS service from its network accessibility. A Private Endpoint acts as a local private proxy in your virtual network.

```
                  SPOKE VIRTUAL NETWORK (Subnet: 10.2.1.0/24)
       ┌────────────────────────────────────────────────────────────────┐
       │   VM / AKS Pod (10.2.1.15)                                     │
       │   Query: `mydbserver.database.windows.net`                      │
       └───────────────────────────────┬────────────────────────────────┘
                                       │ 1. DNS Query (UDP 53)
                                       ▼
       ┌────────────────────────────────────────────────────────────────┐
       │             AZURE PRIVATE DNS ZONE                             │
       │             `privatelink.database.windows.net`                 │
       │             Record: mydbserver -> 10.2.1.50                    │
       └───────────────────────────────┬────────────────────────────────┘
                                       │ 2. Returns 10.2.1.50
                                       ▼
       ┌────────────────────────────────────────────────────────────────┐
       │             AZURE PRIVATE ENDPOINT (NIC: 10.2.1.50)            │
       │             - Encapsulated inside your private subnet          │
       │             - Bound to exact resource ID                       │
       └───────────────────────────────┬────────────────────────────────┘
                                       │ 3. Private Link Micro-Tunnels
       ════════════════════════════════╪═════════════════════════════════
                                       │ (Microsoft SDN Backplane)
                                       ▼
       ┌────────────────────────────────────────────────────────────────┐
       │            AZURE MANAGED PAAS MULTI-TENANT INFRASTRUCTURE      │
       │                                                                │
       │     ┌────────────────────────────────────────────────────┐     │
       │     │ Azure SQL Database: `mydbserver`                   │     │
       │     │ (Public Access: STRICTLY DISABLED)                 │     │
       │     └────────────────────────────────────────────────────┘     │
       └────────────────────────────────────────────────────────────────┘
```

### Core Architecture Constructs

1. **Private Endpoint:** A special network interface (NIC) allocated from your VNet's subnet that is assigned a private IP from the subnet's CIDR. It represents the private target for connections to the specified Azure service.
2. **Private Link Service:** The provider-side resource. If your organization builds a multi-tenant backend service hosted behind an internal Standard Load Balancer, you can expose it as a Private Link Service to other Azure subscriptions or enterprise customers without cross-tenant VNet peering or public IP exposure.
3. **Private DNS Zone Integration:** Azure PaaS public FQDNs (e.g., `storageaccount.blob.core.windows.net`) resolve to public IPs by default. When a Private Endpoint is created, Azure creates a CNAME alias pointing to `storageaccount.privatelink.blob.core.windows.net`. By linking an Azure Private DNS Zone to the VNet, queries for the public FQDN transparently resolve to the **Private Endpoint IP**.

---

## 2. Service Endpoints vs Private Endpoints

Understanding the architectural distinction is critical for network security compliance:

| Dimension | Service Endpoints (`Microsoft.Storage`) | Private Endpoints (Azure Private Link) |
| :--- | :--- | :--- |
| **IP Address Representation** | Public IP of the PaaS service (routes over Azure backbone) | **Private RFC 1918 IP** inside your private subnet |
| **Data Exfiltration Risk** | **High:** Workloads can reach *any* storage account globally over the endpoint | **Zero:** Endpoint is strictly pinned to *one specific resource ID* |
| **On-Premises Transit** | **Not supported:** Cannot route from on-prem over ExpressRoute/VPN | **Fully supported:** Routable from on-prem across ExpressRoute/VPN |
| **VNet Peering Transit** | Non-transitive | Routable across peered VNets and Virtual WAN |
| **Network Security Groups (NSG)**| NSG rules apply to outgoing traffic | NSG rules apply directly to the Private Endpoint NIC |
| **Pricing** | Free (Included in VNet) | Hourly endpoint fee + inbound/outbound data processing |

---

## 3. Production Deployment & CLI Operations (`az`)

### 1. Create a Storage Account with Public Access Completely Disabled

```bash
az group create --name rg-data-prod --location eastus

# Deploy Storage Account with public network access disabled
az storage account create \
    --name stfinancedataprod01 \
    --resource-group rg-data-prod \
    --location eastus \
    --sku Standard_ZRS \
    --kind StorageV2 \
    --public-network-access Disabled \
    --allow-blob-public-access false
```

### 2. Deploy Private Endpoint into Secure Subnet

```bash
# Obtain Storage Account Resource ID
STORAGE_ID=$(az storage account show \
    --name stfinancedataprod01 \
    --resource-group rg-data-prod \
    --query id -o tsv)

# Deploy Private Endpoint targeting the 'blob' sub-resource
az network private-endpoint create \
    --name pe-stfinancedata-blob \
    --resource-group rg-data-prod \
    --vnet-name vnet-spoke-prod \
    --subnet snet-private-endpoints \
    --private-connection-resource-id "${STORAGE_ID}" \
    --group-id blob \
    --connection-name conn-pe-blob
```

### 3. Deploy and Link Azure Private DNS Zone

```bash
# Create Private DNS Zone for Blob Storage
az network private-dns zone create \
    --resource-group rg-network-hub-prod \
    --name "privatelink.blob.core.windows.net"

# Link Private DNS Zone to the Spoke VNet
az network private-dns link vnet create \
    --resource-group rg-network-hub-prod \
    --zone-name "privatelink.blob.core.windows.net" \
    --name link-hub-and-spoke \
    --virtual-network vnet-spoke-prod \
    --registration-enabled false

# Automatically register DNS A record via Private DNS Zone Group
az network private-endpoint dns-zone-group create \
    --resource-group rg-data-prod \
    --endpoint-name pe-stfinancedata-blob \
    --name default-zone-group \
    --private-dns-zone "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-network-hub-prod/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net" \
    --zone-name blob
```

### 4. Verify Split-Horizon DNS Resolution and Connectivity

```bash
# Query FQDN from a VM inside the VNet:
# Expected: mydbserver.privatelink.blob.core.windows.net -> 10.2.1.50
nslookup stfinancedataprod01.blob.core.windows.net

# Verify TLS connection and download over private link
curl -I https://stfinancedataprod01.blob.core.windows.net
```

---

## 4. Quotas, Performance, and Configuration Limits

| Parameter / Dimension | Default Quota | Engineering Guidance |
| :--- | :--- | :--- |
| **Private Endpoints per VNet** | 1,000 endpoints | Dedicated subnet `/24` supports 250 endpoints |
| **Private Endpoints per Resource** | 100 endpoints | Useful for multi-VNet direct attachment |
| **Throughput per Private Endpoint**| Up to 100 Gbps | Backed by Azure accelerated networking |
| **Private DNS Zone VNet Links** | 1,000 links per zone | Link central hub DNS zone to all spoke VNets |
| **Private DNS Records per Zone** | 25,000 records | Use automated DNS Zone Groups |
| **Network Security Group Support** | Enabled via subnet property | Supported via `PrivateEndpointNetworkPolicies=Enabled` |

---

## 5. Official References & Documentation

- [What is Azure Private Link?](https://learn.microsoft.com/en-us/azure/private-link/private-link-overview)
- [What is an Azure Private Endpoint?](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview)
- [Azure Private Endpoint DNS Configuration](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)
- [Compare Private Endpoints and Service Endpoints](https://learn.microsoft.com/en-us/azure/private-link/service-endpoint-vs-private-endpoint)
- [Azure Private Link Pricing Matrix](https://azure.microsoft.com/en-us/pricing/details/private-link/)

---

## 6. Realistic Pricing Scenarios

Azure Private Link pricing is composed of:
1. **Private Endpoint Inbound/Outbound Duration:** ~$0.01 per endpoint per hour (~$7.30/month per endpoint).
2. **Data Processing:**
   - Inbound data processed: $0.01 per GB.
   - Outbound data processed: $0.01 per GB.
3. **Private DNS Zones:** $0.50 per hosted zone per month (first 25 zones); $0.40 per million DNS queries.

### Scenario A: Enterprise Microservices Cluster with 5 Private Endpoints

- **Inventory:**
  - 5 Private Endpoints (1 Azure SQL Database, 2 Storage Accounts, 1 Key Vault, 1 Redis Cache).
  - Deployed in `East US`.
  - Data transfer: 2,000 GB (2 TB) inbound/outbound per month across all endpoints.
  - 1 Private DNS Zone with 500,000 DNS queries.
- **Monthly Cost Calculation:**
  - Endpoint Hourly Cost: 5 endpoints × $0.01/hr × 730 hrs = **$36.50**
  - Data Processing: 2,000 GB × $0.01/GB = **$20.00**
  - Private DNS Zone: $0.50 + ($0.40 × 0.5) = **$0.70**
- **Total Monthly Cost:** **$57.20 / month**

### Scenario B: Massive Petabyte-Scale Analytics Data Lake (ADLS Gen2)

- **Inventory:**
  - 10 Private Endpoints for distributed data ingest nodes.
  - Data Lake throughput: 50,000 GB (50 TB) processed through endpoints per month.
- **Monthly Cost Calculation:**
  - Endpoint Hourly Cost: 10 endpoints × $0.01/hr × 730 hrs = **$73.00**
  - Data Processing: 50,000 GB × $0.01/GB = **$500.00**
  - DNS: Negligible ($1.00)
- **Total Monthly Cost:** **$574.00 / month**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **The DNS CNAME Hijack / Custom DNS Server Failure:** When a client resolves an Azure service with Private Link, the public DNS returns a CNAME to `*.privatelink.*`. If your VMs use on-premises Active Directory or custom BIND DNS servers that do not forward `privatelink.*` queries to the Azure DNS IP `168.63.129.16`, queries resolve to the **public IP of the PaaS service**. If public access was disabled on the resource, all application queries fail with `403 Forbidden: Public access is disabled`. You **must** configure DNS conditional forwarders for all Azure privatelink zones pointing to `168.63.129.16` or deploy an Azure DNS Private Resolver.
2. **Subnet Delegation Blocks Private Endpoints:** If a subnet has a delegation configured (e.g., `Microsoft.Web/serverFarms` for App Service or `Microsoft.ContainerApp/environments` for ACA), Azure **strictly prohibits deploying Private Endpoints into that same subnet**. Always designate a separate, dedicated subnet (e.g., `snet-private-endpoints`) for hosting all private endpoints in the VNet.
3. **Sub-Resource Group ID Mismatches:** For complex services like Azure Storage, there is no single "Storage" private endpoint. You must create separate private endpoints for each required sub-resource: `blob`, `table`, `queue`, `file`, `dfs` (ADLS Gen2), and `web`. If an application talks to both Blob and ADLS Gen2 (`dfs`) endpoints, but you only created a private endpoint for `blob`, calls targeting the `dfs.core.windows.net` endpoint will traverse the public internet and fail.
4. **Network Security Group (NSG) Policies on Private Endpoints:** Historically, NSGs did not apply to Private Endpoints; traffic flowed through them unimpeded. Azure now supports NSGs on Private Endpoints, but it requires the subnet setting `PrivateEndpointNetworkPolicies = Enabled`. If you enable this setting without updating your NSG inbound rules, your NSG will block traffic to the private endpoint, causing immediate database connection timeouts.
5. **Private Link Asymmetric Routing with Firewalls:** If a VM in Spoke A talks to a Private Endpoint in Spoke B, traffic should route directly across VNet peering. However, if Spoke A has a UDR sending `0.0.0.0/0` to Azure Firewall, and the Private Endpoint is in a separate spoke that the firewall knows about, return traffic might get dropped if routing paths asymmetric. Ensure your spoke route tables include specific `/32` or subnet routes for private endpoints to bypass firewall inspection when east-west filtering is not desired.
6. **Hard CNAME Aliases in Application Code Break TLS:** Never hardcode `privatelink.database.windows.net` into your application connection strings. Always connect using the standard public hostname `mydbserver.database.windows.net`. The TLS certificate presented by the Azure database matches `*.database.windows.net`. If your code connects directly to the `privatelink` hostname, TLS certificate validation will fail with `SSLHandshakeException: Hostname mydbserver.privatelink.database.windows.net does not match certificate common name`.
