---
title: AWS AI Services
description: AWS AI services — Rekognition (vision), Comprehend (NLP), Polly (speech), Translate, Transcribe, Textract (documents), Lex (chatbots), Kendra (search), and Contact Lens. Pre-trained APIs, no ML expertise needed.
tags:
  - aws
  - machine-learning
  - ai
  - ai-services
  - rekognition
  - comprehend
  - polly
  - translate
  - transcribe
  - textract
  - lex
  - kendra
---

# AWS AI Services (Pre-trained APIs)

AI Services provide pre-trained ML models via simple APIs. No ML expertise, no training data, no model deployment — just call an API and get a result. Pay per use.

## Quick Comparison

| Service | What it Does | Input | Output |
|---------|-------------|-------|--------|
| Rekognition | Image/video analysis | Image bytes or S3 | Labels, faces, text, celebrities |
| Comprehend | NLP text analysis | Text or S3 | Sentiment, entities, PII, topics |
| Polly | Text-to-speech | Text | MP3/PCM audio |
| Translate | Neural machine translation | Text or S3 | Translated text |
| Transcribe | Speech-to-text | Audio or S3 | Transcripts |
| Textract | Document extraction | Image/PDF or S3 | Text, tables, forms |
| Lex | Chatbots | Text or voice | Intent/slot parsing |
| Kendra | Enterprise search | Questions | Ranked answers |
| Contact Lens | Contact center analytics | Audio/text | Sentiment, categories |

## Rekognition (Vision)

### Image Analysis

```python
import boto3

rekognition = boto3.client('rekognition')

# Detect objects and scenes
response = rekognition.detect_labels(
    Image={'S3Object': {'Bucket': 'my-bucket', 'Name': 'photo.jpg'}},
    MaxLabels=10
)

for label in response['Labels']:
    print(f"{label['Name']} ({label['Confidence']:.1f}%)")
```

### Face Comparison

```python
# Compare faces
response = rekognition.compare_faces(
    SourceImage={'S3Object': {'Bucket': 'my-bucket', 'Name': 'id-card.jpg'}},
    TargetImage={'S3Object': {'Bucket': 'my-bucket', 'Name': 'selfie.jpg'}},
    SimilarityThreshold=80
)

for match in response['FaceMatches']:
    print(f"Match: {match['Similarity']:.1f}%")
```

### Video Analysis

```python
# Start video analysis
response = rekognition.start_label_detection(
    Video={'S3Object': {'Bucket': 'my-bucket', 'Name': 'video.mp4'}},
    MinConfidence=80,
    NotificationChannel={'SNSTopicArn': 'arn:aws:sns:us-east-1:...', 'RoleArn': 'arn:aws:iam::...'}
)
```

## Comprehend (NLP)

### Sentiment Analysis

```python
comprehend = boto3.client('comprehend')

# Detect sentiment
response = comprehend.detect_sentiment(
    Text="I absolutely love this product! Best purchase ever.",
    LanguageCode='en'
)
print(response['Sentiment'])  # POSITIVE
print(response['SentimentScore'])  # {POSITIVE: 0.99, ...}
```

### Entity Detection

```python
# Detect entities (people, places, organizations)
response = comprehend.detect_entities(
    Text="Amazon opened its new office in Seattle last week. CEO Andy Jassi announced.",
    LanguageCode='en'
)

for entity in response['Entities']:
    print(f"{entity['Type']}: {entity['Text']} (Score: {entity['Score']:.2f})")
```

### PII Detection

```python
# Detect personally identifiable information
response = comprehend.detect_pii_entities(
    Text="Customer John Smith, SSN 123-45-6789, email john@example.com",
    LanguageCode='en'
)

for pii in response['Entities']:
    print(f"{pii['Type']}: {pii['Score']:.2f}")
```

### Medical Comprehend (HIPAA Eligible)

```python
medical = boto3.client('comprehendmedical')

# Detect medical entities
response = medical.detect_entities_v2(
    Text="Patient has Type 2 diabetes. Takes 500mg Metformin twice daily."
)

for entity in response['Entities']:
    print(f"{entity['Category']}: {entity['Text']} ({entity['Type']})")
```

## Polly (Text-to-Speech)

```python
polly = boto3.client('polly')

# Synthesize speech
response = polly.synthesize_speech(
    Text="Hello! Welcome to AWS machine learning services.",
    OutputFormat='mp3',
    VoiceId='Joanna'  # Neural voice
)

# Save to file
with open('welcome.mp3', 'wb') as f:
    f.write(response['AudioStream'].read())
```

### Speech Synthesis Marks (SSML)

```python
response = polly.synthesize_speech(
    Text='<speak><prosody rate="slow">This is slow.</prosody> <break strength="strong"/> <prosody rate="fast">This is fast.</prosody></speak>',
    OutputFormat='mp3',
    VoiceId='Joanna',
    TextType='ssml'
)
```

## Translate

```python
translate = boto3.client('translate')

# Translate text
response = translate.translate_text(
    Text="Hello, how are you?",
    SourceLanguageCode='en',
    TargetLanguageCode='es'
)
print(response['TranslatedText'])  # "Hola, ¿cómo estás?"
```

