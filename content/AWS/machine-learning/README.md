---
title: AWS Machine Learning
description: AWS machine learning services — AI services (pre-trained APIs), SageMaker (build your own), Bedrock (LLMs), Rekognition (vision), Comprehend (NLP), and SageMaker Canvas (no-code ML).
tags:
  - aws
  - machine-learning
  - ai
---

# AWS Machine Learning

AWS offers ML services across the spectrum — from pre-trained AI APIs ( Rekognition, Comprehend, Polly) that require zero ML expertise, to SageMaker for building custom models, to Bedrock for foundation models and LLM applications.

## Service Map

| Service | Type | Use Case |
|---------|------|----------|
| [[ai-services/README\|AI Services]] | Pre-trained APIs | Vision, NLP, speech, document, contact center |
| [[bedrock/README\|Bedrock]] | Foundation Models | LLMs, RAG, agents, image generation |
| [[sagemaker/README\|SageMaker]] | ML Platform | Build, train, deploy custom models |
| [[sagemaker-canvas/README\|SageMaker Canvas]] | No-Code ML | Business analyst predictions |
| [[rekognition/README\|Rekognition]] | Vision AI | Image/video analysis, face comparison |
| [[comprehend/README\|Comprehend]] | NLP AI | Text extraction, sentiment, entities, topics |

## ML Stack

```
Pre-built AI APIs (AI Services)
  │ rekognition, comprehend, polly, translate, transcribe, textract, lex, kendra
  │ Zero ML expertise needed. Pay per use. Easy API access.
  ▼
Foundation Models (Bedrock)
  │ Claude, Llama, Mistral, Stable Diffusion, Titan
  │ Pre-trained on massive data. Fine-tune or RAG. API access.
  ▼
ML Platform (SageMaker)
  │ Jupyter, training, inference, edge deployment
  │ Full control. Data scientists. Bring your own model.
  ▼
ML Infrastructure
  │ EC2 GPU instances, EFA networking, Trainium/Inferentia chips
  │ Raw compute. When you need maximum control.
```

## Choosing an ML Approach

```
Do you need to build a custom model?
  │
  ├── NO (use existing model)
  │   ├── Pre-built API (AI Services) → Rekognition, Comprehend, Polly, etc.
  │   └── Foundation Model (Bedrock) → Claude, Llama, Mistral, Stable Diffusion
  │
  └── YES (build custom)
      ├── No-code (SageMaker Canvas) → Business analysts
      └── Full platform (SageMaker) → Data scientists
```

## Security and Compliance

| Consideration | Implementation |
|--------------|----------------|
| Data residency | SageMaker processing jobs run in your VPC |
| Model ownership | You own your models and data |
| Encryption | KMS for models at rest, TLS in transit |
| Access control | IAM for API access, SageMaker for notebook access |
| Audit | CloudTrail for API calls, SageMaker for training jobs |
| Compliance | HIPAA, GDPR, FedRAMP (varies by service) |

## Cost Optimization

| Strategy | How |
|----------|-----|
| Spot instances | Training jobs: 60-70% savings |
| Managed spot | SageMaker managed spot: `MaxRuntimeInSeconds` |
| Inference endpoints | Auto-scaling + GPU switching (P4 → T4) |
| Multi-model endpoints | Deploy 100s of models on one endpoint |
| Serverless inference | SageMaker Serverless: pay per call |
| AI Services | Pay per API call, no idle cost |

## References

- **Homepage:** https://aws.amazon.com/machine-learning/
- **Documentation:** https://docs.aws.amazon.com/machine-learning/
- **Pricing:** https://aws.amazon.com/machine-learning/pricing/

## Nuggets & Gotchas

- **AI Services (Rekognition, Comprehend, etc.) are NOT HIPAA-eligible by default — you need a Business Associate Addendum (BAA):** If you're processing PHI, use Bedrock (HIPAA eligible) or SageMaker with your own models. Always verify compliance requirements before using AI Services with health data.
- **SageMaker training jobs run on managed infrastructure — your data IS processed by AWS:** Even though SageMaker runs in your VPC, the training compute is managed by AWS. For maximum data isolation, use VPC-only endpoints and SageMaker Direct.
- **Bedrock's data processing varies by model provider — Anthropic, Meta, Mistral have different data policies:** Before using Bedrock for sensitive data, read the model provider's data policy. Some models train on input data (opt-out available).
- **AI Services pricing is per API call — at scale, costs add up fast:** Rekognition at $0.0012/image × 10M images/month = $12,000/month. Budget carefully before deploying AI Services at production scale.
- **SageMaker Canvas produces models but doesn't give you the model artifact — you're locked into Canvas predictions:** If you need to deploy the model elsewhere (edge, mobile), use SageMaker Pipelines to export the model or use the built-in model registry.