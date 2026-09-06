---
title: Azure Event Hubs Architecture, Kafka Compatibility, and Streaming Ingestion
description: Exhaustive engineering guide to Azure Event Hubs — planetary-scale event streaming, Apache Kafka wire-protocol compatibility, partitions, consumer groups, Event Hubs Capture to Blob/ADLS, and dedicated clusters.
tags:
  - azure
  - messaging
  - event-hubs
  - kafka
  - streaming
  - big-data
---

# Azure Event Hubs Architecture, Kafka Compatibility, and Streaming Ingestion 🌊📡

**Azure Event Hubs** is a fully managed, real-time distributed data streaming platform capable of ingesting millions of events per second with sub-second latencies. Functioning as a high-throughput event ingestion front-door, Event Hubs natively supports the **Apache Kafka 1.0+ client wire protocol**, enabling organizations to run existing Kafka applications, Kafka Connect pipelines, and MirrorMaker 2.0 without hosting, patching, or sizing Apache ZooKeeper / KRaft clusters.

---

## 1. Architecture & Disaggregated Log Storage

Unlike traditional message brokers (like Service Bus) where messages are deleted upon acknowledgment, Event Hubs utilizes a **partitioned, append-only commit log architecture** similar to Apache Kafka.

```
                        EVENT PRODUCERS (IoT, Microservices, Fluentbit)
                                        │
                                        ▼ (HTTPS / AMQP 1.0 / Kafka Port 9093)
       ┌────────────────────────────────────────────────────────────────────────┐
       │                 AZURE EVENT HUBS INGESTION GATEWAY                     │
       │  - Native Apache Kafka API translation layer                           │
       │  - TLS termination & Entra ID / SAS Token Authentication               │
       └───────────────────────────────────┬────────────────────────────────────┘
                                           │
       ┌───────────────────────────────────┴────────────────────────────────────┐
       │                EVENT HUB (TOPIC): 32 PARTITIONS                        │
       │                                                                        │
       │  Partition 0  [0]─►[1]─►[2]─►[3]─►[4]─►[5]  (Sequential Offset Log)   │
       │  Partition 1  [0]─►[1]─►[2]─►[3]             (Sequential Offset Log)   │
       │  Partition N  [0]─►[1]─►[2]─►[3]─►[4]─►[5]─►[6] (Sequential Offset Log)│
       └───────────────────┬────────────────────────────────┬───────────────────┘
                           │                                │
                           ▼ Continuous Batch Capture       ▼ Independent Consumer Offsets
       ┌──────────────────────────────────────┐  ┌──────────────────────────────┐
       │      EVENT HUBS CAPTURE ENGINE       │  │   INDEPENDENT CONSUMER       │
       │  (Zero-Code Pipeline to Storage)     │  │          GROUPS              │
       │  - Batches by time (1-15 min) or     │  │  ┌────────────────────────┐  │
       │    size (10-500 MB)                  │  │  │ Consumer Group: $Default│ │
       │  - Writes Avro / Parquet to Blob     │  │  │ (Stream Analytics /    │  │
       │    or Azure Data Lake Storage Gen2   │  │  │  Real-Time Dashboards) │  │
       └───────────────────┬──────────────────┘  │  └────────────────────────┘  │
                           │                     │  ┌────────────────────────┐  │
                           ▼                     │  │ Consumer Group: ML-Model│ │
       ┌──────────────────────────────────────┐  │  │ (Databricks / Python   │  │
       │    AZURE BLOB / ADLS GEN2 STORAGE    │  │  │  Inference Pipeline)   │  │
       │  `/year/month/day/hour/part-0.avro`  │  │  └────────────────────────┘  │
       └──────────────────────────────────────┘  └──────────────────────────────┘
```

### Core Architecture Constructs

1. **Partitions:** An ordered sequence of events stored in an immutable append-only commit log. The partition count is determined at creation (1 to 32 in Standard; up to 1,024 in Dedicated) and dictates the maximum number of concurrent consumer threads per consumer group.
2. **Event Offset:** A monotonically increasing numerical marker indicating the position of an event within a partition. Consumers read forward from specific offsets and commit checkpoint markers.
3. **Consumer Groups:** Independent reader views over the entire Event Hub. Each consumer group can read the full log stream at its own cadence without interfering with other reader groups.
4. **Event Hubs Capture:** An automated background daemon that streams raw event batches directly into Azure Blob Storage or Azure Data Lake Storage Gen2 in **Apache Avro** or **Parquet** format with zero custom ingestion code.

---

## 2. Apache Kafka Wire-Protocol Compatibility

Event Hubs exposes an endpoint compatible with Apache Kafka clients version 1.0 and higher:
- **Concept Translation:**
  - Kafka Topic $\Longleftrightarrow$ Event Hub
  - Kafka Partition $\Longleftrightarrow$ Event Hub Partition
  - Kafka Consumer Group $\Longleftrightarrow$ Event Hub Consumer Group
  - Kafka Cluster / Bootstrap Server $\Longleftrightarrow$ `<namespace>.servicebus.windows.net:9093`
