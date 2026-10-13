---
title: "Amazon Bedrock"
description: "Bedrock offers supported foundation-model inference and application capabilities including knowledge bases, agents and guardrails."
tags:
  - aws/machine-learning
date: 2026-10-12
---

# Amazon Bedrock

Bedrock offers supported foundation-model inference and application capabilities including knowledge bases, agents and guardrails. Prerequisites: [[AWS/machine-learning/README|ML evaluation]], [[AWS/security/iam/README|IAM]] and [[AWS/analytics/opensearch/README|vector-store security]] where applicable.

## Models, APIs and lifecycle

Discover model IDs and modelLifecycle with ListFoundationModels/GetFoundationModel in your Region. Model availability, modalities, customization and inference profiles differ; lifecycle policies distinguish models launched before versus on/after September 7, 2026. A historical catalog table is not a guarantee of current access.

The bedrock client is control plane; bedrock-runtime invokes supported inference/Converse/guardrail operations. There is no separate bedrock-guardrail Boto3 client. Agent runtime invocation is a separate namespace. Pin SDK/model versions and consult the chosen model's request schema rather than reuse one provider's JSON for another.

```python
import boto3

client = boto3.client("bedrock")
response = client.list_foundation_models()
for model in response.get("modelSummaries", []):
    print(model["modelId"], model.get("modelLifecycle", {}).get("status"))
```

This read-only SDK example needs credentials/Region/access. It discovers models, not provider approval, a deployment or supported customization in every Region.

## RAG, agents and guardrails

RAG embeds supported chunks, retrieves authorized context and asks the model to answer with evidence. Use an authenticated OpenSearch data-plane client for vector search; Boto3 opensearch configures service resources rather than searching indexes. Titan Embeddings v2 supports up to 8,192 tokens/50,000 characters; 1,024 is the default vector dimension, not an input-token limit.

Agent calls sharing sessionId retain session context until configured TTL; isolate tenants and authorize tools/data separately. Guardrails provide configured checks, not a universal prevention guarantee. Some Claude models support fine-tuning in documented Regions, so verify model-specific eligibility rather than declare every Claude model untunable.

## Privacy and evaluation exercise

Current account/project retention modes are none, default and aws_review with model compatibility/terms; legacy provider_data_share does not currently send content to providers. Do not promise universal no-retention or infer provider training from old speculation. Customer-configured inference logging/storage is a separate responsibility.

In a budgeted sandbox, select an eligible model and a synthetic held-out question set. Compare grounded/unanswerable questions, prompt injection attempts and unauthorized retrieval. Verify citations against actual retrieved text and measure cost/latency. A blocked output is not proof every unsafe input is caught.

Record model ID/lifecycle, retention mode, SDK and evaluation criteria. Delete sandbox agents/knowledge bases/provisioned throughput/vector resources and reviewed logs/data as applicable. Bill tokens or operation-specific units plus embeddings, retrieval, tools and supporting infrastructure.

## Production request blueprint

Select a currently accessible model that supports the required Converse features. Start with a nonsensitive question through Converse; use ConverseStream only after testing event handling, cancellation, errors and final usage reporting. Persist the intended conversation messages in your application; do not confuse an ordinary Converse request with an agent session that manages its own state.

For tool use, handle the model's tool-use request as **untrusted input**. Allow only registered tool names, validate argument schemas/ranges, authorize the actual caller against each resource and require approval for destructive actions. Execute the approved action and return the correlated tool result through the supported conversation protocol. A generated tool argument or guardrail pass is not authorization.

Keep retrieval authorization separate from generation: enforce tenant/document access before returning chunks, record which evidence was retrieved and check the final answer's citations. Test unanswerable questions and malicious instructions inside retrieved text. Guardrail coverage, input/output limits, languages and invocation configuration are feature/model specific; fail safely when a check or dependency is unavailable.

### Region, quotas and observability

Cross-Region inference profiles can route to documented destination Regions. Review their destination set, IAM/SCP permissions, data residency and supported model/Region before enabling one. A source endpoint in an approved Region is not by itself proof that inference remains there; distinguish geographic profiles from global routing.

Check actual per-model/profile request and token capacity. Use bounded retries/backoff for throttling, limit concurrency and distinguish admission failure from model/stream/tool failure. Measure first-token/end-to-end latency, errors, token usage, retrieval quality and tool outcomes. Inference logging can store prompts/responses; configure its access, encryption and retention consciously instead of enabling sensitive payload capture by default.

### Sizing and failure exercise

For 10,000 requests averaging 2,000 input tokens (including system/history/retrieval) and 500 output tokens, budget 20 million input and 5 million output tokens before retries. At **hypothetical**, non-quoted rates of USD 0.001/1,000 input and USD 0.002/1,000 output, the calculation is USD 20 + USD 10 = USD 30. Replace both rates with the selected model/Region/mode tariff and include caching, embeddings, vector storage, tools, logs and any reserved capacity separately. A maximum-output setting is not the measured average token count.

