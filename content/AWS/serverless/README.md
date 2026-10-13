---
title: "AWS serverless"
description: "Select functions, containers, APIs and workflows by execution/failure needs and actual billing dimensions."
tags:
  - cloud/aws/serverless
date: 2026-10-12
---

# AWS serverless

Serverless shifts infrastructure management to the service; it does not mean limitless scaling, no provisioning latency or exclusively per-request billing.

## Learning route

| Requirement                              | Lesson                                                                | Key boundary                                   |
| ---------------------------------------- | --------------------------------------------------------------------- | ---------------------------------------------- |
| Event-driven code                        | [[AWS/compute/lambda/README\|Lambda]]                                 | Invocation model, duration, idempotency        |
| Client-facing API                        | [[AWS/serverless/api-gateway/README\|API Gateway]]                    | Authentication, integration, timeout, logs     |
| Existing-customer managed web deployment | [[AWS/serverless/app-runner/README\|App Runner]]                      | Source/image path, active/provisioned capacity |
| Container control                        | [[AWS/compute/ecs/README\|ECS/Fargate]]                               | Task/service lifecycle, networking, roles      |
| Orchestration                            | [[AWS/application-integration/step-functions/README\|Step Functions]] | Retry/Catch, state, external side effects      |
| Buffered work                            | [[AWS/application-integration/sqs/README\|SQS]]                       | Visibility, ordering, poison messages          |

App Runner supports source repositories as well as container images; a user Dockerfile is not universally required. Lambda supports archives and supported container images; image packaging does not remove Lambda's execution constraints.

Standard Lambda functions have a fifteen-minute invocation limit; advanced execution modes have separately documented boundaries. App Runner HTTP requests have a 120-second timeout even though its service instances remain running.

## Price the workload

One hundred million Lambda requests at an illustrative \$0.20/million cost \$20 **in request charges**, not \$20,000. Add billed memory-duration and dependencies. Provisioned concurrency and App Runner provisioned memory can be charged while idle.

Model request count/size, execution duration, memory/CPU, data transfer, storage, telemetry and optional features. Specify Region, architecture and pricing date. Do not infer that one runtime is always cheaper from request count alone.

## Failure exercise

Design an upload API and queued worker. Explain synchronous acceptance versus eventual completion, duplicate handling, DLQ ownership, retry limits and cancellation. Use the canonical Lambda/SQS/API lessons for test setup and cleanup. Define measurable end-to-end latency, not a universal cold-start number.

## Execution and architecture comparison

| Workload                             | Function/API path                     | Container/workflow alternative | Trade-off to test                                       |
| ------------------------------------ | ------------------------------------- | ------------------------------ | ------------------------------------------------------- |
| Short request                        | Lambda + supported API front end      | ECS/Fargate web service        | Latency, concurrency, runtime/resources and idle demand |
| Buffered processing                  | Queue→Lambda mapping                  | Queue→container worker/Batch   | Batch size, retries, long work and side effects         |
| Multi-step business process          | Step Functions tasks                  | Application-owned workflow     | Durable state, compensation and timeout                 |
| Existing eligible simple web service | App Runner source/image               | ECS/Express Mode for new users | Product eligibility, role/network/control boundaries    |
| OS/device-specific work              | Not automatically suitable for Lambda | Supported EC2/container model  | Drivers, hardware, licensing and operational ownership  |

```text
client → API auth/validation → accepted job ID
                              ↓
                        queue/workflow → worker → durable result
                              ↓
                   bounded retry/DLQ/reconciliation → operator
```

The client needs accepted/processing/completed/failed status semantics. A 202/async acceptance is not business completion. Design cancellation, poison jobs, duplicate events, tenant authorization and result retention.

## Cold-start and capacity investigation

Measure actual initialization, package/dependency access, source batching, downstream connections and steady-state duration. Container image size, runtime import and instrumentation can influence startup; no one universal milliseconds table decides workload suitability.

Use provisioned concurrency or warm capacity only for measured requirements and include their billing. A function or managed container can scale faster than a downstream database/API quota; cap concurrency and apply backpressure rather than retry amplification.

## Price comparable workloads

Compare equal Region, memory/CPU, latency/availability, duration and volume. Lambda duration is memory GB × seconds × requests; container bills use provisioned resources/duration and product idle/active dimensions. Requests alone cannot compare the totals.

For a continuously allocated container, count all retained hours; for bursty work include startup/minimum-duration behavior and idle settings. Add API, queue, images, logging, gateways/endpoints, transfer, storage and database. Free-tier/account eligibility and commitment benefits are separate from the workload's base dimensions.

## Deployment and operating ownership

A managed host does not remove runtime/image patching, application authorization, dependency upgrades, alarm/runbook and restore responsibility. Pin supported runtime/image revisions, define rollback with data/schema compatibility and test the exact event contract.

After a sandbox architecture drill remove queues/mappings, workflow executions, APIs/routes, managed services and dedicated network/log/image/secret resources in dependency order. Keep shared infrastructure and required failure evidence. See canonical compute/integration lessons for complete create/test steps rather than duplicating contradictory tariff/limit tables.

## Across the wiki

- [[AI/aws/bedrock|Amazon Bedrock Architecture & Implementation]] — generative AI platforms (AI)
- [[AI/rag|Retrieval-Augmented Generation (RAG) Architecture]] — generative AI platforms (AI)
- [[AI/aws/sagemaker/README|Sagemaker]] — generative AI platforms (AI)
- [[AI/aws/services|Services]] — generative AI platforms (AI)

## References

- [Serverless overview](https://aws.amazon.com/serverless/).
- [Lambda pricing](https://aws.amazon.com/lambda/pricing/).
- [API Gateway pricing](https://aws.amazon.com/api-gateway/pricing/).
- [App Runner pricing](https://aws.amazon.com/apprunner/pricing/).

## Owning contracts and availability

- [Lambda quota/mode boundaries](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html).
- [App Runner existing-customer availability](https://docs.aws.amazon.com/apprunner/latest/dg/apprunner-availability-change.html).

App Runner is closed to new customers; new deployments should follow the supported ECS path rather than assuming eligibility.
