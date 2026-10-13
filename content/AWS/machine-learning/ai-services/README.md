---
title: "AWS AI services"
description: "Managed AI APIs handle supported tasks without your own model-training pipeline."
tags:
  - aws/machine-learning
date: 2026-10-12
---

# AWS AI services

Managed AI APIs handle supported tasks without your own model-training pipeline. They still need input-contract checks, authorization, evaluation, bounded asynchronous workflows and privacy controls. Prerequisites: [[AWS/machine-learning/README|ML evaluation]], [[AWS/security/iam/README|IAM]] and [[AWS/storage/s3/README|S3]].

## Service and API boundaries

| Service                                                  | Task and contract                                                                                                                    |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| [[AWS/machine-learning/comprehend/README\|Comprehend]]   | Language/entities/sentiment/PII and supported custom models; PII results provide offsets.                                            |
| [[AWS/machine-learning/rekognition/README\|Rekognition]] | Supported image/video analysis and Custom Labels; asynchronous video has JobStatus/pagination.                                       |
| Textract                                                 | AnalyzeDocument with TABLES/FORMS and Blocks/Relationships; async StartDocumentAnalysis/GetDocumentAnalysis for supported documents. |
| Transcribe                                               | Batch jobs or streaming audio over supported SDK/HTTP2/WebSocket transports; supported custom vocabulary/language-model choices.     |
| Translate                                                | TranslateText for synchronous text, or StartTextTranslationJob with separate batch contract.                                         |
| Polly                                                    | Supported text-to-speech voices/engines/output formats; evaluate pronunciation and supported language/Region.                        |
| Amazon Lex V2                                            | Conversational AI bots with intents, slots, multi-language support, and runtime session management (distinct from retired Lex V1).   |
| Amazon Kendra                                            | Enterprise natural-language search with document indexers, connectors, and ML ranking; billed by index hours and query capacity.     |

Textract has no get_table_document operation. Reconstruct tables from Blocks and Relationships rather than guessing a ready-made table JSON field. Async workflows must handle terminal failures, pagination and timeouts.

Transcribe streaming is not an ordinary Boto3 batch-client operation. Custom language models are supported for selected languages/modes, not only vocabulary lists. Current standard batch/streaming pricing is per second with no minimum; Call Analytics add-ons have different minimums.

Translate batch uses plural TargetLanguageCodes, input/output configuration, a data-access role and ClientToken for idempotency. Do not copy TranslateText's singular target shape into the batch API.

## Synchronous AI task examples

### Synchronous text translation

TranslateText provides immediate translation for short texts (up to 10,000 bytes per request) without asynchronous S3 batch setup:

```python
import boto3

translate = boto3.client("translate")
result = translate.translate_text(
    Text="Hello, world!",
    SourceLanguageCode="en",
    TargetLanguageCode="es",
)
assert result["TranslatedText"] == "¡Hola, mundo!"
print("Source en:", "Hello, world!")
print("Target es:", result["TranslatedText"])
```

### Text-to-speech synthesis with Polly

SynthesizeSpeech streams audio data synchronously via the `AudioStream` response body:

```python
import boto3

polly = boto3.client("polly")
response = polly.synthesize_speech(
    Text="Hello from Amazon Polly.",
    OutputFormat="mp3",
    VoiceId="Joanna",
    Engine="neural",
)
audio_bytes = response["AudioStream"].read()
assert len(audio_bytes) > 0, "Audio stream must contain synthesized bytes"
print(f"Synthesized audio: {len(audio_bytes)} bytes, content-type: {response['ContentType']}")
```

### Document text detection with Textract

DetectDocumentText extracts printed or handwritten lines and words from non-sensitive document bytes:

```python
import boto3

textract = boto3.client("textract")
# Document bytes or S3 object:
# response = textract.detect_document_text(Document={"Bytes": image_bytes})
# Blocks include PAGE, LINE, and WORD hierarchies with geometry and confidence:
sample_blocks = [
    {"BlockType": "PAGE", "Id": "b-1"},
    {"BlockType": "LINE", "Id": "b-2", "Text": "Invoice #1042", "Confidence": 99.4},
    {"BlockType": "LINE", "Id": "b-3", "Text": "Total: $150.00", "Confidence": 98.8},
]
lines = [b["Text"] for b in sample_blocks if b["BlockType"] == "LINE"]
assert lines == ["Invoice #1042", "Total: $150.00"]
print("Extracted lines:", lines)
```

## Safe contract/evaluation exercise

Use a tiny synthetic document/audio/text sample and one owning SDK example for the chosen operation. Record language, file format/size, API and result schema. Verify extracted text/labels against a known answer and inspect confidence/errors rather than trusting successful HTTP status.

