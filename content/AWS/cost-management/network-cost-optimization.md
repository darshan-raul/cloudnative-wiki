---
title: Network Cost Optimization
description: AWS network cost optimization — AZ-to-AZ transfer, NAT Gateway pricing, VPC Endpoints, PrivateLink, Direct Connect, CloudFront caching
tags:
  - aws
  - cost-management
  - networking
---

# Network Cost Optimization

Network costs are the most commonly underestimated line item in AWS billing. Data transfer charges appear across multiple services and are easy to overlook until they show up as a surprise on the monthly bill.

## Data Transfer Pricing Hierarchy

Understanding where data flows determines the cost:

| Source | Destination | Cost (approximate) |
|--------|-------------|---------------------|
| Same AZ (same VPC) | Same AZ | Free |
| AZ-to-AZ (same region) | Same region, different AZ | ~$0.01/GB |
| Inter-region | Different AWS region | ~$0.02-0.09/GB |
| Internet egress | Public internet | ~$0.09/GB |
| CloudFront | Internet | ~$0.085/GB (first 10TB) |

**The AZ trap:** A common architecture mistake: placing a web server in AZ-a and a database in AZ-b, then running high-throughput application code that queries the database on every request. At scale, AZ-to-AZ transfer adds significant cost.

**Mitigation:** Place application components in the same AZ when possible. Use cross-AZ load balancing for availability (ALB spans AZs automatically) but keep application-to-database traffic within a single AZ.

## NAT Gateway Costs

NAT Gateway has two billing components:
- **Per hour:** ~$0.045/hour in us-east-1
- **Per GB of data processed:** ~$0.045/GB

For a server that processes 100GB/month of outbound traffic:
```
NAT Gateway: $0.045 × 24 × 30 = $32.40
Data transfer: 100GB × $0.045 = $4.50
Total: ~$37/month per NAT Gateway
```

**Multi-AZ NAT Gateway:** Running NAT Gateway in multiple AZs for HA doubles/triples the hourly cost.

**NAT Gateway alternatives:**
- **NAT Instance:** EC2 instance acting as NAT. Much cheaper hourly cost but requires manual management, no HA by default. Use for cost-sensitive non-production environments.
- **Egress-only internet gateway:** For IPv6, replaces NAT Gateway for outbound traffic only. No inbound inbound. Free.
- **VPC Endpoints:** For S3 and DynamoDB access from private VPCs — eliminates NAT Gateway entirely for those services. Free.

## VPC Endpoints

VPC Endpoints let private VPC resources access AWS services without going through the internet or NAT Gateway.

**Gateway Endpoints (S3, DynamoDB):** Free. Route traffic to S3/DynamoDB via the endpoint. Requires a route table entry with a target to the endpoint. Eliminates NAT Gateway costs for S3/DynamoDB access.

**Interface Endpoints (PrivateLink):** ~$0.01/hour + per GB processing. Used for services like EC2, SNS, SQS, CloudWatch, Secrets Manager, Systems Manager, etc. Establishes an ENI in your subnet with a private IP.

**When to use PrivateLink:**
- Private resources in a VPC that need to access AWS services without internet
- Connecting to services in another VPC without VPC peering
- Third-party SaaS services that support PrivateLink

## PrivateLink vs VPC Peering vs Transit Gateway

| Approach | Use When | Cost |
|----------|----------|------|
| VPC Peering | Two VPCs, same region, permanent connection | Free within region |
| Transit Gateway | Hub-and-spoke for 3+ VPCs, cross-account | ~$0.02/GB + hourly |
| PrivateLink | Access a service endpoint privately | ~$0.01/hour + per GB |
| Direct Connect | On-premises to AWS, large data volumes | $0.03-0.05/GB |

**Cost optimization insight:** Transit Gateway data processing charges add up fast in hub-and-spoke topologies. For 10 VPCs all routing through a central transit gateway, every byte of traffic between VPCs incurs transit gateway charges. VPC Peering between two VPCs is free within the same region — use it for permanent two-VPC connections.

## Load Balancer Costs

**ALB (Application Load Balancer):**
- Per hour: ~$0.0225 (varies by region)
- Per LCU (Load Balancer Capacity Unit): ~$0.008
  - 1 LCU covers: 800 connections/minute, 100 rules, 1GB/hour data processing
  - Multiple LCUs can run in parallel

**NLB (Network Load Balancer):**
- Per hour: ~$0.0225
- Per NCU (NCUs scale with throughput, not connections)
- Much cheaper at high throughput than ALB

**CLB (Classic Load Balancer):** Legacy, billed per hour + per GB. Avoid for new architectures.

**Idle LBs:** A common cost issue — ALB/NLB running 24/7 serving very low traffic. For always-on production, this is expected. For dev/test environments, consider stopping the ALB during non-business hours or using AWS Instance Scheduler to automate.

## CloudFront