### Batch Translation

```python
# Batch translate documents in S3
response = translate.start_text_translation_job(
    InputDataConfig={'S3Uri': 's3://my-input/batch/', 'ContentType': 'text/plain'},
    OutputDataConfig={'S3Uri': 's3://my-output/batch/'},
    SourceLanguageCode='en',
    TargetLanguageCode='es',
    DataAccessRoleArn='arn:aws:iam::123456789012:role/translate-role'
)
```

## Transcribe (Speech-to-Text)

```python
transcribe = boto3.client('transcribe')

# Start transcription job
transcribe.start_transcription_job(
    TranscriptionJobName='my-podcast',
    Media={'MediaFileUri': 's3://my-bucket/podcast.mp4'},
    MediaFormat='mp4',
    LanguageCode='en-US',
    Settings={
        'ShowSpeakerLabels': True,
        'MaxSpeakerLabels': 10,
        'VocabularyName': 'custom-vocabulary'  # Optional custom words
    }
)

# Get result
response = transcribe.get_transcription_job(TranscriptionJobName='my-podcast')
print(response['TranscriptionJob']['Transcript']['TranscriptFileUri'])
```

### Real-time Transcription

```python
# Start stream transcription (WebSocket)
transcribe.start_stream_transcription(
    LanguageCode='en-US',
    MediaSampleRateHertz=16000,
    MediaEncoding='pcm',
    VocabularyName='custom-vocabulary'
)
```

## Textract (Document Extraction)

### Text and Tables

```python
textract = boto3.client('textract')

# Analyze document
response = textract.analyze_document(
    Document={'S3Object': {'Bucket': 'my-bucket', 'Name': 'invoice.pdf'}},
    FeatureTypes=['TABLES', 'FORMS']
)

# Extract tables
for block in response['Blocks']:
    if block['BlockType'] == 'TABLE':
        table = textract.get_table_document(TableBlockId=block['Id'])
        # Process table data
```

### Expense Receipts

```python
# Analyze expense
response = textract.analyze_expense(
    Document={'S3Object': {'Bucket': 'my-bucket', 'Name': 'receipt.jpg'}}
)

for expense_field in response['ExpenseDocuments'][0]['SummaryFields']:
    print(f"{expense_field['Type']}: {expense_field['ValueDetection']['Text']}")
```

## Lex (Chatbots)

```python
lex = boto3.client('lexv2-runtime')

# Send message
response = lex.recognize_text(
    botId='my-bot-id',
    botAliasId='my-alias',
    localeId='en-US',
    sessionId='user-123',
    text='I want to book a flight'
)

for message in response['messages']:
    print(f"{message['content']}")
```

## Kendra (Enterprise Search)

```python
kendra = boto3.client('kendra')

# Query
response = kendra.query(
    IndexId='my-index-id',
    QueryText='What is our return policy?'
)

for result in response['ResultItems']:
    print(f"{result['ScoreAttributes']['ScoreConfidence']}: {result['DocumentTitle']['Text']}")
    print(f"  {result['DocumentExcerpt']['Text'][:200]}...")
```

## Pricing

| Service | Cost |
|---------|------|
| Rekognition (image) | $0.0012/image (first 1M), cheaper after |
| Rekognition (video) | $0.10/minute |
| Comprehend (sentiment) | $0.0001/character |
| Polly (Neural) | $0.016/1K characters |
| Translate | $0.000015/character |
| Transcribe | $0.024/15 seconds (standard), $0.042/15 seconds (medical) |
| Textract (sync) | $0.0015/page (text), $0.015/page (forms/tables) |
| Lex | $0.004/utterance |
| Kendra | $0.25/1K queries (enterprise edition) |

## References

- **Homepage:** https://aws.amazon.com/ai/services/
- **Documentation:** https://docs.aws.amazon.com/rekognition/, https://docs.aws.amazon.com/comprehend/, etc.
- **Pricing:** https://aws.amazon.com/ai-services/pricing/

## Nuggets & Gotchas

- **AI Services return confidence scores — 99% confidence doesn't mean 100% correct:** Always treat AI Service outputs as probabilistic. For high-stakes decisions, add human review or validation. A 99% confidence face match is still wrong 1% of the time.
- **Rekognition's face comparison is NOT identity verification — it's similarity scoring:** Rekognition tells you two faces are 95% similar. It doesn't tell you WHO the person is. For identity verification, use Amazon Verify or a different approach.
- **Comprehend Medical is a separate service with different pricing — Comprehend (general) is NOT HIPAA eligible:** If you need HIPAA-compliant NLP, use `comprehendmedical` endpoint, not `comprehend`. They're separate APIs with different compliance certifications.
- **Transcribe supports custom vocabularies but not custom models — if your domain vocabulary is niche, build a custom vocabulary:** Custom vocabulary improves accuracy for domain-specific terms (medical, legal, technical). Without it, "Glucoma" gets transcribed as "Glaucoma" incorrectly.
- **AI Services are eventually consistent — for the same input, you might get slightly different outputs over time:** If you need deterministic outputs (for testing or compliance), be aware that AI Service outputs can vary slightly between calls for the same input.