---
title: Amazon Route 53
description: Amazon Route 53 — managed DNS service with hosted zones, DNS record types, routing policies (simple, weighted, latency, geolocation, failover), and health checks.
tags:
  - aws
  - networking
  - dns
  - route53
---

# Amazon Route 53

Route 53 is AWS's managed DNS service. It handles three functions:
1. **Domain registration** — Buy and manage domain names
2. **DNS routing** — Resolve DNS queries with routing policies
3. **Health checking** — Monitor endpoint health and route around failures

## Hosted Zones

A hosted zone is a container for DNS records for a domain. Two types:

**Public hosted zone** — DNS records visible on the internet. The authoritative DNS for your domain on the internet.

**Private hosted zone** — DNS records visible only within your VPCs (or VPCs you specify). For internal domain names like `corp.internal`.

```
Public: example.com → public internet
Private: corp.internal → VPC-A, VPC-B (resolved via VPC DNS)
```

## DNS Record Types

| Type | Purpose | Example |
|------|---------|---------|
| A | IPv4 address | `api.example.com` → `54.123.45.67` |
| AAAA | IPv6 address | `api.example.com` → `2001:db8::1` |
| CNAME | Canonical name (alias for another name) | `www.example.com` → `api.example.com` |
| Alias | AWS-specific: points to AWS resource | `www.example.com` → ALB DNS name |
| MX | Mail server | `example.com` → `10 mail.example.com` |
| TXT | Text records (SPF, DKIM, verification) | `example.com` → `"v=spf1 include:_spf.example.com"` |
| NS | Name server (delegation) | `example.com` → `ns-123.awsdns-45.com` |
| SOA | Start of authority | Included automatically |
| PTR | Reverse DNS (IP → hostname) | `67.45.123.54.in-addr.arpa` → `api.example.com` |
| SPF | Sender Policy Framework (deprecated, use TXT) | |
| SRV | Service locator | `_http._tcp.example.com` → `10 5 80 api.example.com` |
| CAA | Certification Authority Authorization | `example.com` → `0 issue "letsencrypt.org"` |

## Alias Records vs CNAMEs

**CNAME:** Maps a name to another name. Can't be used at the zone apex (example.com — must be www.example.com).

**Alias:** AWS-specific. Maps a name to an AWS resource (ALB, CloudFront, S3 website hosting, Elastic Beanstalk, etc.). At no cost for queries and can be used at the zone apex.

```
example.com (zone apex) → ALB DNS name (alias record)
www.example.com       → api.example.com (CNAME)
```

## Routing Policies

### Simple Routing

One or more values (IP addresses) returned in random order. No health checks. Use for single-server deployments.

```
api.example.com → [54.123.45.67, 54.123.45.68]
```

### Weighted Routing

Distributes traffic by ratio. Useful for:
- A/B testing (send10% of traffic to new version)
- Blue/green deployments (gradually shift traffic)
- Multi-region routing (weight by region)

```
api.example.com → 80% → us-east-1 (10.0.1.1)
                → 20% → eu-west-1 (10.1.1.1)
```

### Latency-Based Routing

Route 53 measures latency from the resolver to your regions and returns the lowest-latency record. Useful for multi-region active-active architectures.

```
api.example.com → us-east-1 (latency-routing, weight: 1)
                → eu-west-1 (latency-routing, weight: 1)
                → ap-southeast-1 (latency-routing, weight: 1)
```

### Geolocation Routing

Routes based on the DNS resolver's geographic location. Use for:
- Content localization (serve region-specific content)
- Legal compliance (block or allow specific regions)
- Disaster recovery (redirect traffic away from a region)

```
api.example.com → North America → us-east-1 IPs
                → Europe → eu-west-1 IPs
                → Default → us-east-1 IPs
```

### Failover Routing

Routes to a primary target until health checks fail, then routes to a secondary (failover) target. Use for active-passive DR.

```
api.example.com → Primary (us-east-1) → Evaluate health check
 → Secondary (eu-west-1) → Evaluate health check

Health check: GET http://54.123.45.67/health
Threshold: 3 failures = unhealthy
```

### Multi-Value Answer

Like simple routing but with health checks per record. Route 53 returns only healthy records. Not a replacement for load balancing, but useful for simple DNS-based redundancy.

```
api.example.com → [54.123.45.67,54.123.45.68]
 (each with associated health check)
```

## Health Checks

