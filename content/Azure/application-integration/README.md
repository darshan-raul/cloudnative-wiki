---
title: Azure Application Integration & Messaging Hub
description: Master architectural guide to Microsoft Azure application integration and enterprise messaging — Event Grid, Service Bus, Event Hubs, Logic Apps, and API Management.
tags:
  - azure
  - application-integration
  - messaging
  - event-grid
  - service-bus
  - event-hubs
  - logic-apps
  - apim
date: 2026-10-15
---

# Azure Application Integration & Messaging Hub 📨🔄

Microsoft Azure provides a comprehensive enterprise integration platform spanning message queuing, real-time streaming, reactive serverless eventing, low-code workflow orchestration, and enterprise API gateways (see also: [[Azure/messaging/README|Azure Messaging Architecture]]).

---

## Architectural Decision Framework

Choosing the correct integration service depends on message semantics, throughput requirements, consumer pacing, and protocol standards:

```
                                Integration Pattern
                                         │
         ┌───────────────────────────────┼───────────────────────────────┐
         ▼                               ▼                               ▼
Enterprise Message Broker          Big Data Streaming              Reactive Event Router
(AMQP 1.0 / FIFO / Sessions)      (Kafka Wire Protocol / Log)     (CloudEvents 1.0 / MQTT)
         │                               │                               │
[[Azure/messaging/service-bus/README|Azure Service Bus]]        [[Azure/messaging/event-hubs/README|Azure Event Hubs]]        [[Azure/application-integration/event-grid|Azure Event Grid]]
- Queues & Topics                 - Partitions & Consumer Groups  - Namespaces & MQTT v5.0
- Dead-Lettering & Duplicates     - Event Hubs Capture (Blob/ADLS)- Push Webhooks & Pull Queue
         │                               │                               │
         └───────────────────────────────┼───────────────────────────────┘
                                         │
                     ┌───────────────────┴───────────────────┐
                     ▼                                       ▼
            Workflow Orchestration                     API Gateway & Mediation
            (iPaaS / Connectors)                      (Policies / mTLS / Developer)
                     │                                       │
      [[Azure/application-integration/logic-apps|Azure Logic Apps]]          [[Azure/application-integration/apim|Azure API Management (APIM)]]
      - Standard (Single-Tenant)               - v2 Tiers (Standard v2, Premium v2)
      - 400+ SaaS Connectors                   - XML Policy Engine & JWT Validation
```

### Messaging & Integration Capabilities Matrix

| Service                                                                 | Primary Paradigm               | Core Protocols                   | Ordering & Guarantees                                | Best Fit                                                                          |
| :---------------------------------------------------------------------- | :----------------------------- | :------------------------------- | :--------------------------------------------------- | :-------------------------------------------------------------------------------- |
| **[[Azure/messaging/service-bus/README\|Azure Service Bus]]**           | Enterprise Messaging Broker    | AMQP 1.0, SBMP                   | Strict FIFO (Sessions), Exactly-Once / At-Least-Once | Financial transactions, order processing, decoupling microservices.               |
| **[[Azure/messaging/event-hubs/README\|Azure Event Hubs]]**             | Distributed Partitioned Stream | Kafka 1.0+, AMQP, HTTPS          | Ordered per partition, consumer-managed offsets      | Big data telemetry, log aggregation, clickstream ingestion, Kafka bridge.         |
| **[[Azure/application-integration/event-grid\|Azure Event Grid]]**      | Reactive Event Routing Fabric  | CloudEvents 1.0, MQTT v5.0, HTTP | Event-level filtering, Push/Pull delivery            | Serverless microservice notifications, IoT fleets, system state changes.          |
| **[[Azure/application-integration/logic-apps\|Azure Logic Apps]]**      | Cloud iPaaS Workflow Engine    | HTTP, AS2, EDIFACT, 400+ SaaS    | Stateful/Stateless workflow orchestrations           | SaaS integration (Salesforce/SAP), B2B trading partner EDI, business processes.   |
| **[[Azure/application-integration/apim\|Azure API Management (APIM)]]** | Full Lifecycle API Gateway     | HTTP/1.1, HTTP/2, WebSocket      | Policy pipeline (rate limits, transforms, auth)      | Exposing APIs to web/mobile/partners, token validation, microservice abstraction. |

---

## Service Catalog

- [[Azure/application-integration/event-grid|Azure Event Grid Architecture & CloudEvents Broker]] — Namespaces, MQTT v5.0 broker, CNCF CloudEvents v1.0 standard, push vs pull delivery, filtering, and serverless reactive eventing.
- [[Azure/messaging/service-bus/README|Azure Service Bus Enterprise Architecture]] — Queues vs Topics, AMQP 1.0 wire protocol, FIFO message sessions, duplicate detection, dead-lettering, and transactions.
- [[Azure/messaging/event-hubs/README|Azure Event Hubs & Kafka Ingestion Architecture]] — Partitioning, consumer groups, Event Hubs Capture to ADLS Gen2, Kafka protocol compatibility, and throughput units.
- [[Azure/application-integration/logic-apps|Azure Logic Apps Architecture & Enterprise Integration]] — Standard (single-tenant containerized) vs Consumption runtimes, 400+ connectors, stateful vs stateless workflows, and VNet integration.
- [[Azure/application-integration/apim|Azure API Management (APIM) Architecture & Enterprise Gateway]] — Modern v2 tiers (Basic v2, Standard v2, Premium v2), XML policy pipeline, developer portal, OAuth2/JWT validation, and internal VNet injection.

---

## Multi-Cloud Equivalents

| Capability                   | Microsoft Azure                                                | Amazon Web Services (AWS)    | Google Cloud Platform (GCP) |
| :--------------------------- | :------------------------------------------------------------- | :--------------------------- | :-------------------------- |
| **Enterprise Message Queue** | [[Azure/messaging/service-bus/README\|Azure Service Bus]]      | Amazon SQS / Amazon MQ       | Cloud Tasks                 |
| **Event Streaming Engine**   | [[Azure/messaging/event-hubs/README\|Azure Event Hubs]]        | Amazon Kinesis Data Streams  | Cloud Pub/Sub (Streaming)   |
| **Reactive Event Router**    | [[Azure/application-integration/event-grid\|Azure Event Grid]] | Amazon EventBridge           | Eventarc                    |
| **Workflow Orchestration**   | [[Azure/application-integration/logic-apps\|Azure Logic Apps]] | AWS Step Functions / AppFlow | Workflows / Cloud Composer  |
| **API Gateway**              | [[Azure/application-integration/apim\|Azure API Management]]   | Amazon API Gateway           | Apigee API Management       |
