---
title: Amazon Bedrock
description: Amazon Bedrock — foundation models (LLMs) via API. Claude, Llama, Mistral, Stable Diffusion, Titan. RAG, agents, fine-tuning, Guardrails, and multi-region inference.
tags:
  - aws
  - machine-learning
  - bedrock
  - llm
  - generative-ai
  - rag
---

# Amazon Bedrock

Bedrock provides API access to foundation models from Anthropic (Claude), Meta (Llama), Mistral AI (Mistral), Stability AI (Stable Diffusion), Cohere (Command), and AWS (Titan). No training data needed — just call an API.

## Models

### Text Models (LLMs)

| Model | Provider | Context | Strengths |
|-------|----------|---------|-----------|
| Claude 3.5 Sonnet | Anthropic | 200K | Coding, reasoning, long documents |
| Claude 3 Haiku | Anthropic | 200K | Fast, affordable, good reasoning |
| Llama 3.1 70B | Meta | 128K | Open weights, good all-rounder |
| Llama 3.1 8B | Meta | 128K | Fast, local deployment friendly |
| Mistral Large 2 | Mistral | 32K | French/German/Spanish, code |
| Mistral 7B | Mistral | 32K | Open weights, fast |
| Command R+ | Cohere | 128K | RAG, citations, multilingual |
| Titan Text | AWS | 32K | Tight AWS integration |

### Image Models

| Model | Provider | Strengths |
|-------|----------|-----------|
| Stable Diffusion XL 1.0 | Stability AI | Artistic, photorealistic |
| Titan Image Generator | AWS | Fast, AWS integration |

## Using Bedrock (API)

### Python SDK

```python
import boto3
import json

bedrock = boto3.client('bedrock-runtime', region_name='us-east-1')

# Claude 3.5 Sonnet
response = bedrock.invoke_model(
    modelId='anthropic.claude-3-5-sonnet-20241022-2',
    contentType='application/json',
    accept='application/json',
    body=json.dumps({
        'anthropic_version': 'bedrock-2023-05-31',
        'max_tokens': 1024,
        'messages': [
            {'role': 'user', 'content': 'Explain AWS IAM roles in simple terms.'}
        ]
    })
)

result = json.loads(response['body'].read())
print(result['content'][0]['text'])
```

### Llama (Meta)

```python
response = bedrock.invoke_model(
    modelId='meta.llama3-1-70b-instruct-v1:0',
    contentType='application/json',
    accept='application/json',
    body=json.dumps({
        'prompt': 'What is the difference between S3 and EFS?',
        'max_gen_len': 512,
        'temperature': 0.7,
        'top_p': 0.9
    })
)
```

### Stable Diffusion (Image Generation)

```python
import base64

response = bedrock.invoke_model(
    modelId='stability.stable-diffusion-xl-1.0',
    contentType='application/json',
    accept='application/json',
    body=json.dumps({
        'text_prompts': [{'text': 'A futuristic server room with blue lighting, cinematic', 'weight': 1.0}],
        'cfg_scale': 7.5,
        'steps': 30,
        'seed': 42
    })
)

image_data = json.loads(response['body'].read())['artifacts'][0]['base64']
with open('server_room.png', 'wb') as f:
    f.write(base64.b64decode(image_data))
```

## RAG (Retrieval-Augmented Generation)

### Architecture

```
User Question
    │
    ▼
Embedding Model (Titan Embeddings)
    │
    ▼
Vector Store (OpenSearch, Aurora, Pinecone)
    │
    ▼
Relevant Documents Retrieved
    │
    ▼
LLM (Claude) generates answer with context
```

### Implementation

```python
# 1. Generate embedding
bedrock = boto3.client('bedrock-runtime')
embeddings = bedrock.invoke_model(
    modelId='amazon.titan-embed-text-v2:0',
    body=json.dumps({'inputText': 'AWS IAM role example'})
)
embedding = json.loads(embeddings['body'].read())['embedding']

# 2. Search vector store (example with OpenSearch)
opensearch = boto3.client('opensearch')
results = opensearch.search(
    index='documents',
    body={'query': {'knn': {'embedding': {'vector': embedding, 'k': 5}}}}
)

# 3. Build context
context = '\n'.join([hit['_source']['text'] for hit in results['hits']['hits']])

# 4. Generate with context
response = bedrock.invoke_model(
    modelId='anthropic.claude-3-5-sonnet-20241022-2',
    body=json.dumps({
        'anthropic_version': 'bedrock-2023-05-31',
        'max_tokens': 1024,
        'messages': [
            {'role': 'user', 'content': f"Context:\n{context}\n\nQuestion: What are IAM roles?"}
        ]
    })
)
```

## Agents

Bedrock Agents execute multi-step tasks using tools (Lambda, knowledge bases, user input):