For async jobs, poll with backoff, a deadline and failure handling; page all results. Try an unsupported format and unauthorized identity to demonstrate visible failures. Do not print sensitive input/output into logs. Delete sandbox jobs/artifacts/output objects and any chargeable resources created for the test.

Comprehend is HIPAA-eligible, but eligibility alone does not establish compliance: use the BAA, supported configuration and shared-responsibility controls. Medical is a distinct specialist service.

## Document, speech and translation workflows

```text
Document: private S3 → Textract start/analyze → Blocks/Relationships → validated rows
Speech: supported audio → batch/stream Transcribe → transcript → human/domain checks
Translation: text or supported batch input → Translate → quality/terminology checks
Synthesis: supported text/SSML → Polly → audio + pronunciation validation
```

For Textract tables, follow block IDs/relationships from TABLE to CELL/MERGED_CELL and child text as supported. Page/row/column reconstruction, confidence and missing fields require explicit validation. Asynchronous documents need supported job notification/status/pagination, not an invented get_table_document method.

Transcribe batch jobs reference an authorized media object and supported language/settings; streaming sends audio through a supported transport and reads incremental results. Partial and final transcript results have different stability; don't publish partial text as a permanently reconciled record. Custom vocabulary and eligible language models address different domain problems.

## Correct batch translation contract

This example submits a chargeable asynchronous text-translation job. It requires actual supported input files, private output prefix and a role authorized for both locations; it does not upload input or wait for completion.

```python
import uuid
import boto3

client = boto3.client("translate")
response = client.start_text_translation_job(
    JobName="sandbox-translation",
    InputDataConfig={
        "S3Uri": "s3://example-unique-bucket/sandbox/translate-input/",
        "ContentType": "text/plain",
    },
    OutputDataConfig={
        "S3Uri": "s3://example-unique-bucket/sandbox/translate-output/",
    },
    DataAccessRoleArn="arn:aws:iam::123456789012:role/SandboxTranslateRole",
    SourceLanguageCode="en",
    TargetLanguageCodes=["fr"],
    ClientToken=str(uuid.uuid4()),
)
print(response["JobId"])
```

Persist/reuse ClientToken for a retry of the same submission instead of generating a new token for every retry. Poll the job with a deadline and inspect failures/output before cleanup. This plural-target batch schema is different from TranslateText.

## Comparison and quality controls

| Input/output              | Common failure                            | Evidence to retain                                |
| ------------------------- | ----------------------------------------- | ------------------------------------------------- |
| Scanned table             | Low-quality scan/merged cells/type errors | Expected rows/columns and extraction exceptions   |
| Speech                    | Domain terms, accents/background noise    | Representative error cases and correction process |
| Translation               | Context/terminology ambiguity             | Bilingual review and terminology version          |
| Generated speech          | Pronunciation/prosody/language support    | Chosen voice/engine and listening evaluation      |
| Language/vision inference | False positives/negatives                 | Held-out labels and selected threshold            |

Each service has its own synchronous/asynchronous/streaming contracts and quotas. Costs meter pages, characters, audio seconds, images or capacity according to operation; do not force all services into one per-request table. Keep PHI/privacy/retention and permission handling explicit across integrations.

## Cost and references

Comprehend standard operations use 100-character units with a 300-character request minimum; operation/Region/tier differ. Other services meter pages, seconds, characters, images or hosted capacity according to the operation. Do not multiply a displayed per-minute rate as though it were a fifteen-second tariff.

- [Textract AnalyzeDocument](https://docs.aws.amazon.com/boto3/latest/reference/services/textract/client/analyze_document.html)
- [Transcribe streaming](https://docs.aws.amazon.com/transcribe/latest/dg/streaming.html)
- [Transcribe pricing](https://aws.amazon.com/transcribe/pricing/)
- [Translate batch contract](https://docs.aws.amazon.com/boto3/latest/reference/services/translate/client/start_text_translation_job.html)
- [HIPAA eligible services](https://aws.amazon.com/compliance/hipaa-eligible-services-reference/)
- [Comprehend pricing](https://aws.amazon.com/comprehend/pricing/)

## Across the wiki

- [[AI/aws/bedrock|Amazon Bedrock Architecture & Implementation]] — generative AI platforms (AI)
- [[AI/rag|Retrieval-Augmented Generation (RAG) Architecture]] — generative AI platforms (AI)
- [[AI/aws/sagemaker/README|Sagemaker]] — generative AI platforms (AI)
- [[AI/aws/services|Services]] — generative AI platforms (AI)
