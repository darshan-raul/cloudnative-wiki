---
title: Amazon Lightsail
description: Amazon Lightsail — simple virtual private servers for basic workloads. Pre-configured blueprints, fixed pricing, simple networking, and limited vs EC2 comparison.
tags:
  - aws
  - compute
  - lightsail
---

# Amazon Lightsail

Lightsail is a simplified VPS (Virtual Private Server) service for basic workloads — websites, small databases, dev/test environments. It provides pre-configured instances with fixed pricing, simple networking, and a minimal management console. Unlike EC2, Lightsail doesn't require deep AWS knowledge.

## Core Concepts

### How Lightsail Works

```
Lightsail Instance
  ├── Pre-configured blueprint (Ubuntu, Amazon Linux, Debian, etc.)
  ├── Fixed specs (1 vCPU, 2GB RAM, 80GB SSD)
  ├── Built-in networking (static IP, DNS, firewall)
  └── Simple pricing ($5-$160/month, all-inclusive)

No Auto Scaling, no complex VPC, no security groups (simplified firewall)
```

### Instance Plans

| Plan | vCPU | RAM | SSD | Cost/mo |
|------|------|-----|-----|---------|
| Nano | 1 | 512 MB | 20 GB | $3.50 |
| Small | 1 | 1 GB | 40 GB | $5.00 |
| Medium | 1 | 2 GB | 80 GB | $10.00 |
| Large | 2 | 4 GB | 160 GB | $20.00 |
| XLarge | 2 | 8 GB | 320 GB | $40.00 |
| 2XLarge | 4 | 16 GB | 640 GB | $80.00 |

Plus database plans (MySQL, PostgreSQL, MongoDB) and load balancers.

## Creating an Instance

### Via Console

Lightsail → Create instance → Choose blueprint → Choose plan → Name → Create

### Via CLI

```bash
aws lightsail create-instances \
  --instance-names my-server \
  --blueprint-id ubuntu_22_04_lts \
  --bundle-id nano_2_0 \
  --zone us-east-1a
```

## SSH Access

```bash
# Download default key pair
aws lightsail download-default-key-pair --output-file ~/lightsail-key.pem

# SSH
chmod 600 ~/lightsail-key.pem
ssh -i ~/lightsail-key.pem ubuntu@public-ip

# Or: Browser-based SSH (Console)
```

## Static IP

```bash
# Create static IP
aws lightsail allocate-static-ip --static-ip-name my-static-ip

# Attach to instance
aws lightsail attach-static-ip --static-ip-name my-static-ip --instance-name my-server
```

## Networking

### Firewall Rules

```bash
# Allow HTTP/HTTPS
aws lightsail put-instance-public-ports \
  --instance-name my-server \
  --portInfos '[{"protocol": "tcp", "fromPort": 80, "toPort": 80}, {"protocol": "tcp", "fromPort": 443, "toPort": 443}]'
```

### DNS Zone

```bash
# Create DNS zone
aws lightsail create-domain --domain-name mydomain.com

# Create DNS record
aws lightsail create-domain-entry \
  --domain-name mydomain.com \
  --entry '{
    "type": "A",
    "name": "www",
    "value": "203.0.113.10"
  }'
```

## Load Balancer

```bash
# Create load balancer
aws lightsail create-load-balancer \
  --load-balancer-name my-lb \
  --instance-port 80 \
  --zone us-east-1a

# Attach instance
aws lightsail attach-instances-to-load-balancer \
  --load-balancer-name my-lb \
  --instance-ids my-server
```

## Database (Managed MySQL/PostgreSQL)

```bash
# Create MySQL database
aws lightsail create-relational-database \
  --relational-database-name my-db \
  --blueprint-id mysql_8_0 \
  --bundle-id micro_2_0 \
  --zone us-east-1a
```

### Database Features

- Automatic backups (daily, 7-day retention)
- Point-in-time recovery
- Master username/password
- Firewall (whitelist IPs)
- Monitoring (CloudWatch metrics)

## Snapshots

