---
title: Elastic Load Balancing
description: AWS Elastic Load Balancing — ALB (HTTP/S layer 7), NLB (TCP/UDP layer 4), and CLB (legacy). Target groups, health checks, sticky sessions, and cross-zone load balancing.
tags:
  - aws
  - networking
  - load-balancing
  - alb
  - nlb
---

# Elastic Load Balancing (ELB)

AWS provides three load balancer types. ALB and NLB are the current-generation types; CLB is the legacy type and should not be used for new deployments.

## Load Balancer Types

| | ALB | NLB | CLB |
|--|--|--|--|
| OSI Layer | Layer 7 (HTTP/S) | Layer 4 (TCP/UDP) | Layer 4 and 7 |
| Routing | Path-based, host-based | IP-based | Port-based |
| TLS Termination | Yes | Pass-through | Yes |
| WebSocket | Yes | Yes | Yes |
| HTTP/2 | Yes | No | Yes |
| AWS WAF | Yes (integrated) | No | No |
| Static IP | No (changes on AZ changes) | Yes (one per AZ) | Yes |
| Preserve Client IP | X-Forwarded-For header | Via proxy protocol | X-Forwarded-For |
| Use when | HTTP/S web services | High-throughput, low-latency TCP/UDP | Legacy only |

## ALB: Application Load Balancer

ALB operates at layer 7 and routes traffic based on URL path, host header, or query parameters. It's the right choice for microservices and HTTP APIs.

### Components

**Listener:** Listens on a port (e.g., TCP 443) with a TLS certificate and a default action.

**Target Group:** A group of targets (EC2 instances, Lambda functions, IP addresses) that receive traffic. Each target group has its own health check.

**Rule:** Routes conditions (path `/api/*`, host `api.example.com`) to target groups.

### Rule Example

```
Rule1: IF host is api.example.com AND path is /v1/*
 → Forward to: tg-api-v1

Rule 2: IF host is api.example.com AND path is /v2/*
  → Forward to: tg-api-v2

Rule 3: IF host is app.example.com
  → Forward to: tg-web

Default: IF no rule matches
  → Redirect to: https://www.example.com
```

### Health Checks

ALB sends HTTP GET requests to each target's health check path. A target is healthy when it returns2xx within the timeout window.

```
Health check: GET /health
Timeout: 5 seconds
Healthy threshold: 2 consecutive successes
Unhealthy threshold: 2 consecutive failures
Interval: 10 seconds
```

### Sticky Sessions

ALB can route requests from the same client to the same target using a cookie (`AWSALB` cookie). Useful for sessions stored in-memory on the target.

```
Target group stickiness: Enabled (1 hour cookie duration)
→ First request: routed to any target, cookie set
→ Subsequent requests: routed to same target
```

## NLB: Network Load Balancer

NLB operates at layer 4 and handles TCP, UDP, and TLS traffic. It can handle millions of requests per second with ultra-low latency.

### Key Features

- **Static IP addresses** — One per AZ (using one Elastic IP per AZ)
- **Preserve client IP** — Client IP is visible to targets via proxy protocol or, for TCP, directly
- **Cross-zone load balancing** — Off by default (targets in AZ-A only receive traffic from AZ-A's NLB node)

### Target Types

NLB can route to:
- EC2 instances (via ENI)
- IP addresses (for on-premises targets via Direct Connect)
- Application Load Balancers (NLB → ALB pattern for WAF integration)

### TLS Termination on NLB

Unlike ALB, NLB passes TLS through to targets without terminating. To terminate TLS at the NLB, use a TLS listener with a certificate.

## Cross-Zone Load Balancing

**ALB:** Cross-zone load balancing is enabled by default. Each AZ's ALB node distributes traffic to targets in all AZs.

**NLB:** Cross-zone load balancing is disabled by default. Traffic from an AZ's NLB node only goes to targets in the same AZ. Enable it to distribute evenly across all targets regardless of AZ.

```
NLB with cross-zone disabled:
 AZ-A NLB node → only targets in AZ-A
  AZ-B NLB node → only targets in AZ-B

NLB with cross-zone enabled:
  AZ-A NLB node → targets in AZ-A AND AZ-B
```

## Connection Draining

Connection draining allows in-flight requests to complete before a target is deregistered. Prevents request failures during deployments and ASG scale-in events.

```
Connection draining timeout: 300 seconds (default, configurable 1-3600)
→ Target marked deregistering
→ ALB/NLB stops sending new requests
→ Existing connections allowed to complete
→ Target fully deregistered after draining
```

## ALB vs NLB Decision Matrix

| Use Case | Recommended LB |
|----------|---------------|
| HTTP/S microservice with URL routing | ALB |
| HTTP/S API with WAF integration | ALB |
| gRPC service | ALB (HTTP/2) |
| High-throughput TCP/UDP (video streaming, gaming) | NLB |
| IoT MQTT over TCP | NLB |
| DNS-over-TCP | NLB |
| Legacy TCP application | NLB |
| TLS termination at load balancer | ALB (easier) or NLB |
| Static IP for whitelisting | NLB |

## Limits

| Resource | Limit |
|----------|-------|
| Load balancers per region | 50 |
| Target groups per LB | 100 |
| Targets per target group | 1000 |
| Listeners per LB | 50 |
| Rules per LB | 100 (minus default rule) |
| Certificates per LB | 25 |

## References

- **Homepage:** https://aws.amazon.com/elasticloadbalancing/
- **Documentation:** https://docs.aws.amazon.com/elasticloadbalancing/
- **Pricing:** https://aws.amazon.com/elasticloadbalancing/pricing/

## Pricing Examples

**Scenario 1:** A production web application with ALB,3 targets (t3.medium EC2 instances), 1M requests/month. ALB hourly: $0.0225 ×720hr = $16.20/month. LCU: 1M requests/month ÷ 30 days = 33K requests/day = ~0.5 LCU/hour. At $0.008/LCU-hour = $0.004/hr × 720hr = $2.88/month. Total: ~$19/month. Plus NLB for a separate TCP service: $0.0225 × 720hr = $16.20/month.

**Scenario 2:** A high-throughput video streaming service using NLB with 10 targets across 3 AZs. 10Gbps throughput. NLB hourly: $0.0225 × 720hr = $16.20/month. NLB Capacity Units (NCU): 10 NCUs × $0.006/NCU-hour × 720hr = $43.20/month. Total: ~$59/month. Plus cross-zone load balancing enabled: traffic now distributes evenly, reducing per-target CPU variance.

## Nuggets & Gotchas

- **ALB security groups must allow traffic from anywhere (0.0.0.0/0):** The ALB is the internet-facing entry point. If its security group restricts inbound traffic, clients can't reach it. The ALB security group should allow 0.0.0.0/0 on the listener port.
- **NLB cross-zone load balancing is disabled by default:** Without it, if AZ-A has 2 targets and AZ-B has 10 targets, AZ-A's NLB node only sends traffic to its 2 targets. Enable cross-zone load balancing for even distribution.
- **ALB health checks are HTTP — targets must respond to GET /health:** If your service doesn't expose an HTTP endpoint, use TCP health checks (ALB supports TCP health checks too). A service that only accepts POST requests will always fail HTTP health checks.
- **Connection draining has a 5-minute default timeout:** During deployments, targets are deregistered and new ones added. With connection draining, old targets complete in-flight requests before terminating. Set it appropriately — 300 seconds is conservative for most web apps, 60 seconds is fine for stateless services.
- **ALB deregistration delay vs connection draining:** Deregistration delay is the new name for connection draining. Same concept, new name. Use deregistration delay in ALB configuration, connection draining in NLB configuration.
