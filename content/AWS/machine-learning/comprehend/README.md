---
title: Amazon Comprehend
description: Amazon Comprehend — natural language processing. Sentiment analysis, entity recognition, PII detection, topic modeling, language detection, and Comprehend Medical for PHI.
tags:
  - aws
  - machine-learning
  - comprehend
  - nlp
  - ai-services
---

# Amazon Comprehend

Comprehend provides NLP APIs for text analysis — sentiment, entities, key phrases, topics, language detection, and toxic content. For medical text, use Comprehend Medical (HIPAA-eligible).

## Language Support

| Language | Sentiment | Entities | Key Phrases | Syntax |
|----------|-----------|----------|-------------|--------|
| English | Yes | Yes | Yes | Yes |
| Spanish | Yes | Yes | Yes | Yes |
| German | Yes | Yes | Yes | No |
| French | Yes | Yes | Yes | No |
| Italian | Yes | Yes | Yes | No |
| Portuguese | Yes | Yes | Yes | No |
| Chinese (Simplified) | Yes | Yes | Yes | No |
| Japanese | Yes | Yes | Yes | No |
| Korean | Yes | Yes | Yes | No |

## Core Operations

### Detect Sentiment

```python
import boto3

comprehend = boto3.client('comprehend')

response = comprehend.detect_sentiment(
    Text="I absolutely love this product! Best purchase I've ever made.",
    LanguageCode='en'
)

print(f"Sentiment: {response['Sentiment']}")  # POSITIVE
print(f"Scores: {response['SentimentScore']}")
# {'Positive': 0.9997, 'Negative': 0.0001, 'Neutral': 0.0001, 'Mixed': 0.0001}
```

### Detect Entities

```python
response = comprehend.detect_entities(
    Text="Amazon opened its new headquarters in Seattle, Washington. CEO Andy Jassi announced the expansion.",
    LanguageCode='en'
)

for entity in response['Entities']:
    print(f"{entity['Type']}: '{entity['Text']}' (Score: {entity['Score']:.2f})")
# ORGANIZATION: 'Amazon' (Score: 0.99)
# LOCATION: 'Seattle, Washington' (Score: 0.95)
# PERSON: 'Andy Jassi' (Score: 0.87)
```

### Detect PII (Personally Identifiable Information)

```python
response = comprehend.detect_pii_entities(
    Text="Customer John Smith, SSN 123-45-6789, email john@example.com, phone 555-123-4567",
    LanguageCode='en'
)

for pii in response['Entities']:
    print(f"{pii['Type']}: '{pii['Text']}' (Score: {pii['Score']:.2f})")
# NAME: 'John Smith' (Score: 0.99)
# SSN: '123-45-6789' (Score: 0.99)
# EMAIL: 'john@example.com' (Score: 0.99)
# PHONE: '555-123-4567' (Score: 0.99)
```

### Detect Key Phrases

```python
response = comprehend.detect_key_phrases(
    Text="Amazon Web Services provides cloud computing solutions to businesses worldwide.",
    LanguageCode='en'
)

for phrase in response['KeyPhrases']:
    print(f"'{phrase['Text']}' (Score: {phrase['Score']:.2f})")
# 'Amazon Web Services' (Score: 0.99)
# 'cloud computing solutions' (Score: 0.98)
# 'businesses' (Score: 0.95)
```

### Detect Language

```python
response = comprehend.detect_dominant_language(Text="Bonjour, comment allez-vous?")

for lang in response['Languages']:
    print(f"{lang['LanguageCode']}: {lang['Score']:.2f}")
# fr: 0.99
```

### Detect Syntax (Parts of Speech)

```python
response = comprehend.detect_syntax(
    Text="AWS provides reliable cloud services.",
    LanguageCode='en'
)

for token in response['SyntaxTokens']:
    print(f"{token['Word']} ({token['PartOfSpeech']['Tag']}, {token['PartOfSpeech']['Score']:.2f})")
# AWS (PROPN, 0.99) — proper noun
# provides (VERB, 0.97)
# reliable (ADJ, 0.95)
# cloud (NOUN, 0.99)
# services (NOUN, 0.98)
# . (PUNCT, 0.99)
```

## Topic Modeling

Discover topics in a collection of documents:

```python
# Start topic detection job (processes documents in S3)
response = comprehend.start_topics_detection_job(
    InputDataConfig={
        'S3Uri': 's3://my-bucket/documents/',
        'InputFormat': 'ONE_DOC_PER_LINE'
    },
    OutputDataConfig={'S3Uri': 's3://my-bucket/topics-output/'},
    DataAccessRoleArn='arn:aws:iam::123456789012:role/comprehend-role',
    NumberOfTopics=10
)

job_id = response['JobId']
```