Extend the synthetic evaluation with a throttled dependency, a denied tool action and an interrupted stream. Verify bounded retry, no unauthorized effect, recorded failure and recoverable client state. Stop/delete only dedicated inference capacity and supporting sandbox resources afterward; ordinary on-demand calls do not create a persistent endpoint to delete.

## Supported runtime invocation

For a model supporting Converse in your Region/account, define BEDROCK_LAB_MODEL_ID as the verified model or required inference-profile ID. This SDK example is a billable inference request, not a universal request schema for every modality/provider.

```python
import os
import boto3

model_id = os.environ["BEDROCK_LAB_MODEL_ID"]
runtime = boto3.client("bedrock-runtime")
response = runtime.converse(
    modelId=model_id,
    messages=[{
        "role": "user",
        "content": [{"text": "Explain a cache miss in one sentence."}],
    }],
    inferenceConfig={"maxTokens": 64, "temperature": 0},
)
for block in response["output"]["message"]["content"]:
    if "text" in block:
        print(block["text"])
```

Inspect stop reason, usage and actual response content; not every block is text. Provider-specific InvokeModel bodies and supported multimodal inputs need their own contract. Discover capability/lifecycle and handle unsupported/retired model responses deliberately.

## RAG architecture and implementation sequence

```text
authorized documents → parse/chunk → compatible embeddings → vector store
user identity + question → retrieve allowed chunks → compose context
  → guarded model invocation → answer with evidence → evaluate/log minimally
```

1. Define supported document types, ownership and update/deletion propagation.
2. Chunk with identifiers/source references; retain document/version metadata.
3. Generate compatible embeddings and use the matching vector dimension/index mapping.
4. Enforce retrieval authorization before constructing context; filter by actual data policy.
5. Retrieve bounded candidates and evaluate relevance rather than returning every nearest vector.
6. Separate retrieved content from trusted instructions; treat source text as potentially hostile.
7. Answer with traceable citations and a fallback for missing/contradictory evidence.
8. Test stale/deleted documents, denied tenants and prompt injection against both retrieval and tool use.

Embedding dimensions and input limits are distinct. An embedding model change can require reindexing; changing vector size without rebuilding the index is not a harmless request tweak. The OpenSearch control-plane client cannot execute the data-plane search.

## Agents, guardrails and customization comparisons

| Capability             | What it adds                                     | Boundary to test                                            |
| ---------------------- | ------------------------------------------------ | ----------------------------------------------------------- |
| Agent/action group     | Tool orchestration and supported session context | Tool authorization, arguments, retries and tenant isolation |
| Knowledge base         | Supported retrieval integration                  | Source permissions, freshness, grounding and citations      |
| Guardrail              | Configured input/output policies                 | Coverage, false positives/negatives and model compatibility |
| Fine-tuning            | Supported model/task customization               | Eligibility, data preparation and evaluation                |
| Provisioned throughput | Supported capacity purchasing                    | Model/version, capacity use and continuing cost             |

Maintain a sessionId per intended conversation/tenant rather than reuse a global value. A tool capable of changing infrastructure should have a narrower role and explicit action approval; model text is not authorization. Guardrails do not replace retrieval permissions or validation of tool results.

## Operational scenario

A grounded helpdesk answer incurs embedding/retrieval, generation and supporting storage/log/tool costs. Count actual input/output tokens including context, not only the user's question. Measure p95 latency, throttling, refusals and unsupported answers. Retention mode and customer inference logs are separate controls; document both before processing sensitive content. Delete sandbox capacity/agent/vector artifacts deliberately, not merely the chat session.

## Production references

- [Converse and streaming contracts](https://docs.aws.amazon.com/bedrock/latest/userguide/conversation-inference.html).
- [Tool-use protocol](https://docs.aws.amazon.com/bedrock/latest/userguide/tool-use.html).
- [Cross-Region profile scope](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles-support.html).
- [Invocation logging](https://docs.aws.amazon.com/bedrock/latest/userguide/model-invocation-logging.html).

## Foundational references

- [Model lifecycle](https://docs.aws.amazon.com/bedrock/latest/userguide/model-lifecycle.html)
- [Current retention modes](https://docs.aws.amazon.com/bedrock/latest/userguide/data-retention.html)
- [Bedrock runtime contracts](https://docs.aws.amazon.com/boto3/latest/reference/services/bedrock-runtime.html)
- [Titan Embeddings v2](https://docs.aws.amazon.com/bedrock/latest/userguide/titan-embedding-models.html)
- [Agent sessions](https://docs.aws.amazon.com/bedrock/latest/userguide/agents-session-state.html)
- [Bedrock pricing](https://aws.amazon.com/bedrock/pricing/)

## Across the wiki

- [[AI/aws/bedrock|Amazon Bedrock Architecture & Implementation]] — generative AI platforms (AI)
- [[AI/rag|Retrieval-Augmented Generation (RAG) Architecture]] — generative AI platforms (AI)
- [[AI/aws/sagemaker/README|Sagemaker]] — generative AI platforms (AI)
- [[AI/aws/services|Services]] — generative AI platforms (AI)