- **Zero Code Modification:** Kafka client applications in Java, Go, or Python only require updating connection strings and JAAS configurations to point to Event Hubs over port 9093.

---

## 3. Production Deployment & CLI Operations (`az`)

### 1. Deploy a Standard Event Hubs Namespace with Auto-Inflate

```bash
az group create --name rg-streaming-prod --location eastus

# Create Event Hubs Namespace with 4 Throughput Units (TUs) and Auto-Inflate enabled up to 20 TUs
az eventhubs namespace create \
    --name eh-telemetry-prod-eastus \
    --resource-group rg-streaming-prod \
    --location eastus \
    --sku Standard \
    --capacity 4 \
    --enable-auto-inflate true \
    --maximum-throughput-units 20 \
    --enable-kafka true \
    --minimum-tls-version 1.2
```

### 2. Create an Event Hub with 16 Partitions & Event Hubs Capture

```bash
# Retrieve Storage Account Resource ID for Capture destination
STORAGE_ID=$(az storage account show \
    --name stfinancedataprod01 \
    --resource-group rg-data-prod \
    --query id -o tsv)

# Create Event Hub with 7-day retention and automated Blob Capture in Avro format
az eventhubs eventhub create \
    --name raw-telemetry-stream \
    --namespace-name eh-telemetry-prod-eastus \
    --resource-group rg-streaming-prod \
    --partition-count 16 \
    --message-retention 7 \
    --enable-capture true \
    --capture-interval 300 \
    --capture-size-limit 314572800 \
    --destination-name EventHubArchive.AzureBlockBlob \
    --storage-account "${STORAGE_ID}" \
    --blob-container telemetry-archive \
    --archive-name-format "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
```

### 3. Create Dedicated Consumer Groups for Microservices

```bash
# Create Consumer Group for Real-Time Fraud Engine
az eventhubs eventhub consumer-group create \
    --name fraud-detection-pipeline \
    --eventhub-name raw-telemetry-stream \
    --namespace-name eh-telemetry-prod-eastus \
    --resource-group rg-streaming-prod

# Create Consumer Group for Databricks Lakehouse Ingest
az eventhubs eventhub consumer-group create \
    --name databricks-ingestion \
    --eventhub-name raw-telemetry-stream \
    --namespace-name eh-telemetry-prod-eastus \
    --resource-group rg-streaming-prod
```

### 4. Connect Kafka Client to Event Hubs (`producer.properties`)

Configure standard Apache Kafka clients to write directly into Event Hubs:

```properties
bootstrap.servers=eh-telemetry-prod-eastus.servicebus.windows.net:9093
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required \
    username="$ConnectionString" \
    password="Endpoint=sb://eh-telemetry-prod-eastus.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=secretKey123";
client.id=telemetry-kafka-producer
acks=all
```

---

## 4. Quotas, Performance, and Configuration Limits

| Parameter / Dimension | Standard Tier | Premium Tier | Dedicated Cluster |
| :--- | :--- | :--- | :--- |
| **Capacity Units** | Throughput Units (TUs) | Processing Units (PUs) | Capacity Units (CUs) |
| **Ingress Rate per Unit**| 1 MB/s (1,000 events/sec) | 5 MB/s to 10 MB/s | 100+ MB/s |
| **Egress Rate per Unit** | 2 MB/s (4,096 events/sec) | 10 MB/s to 20 MB/s | 200+ MB/s |
| **Max Message Size** | 1 MB | 100 MB | 100 MB |
| **Partitions per Hub** | Up to 32 partitions | Up to 100 partitions | Up to 1,024 partitions |
| **Event Retention** | 1 to 7 days | 1 to 90 days | Up to 90 days |
| **Consumer Groups per Hub**| 20 consumer groups | 100 consumer groups | 1,000 consumer groups |

---

## 5. Official References & Documentation

