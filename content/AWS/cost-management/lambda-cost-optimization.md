---
title: Lambda Cost Optimization
description: Lambda cost optimization — memory vs duration, provisioned concurrency, VPC Lambda ENI costs, HTTP API vs REST API, cold starts
tags:
  - aws
  - cost-management
  - serverless
---

# Lambda Cost Optimization

Lambda pricing has two components: **invocations** (per request) and **duration** (GB-second). The product of memory allocated and execution time determines cost. Understanding this relationship unlocks significant optimization.

## Pricing Model

```
Cost = (Invocations × $0.0000002) + (GB-seconds × $0.0000166667)
```

1 million invocations at 512MB for 200ms:
```
Requests: 1,000,000 × $0.0000002 = $0.20
Duration: 1,000,000 × (0.512 GB × 0.2 sec) = 102,400 GB-seconds
          102,400 × $0.0000166667 = $1.71
Total: ~$1.91
```

## Memory vs Duration Trade-off

Lambda allows you to set memory from 128MB to 10,240MB (10GB). The more memory you allocate, the more CPU you get proportionally — double the memory, double the CPU.

**The trick:** Increasing memory often reduces duration enough to lower total cost. A function running at 128MB for 500ms might run at 512MB for 100ms. The duration reduction outweighs the memory increase.

```
128MB for 500ms:
  GB-seconds = 0.128 × 0.5 = 0.064
  Cost = 0.064 × $0.0000166667 = $0.00000107 per invocation

512MB for 100ms:
  GB-seconds = 0.512 × 0.1 = 0.051
  Cost = 0.051 × $0.0000166667 = $0.00000085 per invocation

32% cost reduction by doubling memory and reducing duration by 80%
```

**Optimization approach:** Test your function at different memory settings and measure actual cost. Lambda Power Tuning (AWS Solutions) automates this.

## VPC Lambda Costs

When a Lambda function accesses VPC resources (RDS, ElastiCache, internal APIs), it must attach to a VPC. This introduces a hidden cost: **ENI attachment**.

Lambda creates an ENI in each subnet you configure. When the function runs:
1. Lambda allocates an ENI in your subnet (first invocation cold start)
2. Lambda scales ENIs as concurrent executions increase
3. ENIs persist even when functions aren't running

**The hidden cost:** Each ENI in a private subnet consumes a private IP address. More importantly, if your function runs frequently and you're paying for NAT Gateway, every Lambda invocation that accesses VPC resources routes through NAT Gateway:

```
VPC Lambda → NAT Gateway → Private subnet → RDS
         ↓
    NAT Gateway charges per GB + per hour
```

**Mitigation:**
- Use RDS Proxy — it has its own private IP, Lambda connects to it directly without routing through NAT
- Place Lambda in the same AZ as the RDS instance to minimize cross-AZ charges
- Use Amazon API Gateway private endpoints (PrivateLink) instead of routing through NAT
- Use S3 Gateway Endpoints (free) for S3 access from VPC Lambda

## Provisioned Concurrency

Provisioned Concurrency keeps Lambda functions initialized and ready to respond in milliseconds — no cold starts. Pricing: you pay for the allocated concurrency and duration, not per invocation.

**When it makes sense:**
- Predictable, latency-sensitive traffic (API calls, synchronous processing)
- When cold start latency is unacceptable (e.g., < 100ms SLA)
- When you can forecast concurrency needs

**When it's not worth it:**
- Sporadic, unpredictable traffic
- Asynchronous workloads (S3 triggers, SQS consumers) — cold starts don't matter
- Batch workloads where total duration matters more than individual invocation latency

**Cost comparison:**
```
On-Demand: $0.20 per million invocations
Provisioned: You pay for reserved concurrency × duration

1,000 concurrent requests × 500ms each × 1M requests/month
On-Demand: ~$0.20 per invocation
Provisioned: Reserved 1,000 concurrency × $0.0000166667 per GB-second
  = 1,000 × 0.5GB × 0.5sec × $0.0000166667 = $0.004 per invocation
```

At high concurrency, provisioned concurrency can actually be cheaper — you're paying for reserved capacity, not per-invocation overhead.

## API Gateway Cost Optimization

**REST API vs HTTP API:**
- REST API: $3.50 per million requests + caching costs
- HTTP API: $1.00 per million requests (70% cheaper), no caching option

