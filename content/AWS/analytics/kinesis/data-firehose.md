---
title: Kinesis Data Firehose
description: Kinesis Data Firehose — near-real-time data delivery to S3, Redshift, Elasticsearch, Splunk, HTTP endpoints. Buffering, transforms, compression, and use cases
tags:
  - aws
  - analytics
  - kinesis
---

# Kinesis Data Firehose

Kinesis Data Firehose is a managed near-real-time delivery service. Unlike Kinesis Data Streams (which you consume from), Firehose automatically delivers data to destinations — S3, Redshift, Elasticsearch, Splunk, or any HTTP endpoint. You configure it, and data flows.

## How It Works

```
Producer → Firehose Stream → Buffer (configurable) → Transform (optional) → Destination
```

**Buffering:** Firehose buffers incoming records and delivers them in batches. The buffer size and interval are configurable:
- **Buffer size:** 1MB-128MB (depending on destination)
- **Buffer interval:** 60-900 seconds

Delivery triggers when **either** the buffer size **or** the buffer interval is reached, whichever comes first.

**Example:** Buffer of 5MB or 60 seconds. If you send 1MB at t=0 and then nothing, delivery happens at t=60. If you send 10MB in one burst, delivery happens immediately when 5MB threshold is hit.

## Destinations

### S3

The most common destination. Firehose writes data to S3 as compressed objects.

```json
{
  "Destination": "S3",
  "S3Configuration": {
    "BucketARN": "arn:aws:s3:::my-bucket",
    "Prefix": "firehose/raw/",      // Optional prefix per delivery
    "ErrorOutputPrefix": "errors/", // Where to write failed records
    "BufferingHints": {
      "SizeInMBs": 10,
      "IntervalInSeconds": 300
    },
    "CompressionFormat": "GZIP",     // GZIP, ZIP, Snappy, Parquet, NotCompressed
    "EncryptionConfiguration": {
      "NoEncryptionConfig": "EncryptionDisabled"
    }
  }
}
```

**Formats:** Firehose can convert records to JSON, CSV, Parquet, or ORC before writing to S3. Parquet is most efficient for analytical queries.

### Amazon Redshift

Firehose unloads data to S3 first (as an intermediate step), then executes a COPY command into Redshift.

```
Firehose → S3 (staging) → COPY into Redshift
```

The COPY command is triggered automatically when Firehose delivers to the staging S3 bucket. This means:
- A separate Redshift cluster must be accessible from the Firehose VPC endpoint
- Staging bucket must be in the same region as Redshift
- COPY adds latency — data isn't in Redshift until after the COPY completes (usually within a few minutes of Firehose delivery)

### Elasticsearch / OpenSearch

Direct delivery to Elasticsearch domain. Firehose writes to a specified index with configurable document ID generation.

### Splunk

Delivers to Splunk HEC (HTTP Event Collector). Firehose handles token authentication and can retry on failure.

### HTTP Endpoint

Custom destination for any HTTP endpoint. Firehose sends batches via POST request with JSON payload. Useful for third-party integrations, data platforms that support HTTP ingestion.

## Data Transformation

Firehose can transform records using Lambda before delivery:

```python
import json

def lambda_handler(event, context):
    output = []
    for record in event['records']:
        # Parse the incoming record
        data = json.loads(record['data'])
        
        # Transform: add timestamp, normalize fields
        transformed = {
            'event_time': data['timestamp'],
            'user_id': data['userId'],
            'action': data['event'],
            'properties': data.get('properties', {}),
            'processed_at': datetime.utcnow().isoformat()
        }
        
        output.append({
            'record_id': record['recordId'],
            'data': json.dumps(transformed).encode('utf-8'),
            'result': 'Ok'  # or 'Dropped' or 'ProcessingFailed'
        })
    
    return {'records': output}
```

**Transformation flow:**
1. Records accumulate in Firehose buffer
2. Firehose invokes your Lambda with a batch of records
3. Lambda transforms each record and returns the result
4. Firehose delivers transformed records to the destination

**Error handling:** If Lambda returns `ProcessingFailed`, Firehose retries the Lambda invocation. After 3 failures, it writes the original record to the S3 error prefix you specified.

## Buffering and Delivery Tuning

