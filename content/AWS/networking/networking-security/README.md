---
title: AWS Networking Security
description: AWS networking security services — WAF (web application firewall), Shield (DDoS protection), Network Firewall (VPC-level IDS/IPS), and VPC Flow Logs for traffic analysis.
tags:
  - aws
  - networking
  - security
  - waf
  - shield
  - network-firewall
---

# AWS Networking Security

AWS provides layered security services: WAF for application-layer filtering (Layer 7), Shield for DDoS protection, and Network Firewall for VPC-level packet inspection.

## AWS WAF

AWS WAF is a web application firewall that filters HTTP/S traffic at CloudFront, ALB, API Gateway, and AppSync. You write rules that match conditions and define actions (allow, block, count).

### What WAF Filters

WAF operates on Layer 7 (HTTP/HTTPS) attributes:
- Request URI path
- Query string parameters
- HTTP headers (User-Agent, Host, Cookie)
- Request body (for inspection)
- IP address (geo-block)
- Rate-based conditions (flood protection)

### Rule Types

**Regular Rule:** Match conditions and take action (allow/block/count)

**Rate-Based Rule:** Block an IP after N requests per 5-minute window. Used for brute-force and DDoS protection.

```
Rate limit: 1000 requests per 5 minutes per IP
Action: block
```

**Group Rules:** AWS-managed rule groups (pre-configured):
- **AWS Managed Rules** — Common threats (OWASP Top 10, SQLi, XSS, etc.)
- **IP Reputation Lists** — Known malicious IPs (第三方 feeds)
- **Bot Control** — Identify and block bots, scrapers

### Custom Rules vs Managed Rules

**Managed rules** are pre-built rule sets maintained by AWS or third-party vendors. They're the fastest way to get protection but require careful tuning to avoid false positives.

**Custom rules** are rules you write for your specific application. Use when managed rules don't cover your use case.

### Web ACL Structure

```
Web ACL (attached to ALB)
  ├── Rule 1: AWS Managed Rules - Core Rule Set (priority 1)
  │   └── Action: Block (AWS-managed)
  ├── Rule 2: Block specific IPs (priority 2)
  │   └── Condition: IP matching 192.0.2.0/24
  │   └── Action: Block
  ├── Rule 3: Allow all others (priority 3)
  │   └── Action: Allow
  └── Default Action: Block (if no rule matches)
```

### Common Attack Patterns WAF Blocks

- **SQL Injection (SQLi):** `SELECT * FROM users WHERE id=1 OR 1=1`
- **Cross-Site Scripting (XSS):** `<script>alert('xss')</script>`
- **Local File Inclusion (LFI):** `/../../etc/passwd`
- **HTTP Flood:** 1,000 requests/minute from same IP
- **Scrapers/Bots:** Automated tools crawling your site

### Logging and Monitoring

WAF logs are sent to CloudWatch Logs or S3. Monitor:
- Blocked requests (attack attempts blocked)
- Allowed requests (should be legitimate)
- Sampled requests (for debugging)

## AWS Shield

AWS Shield is DDoS protection at Layers 3, 4, and 7.

### Shield Standard (Free)

Automatically included with CloudFront, Route 53, and ELB. Protects against:
- **SYN/ACK floods** (Layer 4)
- **UDP reflection attacks** (Layer 3)
- **HTTP/S floods** (Layer 7, basic mitigation)

Standard protection is always-on and requires no configuration.

### Shield Advanced ($3,000/month)

Enhanced DDoS protection with:
- **Always-on Layer 3/4 DDoS mitigation** (full spectrum attack protection)
- **24/7 AWS DDoS Response Team (DRT)** — they can help configure WAF rules during an attack
- **Cost protection** — AWS absorbs elastic scaling costs during DDoS attacks (up to $30,000/month for qualifying charges)
- **Real-time metrics** and attack notification via CloudWatch
- **DDoS App Layer Protection** — WAF rules auto-tuned during attacks

### Shield Advanced Use Cases

- **Revenue-critical services** (e-commerce, financial services)
- **Gaming** (real-time, latency-sensitive, attractive DDoS target)
- **Any service that cannot afford downtime**

## Network Firewall

Network Firewall is a managed VPC-level intrusion detection and prevention system (IDS/IPS). It inspects traffic flowing between subnets (typically from public subnets to private subnets) and can block, alert, or allow based on rules.

### How Network Firewall Works

```
Public Subnet (ALB) → Network Firewall Endpoint (ENI in each AZ)
                              ↓
                      Network Firewall Policy
                              ↓
Private Subnet (EC2)
```

### Firewall Policy Components

**Stateless Inspection:** Individual packets evaluated by rules (like NACLs but more powerful)

**Stateful Inspection:** Connection tracking — if outbound HTTP is allowed, return traffic is auto-allowed

**Suricata Rule Sets:** Network Firewall uses open-source Suricata rules. You can import rule groups or write custom rules.

### Rule Action Order

```
1. Stateless Default Action (pass/forward)
2. Stateful Engine (connection tracking)
3. Stateless Rules (final packet inspection)
```

### When to Use Network Firewall vs Security Groups