HTTP API is the right choice for most new workloads unless you specifically need:
- API caching
- SOAP passthrough
- Private integrations (use HTTP API with PrivateLink instead)

**Caching:** API Gateway caching adds ~$0.02 per 1,000 requests. At high traffic, caching reduces backend Lambda invocations significantly. Calculate whether the caching cost is less than the Lambda cost reduction.

**Regional vs Edge-optimized:** Edge-optimized endpoints route through CloudFront, adding ~2-5ms latency for most users. If your users are in a single region, use regional endpoints and save the CloudFront charges.

## Cold Start Cost Impact

Cold starts add duration to the first invocation after a period of inactivity. For VPC Lambda, cold starts are longer (20-30 seconds) due to ENI attachment.

**Duration impact:** Cold starts run your function code, paying for the full cold start duration. A 1-second cold start at 512MB costs the same as 1 second of normal execution.

**Mitigation:**
- Keep functions warm with scheduled CloudWatch Events (every 5 minutes)
- Use provisioned concurrency for latency-sensitive workloads
- Provisioned concurrency eliminates cold starts entirely
- Move dependencies outside the handler (global scope) so they're initialized once
- Use lighter runtimes (Python/Node.js over Java/JVM which has longer cold starts)

## Cost Optimization Checklist

```
□ Run Lambda Power Tuning to find optimal memory setting
□ Move to HTTP API from REST API where caching isn't needed
□ Check if VPC Lambda is causing unnecessary NAT Gateway charges
□ Use S3 Gateway Endpoints for S3 access from Lambda in VPC
□ Use RDS Proxy to avoid NAT for database access
□ Replace scheduled Lambda warming with provisioned concurrency if cost-effective
□ Set appropriate timeout (don't let a 100ms function run for 5 minutes on error)
□ Monitor for functions that are constantly timing out (wasted duration)
```

## References

- **Homepage:** https://aws.amazon.com/lambda/pricing/
- **Documentation:** https://docs.aws.amazon.com/lambda/latest/dg/welcome.html
- **Pricing:** https://aws.amazon.com/lambda/pricing/

## Pricing Examples

**Scenario 1:** A webhook processing Lambda: 128MB memory, avg 80ms duration, 500K invocations/day. Monthly cost: 500K × 30 = 15M invocations × $0.20/million = $3.00 + compute:15M × 0.08s × $0.000008333/vCPU-second (128MB = 0.125 vCPU) = $10.00. Total: ~$13/month. Increasing memory to 512MB (4x) but reducing duration to 20ms: compute = 15M × 0.02s × $0.0000333/vCPU-second = $10.00. Total: ~$13/month. Same cost, better performance.

**Scenario 2:** A VPC Lambda function making 10M invocations/month. VPC Lambda creates an ENI in your subnet. ENI hourly cost (us-east-1): $0.045/hr per ENI. With 10M invocations and the Lambda hyperplane sharing ENIs, ~50 ENIs active:50 × $0.045 × 730hr = $1,642/month just for ENIs. Moving the Lambda out of the VPC saves $1,600/month. For Lambda that only needs AWS service access, VPC is rarely worth the cost.

## Nuggets& Gotchas

- **Lambda pricing rounds duration UP to the nearest millisecond:** A function that runs 1ms is billed as 1ms. A function that runs 1.1ms is billed as 2ms. Optimize your functions to run just under the millisecond boundary where possible.
- **Provisioned Concurrency is billed whether you use it or not:** You pay for the configured concurrency instances at the On-Demand rate. If you set 100 provisioned concurrency and only use 10, you still pay for all 100. Only use it for baseline load that must not cold-start.
- **Lambda ENI creation is the main cause of cold starts in VPC:** The hyperplane ENI sharing reduces this for high-concurrency functions, but new accounts or new subnets still see cold starts of 5-10 seconds. Minimize VPC Lambda where cold starts are unacceptable.
- **Lambda cost is dominated by duration, not invocation count:** At 128MB, each GB-second costs $0.000008333. A 100ms function at 128MB costs 0.000008333 cents. But a 30-second function at 512MB costs 0.025 cents — 3,000x more. Optimize for duration first.
- **Lambda layer extraction happens at every cold start:** If your layer is 50MB, it needs to be extracted from /opt before your function runs. Large layers extend cold start times. Keep layers small or bundle dependencies inline.