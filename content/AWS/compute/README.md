---
title: AWS Compute
description: AWS compute services — EC2 for virtual servers, Lambda for serverless functions, ECS/EKS for containers, Batch for batch jobs, and Lightsail for simple workloads.
tags:
  - aws
  - compute
---

# AWS Compute

AWS compute covers the full spectrum from bare-metal servers to fully managed serverless functions. Choosing the right compute model depends on workload characteristics: long-running (EC2), event-driven (Lambda), containerized (ECS/EKS), or batch (Batch).

## Service Map

| Service | Compute Model | Control | Use Case |
|---------|--------------|---------|----------|
| [[ec2/README|EC2]] | Virtual machine (bare metal available) | Full control | Long-running, predictable workloads |
| [[lambda/README|Lambda]] | Serverless functions | None (managed) | Event-driven, spiky, short-duration |
| [[ecs/README|ECS]] | Docker containers on EC2 or Fargate | Shared responsibility | Containerized microservices |
| [[eks/README|EKS]] | Kubernetes on EC2 or Fargate | Full K8s API | Complex container orchestration |
| [[batch/README|Batch]] | Batch jobs on managed infra | Job definitions | Scheduled/queued batch processing |
| [[lightsail/README|Lightsail]] | Simple VPS | Simplified | Simple websites, dev/test |

## Compute Decision Tree

```
How long does your workload run?
  │
  ├── Short (< 15 minutes) + event-driven?
  │     YES → Lambda (serverless, pay-per-invocation)
  │     NO ↓
  │
  ├── Containerized?
  │     YES → Do you need full Kubernetes API?
  │           YES → EKS (managed Kubernetes)
  │           NO → ECS (simpler container orchestrator)
  │     NO ↓
  │
  ├── Batch/scheduled jobs?
  │     YES → Batch (managed job scheduler)
  │     NO ↓
  │
  ├── Predictable, long-running?
  │     YES → EC2 (full control, reserved pricing)
  │     NO ↓
  │
  └── Simple website/dev environment?
        YES → Lightsail (simplified, cheap)
        NO → EC2 with auto-scaling
```

## Instance Family Overview

| Family | Specialty | Use Case |
|--------|-----------|----------|
| A/T/M | General purpose | Web servers, small databases |
| C | Compute optimized | Media processing, CI/CD runners |
| R/X | Memory optimized | Databases, in-memory caches |
| G/P/INF | GPU | ML training, inference, graphics |
| I/D | Storage optimized | HDFS, data warehousing,日志处理 |
| Hpc | High performance | Scientific computing, CFD |

## Architecture Patterns

### Auto-Scaling Compute

```
ALB → Auto Scaling Group → EC2 fleet (multi-AZ)
                        → Spot instances (cheap, interruptible)
                        → On-demand (baseline)
```

### Serverless Event-Driven

```
Event (S3, SNS, SQS, CloudWatch, API GW)
  → Lambda function
      → RDS (synchronous)
      → SQS (async processing)
      → SNS (fan-out)
```

### Container Cluster

```
ECS/EKS Cluster
  ├── Service A (3 tasks/pods, multi-AZ)
  ├── Service B (5 tasks/pods)
  └── Service C (1 task, batch job)

  Fargate (serverless containers) or EC2 (self-managed)
```

## AWS Services Organized by Category

**Bare Metal / Virtual Machines**
- [[ec2/README|EC2]] — Virtual servers (instances)

**Serverless**
- [[lambda/README|Lambda]] — Event-driven functions

**Containers**
- [[ecs/README|ECS]] — Docker container orchestrator (Elastic Container Service)
- [[eks/README|EKS]] — Managed Kubernetes (Elastic Kubernetes Service)

**Batch / Scheduled**
- [[batch/README|Batch]] — Managed batch processing

**Simple**
- [[lightsail/README|Lightsail]] — Simple VPS for basic workloads

## References

- **Homepage:** https://aws.amazon.com/products/compute/
- **Documentation:** https://docs.aws.amazon.com/compute/
- **Pricing:** https://aws.amazon.com/pricing/compute/

## Nuggets & Gotchas

- **Lambda has a 15-minute max execution time — long-running tasks need EC2 or ECS:** If your workload takes > 15 minutes, use EC2 (with Auto Scaling) or ECS Tasks. Lambda is designed for short, event-driven processing.
- **EC2 Spot instances are 70-90% cheaper but can be interrupted with 2-minute notice:** Use Spot for fault-tolerant workloads (batch jobs, stateless services). Don't use Spot for databases or stateful services without checkpointing.
- **ECS and EKS both use the same underlying Docker infrastructure — EKS adds Kubernetes API:** If you know Kubernetes, use EKS. If you want simpler AWS-native container management, use ECS. Both can run on EC2 or Fargate.
- **Batch and Lambda solve different problems — Batch for jobs > 15 min, Lambda for < 15 min:** Batch jobs run on EC2 (or Fargate) with job queuing and scheduling. Lambda is for sub-15-minute event-driven tasks.
- **Lightsail is limited compared to EC2 — no Auto Scaling, limited instance types, no VPC peering:** Lightsail is for simple use cases (WordPress, small databases). For production, use EC2 with Auto Scaling and proper networking.