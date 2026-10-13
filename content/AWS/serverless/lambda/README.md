---
title: Lambda in serverless architectures
description: Connect the canonical Lambda lesson to API, queue and workflow architectures without duplicating runtime, pricing or quota catalogs.
tags:
  - cloud/aws/serverless
date: 2026-10-12
---

# Lambda in serverless architectures

Start with [[AWS/compute/lambda/README|the canonical Lambda lesson]] for a complete small lab, invocation models, supported-runtime discovery, concurrency, VPC access and checked cost arithmetic.

## Choose the boundary

Use [[AWS/serverless/api-gateway/README|API Gateway]] when clients need an API contract, authentication and access logs. API keys are not authentication. Use [[AWS/application-integration/sqs/README|SQS]] when work can be buffered; define visibility timeout, retries, poison-message handling and idempotency. Use [[AWS/application-integration/step-functions/README|Step Functions]] for explicit multi-step orchestration and compensating actions.

Avoid assuming that Lambda has exactly-once invocation, that provisioned concurrency makes execution free, or that a public VPC subnet fixes internet access. All runtime, quota and tariff details belong to the canonical lesson.

## Architecture exercise

For an image-upload pipeline, identify where the object lives, who authorizes the upload, what event creates the job, how duplicate events are handled, and where failed jobs are retained. Distinguish accepted, processing and completed states in the client-facing API. Define how operators replay failures without repeating successful effects.

Measure end-to-end latency rather than only function duration. Include queue age, retries, dependency timeouts and log/transfer/storage charges.

## Runtime, packaging and handler architecture

Use the canonical [[AWS/compute/lambda/README|compute Lambda lab]] for creation, current supported-runtime discovery and cost. This architecture view adds event adapters, rollout and operational configuration rather than duplicating a stale version catalog.

| Package                  | Ownership                                               | Upgrade constraint                                                   |
| ------------------------ | ------------------------------------------------------- | -------------------------------------------------------------------- |
| Zip with managed runtime | Application/dependencies plus supported runtime updates | Track deprecation/create/update rules and dependency compatibility   |
| OS-only/custom runtime   | Runtime bootstrap and application                       | You own language/runtime patching                                    |
| Container image          | Runtime/image/application dependencies                  | Rebuild/scan/redeploy immutable reviewed image                       |
| Layer version            | Shared supported archive dependencies                   | Immutable version; functions do not automatically adopt new versions |

For a JavaScript direct-invoke synthetic fixture, this is a complete handler with no undefined helper or full-event logging:

```javascript
exports.handler = async (event) => {
  const name = event.name ?? "learner";
  if (typeof name !== "string") {
    throw new Error("name must be a string");
  }
  return {
    statusCode: 200,
    body: JSON.stringify({ message: `Hello, ${name}` }),
  };
};
```

Direct event objects, API Gateway payloads and queue/stream/S3 envelopes are different contracts. A response with statusCode has meaning only to a compatible caller/integration; it does not acknowledge every queue record automatically.

## Source-specific event walkthroughs

```text
API request → synchronous invoke → caller sees result/error
S3 event → asynchronous invoke → retry/destination/recursive-event risk
DynamoDB/Kinesis → polled stream batch → checkpoint/retry/order constraints
SQS → polled queue batch → visibility/redrive + partial failures
```

This complete S3 metadata adapter decodes URL-encoded keys and performs no object access or confidential payload logging:

```python
from urllib.parse import unquote_plus

def handler(event, context):
    objects = []
    for record in event.get("Records", []):
        if record.get("eventSource") != "aws:s3":
            raise ValueError("expected S3 event")
        objects.append({
            "bucket": record["s3"]["bucket"]["name"],
            "key": unquote_plus(record["s3"]["object"]["key"]),
        })
    return {"objects": objects}
```

The exercise's object names are nonsensitive. Production processing requires scoped S3/KMS access, idempotency using the applicable event/object version identity and no source→output-prefix notification loop.

For DynamoDB streams, select the desired stream view and handle INSERT/MODIFY/REMOVE; OldImage/NewImage presence depends on that view. AttributeValue structures are not plain application JSON and numeric/binary conversion needs explicit serialization choices. Test deletes and retries, not only inserts.

For SQS use [[AWS/application-integration/sqs/README|the complete partial-batch handler]], enable ReportBatchItemFailures and preserve FIFO order. A returned processed count does not enable partial failures.

