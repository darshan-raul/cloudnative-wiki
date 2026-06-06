---
title: Load Balancing
tags: [architecture, networking, scalability]
date: 2025-05-24
description: Load balancing algorithms, health checks, and patterns
---

# Load Balancing

Load balancers sit in front of your services and distribute traffic across multiple backend instances — improving availability and scalability.

---

## How It Works

```
Client
 │
   ▼
┌─────────────────┐
│  Load Balancer   │ ← health checks backends
│  (LB Algorithm)  │ ← routes to healthy instances
└────────┬────────┘
         │
    ┌────┴────┐
    ▼         ▼
┌──────┐  ┌──────┐
│server│ │server│
│  1   │  │  2   │
└──────┘  └──────┘
```

---

## Algorithms

### Round Robin

Cycles through backends in order. Best for backends with similar capacity.

```
Request1 → server-1
Request 2 → server-2
Request 3 → server-3
Request 4 → server-1 (repeat)
```

### Weighted Round Robin

Assign weights to backends based on capacity.

```
server-1 (weight=3): gets3x more traffic
server-2 (weight=2): gets 2x more traffic
server-3 (weight=1): gets1x
```

### Least Connections

Routes to the backend with the fewest active connections.

```
backend-1: 47 active connections ← routes here
backend-2: 12 active connections
backend-3: 33 active connections
```

Best when requests have variable duration (long-running vs short).

### IP Hash

Hash the client IP to always route the same client to the same backend.

```
hash(client_ip) % num_backends = target_backend
```

Used for **session affinity** — but generally avoid unless you have a specific need.

### Least Response Time

Routes to the backend with the lowest average response time.

---

## Health Checks

Load balancers must detect and remove unhealthy backends.

```yaml
# AWS ALB health check example
Target: HTTP:8080/health
Interval: 30 seconds
Timeout: 5 seconds
Healthy threshold: 2 consecutive successes
Unhealthy threshold: 2 consecutive failures
```

### Types

| Type | What It Checks | Example |
|------|---------------|---------|
| TCP connect | Port open | `nc -z backend:8080` |
| HTTP/HTTPS | `/health` returns 200 | `curl -f http://backend:8080/health` |
| Deep health check | Actual DB connectivity | Query `SELECT 1` |

**Deep health checks** are more reliable but add load — use them sparingly.

---

## L4 vs L7 Load Balancing

| Layer | What It Routes | Use When |
|-------|---------------|---------|
| **L4 (TCP)** | By IP + port | High throughput, simple routing |
| **L7 (HTTP)** | By URL, headers, cookies | Path routing, auth, canaries |

```
L4: Client → LB → Backend (raw TCP stream)
L7: Client → LB → Backend (HTTP, can inspect headers)
```

**L7 is more flexible** for modern microservice architectures. L4 is higher performance for raw throughput.

---

## Common Patterns

### 1. Client-Side Discovery

```
Service A ──▶ Service Registry (e.g., Consul)
 │
                    │ (reads list of healthy instances)
                    ▼
              Service B (one of N instances)
```

###2. Server-Side Discovery

```
Service A ──▶ Load Balancer ──▶ Service B
              (LB handles routing)
```

### 3. Canary Deployment

```
90% traffic ──▶ Production (v1)
10% traffic ──▶ Canary (v2) ← monitored before full rollout
```

Load balancer weight-based routing enables canary without duplicate infrastructure.

### 4. Circuit Breaker Integration

```python
# Hystrix-style circuit breaker behind load balancer
# LB removes open circuits automatically
# (Envoy, HAProxy both support this)
```

---

## AWS/GCP/Azure LB Options

| Provider | L4 | L7 | Managed |
|----------|----|----|---------|
| AWS | NLB | ALB | ✅ |
| GCP | TCP LB | HTTP(S) LB | ✅ |
| Azure | L4 Basic | Application Gateway | ✅ |
| HAProxy | ✅ | ✅ | ❌ (self-managed) |
| Envoy | ✅ | ✅ | ❌ (self-managed) |
| NGINX | ✅ | ✅ | ❌ (self-managed) |

---

## Quick Checklist

```
□ Health check at /health (or /ready)
□ Graceful shutdown: drain connections before removing backend
□ Idle timeout configured (not too long, not too short)
□ SSL termination at LB (not at every backend)
□ Connection multiplexing (HTTP/2 or keep-alive)
□ Canary routing via weight-based algorithm
□ Circuit breaker at service level (don't rely solely on LB)
```

---

## Source

- [Samwho.dev — Load Balancing](https://samwho.dev/load-balancing/) (interactive visualization)
- [AWS — Load Balancing Best Practices](https://aws.amazon.com/architecture/load-balancing/)