### S3 Destination Buffering

| Buffer Size | Buffer Interval | Use When |
|------------|-----------------|----------|
| 1MB | 60s | Low-latency requirements, small payloads |
| 5MB | 300s | Balanced latency/cost for most analytics workloads |
| 128MB | 900s | Large payloads, cost-optimized for infrequent delivery |

### Redshift Buffering

Redshift COPY performs best with larger batches. Recommended:
- Buffer size: 64MB or higher
- Buffer interval: 300-600 seconds
- This reduces the number of COPY commands and improves Redshift query performance

### Compression

GZIP is the default and most compatible. Snappy provides better performance with Athena (columnar formats like Parquet benefit from Snappy). If you're delivering to S3 for Athena queries, use Parquet with Snappy compression — fastest query performance.

## Delivery Failures and Retries

Firehose retries delivery for up to a configurable timeout period (default: 3,600 seconds). After timeout:
1. Data is written to the S3 error prefix you configured
2. CloudWatch metric `Firehose.DeliveryToS3.DataFreshness` shows how old data in the buffer is

**Common failure causes:**
- Lambda transformation failures (invalid JSON output)
- Redshift cluster unavailable
- Elasticsearch domain throttling
- S3 bucket permissions changed

## vs Kinesis Data Streams

| | Data Streams | Data Firehose |
|--|-------------|--------------|
| Consumer model | You build consumer apps | Fully managed delivery |
| Scaling | Manual shard management | Automatic (auto-scales) |
| Latency | Sub-second (real-time) | Near-real-time (buffered, 1-5 min) |
| Replay | Yes (configurable start position) | No (no replay capability) |
| Use when | You need real-time consumers | You just need data delivered to storage |

**Typical architecture:** Data Streams for real-time processing → Firehose for durable delivery to storage. Or use Firehose alone if you just need data delivered to S3/S3+Redshift without real-time processing.

## References

- **Homepage:** https://aws.amazon.com/kinesis/data-firehose/
- **Documentation:** https://docs.aws.amazon.com/firehose/latest/dev/
- **Pricing:** https://aws.amazon.com/kinesis/data-firehose/pricing/

## Pricing Examples

**Scenario 1:** A log aggregation pipeline: 10GB/day of application logs → Firehose → S3. Firehose charges: $0.029/GB for data ingested (first 10TB/month).10GB/day × 30 = 300GB/month. Cost: 300GB × $0.029 = $8.70/month. S3 storage (300GB Standard):300GB × $0.023 = $6.90/month. Total: ~$15.60/month. Compare to CloudWatch Logs at $0.50/GB ingestion + $0.03/GB storage = $159/month.

**Scenario 2:** A security pipeline: 50GB/day of VPC flow logs → Firehose → S3 → Athena. Firehose: 50GB × 30 = 1,500GB × $0.029 = $43.50/month. S3: 1,500GB × $0.023 = $34.50/month. Athena:1,500GB scanned × $5/TB = $7.50/query if queried monthly. Total: ~$78/month plus Athena query costs.

## Nuggets & Gotchas

- **Firehose buffers data and delivers at batch boundaries:** Buffer size (default 5MB) and buffer interval (default 5 minutes) determine delivery latency. A low-traffic stream might deliver only once every 5 minutes, not sub-second.
- **S3 compression is per-buffer, not per-object:** If you set GZIP compression, each buffer flush creates one compressed object in S3. If you have small, frequent buffers, you'll have many small S3 objects — which is expensive to list and expensive to query in Athena.
- **No replay in Firehose:** Unlike Kinesis Data Streams, Firehose doesn't support replay. If you need to reprocess data, you need to replay it from the source (e.g., re-send from your application or use a separate Streams → Firehose architecture).
- **S3 destination failed delivery goes to S3 backup bucket:** When Firehose can't deliver to S3 (e.g., bucket doesn't exist), it writes to a backup bucket you configure. If you don't configure one, data is lost. Always configure a backup bucket.
- **Firehose API calls are separate from data ingestion billing:** API calls for DescribeDeliveryStream, ListDeliveryStreams, etc. are charged separately at $0.04/million. At high API call rates (e.g., from misconfigured SDK retries), this can add up.