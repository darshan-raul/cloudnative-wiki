---
title: AWS Serverless
description: AWS serverless services — Lambda (compute), API Gateway (HTTP/REST/WebSocket APIs), App Runner (containers), and Bedrock (foundation models). Pay only for what you use.
tags:
  - aws
  - serverless
---

# AWS Serverless

Serverless means you don't manage servers — AWS handles provisioning, scaling, and capacity. You write functions or deploy containers, and pay per execution/request.

## Service Map

| Service | Type | Use Case |
|---------|------|----------|
| [[lambda/README\|Lambda]] | Functions | Event-driven compute, glue logic |
| [[api-gateway/README\|API Gateway]] | API | REST/WebSocket/HTTP APIs, rate limiting |
| [[app-runner/README\|App Runner]] | Containers | Web apps, APIs without infra management |
| [[../machine-learning/bedrock/README\|Bedrock]] | Foundation Models | LLMs, RAG, agents |

## When to Use Serverless

```
Need to run code?
  │
  ├── Short-running (< 15 min) ──► Lambda (functions)
  │
  ├── Long-running (> 15 min)
  │   ├── Container workload ────► App Runner / ECS Fargate
  │   └── Batch job ────────────► Batch
  │
  └── HTTP/REST API ─────────────► API Gateway + Lambda
  │
  └── Web app (container) ───────► App Runner
```

## Cold Starts

```
Request arrives
  │
  ├── Warm (instance cached) ──► Execute immediately ──► Response
  │
  └── Cold ──► Download code ──► Start runtime ──► Execute ──► Response
               │                                         │
               └── 500ms-2s latency                     └── Total time
```

## Pricing Comparison

| Service | Pricing Model |
|---------|--------------|
| Lambda | $0.20/1M requests + $0.0000166667/GB-second |
| API Gateway | $3.50/million API calls (REST), $0.50/million (HTTP) |
| App Runner | $0.05/vCPU-hour + $0.02/GB-hour |
| Fargate | $0.04048/vCPU-hour + $0.004442/GB-hour |

## References

- **Homepage:** https://aws.amazon.com/serverless/
- **Documentation:** https://docs.aws.amazon.com/lambda/, https://docs.aws.amazon.com/apigateway/
- **Pricing:** https://aws.amazon.com/lambda/pricing/, https://aws.amazon.com/apigateway/pricing/

## Nuggets & Gotchas

- **Lambda cold starts can be 1-5 seconds — for latency-sensitive apps, keep functions warm:** Use provisioned concurrency (pre-warmed instances) or scheduled pings to keep functions warm. Provisioned concurrency costs money but eliminates cold starts.
- **Serverless doesn't mean scale-to-zero instantly — there's always a brief provisioning delay:** Even with Lambda's near-infinite scale, the first request to a new instance after idle has a cold start. Design for this.
- **Lambda has a 15-minute maximum execution time — for longer jobs, use Step Functions or ECS/Fargate:** If your job takes 30 minutes, Lambda will timeout at 15 minutes. Break into smaller steps or use a different service.
- **App Runner is NOT the same as Lambda — you manage the container image, not just code:** App Runner runs containers, so you need a Dockerfile and container registry. Lambda lets you just upload code/zip. App Runner is for when you need full runtime control.
- **Serverless pricing can be unexpectedly high at scale — 100M Lambda invocations/month = $20K/month:** At low volume, serverless is cheap. At high volume (millions of requests/minute), a persistent service (ECS/Fargate) is often cheaper. Model your costs before going all-in on serverless.