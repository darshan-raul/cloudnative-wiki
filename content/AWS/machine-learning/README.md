---
title: "AWS Machine Learning"
description: "Choose the smallest supported ML approach that solves the task, then evaluate quality, privacy, latency and lifecycle costs."
tags:
  - aws/machine-learning
date: 2026-10-12
---

# AWS Machine Learning

Choose the smallest supported ML approach that solves the task, then evaluate quality, privacy, latency and lifecycle costs. Model access is not evidence that predictions are correct or compliant.

Prerequisites: [[AWS/security/iam/README|IAM]], [[AWS/storage/s3/README|S3]], [[AWS/analytics/README|data pipelines]] and a representative evaluation dataset.

## Learning path

| Lesson                                                   | Appropriate starting point                                                           |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| [[AWS/machine-learning/ai-services/README\|AI services]] | Managed document, speech, translation, vision and language APIs for supported tasks. |
| [[AWS/machine-learning/comprehend/README\|Comprehend]]   | Language/PII analysis and supported custom classifiers/entities.                     |
| [[AWS/machine-learning/rekognition/README\|Rekognition]] | Supported image/video analysis and Custom Labels.                                    |
| [[AWS/machine-learning/bedrock/README\|Bedrock]]         | Foundation-model inference, RAG, guarded applications and supported customization.   |
| [[AWS/machine-learning/sagemaker/README\|SageMaker AI]]  | Custom training, deployment, feature management and MLOps.                           |
| [[AWS/machine-learning/sagemaker-canvas/README\|Canvas]] | Supported visual/no-code workflows with explicit deployment/evaluation boundaries.   |

## Architectural choices

Managed task APIs reduce training/hosting work but impose operation, language, input and customization constraints. Bedrock exposes supported foundation models; RAG supplies retrieved context but does not automatically make answers true. SageMaker AI provides more training/hosting control and corresponding operational responsibility. Canvas simplifies parts of the workflow without eliminating execution-role, data-quality or endpoint costs.

Separate data preparation, training/evaluation, model registration, deployment and monitoring. Avoid train/test leakage; retain reproducible versions of input, features, model and evaluation criteria. Distinguish statistical drift from application/business failure and require a fallback for unavailable or low-confidence output.

## Safety and cost exercise

Use synthetic/non-sensitive inputs and a labelled held-out dataset. Compare a managed API/model to a simple baseline; report false positives/negatives and subgroup behavior rather than only one accuracy score. Test an unauthorized identity and define what sensitive inputs/output logs may be retained.

For PHI, service HIPAA eligibility alone is insufficient: the BAA, supported feature/Region, permissions and shared-responsibility configuration matter. Document model/account retention settings and customer-created inference logs separately.

Measure requests/tokens, training/processing hours, notebook/session resources, endpoints, storage and network dimensions from current regional pricing. Endpoints can charge while idle. Delete sandbox apps, jobs/endpoints and reviewed artifacts; avoid retaining sensitive evaluation output in default logs.

## The ML stack and choosing ownership

```text
Managed task APIs: input → supported task result
Bedrock: prompt/context → supported foundation model → guarded/evaluated result
SageMaker AI: data → train/evaluate → approved artifact → hosting/monitoring
Canvas: visual preparation/build/evaluation → supported prediction/deployment
```

These are ownership choices, not a quality ranking. A managed API can outperform a custom model with poorly curated labels; a foundation model may be unsuitable for a deterministic extraction task. Start from the task and held-out evaluation, then justify custom training where it adds value.

| Requirement               | Approach to investigate       | What you still own                                          |
| ------------------------- | ----------------------------- | ----------------------------------------------------------- |
| OCR/table extraction      | Textract                      | Document quality, response reconstruction and validation    |
| Domain speech             | Transcribe customization      | Supported language/mode, vocabulary/model quality           |
| Classification/PII        | Comprehend or justified model | False negatives, thresholds and privacy handling            |
| Generative application    | Bedrock                       | Grounding, authorization, prompt/tool safety and evaluation |
| Custom algorithm/features | SageMaker AI                  | Dataset/algorithm/runtime and MLOps lifecycle               |
| Visual business workflow  | Canvas                        | Data/target/evaluation and eligible deployment              |

## Evaluation and production handoff

Define a baseline, dataset version, held-out split, success threshold and business cost of errors. For classification, compare precision/recall across classes; for forecasting, split chronologically; for generation, evaluate answer support and refusal on unanswerable questions. Training completion and one impressive sample are not quality gates.

Separate notebook experimentation from repeatable jobs. Preserve code, dependencies, data/feature schema, artifact and evaluation evidence. Require explicit deployment approval and an endpoint rollback/fallback strategy. Monitor input drift, output quality where measurable, latency/errors and cost.

Shared responsibility includes least-privilege data access, encryption, supported privacy/retention configuration and logging minimization. Human review and consent requirements do not disappear because a service is HIPAA-eligible or an output has high confidence.

## References

- [SageMaker AI documentation](https://docs.aws.amazon.com/sagemaker/latest/dg/whatis.html)
- [Bedrock documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/what-is-bedrock.html)
- [HIPAA eligible services](https://aws.amazon.com/compliance/hipaa-eligible-services-reference/)

## Across the wiki

- [[Azure/compute/aks/gpu-orchestration-ai|AKS GPU Orchestration for AI/ML — NVIDIA H100/A100, InfiniBand RDMA, and KubeRay]] — GPU and AI workloads (Azure)
- [[GCP/compute/gke/gpu-tpu-orchestration|GKE GPU & TPU Orchestration — AI/ML Accelerators, Ray on GKE, and Kueue]] — GPU and AI workloads (GCP)
- [[Kubernetes/concepts/L06-scheduling-scaling/14-extended-resources|Extended Resources and Device Plugins]] — GPU and AI workloads (Kubernetes)
- [[AI/run-locally/ollama-best-practices|Ollama Best Practices Guide]] — GPU and AI workloads (AI)