Route 53 health checks are performed from multiple global locations. A resource is healthy when the majority of health checkers (default: 3/3) report healthy.

### Health Check Types

- **Endpoint:** HTTP/HTTPS/TCP health checks against an IP or hostname
- **CloudWatch Alarm:** Route53 monitors a CloudWatch alarm (e.g., from an ASG)
- **Calculated:** Combines multiple health checks with AND/OR logic

### Health Check Configuration

```
Protocol: HTTPS
Domain: api.example.com
Path: /health
Interval: 30 seconds (10 seconds for faster detection, costs more)
Failure threshold: 3 (3 consecutive failures = unhealthy)
Latency threshold: 10 seconds (slow response = unhealthy)
```

### Latency Check vs TCP Check

- **HTTP/HTTPS check:** Sends a GET request, validates the response. Requires the endpoint to respond to HTTP requests.
- **TCP check:** Opens a TCP connection. Use when the service doesn't expose HTTP (e.g., SMTP, database).
- **Latency check:** Measures time to first byte. Useful for detecting slow responses before they time out.

## Private Hosted Zones

A private hosted zone resolves names within your VPCs:

```
corp.internal (private hosted zone)
├── api.corp.internal →10.0.1.10 (EC2 instance in VPC-A)
├── db.corp.internal  → 10.0.21.15 (RDS in VPC-A)
└── monitoring.corp.internal → 10.0.5.20 (managed service in VPC-B)
```

**VPC DNS must be enabled** for private hosted zones to resolve. Route 53 Resolver automatically handles private hosted zone resolution when associated with the VPC.

## Common Architectures

### Web Application with Failover

```
users → Route53 (failover routing)
 ├── Primary: api.example.com → ALB (us-east-1) [health check]
           └── Secondary: api.example.com → ALB (eu-west-1) [health check]

When us-east-1 health check fails → Route 53 returns eu-west-1 IPs
```

### Blue/Green Deployment

```
api.example.com → 90% → Blue ALB (us-east-1)
                → 10% → Green ALB (us-east-1, new version)

Gradually increase green weight as confidence grows
```

## Limits

| Resource | Limit |
|----------|-------|
| Hosted zones per account | 500 |
| Records per hosted zone | 10,000 |
| Health checks per account | 50 (can request increase) |
| Domains per account | 50 |
| TTL for alias records | 300 seconds (fixed) |
| TTL for other records | 60-172800 seconds |

## References

- **Homepage:** https://aws.amazon.com/route53/
- **Documentation:** https://docs.aws.amazon.com/route53/
- **Pricing:** https://aws.amazon.com/route53/pricing/

## Pricing Examples

**Scenario 1:** A production application with 1 domain, 20 DNS records, 2 health checks (primary + secondary API endpoints). Monthly: $0.50/month hosted zone + $0.40/month for 20 standard queries/day + $7.50/month for 2 health checks × $0.50 = $0.75/month health checks. Total: ~$1.65/month. Plus domain registration: $13/year = $1.08/month. Total: ~$2.73/month.

**Scenario 2:** A global application with latency-based routing across 3 regions (us-east-1, eu-west-1, ap-southeast-1).100M queries/month. At $0.40/million after first 1B queries:100M × $0.40/million = $0.04/month. Health checks: 3 endpoints × $0.50/month × 3 regions × 3 checker locations = $13.50/month. Total: ~$13.54/month plus hosted zone fees.

## Nuggets & Gotchas

- **Alias records are free — CNAMEs are not:** Route 53 charges per query for all record types except Alias records pointing to AWS resources. Use Alias records for ALB, CloudFront, S3, etc. to avoid per-query charges.
- **Zone apex (example.com) can't use CNAME records:** DNS RFC prevents CNAME at the zone apex. Use an Alias record instead. Alias records are AWS-specific and resolve to the AWS resource's DNS name.
- **Health checks are performed from multiple global locations — not from your VPC:** A health check that passes from Route 53's checkers might still fail from inside your VPC due to network policies. Use CloudWatch alarm health checks for accurate internal monitoring.
- **Health check interval of 10 seconds detects failures faster but costs 3x:** 30-second interval = $0.50/health check/month. 10-second interval = $1.50/health check/month. For critical production endpoints, 10-second detection is worth the cost.
- **Private hosted zones don't automatically resolve across VPCs:** You must associate the private hosted zone with each VPC that needs to resolve it. If a new VPC is created and doesn't resolve internal names, check that it's associated with the private hosted zone.