CloudFront costs have three components:
- **Requests:** ~$0.0075-0.0090 per 10,000 requests (varies by region)
- **Data transfer:** ~$0.085/GB first 10TB/month, decreasing at higher volumes
- **Invalidations:** $0.005 per invalidation path

**Caching strategy for cost:**
- Long TTL on static assets (images, CSS, JS) — reduces origin fetches
- Cache API responses where appropriate — reduces ALB and origin EC2/Lambda costs
- Use Lambda@Edge for edge logic without hitting origin

**CloudFront → S3 vs S3 direct:**
- Direct S3 egress: ~$0.09/GB
- CloudFront → Internet: ~$0.085/GB + cheaper tier for first 10TB
- For a site serving 1TB/month, CloudFront saves ~$5/month + improves performance
- For very low traffic sites, the request charges may outweigh the per-GB savings

## Direct Connect Costs

Direct Connect pricing has three components:
- **Port hours:** ~$0.03-0.05/minute depending on speed (1Gbps, 10Gbps, etc.)
- **Data transfer:** ~$0.02-0.05/GB (varies by region pair)
- **Virtual interfaces:** Usually included in port cost

Direct Connect is almost always more expensive than S2S VPN for moderate data volumes. It makes economic sense when:
- You're moving large amounts of data (> 10TB/month) at consistently high throughput
- You need predictable, low-latency connectivity for on-premises systems
- You have compliance requirements that prohibit internet-based connectivity

## Cost Audit Checklist

```
□ Check if resources in different AZs are communicating unnecessarily
□ Check NAT Gateway hours — do you need one in every AZ?
□ Check if S3/DynamoDB access goes through NAT Gateway (use Gateway endpoints)
□ Check for idle load balancers in dev/test environments
□ Check VPC peering vs Transit Gateway — is Transit Gateway adding unnecessary cost?
□ Check CloudFront cache hit ratio — low ratio means you're paying for origin fetches + CloudFront
□ Check PrivateLink vs internet access for AWS services
□ Check data transfer between services in the same AZ (should be free)
```

## References

- **Homepage:** https://aws.amazon.com/blogs/networking-and-content-delivery/
- **Documentation:** https://docs.aws.amazon.com/vpc/latest/userguide/
- **Pricing:** https://aws.amazon.com/vpc/pricing/

## Pricing Examples

**Scenario 1:** A 3-tier web application: ALB (in3 AZs) → 6 EC2 instances (2 per AZ) → RDS Multi-AZ in1 AZ. Inter-AZ traffic: ALB to EC2 (2 AZs used, 1 AZ idle) = $0.01/GB per direction. EC2 to RDS = $0.01/GB. Monthly500TB data transfer: ~$5,000/month. Optimizing to place EC2 instances in the same 2 AZs as RDS and using cross-zone ELB disabled: reduces inter-AZ transfer by60%, saving ~$3,000/month.

**Scenario 2:** A microservices architecture with 20 Lambda functions in a VPC, all calling DynamoDB and S3 via NAT Gateway. Monthly NAT Gateway cost: 720 hours × $0.045 = $32 +500GB processed × $0.045 = $22.50 = $54.50/month just for NAT Gateway. Replacing with Gateway VPC Endpoints for S3 and DynamoDB: $0.01/GB for the endpoint data (same data, same amount, but cheaper):500GB × $0.01 = $5/month. Savings: ~$50/month.

## Nuggets & Gotchas

- **AZ-to-AZ data transfer costs stack:** If service A in AZ1 calls service B in AZ2, and B calls service C in AZ3, you pay AZ1→AZ2 AND AZ2→AZ3. A microservices chain of 5 services in 5 different AZs accumulates transfer charges at every hop. Keep synchronous chains within the same AZ.
- **NAT Gateway is charged per hour AND per GB:** $0.045/hr in us-east-1 is charged even if you transfer 0 bytes. A NAT Gateway that sits idle still costs $32/month. Delete idle NAT Gateways.
- **S3 Gateway Endpoint is free, S3 Interface Endpoint is not:** A Gateway VPC Endpoint for S3 routes traffic through AWS's internal network and costs nothing. An Interface Endpoint (for PrivateLink access to S3 from on-prem) costs $0.01/GB + $0.005 per availability zone/hour. Use Gateway endpoints where possible.
- **CloudFront cache miss costs more than direct S3:** When CloudFront misses cache, it fetches from origin (S3) and then serves to the user. You pay S3 egress (for the origin fetch) AND CloudFront data transfer out. For rarely-accessed objects, direct S3 access is cheaper than CloudFront.
- **PrivateLink charges for each AZ it's deployed in:** If you deploy an Interface Endpoint for an AWS service in 3 AZs, you pay 3 × hourly rate. If your Lambda only runs in 1 AZ, deploy the Interface Endpoint only in that AZ. Most services only need to be reachable from 1-2 AZs.