| | Network Firewall | Security Groups |
|--|--|--|
| Scope | VPC-level (cross-subnet traffic) | Instance-level (per-ENI) |
| Protocol | All (TCP, UDP, ICMP, application-layer) | TCP, UDP, ICMP only |
| Inspection depth | Full packet payload (with Suricata) | Header only |
| IDS/IPS | Yes (with Suricata rules) | No |
| Centralized | Yes (per VPC) | Per instance |

## VPC Flow Logs

Flow Logs capture metadata about VPC network traffic. They're essential for security monitoring, forensics, and troubleshooting.

### What Flow Logs Capture

```
version account-id interface-id srcaddr dstaddr srcport dstport protocol packets bytes action log-status
```

The `action` field shows ACCEPT (allowed by SG/NACL) or REJECT (blocked by SG/NACL/implicit deny).

### What Flow Logs Don't Capture

- DNS queries to the VPC DNS resolver (resolver IP is the destination, not logged)
- Traffic between instances in the same subnet (doesn't leave the subnet boundary)
- Amazon-provided DNS traffic
- Windows activation traffic
- Instance metadata (169.254.169.254)

### Flow Log Destinations

| Destination | Real-time | Cost |
|------------|-----------|------|
| S3 | No (10-15min delay) | $0.01/GB |
| CloudWatch Logs | Near real-time | $0.50/GB ingested |
| Kinesis Data Firehose | Near real-time | $0.029/GB |

### Flow Log Analysis with Athena

Query Flow Logs in S3 using Athena for security analysis:

```sql
CREATE TABLE vpc_flow_logs (
  version int,
  account string,
  interface string,
  srcaddr string,
  dstaddr string,
  srcport int,
  dstport int,
  protocol int,
  packets bigint,
  bytes bigint,
  action string,
  log_status string
)
PARTITIONED BY (dt string)
ROW FORMAT DELIMITED
STORED AS TEXTFILE
LOCATION 's3://my-vpc-logs/flow-logs/'
TBLPROPERTIES ('skip.header.line.count'='1');
```

## Architecture: Secure VPC with Multiple Defensive Layers

```
Internet
  ↓
CloudFront + Shield Standard (DDoS protection, global edge)
  ↓
ALB (public subnet) + WAF (L7 filtering, bot control)
  ↓
Network Firewall (inspect east-west traffic)
  ↓
Private Subnet (EC2) ← Security Groups
  ↓
RDS (database, private subnet) ← Security Groups + NACLs
```

## Limits

| Resource | Limit |
|----------|-------|
| WAF Web ACLs per account | 100 |
| Rules per Web ACL | 50 |
| Rate-based rules per Web ACL | 10 |
| Shield Advanced protectors | 100 |
| Network Firewall firewalls per VPC | 1 |
| Firewall policies per account | 50 |
| Stateful rule groups per policy | 10 |

## References

- **Homepage:** https://aws.amazon.com/waf/
- **Documentation:** https://docs.aws.amazon.com/waf/
- **Pricing:** https://aws.amazon.com/waf/pricing/

## Pricing Examples

**Scenario 1:** A web application with ALB and WAF using AWS Managed Rules (Core Rule Set + Bot Control). 5M requests/month. WAF: $5/web ACL/month + $0.60/100K rules/month + $0.20/100K requests/month = $5 + $30 + $10 = $45/month. AWS Managed Rules (Bot Control): $1/web ACL/month + $0.50/million requests = $2.50. Total: ~$47/month for WAF protection.

**Scenario 2:** An e-commerce site with Shield Advanced + WAF + custom rules during holiday sale. 50M requests/month, 10M requests during DDoS attack. Shield Advanced: $3,000/month. WAF: $5 + $0.20/1M = $15/month. DDoS attack generates 10M extra requests: Shield Advanced cost protection covers elastic scaling charges up to $30K/month. Total: ~$3,015/month. Without Shield: DDoS attack auto-scales ALB to 100 instances at $0.0225/ALB-hour × 100 × 24hr = $54,000 for a 24-hour attack.

## Nuggets & Gotchas

- **WAF logs don't include blocked requests by default — you must configure logging:** When WAF blocks a request, it may not appear in logs depending on your logging configuration. Set up logging to CloudWatch Logs for complete visibility into what WAF is seeing.
- **WAF rate-based rules block traffic but don't distinguish attack from legitimate flash sale:** A flash crowd of 1,000 users from the same IP (corporate NAT) triggers a rate-based rule. Tune thresholds carefully or use CAPTCHA challenges instead of blocks.
- **Shield Standard doesn't protect against Layer 7 attacks that appear legitimate:** A Layer 7 DDoS that sends 10,000 requests/second for the same valid URL looks like legitimate traffic to Shield Standard. Shield Advanced + WAF is needed for Layer 7 DDoS mitigation.
- **Network Firewall processes traffic in the originating AZ:** If you have instances in AZ-A and AZ-B, but Network Firewall only has endpoints in AZ-A, cross-AZ traffic from AZ-B to AZ-A is inspected. This adds AZ-crossing latency. Deploy Network Firewall endpoints in every AZ.
- **VPC Flow Logs don't log traffic that is blocked by a Security Group's implicit deny:** Traffic that doesn't match any SG rule is silently dropped. This isn't logged as a "REJECT" — it just disappears. This makes debugging "why isn't this connection working?" harder if you don't also have NACLs logging explicit denies.
