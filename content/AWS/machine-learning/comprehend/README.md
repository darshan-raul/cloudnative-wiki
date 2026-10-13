---
title: "Amazon Comprehend"
description: "Comprehend analyzes supported language text using managed entity, sentiment, key-phrase, language and PII operations, plus supported custom models."
tags:
  - aws/machine-learning
date: 2026-10-12
---

# Amazon Comprehend

Comprehend analyzes supported language text using managed entity, sentiment, key-phrase, language and PII operations, plus supported custom models. Prerequisites: [[AWS/machine-learning/README|evaluation/privacy]], [[AWS/security/iam/README|IAM]] and [[AWS/storage/s3/README|S3]] for asynchronous/custom workflows.

## Operation and result contracts

Select an operation whose language/input limits fit your task; synchronous, batch and asynchronous calls have different schemas/quotas. PII entities contain offsets rather than a Text field. Reconstruct a span from the original input while respecting the documented offset semantics; never log detected sensitive values casually.

```python
import boto3

comprehend = boto3.client("comprehend")

# 1. Synchronous sentiment analysis
sentiment_text = "The migration finished ahead of schedule and under budget."
sentiment_res = comprehend.detect_sentiment(Text=sentiment_text, LanguageCode="en")
# Returns Sentiment ('POSITIVE', 'NEGATIVE', 'NEUTRAL', 'MIXED') and SentimentScore
assert sentiment_res["Sentiment"] in {"POSITIVE", "NEGATIVE", "NEUTRAL", "MIXED"}
print("Sentiment:", sentiment_res["Sentiment"])

# 2. Synchronous named entity detection
entity_text = "Amazon Web Services launched new EC2 instances in Seattle."
entity_res = comprehend.detect_entities(Text=entity_text, LanguageCode="en")
# Returns Entities with Type (ORGANIZATION, LOCATION, etc.), BeginOffset, EndOffset, Score
for entity in entity_res["Entities"]:
    span = entity_text[entity["BeginOffset"]:entity["EndOffset"]]
    print(f"Entity: {span} | Type: {entity['Type']} | Score: {entity['Score']:.2f}")

# 3. PII entity detection
pii_text = "Contact Alex at alex@example.com."
pii_res = comprehend.detect_pii_entities(Text=pii_text, LanguageCode="en")
for entity in pii_res["Entities"]:
    print(f"PII Type: {entity['Type']} | Span: [{entity['BeginOffset']}:{entity['EndOffset']}]")
```

These synchronous SDK calls use synthetic inputs, configured credentials/Region and billable operation units (minimum 300 characters billed per call). They display structured classifications, offsets, and scores rather than logging sensitive substrings directly.

## Custom classification and endpoints

Custom classifiers require at least two classes, not five. Multi-class and multi-label tasks have distinct maximums/training-document quotas. Prepare representative labelled data, validate labels and split held-out examples without leakage.

Real-time custom classification requires a deployed endpoint with the supported model/role/capacity. Poll training and endpoint provisioning with exponential backoff, deadlines and explicit terminal-failure handling; infinite while loops are not a deployment runbook. Batch jobs and endpoint requests have different setup/cost.

Comprehend Medical adds medically specialized analysis; general Comprehend is also HIPAA-eligible. A BAA, eligible feature/Region, access controls, retention and shared-responsibility configuration remain necessary.

## Analysis exercise

Use synthetic text with known PII spans and sentiment ambiguity. Record true/false positives and offsets, test an unauthorized identity and verify failed/unsupported input handling. For a custom classifier, compare with a simple baseline and report class-specific precision/recall, not merely training completion.

Delete sandbox custom endpoints immediately after evaluation if no longer needed; hosted capacity can cost money while idle. Remove jobs/artifacts/input-output data according to privacy/retention policy. Do not deploy endpoints merely to confirm a note's syntax.

## Cost arithmetic

Standard operation pricing uses 100-character units and a 300-character request minimum, with operation/Region/tier qualifications. At an illustrative \$0.0001/unit, a single 50,000-character request is 500 units × \$0.0001 = \$0.05, not \$5. Minimums apply per request, so splitting the input can change billed units. Custom model training/hosting is separate.

## Language-analysis operations and result handling

| Operation family               | Useful output               | Validation                                           |
| ------------------------------ | --------------------------- | ---------------------------------------------------- |
| Dominant language              | Supported language scores   | Ambiguous/short/mixed-language input                 |
| Entities/key phrases           | Types, spans and confidence | Domain vocabulary and false positives                |
| Sentiment                      | Supported classes/scores    | Sarcasm, negation and subgroup behavior              |
| PII detection                  | Entity offsets/types/scores | False negatives and redaction policy                 |
| Custom classification/entities | Task-specific labels/spans  | Training coverage, endpoints and held-out evaluation |

A score is model evidence, not a calibrated legal/compliance assurance. Input-language/size limits vary by operation. Offset-based responses should be mapped to the original text; transformations before slicing can shift spans. Do not emit sensitive spans in ordinary debugging logs.

## Custom classifier and endpoint lifecycle

```text
labelled representative data
  → supported training configuration
  → training status/artifact
  → held-out quality gate
  → batch job or eligible real-time endpoint
  → request evaluation
  → stop/delete hosted capacity and retained artifacts deliberately
```

Choose multi-class or multi-label from task semantics. At least two classes are required, while maximum classes/documents and model types have specific quotas. Validate that rare categories appear in train/evaluation splits and establish a baseline that does not exploit leakage.

A real-time custom request needs a provisioned endpoint ARN and supported model/input. Capture created identifiers, poll with exponential backoff/deadline and stop on terminal failure rather than sleep forever. IAM role/data access and active hosting charges are part of the workflow.

## Pricing comparison and privacy operations

Per-request minimum billing changes a split-input scenario. At an illustrative \$0.0001 per 100-character unit with 300-character minimum, one 200-character request bills three units. Ten such requests bill thirty units; combining them into one eligible 2,000-character request bills twenty units for that operation. This is arithmetic, not a current Region quote or a recommendation to ignore operation-size limits.

Record operation, character count, rounding/minimum, tier and elapsed custom-hosting/training usage. Medical-specific features have distinct pricing/input/schema. General Comprehend's HIPAA eligibility still requires the BAA and appropriate configuration; PII detection alone does not prove a dataset is deidentified. Keep input/output retention, encryption and access control explicit.

## References

- [PII response contract](https://docs.aws.amazon.com/boto3/latest/reference/services/comprehend/client/detect_pii_entities.html)
- [Custom model and endpoint limits](https://docs.aws.amazon.com/comprehend/latest/dg/guidelines-and-limits.html)
- [Real-time endpoints](https://docs.aws.amazon.com/comprehend/latest/dg/manage-endpoints.html)
- [HIPAA eligible services](https://aws.amazon.com/compliance/hipaa-eligible-services-reference/)
- [Comprehend pricing](https://aws.amazon.com/comprehend/pricing/)