## Versions, aliases and canary workflow

```text
$LATEST = mutable unpublished draft
publish → version 1 (immutable snapshot)
publish changed draft → version 2 (immutable snapshot)
lab alias → version 1; reviewed canary → weighted version 2
```

Prerequisites: the sandbox function, verified profile/Region, two distinct tested published versions and narrow version/alias permissions.

```bash
aws lambda publish-version --function-name wiki-lambda-lab
aws lambda create-alias --function-name wiki-lambda-lab \
  --name lab --function-version VERSION_1
aws lambda invoke --function-name wiki-lambda-lab --qualifier lab \
  --cli-binary-format raw-in-base64-out --payload '{"name":"alias-test"}' alias-response.json
aws lambda update-alias --function-name wiki-lambda-lab --name lab \
  --function-version VERSION_2
```

Substitute returned numeric versions. PublishVersion requires applicable code/configuration changes; repeatedly publishing unchanged code is not a reliable way to create a new revision. Updating an alias does not modify version 1 or create a link back to $LATEST.

For weighted rollout, use the documented AdditionalVersionWeights form and supported same-role/configuration requirements. Measure per-executed-version errors/latency and business outcomes; random sampling is not exactly ten percent for a tiny fixture. Roll back the alias/weights after a failed acceptance signal, then inspect in-flight/queued effects separately.

## Layers, environment and networking operations

Build a Python layer ZIP with its required python/ directory and compatible runtime/architecture packages. Publish using --zip-file, not an arbitrary binary --content value:

```bash
aws lambda publish-layer-version --layer-name wiki-lab-layer \
  --zip-file fileb://layer.zip --compatible-runtimes SUPPORTED_PYTHON_RUNTIME
aws lambda update-function-configuration --function-name wiki-lambda-lab \
  --layers LAYER_VERSION_ARN
```

The layers list replaces the function's configuration; preserve intended existing layers. Images do not consume Lambda layers through this same workflow. Library/native architecture compatibility needs a real import test.

Environment Variables is a complete map update, not an automatic merge. Keep secrets in supported secret retrieval workflows and do not put credentials in a public JSON example. Key configuration adds authorization/ownership constraints; encryption at rest does not make every runtime process unable to read its environment.

VPC configuration uses actual subnet/SG arrays and Hyperplane networking. A public subnet supplies no public function IP; private database traffic does not universally traverse NAT. Test DNS/routes/SGs/endpoints and egress requirements before applying a latency workaround.

## Concurrency, telemetry and teardown

Reserved concurrency caps/isolates function capacity; setting it to zero stops invocation capacity and can create retry/backlog. Provisioned concurrency applies to a supported published qualifier, has configuration/provisioning state and independent idle-capacity charges. Neither gives unlimited downstream database capacity.

Monitor errors/throttles/duration/init, concurrent executions and source-specific iterator age/queue age/destination failures. On a deployment incident correlate executed version, request ID and dependency error; avoid logging whole events with secrets/customer data.

Remove lab mappings/source notifications, provisioned-concurrency configs and aliases before deleting dedicated versions/layers/functions where dependencies require. Preserve durable idempotency/failure evidence, delete only dedicated logs/roles and confirm recurring publication/resources stop.

References: [event-source mappings](https://docs.aws.amazon.com/lambda/latest/dg/invocation-eventsourcemapping.html), [S3 events](https://docs.aws.amazon.com/lambda/latest/dg/with-s3.html), [versions](https://docs.aws.amazon.com/lambda/latest/dg/configuration-versions.html), [weighted aliases](https://docs.aws.amazon.com/lambda/latest/dg/configuring-alias-routing.html), [layers](https://docs.aws.amazon.com/lambda/latest/dg/configuration-layers.html), [environment updates](https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars.html).

## Across the wiki

- [[GCP/compute/cloud-functions/README|GCP Cloud Functions (2nd Gen) & Eventarc]] — functions (GCP)
- [[Architecture/solution-architecture-concepts/api-design/stateful-vs-stateless|Stateful vs Stateless]] — functions (Architecture)

## References

- [Lambda invocation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-invocation.html).
- [SQS failure handling](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-errorhandling.html).
- [Lambda pricing](https://aws.amazon.com/lambda/pricing/).
