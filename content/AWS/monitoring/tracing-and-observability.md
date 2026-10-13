---
title: "Tracing and operational observability"
description: "Connect logs, metrics and traces to customer outcomes, cross-account access, alarm runbooks and bounded telemetry cost."
tags:
  - cloud/aws/monitoring
date: 2026-10-12
---

# Tracing and operational observability

Logs describe events, metrics summarize measurements and traces show a request's path across instrumented components. None alone proves customer success. Start with [[AWS/monitoring/README|CloudWatch lessons]] and the workload's [[AWS/reliability/README|service objectives]].

## Instrumentation decisions

Propagate trace context across HTTP and supported messaging boundaries; distinguish parent/child relationships from asynchronous links. Use supported OpenTelemetry/ADOT collectors and exporters. X-Ray is a tracing backend/integration, not a substitute for application instrumentation.

Sample intentionally: reducing trace volume lowers cost but can hide rare failures. Never attach credentials, sensitive document text or unbounded customer identifiers to telemetry attributes. Metrics with high-cardinality dimensions can grow costs sharply.

Cross-account observability provides controlled visibility through OAM-supported links. Log centralization/copying is a different data movement/retention design. Establish source/sink permissions and data residency explicitly.

## Correlation exercise

Prerequisites: the sandbox [[AWS/compute/lambda/README|Lambda]] or [[AWS/serverless/app-runner/README|App Runner]] lab, supported tracing setup, a telemetry budget and non-sensitive input.

1. Send one successful and one deliberately failing request with a correlation ID.
2. Locate request logs, latency/error metrics and the trace; show the failing dependency/span rather than only a generic 500.
3. Compare event timestamp with ingestion time when data arrives late.
4. Create an alarm tied to a user-impacting signal with a runbook and owner; trigger it safely.
5. Acknowledge the alert, follow the runbook, correct the sandbox fault and verify recovery.
6. Restore settings and delete dedicated alarms/dashboards/logs/tracing resources after preserving required evidence.

Expected evidence: one correlated request story and an operator action that restores the defined outcome. A dashboard with charts but no investigation path is not an operational handoff.

## Capacity and cost

Distinguish publishing interval, storage resolution, roll-up retention and supported modern OTel metric types. Check actual account quotas rather than copying conflicting subscription limits. Price metric identities/cardinality, API usage, ingested/retained/scanned logs, traces and dashboards separately.

For EKS, reuse [[Kubernetes/eks/observability/metrics/adot|ADOT setup]] and [[Kubernetes/eks/observability/README|the observability track]].

## References

- [ADOT documentation](https://aws-otel.github.io/docs/introduction).
- [OpenTelemetry context propagation](https://opentelemetry.io/docs/concepts/context-propagation/).
- [CloudWatch cross-account observability](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Unified-Cross-Account.html).
- [CloudWatch pricing](https://aws.amazon.com/cloudwatch/pricing/).