- [Azure Event Hubs Overview](https://learn.microsoft.com/en-us/azure/event-hubs/event-hubs-about)
- [Use Azure Event Hubs from Apache Kafka Applications](https://learn.microsoft.com/en-us/azure/event-hubs/azure-event-hubs-kafka-overview)
- [Event Hubs Capture Architecture & Features](https://learn.microsoft.com/en-us/azure/event-hubs/event-hubs-capture-overview)
- [Event Hubs Scalability & Auto-Inflate](https://learn.microsoft.com/en-us/azure/event-hubs/event-hubs-auto-inflate)
- [Azure Event Hubs Pricing Matrix](https://azure.microsoft.com/en-us/pricing/details/event-hubs/)

---

## 6. Realistic Pricing Scenarios

Azure Event Hubs pricing is based on:
1. **Throughput Units (TUs):** $0.03 per TU per hour (~$21.90/month per TU) in Standard Tier.
2. **Ingress Events:** $0.028 per million events ingested.
3. **Capture Feature:** $0.10 per hour per Event Hub (~$73.00/month).
4. **Extended Retention:** $0.10 per GB-month for data retained beyond 1 day.

### Scenario A: High-Throughput IoT Telemetry Stream (Standard Tier - 4 TUs)

- **Workload Profile:**
  - 4 Throughput Units provisioned with Auto-Inflate up to 10 TUs (average steady state: 4 TUs).
  - Ingestion: 200 million IoT events per month (average payload: 1 KB).
  - 1 Event Hub with **Capture enabled** to Azure Data Lake Storage Gen2.
- **Monthly Cost Calculation:**
  - Throughput Units: 4 TUs × $0.03/hr × 730 hrs = **$87.60**
  - Event Ingestion Fee: 200M events × $0.028/M = **$5.60**
  - Event Hubs Capture: $0.10/hr × 730 hrs = **$73.00**
  - ADLS Gen2 Storage (200 GB raw): $200 \times \$0.018 = \mathbf{\$3.60}$
- **Total Monthly Cost:** **$169.80 / month**

### Scenario B: Massive Corporate Kafka Migration (Premium Tier - 2 PUs)

- **Workload Profile:**
  - Migrating 15 Apache Kafka microservices to Event Hubs Premium.
  - Requires 90-day retention, dynamic partition scaling, and private VNet endpoints.
  - 2 Processing Units (PUs) running 24/7 across 3 Availability Zones ($1.40/PU-hr = $2.80/hr total).
  - Ingestion: 2 billion events per month (~1.5 TB raw data).
- **Monthly Cost Calculation:**
  - Processing Units: 2 PUs × $1.40/hr × 730 hrs = **$2,044.00**
  - Event Ingestion: Included with Premium tier ($0.00).
  - Extended Retention Storage (1.5 TB × 3 months = 4.5 TB): $4{,}500 \text{ GB} \times \$0.05/\text{GB} = \mathbf{\$225.00}$
- **Total Monthly Cost:** **$2,269.00 / month**

---

## 7. Battle-Tested Nuggets & Production Gotchas

1. **Throughput Unit (TU) Throttling Quotas are Strict:** A single Throughput Unit (TU) in Standard tier provides exactly **1 MB/s (or 1,000 events/sec) ingress** and **2 MB/s egress**. If your application exceeds these rates even for 1 second, Event Hubs immediately returns `ServerBusyException` (HTTP 503 / Kafka broker error) and rejects messages. Always enable **Auto-Inflate** with a safe upper ceiling (`maximum-throughput-units`) to handle unexpected traffic spikes.
2. **Partition Count Cannot Be Decreased:** While Azure now allows increasing partition counts on certain tiers, **partition count can NEVER be decreased**. If you create an Event Hub with 32 partitions, you will have 32 partitions forever. Furthermore, increasing partitions on an active hub changes the hash mapping for partition keys (`CRC32`), which causes subsequent events for an existing partition key to route to a different partition, breaking strict per-entity ordering.
3. **Partition Sizing Determines Consumer Concurrency:** In the Event Hubs / Kafka consumer model, **each partition can be read by only ONE active consumer instance within a consumer group**. If your Event Hub has 4 partitions and you deploy 10 consumer pods in your AKS cluster, **6 of those pods will sit completely idle** doing zero work. Size your partition count according to your maximum expected parallel consumer concurrency.
4. **Kafka Compaction is NOT Supported in Standard/Premium:** Traditional Kafka clusters support topic log compaction (`cleanup.policy=compact`), keeping only the latest value for each key. Azure Event Hubs operates purely as a chronological retention log and **does not support Kafka log compaction**. If your architecture relies on Kafka state stores (e.g., Kafka Streams KTables) backed by compacted changelog topics, you cannot use Event Hubs Standard/Premium directly.
5. **Event Hubs Capture Skips Empty Buffers:** When configuring Event Hubs Capture with a 5-minute interval, if zero events are published to a partition during that 5-minute window, Capture writes a 0-byte or minimal metadata Avro file depending on the `skip_empty_archives` flag. Ensure downstream ETL pipelines (e.g., Azure Data Factory, Spark) handle empty or missing hourly Avro files gracefully without throwing missing partition exceptions.
6. **Entra ID Token Expiration in Kafka Client Libraries:** When configuring Apache Kafka clients to authenticate to Event Hubs via Microsoft Entra ID (OIDC OAuth2) instead of static Shared Access Signature (SAS) strings, the OAuth bearer token expires after 60 minutes. The Kafka client must implement an automated background token refresher callback (`AuthenticateCallbackHandler`), or client connections will abruptly fail after exactly 1 hour with `SASL authentication failed: invalid token`.