```python
# Create agent via API (or console)
bedrock_agent = boto3.client('bedrock-agent-runtime', region_name='us-east-1')

response = bedrock_agent.invoke_agent(
    agentAliasId='my-alias',
    agentId='my-agent-id',
    sessionId='user-session-123',
    inputText='Book a flight from San Francisco to New York next Tuesday'
)

for event in response['completion']:
    print(event['chunk']['text'])
```

### Agent Tools

Agents can use:
- **Knowledge bases** — RAG from your documents
- **Lambda functions** — Execute code
- **OpenSearch queries** — Search internal data
- **User input** — Ask clarifying questions

## Guardrails

Filter harmful content:

```python
# Create guardrail (via API or console)
bedrock = boto3.client('bedrock-guardrail', region_name='us-east-1')

# Apply to invoke
bedrock.invoke_model(
    modelId='anthropic.claude-3-5-sonnet-20241022-2',
    guardrailIdentifier='my-guardrail-id',
    guardrailVersion='1',
    contentType='application/json',
    accept='application/json',
    body=json.dumps({...})
)
```

Guardrails configured via console:
- **Content filters** — Violence, hate speech, sexual content
- **Topic filters** — Block certain topics
- **Word filters** — Block specific words/phrases
- **PII redaction** — Mask personal information

## Fine-Tuning

Customize a model with your data:

```python
# Prepare training data (JSONL format)
# {"prompt": "Translate to French: Hello", "completion": "Bonjour"}

# Upload to S3
s3 = boto3.client('s3')
s3.upload_file('training.jsonl', 'my-bucket', 'training-data/training.jsonl')

# Start fine-tuning job
bedrock = boto3.client('bedrock', region_name='us-east-1')
bedrock.create_model_customization_job(
    jobName='my-finetune',
    modelId='meta.llama3-1-8b-instruct-v1:0',
    trainingData={'s3Uri': 's3://my-bucket/training-data/training.jsonl'},
    validationData={'s3Uri': 's3://my-bucket/validation-data/validation.jsonl'},
    customModelName='my-llama-finetuned',
    roleArn='arn:aws:iam::123456789012:role/bedrock-role'
)
```

## Provisioned Throughput

For production workloads, reserve capacity:

```python
# Create provisioned throughput
bedrock = boto3.client('bedrock', region_name='us-east-1')
bedrock.create_provisioned_model_throughput(
    modelId='anthropic.claude-3-5-sonnet-20241022-2',
    modelUnits=1,  # 1 unit = ~500 tokens/min
    provisionedModelName='my-production-claude'
)
```

## Pricing

| Model | Input | Output |
|-------|-------|--------|
| Claude 3.5 Sonnet | $0.003/1K tokens | $0.015/1K tokens |
| Claude 3 Haiku | $0.00025/1K tokens | $0.00125/1K tokens |
| Llama 3.1 70B | $0.00265/1K tokens | $0.00265/1K tokens |
| Mistral Large 2 | $0.008/1K tokens | $0.024/1K tokens |
| Stable Diffusion XL | $0.018/image | — |

Provisioned throughput: ~$45K/month for 1 model unit (negotiable).

## Limits

| Resource | Limit |
|----------|-------|
| Context window | Varies by model (8K-200K tokens) |
| Concurrent requests | Per-model, varies |
| RAG Knowledge bases | 5 per agent |
| Fine-tuning | Not available for all models (Claude: no fine-tuning) |

## References

- **Homepage:** https://aws.amazon.com/bedrock/
- **Documentation:** https://docs.aws.amazon.com/bedrock/
- **Pricing:** https://aws.amazon.com/bedrock/pricing/

## Nuggets & Gotchas

- **Anthropic Claude does NOT support fine-tuning on Bedrock — use prompt engineering and RAG instead:** Claude's training is managed by Anthropic. If you need customization, use RAG (inject context) or prompt engineering. Fine-tuning is available for Llama and Titan only.
- **Bedrock's data handling varies by provider — Claude's API does NOT train on your data, but Llama may:** Before using Bedrock with sensitive data, verify the model's data policy. Anthropic has strict data confidentiality. Meta's models may have different policies.
- **Bedrock Agents are stateless across sessions — you must manage conversation context yourself:** If you need multi-turn conversations, store session state (messages array) and pass it on each `invoke_agent` call. The agent doesn't remember previous turns automatically.
- **Provisioned throughput is a MONTHLY commitment — it's expensive and not refundable:** A $45K/month commitment is a significant cost. Start with on-demand (pay per token) and only switch to provisioned when you have predictable, high-volume usage.
- **Bedrock's Titan Embeddings has a 1,024-token limit — for long documents, chunk before embedding:** Split documents into paragraphs or sections (< 512 tokens per chunk) before embedding. Use overlap (50-100 tokens) between chunks to preserve context.