```bash
# Create snapshot
aws lightsail create-instance-snapshot \
  --instance-name my-server \
  --instance-snapshot-name my-server-backup

# Create instance from snapshot
aws lightsail create-instances-from-snapshot \
  --instance-names restored-server \
  --instance-snapshot-name my-server-backup \
  --bundle-id nano_2_0
```

## Container Service (Managed Kubernetes-lite)

Lightsail also offers a simple container service:

```bash
# Create container service
aws lightsail create-container-service \
  --container-service-name my-app \
  --power nano \
  --scale 1
```

Deploy containers without managing Kubernetes. Limited compared to EKS but simpler.

## Limitations vs EC2

| Feature | Lightsail | EC2 |
|---------|-----------|-----|
| Instance types | Fixed plans only | All families (T, M, C, R, etc.) |
| Auto Scaling | No | Yes (ASG) |
| VPC | Single VPC, simplified | Full VPC control |
| Security Groups | Simplified firewall | Full SG control |
| Load Balancer | Simple LB, limited | ALB/NLB/CLB |
| EBS | Fixed sizes | All types (gp3, io2, etc.) |
| Spot Instances | No | Yes |
| Reserved Instances | No | Yes |
| Placement Groups | No | Yes |
| Nitro instances | No | Yes |
| Max instances | 20 | 20 (default, can increase) |

## Use Cases

### Good For Lightsail

- Simple WordPress/blog sites
- Small databases (< 1GB RAM)
- Dev/test environments
- Legacy applications (single server)
- Small team prototypes

### Bad For Lightsail (use EC2 instead)

- High-traffic production websites (needs Auto Scaling)
- Large databases (needs more than 16GB RAM)
- HPC/ML workloads (needs GPU, Spot)
- Microservices requiring container orchestration
- Multi-tier architectures with complex networking

## Pricing

Lightsail pricing is all-inclusive (compute + storage + networking):

```
Nano:   $3.50/month  (512MB, 20GB SSD)
Small:  $5.00/month  (1GB, 40GB SSD)
Medium: $10.00/month (2GB, 80GB SSD)
Large:  $20.00/month (4GB, 160GB SSD)
```

Data transfer: included bandwidth (for nano-small: 1TB/month; for medium+: 2-3TB/month).

## References

- **Homepage:** https://aws.amazon.com/lightsail/
- **Documentation:** https://docs.aws.amazon.com/lightsail/
- **Pricing:** https://aws.amazon.com/lightsail/pricing/

## Pricing Examples

**Scenario 1:** A personal blog with 1 nano instance. $3.50/month. Includes 1TB transfer. MySQL database (nano): $5/month. Total: $8.50/month. Comparable to shared hosting but with dedicated resources and AWS infrastructure.

**Scenario 2:** A small e-commerce site (3 instances: web, DB, cache). Medium instances: 3 × $10 = $30/month. Plus load balancer: $10/month. Plus managed MySQL: $15/month. Total: $55/month. Compare to EC2 (3 × m5.large = $138/month + ELB $22/month + RDS small $50/month = $210/month). Lightsail is 74% cheaper but limited to simple architectures.

## Nuggets & Gotchas

- **Lightsail instances don't support custom security groups — only simplified firewall rules:** If you need complex network segmentation (e.g., private backend, public frontend, VPN access), use EC2 with proper VPC networking. Lightsail's firewall is all-or-nothing on the ports you open.
- **Lightsail load balancers don't support SSL certificates directly — you must use the Lightsail TLS certificate feature:** This is a managed certificate that auto-renews, but it's limited to the Lightsail domain. For custom domains, use the Lightsail distribution (CDN) or terminate SSL on the instance.
- **Lightsail containers are limited compared to ECS/EKS — no sidecars, no service mesh, limited networking:** If you need advanced container features (service discovery, auto-scaling, blue-green deployments), use ECS or EKS. Lightsail containers are for simple web apps only.
- **Lightsail databases are not production-grade — no Multi-AZ, limited backup options:** A managed MySQL on Lightsail has 7-day backup retention and no Multi-AZ. For production databases, use RDS. Lightsail is for dev/test or small production apps with low availability requirements.
- **Lightsail static IPs are tied to a region — you can't migrate them to another region:** If you need multi-region, use EC2 with proper VPC architecture. Lightsail is designed for single-region simplicity.