### Get Topic Results

```python
# Get results
result = comprehend.describe_topics_detection_job(JobId=job_id)

# Topics output contains:
# - topic-words.json: Words associated with each topic
# - doc-topics.json: Documents and their topic weights
```

## Custom Classification

Train a custom classifier for domain-specific categories:

```python
# Create classifier
response = comprehend.create_document_classifier(
    InputDataConfig={'S3Uri': 's3://my-bucket/training-data/'},
    DataAccessRoleArn='arn:aws:iam::123456789012:role/comprehend-role',
    LanguageCode='en',
    ClassifierName='support-ticket-classifier',
    VersionName='v1',
    Tags=[{'Key': 'Environment', 'Value': 'production'}]
)

classifier_arn = response['DocumentClassifierArn']

# Wait for training
import time
while True:
    status = comprehend.describe_document_classifier(ClassifierArn=classifier_arn)
    if status['DocumentClassifierProperties']['Status'] == 'TRAINED':
        break
    time.sleep(60)

# Use classifier
response = comprehend.classify_document(
    Text="My order hasn't arrived and I need help!",
    DocumentClassifierArn=classifier_arn
)
print(response['Classes'])  # [{'Name': 'Shipping Issues', 'Score': 0.92}]
```

## Comprehend Medical (HIPAA Eligible)

```python
medical = boto3.client('comprehendmedical')

# Detect medical entities
response = medical.detect_entities_v2(
    Text="Patient presents with Type 2 diabetes. Takes Metformin 500mg twice daily. No known allergies."
)

for entity in response['Entities']:
    print(f"{entity['Category']}:{entity['Type']} - '{entity['Text']}'")
# MEDICATION:TREATMENT - 'Metformin 500mg'
# DIAGNOSIS:DX - 'Type 2 diabetes'
# FRACTION:AMOUNT - 'twice daily'
```

### ICD-10 and RxNorm Mapping

```python
response = medical.infer_icd10_cm(
    Text="Patient has pneumonia with cough and fever."
)

for diagnosis in response['Diagnosis']:
    print(f"{diagnosis['Description']} (Code: {diagnosis['ICD10CMCode']})")
# 'Pneumonia, unspecified' (Code: J18.9)
```

### RxNorm (Medication Codes)

```python
response = medical.infer_rx_norm(
    Text="Take Metformin 500mg twice daily with food."
)

for medication in response['Medications']:
    print(f"{medication['Text']} (RxNorm: {medication['RxNormCode']})")
```

## Pricing

| Operation | Cost |
|-----------|------|
| DetectSentiment | $0.0001/character |
| DetectEntities | $0.0001/character |
| DetectPiiEntities | $0.0001/character |
| DetectKeyPhrases | $0.0001/character |
| DetectSyntax | $0.00005/character |
| DetectDominantLanguage | $0.0001/100 characters |
| TopicDetection | $0.50/job + $0.0001/character |
| CustomClassification | $0.0005/character |
| ComprehendMedical (DetectEntities) | $0.00035/character |

## References

- **Homepage:** https://aws.amazon.com/comprehend/
- **Documentation:** https://docs.aws.amazon.com/comprehend/
- **Pricing:** https://aws.amazon.com/comprehend/pricing/

## Nuggets & Gotchas

- **Comprehend Medical is a SEPARATE service from Comprehend — different API, different pricing, different compliance:** Comprehend Medical is HIPAA-eligible and uses medical-specific models. Comprehend (general) is NOT HIPAA-eligible. If you process PHI, use `comprehendmedical` endpoint.
- **Comprehend's entity detection uses predefined categories — it won't recognize your domain-specific entities:** For custom entities (product names, SKUs, internal terminology), use Comprehend Custom Entity Recognition.
- **Comprehend pricing is per CHARACTER — watch out for large documents:** A 10-page PDF (50K characters) × $0.0001 = $5/call. If you're processing millions of documents, costs add up fast. Consider summarizing before sending to Comprehend.
- **Comprehend's topic modeling works on DOCUMENT CORPUS, not individual documents:** You need to provide a collection of documents (S3 prefix) to discover topics. It won't tell you the topic of a single document.
- **Comprehend Custom Classification has a 5-class minimum — you can't train with fewer than 5 classes:** If you need binary classification (spam/not-spam), use one class as "other" or consider a different approach.