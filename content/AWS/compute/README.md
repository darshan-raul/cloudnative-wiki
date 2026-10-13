---
title: "AWS compute"
description: "Follow compute lessons by required control, execution model and operational ownership rather than a fixed service ranking."
tags:
  - cloud/aws/compute
date: 2026-10-12
---

# AWS compute

Choose a compute model from workload duration, event/retry semantics, resource requirements, isolation, network access and operating responsibility. “Managed” is not the same as no security or application ownership.

## Learning route

| Requirement                    | Lesson                                      | Operating boundary                                 |
| ------------------------------ | ------------------------------------------- | -------------------------------------------------- |
| Guest OS/device control        | [[AWS/compute/ec2/README\|EC2]]             | Patch OS/software and manage storage               |
| Event-driven function          | [[AWS/compute/lambda/README\|Lambda]]       | Invocation/retry/runtime/dependency ownership      |
| Native container orchestration | [[AWS/compute/ecs/README\|ECS/Fargate]]     | Tasks, services, roles and capacity model          |
| Kubernetes API                 | [[AWS/compute/eks/README\|EKS]]             | Cluster/workload lifecycle and access              |
| Queued batch                   | [[AWS/compute/batch/README\|Batch]]         | Compatible job resources, retries and dependencies |
| Simplified selected plans      | [[AWS/compute/lightsail/README\|Lightsail]] | Product-specific constraints and VM operations     |

Then study [[AWS/compute/auto-scaling|fleet lifecycle]], [[AWS/compute/ecr|image publishing]] and [[AWS/developer-tools/README|delivery pipelines]].

A short job can run on Batch; long-lived containers may run on ECS. Standard Lambda limits are not a universal duration rule for every advanced Lambda mode. Predictable demand does not automatically justify a commitment before measuring eligible usage.

## Selection exercise

For an API, an overnight data job and a device-driver workload, identify the required resources/control, failure model and operations owner. Compare two candidates at equal workload/availability and include storage, network, logs and idle capacity.

Build one sandbox checkpoint through the selected lesson, test an intentional failure and perform its cleanup. Do not treat a product matrix as proof of performance.

## Compute decision tree and common patterns

```text
Need guest OS, driver or device control? ── yes → EC2
                 │ no
Need Kubernetes APIs/ecosystem? ──────── yes → EKS
                 │ no
Is work a queue/scheduled batch? ─────── yes → Batch or an ECS job
                 │ no
Is it an event-driven bounded function? yes → Lambda
                 │ no
Need a continuously serving container?  yes → ECS/Fargate
```

This is a starting route, not an eligibility contract. A workload can require several services: a web API may use an ALB, ECS service, SQS queue, Batch workers and S3. Decide based on latency, state, task duration, GPU/CPU/memory shape, identity and network requirements. A simple VM website may fit Lightsail when its plan and operational boundaries are enough.

| Pattern              | Control/data path                                     | Failure question                                         |
| -------------------- | ----------------------------------------------------- | -------------------------------------------------------- |
| Auto-scaled web tier | DNS → load balancer → EC2 Auto Scaling or ECS service | How is an unhealthy member replaced and traffic drained? |
| Event processing     | Queue/event → Lambda or worker → durable store        | How are duplicates, poison messages and retries handled? |
| Batch pipeline       | Schedule/input → queue → Batch job → durable output   | Can work checkpoint after interruption?                  |
| Container platform   | Registry → revision → ECS task or EKS pod             | Who patches hosts and updates the running revision?      |

For instance selection, compare burstable, general-purpose, compute-, memory-, storage- and accelerator-optimized families against measured use. The family label alone does not establish price or availability in a Region. For cost, count compute plus persistent disks, snapshots, egress, public addresses, load balancers and telemetry; include idle capacity and failure-domain requirements.

## References

- [Compute services](https://aws.amazon.com/products/compute/).
- [EC2 operating responsibilities](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/concepts.html).
- [ECS architecture and operating choices](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/Welcome.html).
- [Pricing calculator](https://calculator.aws/).
