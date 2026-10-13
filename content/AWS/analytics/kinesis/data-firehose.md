---
title: "Amazon Data Firehose"
description: "Amazon Data Firehose is the current name of Kinesis Data Firehose; the firehose API namespace remains unchanged."
tags:
  - aws/analytics
date: 2026-10-12
aliases:
  - Kinesis Data Firehose
---

# Amazon Data Firehose

Amazon Data Firehose is the current name of Kinesis Data Firehose; the firehose API namespace remains unchanged. It delivers buffered records to supported destinations rather than exposing a durable replay/checkpoint interface like [[AWS/analytics/kinesis/data-streams|Data Streams]].

Prerequisites: [[AWS/analytics/kinesis/README|streaming fundamentals]], [[AWS/storage/s3/README|S3]] and [[AWS/security/iam/README|IAM]].

## Delivery and transformation

Configure source, destination, role, encryption, buffering and error/backup settings explicitly. Supported destinations include S3, Redshift, OpenSearch and appropriate HTTP/integration targets, with distinct behavior and permissions. Native format conversion is JSON to Parquet/ORC using configured schema; arbitrary CSV conversion requires a separate transformation. Compression is not format conversion.

Lambda transformation input/output data is base64. Each result must preserve recordId and supply result plus base64 text. This syntactically complete pass-through transform follows that contract but does not deploy a delivery stream:

```python
import base64

def lambda_handler(event, context):
    results = []
    for record in event["records"]:
        payload = base64.b64decode(record["data"])
        results.append({
            "recordId": record["recordId"],
            "result": "Ok",
            "data": base64.b64encode(payload).decode("ascii"),
        })
    return {"records": results}
```

Add schema validation, explicit ProcessingFailed/Dropped handling and size/time controls before adapting it for real transformation. Never log sensitive records.

## Buffering and failure behavior

Buffering is destination-specific. Current S3 hints allow 0–900 seconds, with multipart PUT cost implications below sixty seconds. S3 backup and dynamic partitioning do not support zero buffering. Size and interval are hints, not a universal exact end-to-end latency guarantee.

Direct PUT records are retained up to 24 hours while destination delivery retries. A failing S3 target does not universally switch to a separate backup bucket, nor does absence of such a bucket imply instant loss. Read destination-specific error and retry behavior; retain a replayable upstream source where recovery objectives require it.

## Delivery exercise

Create a small budgeted sandbox stream targeting a private disposable S3 prefix, with a role scoped to its data/KMS operations. Send labelled event IDs, inspect delivered bytes, and compare producer totals with output. Inject an invalid record into a tested transform and verify the configured error path.

Temporarily deny only the sandbox destination role and observe delivery-failure metrics/retry behavior; restore permission before the retention window is exhausted. Test duplicate effects and chosen buffering latency. Delete delivery resources, transforms and disposable S3 outputs separately.

## Destination anatomy and trade-offs

```text
Direct PUT or supported source
  → destination-specific buffer
  → optional Lambda transform / supported format conversion
  → destination delivery
  → configured failed-record/backup path where supported
```

| Destination      | What to verify                                                                                                  |
| ---------------- | --------------------------------------------------------------------------------------------------------------- |
| S3               | Private bucket role, prefix, encryption, buffering and failed-record output settings.                           |
| Redshift         | S3 staging plus COPY permissions/connectivity/schema; staged objects alone are not warehouse ingestion success. |
| OpenSearch       | Supported domain/collection destination, index configuration and rejected-document handling.                    |
| Splunk           | Supported HEC endpoint/token, acknowledgement/retry behavior and backup configuration.                          |
| HTTP destination | Supported endpoint protocol and response contract; arbitrary POST acceptance is insufficient.                   |

Native serialization conversion is separate from compression. Parquet/ORC conversion needs a compatible JSON/schema configuration; Parquet is not a compression enum. Configure your destination using the actual ExtendedS3DestinationConfiguration or relevant supported API structure rather than a generic Destination/S3Configuration pseudo-request.

## Correct JSON enrichment transform

This complete handler demonstrates adding an ingest timestamp to a JSON object. It preserves recordId, handles invalid/nonobject JSON explicitly and returns base64 text. It is an example to test against your size/latency requirements, not a deployed production transform.

```python
import base64
import datetime
import json

def lambda_handler(event, context):
    output = []
    for record in event["records"]:
        try:
            value = json.loads(base64.b64decode(record["data"], validate=True))
            if not isinstance(value, dict):
                raise ValueError("Expected a JSON object")
            value["ingested_at"] = datetime.datetime.now(
                datetime.timezone.utc
            ).isoformat()
            encoded = base64.b64encode(
                (json.dumps(value) + "\n").encode("utf-8")
            ).decode("ascii")
            output.append({
                "recordId": record["recordId"],
                "result": "Ok",
                "data": encoded,
            })
        except (ValueError, TypeError, UnicodeDecodeError):
            output.append({
                "recordId": record["recordId"],
                "result": "ProcessingFailed",
                "data": record["data"],
            })
    return {"records": output}
```

Test good, malformed and oversized input before enabling the transform; account for response-size and retry constraints. ProcessingFailed is not an automatic assurance that a separate bucket receives every error.

Buffer thresholds are hints, with delivery time also depending on transformation, destination response and retries. Dynamic partitioning creates per-partition buffering/limits and can produce small-object/request overhead. Monitor incoming records/bytes, transform failures, destination success/freshness and errors. If freshness approaches source retention, treat it as a recovery incident rather than waiting indefinitely.

## Cost and references

Model ingested rounded units plus optional format conversion, dynamic partitioning, VPC/destination/Lambda and S3 request/storage charges. Direct PUT/Kinesis ingestion rounds records to 5 KB; MSK/vended-log sources differ. There is no documented universal \$0.04/million control-plane API tariff.

- [Rename notice](https://aws.amazon.com/about-aws/whats-new/2024/02/amazon-data-firehose-formerly-kinesis-data-firehose/)
- [Transformation response contract](https://docs.aws.amazon.com/firehose/latest/dev/data-transformation-status-model.html)
- [Format conversion](https://docs.aws.amazon.com/firehose/latest/dev/record-format-conversion.html)
- [Buffer ranges and exceptions](https://docs.aws.amazon.com/firehose/latest/dev/create-configure-backup.html)
- [Delivery behavior](https://docs.aws.amazon.com/firehose/latest/dev/basic-deliver.html)
- [Firehose pricing](https://aws.amazon.com/firehose/pricing/)
