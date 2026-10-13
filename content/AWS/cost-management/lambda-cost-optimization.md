---
title: Lambda Cost Optimization
description: Billing models, trade-offs, safe workflows and scoped examples for lambda cost optimization.
tags:
  - aws/cost-management
date: 2026-10-12
---

# Lambda Cost Optimization

Price exercises use hypothetical us-east-1 (US East, N. Virginia) rates for study on 2026-10-12, not current tariffs, unless explicitly identified as a dated published fee.

Optimize Lambda against latency and correctness targets, not memory alone. Duration is billed in GB-seconds using allocated memory; requests are separately charged. Architecture, Region, pricing tier, additional storage and features affect rates.

## Correct unit arithmetic

At illustrative rates of \$0.20/million requests and \$0.0000166667/GB-second, one million invocations with 512 MB and 200 ms use:

```text
memory = 512 / 1024 = 0.5 GB
compute = 1,000,000 × 0.5 × 0.2 = 100,000 GB-seconds
cost = $1.66667 compute + $0.20 requests ≈ $1.87
```

This excludes Free Tier, discounts, initialization differences and other services. Lambda compute is not billed as vCPU-seconds.

At 128 MB for 500 ms, usage is 0.0625 GB-seconds per request. At 512 MB for 100 ms it is 0.05: a 20% compute reduction despite quadrupling memory. Benchmark representative payloads and tail latency; more CPU does not guarantee proportional speedup.

## VPC connectivity

Lambda Hyperplane ENIs have no separate Lambda ENI hourly charge. The earlier \$0.045/ENI-hour example incorrectly borrowed a NAT Gateway rate. Private Lambda-to-RDS traffic can follow VPC-local routes without NAT. RDS Proxy manages database connections; it is not a NAT-bypass requirement.

Internet egress from a VPC-attached function may require NAT, whose hours and processed bytes are charged separately. S3/DynamoDB gateway endpoints can remove NAT from those supported paths. Interface endpoints have their own pricing. Avoid a single-AZ cost shortcut that violates availability requirements.

## Provisioned concurrency

Pay for configured concurrency × memory × configured time, including idle allocation, at the provisioned-concurrency rate. Also pay request charges and execution duration at the applicable provisioned-concurrency execution rate. Overflow can use On-Demand concurrency and pricing. Reserved concurrency is a concurrency limit, not paid pre-initialized capacity.

Schedule provisioned concurrency around measured demand and monitor utilization/spillover. It reduces initialization latency for prepared environments, but does not guarantee that every invocation avoids a cold start or meets an SLA. Scheduled warm-up invocations are not an equivalent guarantee.

## Surrounding costs

Compare API Gateway HTTP and REST APIs by required features and current regional pricing. HTTP APIs support private integrations; private API endpoints and caching have different product support. Count NAT, logs, traces, queues, proxy and transfer costs, not just function duration.

## Memory benchmark worksheet

| Candidate | Allocated memory | Measured duration | GB-seconds/request   |
| --------- | ---------------- | ----------------- | -------------------- |
| A         | 128 MB           | 500 ms            | 0.125 × 0.5 = 0.0625 |
| B         | 512 MB           | 100 ms            | 0.5 × 0.1 = 0.05     |
| C         | 1,024 MB         | 90 ms             | 1 × 0.09 = 0.09      |

B minimizes compute in this synthetic workload, while C may or may not justify its extra cost through latency. Measure p95/p99, initialization, representative input sizes and throttling before selecting a setting. Requests remain a separate charge even if duration improves.

For a webhook example, assume 15 million monthly requests. At 128 MB and 80 ms, usage is 15,000,000 × 0.125 × 0.08 = 150,000 GB-seconds. At 512 MB and 20 ms, it is also 150,000. At the illustrative rate \$0.0000166667/GB-second and \$0.20/million requests, either costs approximately \$2.50 compute + \$3 requests = \$5.50 before allowances/discounts and supporting services. It is not \$13 based on invented vCPU billing.

## Provisioned-concurrency ledger

Assume 100 configured concurrency, 512 MB, eight hours/day for 22 days, one million executions of 200 ms within that capacity. Use hypothetical us-east-1 study rates dated 2026-10-12:

```text
configured GB-seconds = 100 × 0.5 × 8 × 3,600 × 22 = 31,680,000
execution GB-seconds  = 1,000,000 × 0.5 × 0.2 = 100,000
assumed allocation rate = $0.000004/GB-second → $126.72
assumed execution rate  = $0.000010/GB-second → $1.00
requests                = $0.20
illustrative subtotal   = $127.92
```

These rates are deliberately assumptions, not current Lambda tariffs. Allocation is billed while configured even when idle, and configured periods are subject to AWS rounding rules. Overflow, logs, networking and other features are excluded. Compare this with measured On-Demand cost and business latency value, not “\$0.20 per invocation.”

## API and cold-start decisions

REST API capabilities such as caching/private API endpoints differ from HTTP API private integrations. Price an actual API feature set; caching is provisioned capacity, not a universal per-request fee. Edge optimization is not a guaranteed 2–5-ms overhead or an automatically avoidable separate CloudFront bill.

Reduce package/dependency size and initialize reusable clients outside the handler where appropriate. Current Hyperplane networking is not the old per-invocation ENI model. Initialization billing depends on mode/features; compare the current pricing contract. A five-minute warmer does not guarantee every concurrent environment is ready.

The practical checklist is benchmark memory/architecture, set bounded timeout/retries, analyze initialization/spillover, right-size scheduled concurrency, inspect VPC routes/endpoints, and account for logs/API/database proxies.

## References

- [Lambda pricing, including provisioned concurrency](https://aws.amazon.com/lambda/pricing/)
- [VPC connectivity and Hyperplane ENIs](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html)
- [VPC internet access](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc-internet.html)
- [HTTP versus REST APIs](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-vs-rest.html)

Canonical service lesson: [[AWS/compute/lambda/README|AWS Lambda]].
