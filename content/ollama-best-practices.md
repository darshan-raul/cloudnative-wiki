# Ollama Best Practices Guide
## Optimizing Local LLM Inference for Code Generation (2025)

---

## Table of Contents
1. [Hardware Recommendations](#1-hardware-recommendations)
2. [GPU Options and Comparison](#2-gpu-options-and-comparison)
3. [Model Memory Requirements](#3-model-memory-requirements)
4. [Code Generation Models](#4-code-generation-models)
5. [Quantization Guide](#5-quantization-guide)
6. [Ollama Configuration](#6-ollama-configuration)
7. [Benchmarking and Evaluation](#7-benchmarking-and-evaluation)
8. [Efficiency Tips](#8-efficiency-tips)
9. [Quick Reference](#9-quick-reference)

---

## 1. Hardware Recommendations

### Your Setup
- **Servers**: 64GB DDR4, 128GB DDR4 (no GPU yet)
- **Primary Use Case**: Code Generation

### GPU Recommendations by Budget

| Budget | GPU | VRAM | 7B t/s | 70B t/s | Notes |
|--------|-----|------|--------|---------|-------|
| Budget ($2-3K) | RTX 4090 | 24GB | 60-80 | 5-8* | Good for <34B |
| Mid ($10-20K) | 2x A100 80GB | 160GB | 160-200 | 25-35 | Best value for 70B+ |
| High ($30K+) | H200 | 141GB | 120-150 | 25-35 | Optimal long context |

*70B on single RTX 4090 requires heavy quantization + CPU RAM

### For Code Generation - Key GPU Features
1. **High VRAM Capacity** - Long contexts (16K-128K tokens) consume significant VRAM
2. **Memory Bandwidth** - Continuous generation speed
3. **Transformer Engine** - Long context attention acceleration
4. **PCIe/NVLink Bandwidth** - Multi-GPU tensor parallel

### Server Compatibility Checklist
- [ ] Power Supply: High-end GPUs need 1000W+ PSUs
- [ ] Physical Space: Full-height, double-width cards
- [ ] Cooling: Proper airflow for multi-GPU
- [ ] PCIe Slots: x16 slots available
- [ ] RAM for VRAM offloading: 64GB+ system RAM helps

### PCIe Requirements
| Scenario | PCIe Recommendation |
|----------|---------------------|
| Single RTX 4090 | Gen 4 x16 (minimum) |
| Single A100/H100 | Gen 5 x16 |
| Multi-GPU tensor parallel | Gen 5 x16, high-switch |

---

## 2. GPU Options and Comparison

### NVIDIA Consumer GPUs

| GPU | VRAM | Bandwidth | TDP | Price (est.) | FP16 TFLOPS |
|-----|------|-----------|-----|--------------|-------------|
| RTX 4090 | 24GB GDDR6X | 1,008 GB/s | 450W | $1,800-2,200 | 330 |
| RTX 4090D | 24GB GDDR6X | 1,008 GB/s | 450W | $1,500-2,000 | 310 |

### NVIDIA Data Center GPUs

| GPU | VRAM | Bandwidth | TDP | Price (est.) | FP16 TFLOPS |
|-----|------|-----------|-----|--------------|-------------|
| A100 80GB | 80GB HBM2e | 2 TB/s | 350W | $8,000-12,000 | 312 |
| H100 | 80GB HBM3 | 3.35 TB/s | 350W | $25,000-40,000 | 495 |
| H200 | 141GB HBM3e | 4.8 TB/s | 1000W | $30,000-45,000 | 990 |
| H20 | 80GB | ~2 TB/s | 350W | $10,000-15,000 | - |

### AMD GPUs (ROCm)

| GPU | VRAM | Bandwidth | TDP | Price (est.) | FP16 TFLOPS |
|-----|------|-----------|-----|--------------|-------------|
| RX 7900 XTX | 24GB | 600 GB/s | 355W | $900-1,000 | - |
| MI300X | 192GB HBM3 | 5.3 TB/s | 750W | $10,000-15,000 | 1,307 |

### Multi-GPU Configurations for 70B+ Models

| Configuration | Total VRAM | Feasible for 70B |
|--------------|------------|------------------|
| 2x RTX 4090 | 48GB | Q4_K_M only |
| 4x RTX 4090 | 96GB | Q4 + good perf |
| 2x A100 80GB | 160GB | Full FP16 or Q8 |
| 1x H100 80GB | 80GB | Q8 minimum |

### Ollama GPU Compatibility

| GPU | Ollama Support | Notes |
|-----|----------------|-------|
| NVIDIA RTX/GTX | Excellent | Full CUDA support |
| NVIDIA A100/H100 | Excellent | Data center cards fully supported |
| AMD RX series | Good | ROCm support improving |
| AMD MI300X | Limited | ROCm required, some model issues |

---

## 3. Model Memory Requirements

### Memory Formula
- **FP32**: 4 bytes per parameter
- **FP16**: 2 bytes per parameter
- **INT8**: 1 byte per parameter
- **INT4**: 0.5 bytes per parameter

### VRAM Requirements by Model Size

| Model | FP16 | INT8 | Q4_K_M | Q4_K_S |
|-------|------|------|--------|--------|
| 1B | 2GB | 1GB | 0.5GB | 0.4GB |
| 3B | 6GB | 3GB | 1.5GB | 1.2GB |
| 7B | 14GB | 7GB | 4GB | 3.5GB |
| 8B | 16GB | 8GB | 5GB | 4GB |
| 13B | 26GB | 13GB | 7GB | 6GB |
| 14B | 28GB | 14GB | 8GB | 7GB |
| 32B | 64GB | 32GB | 18GB | 16GB |
| 34B | 68GB | 34GB | 20GB | 18GB |
| 70B | 140GB | 70GB | 40GB | 36GB |
| 236B MoE | 472GB | 236GB | 120GB | 100GB |

### KV Cache Memory

| Context | Q4_K_M Model (70B) |
|---------|-------------------|
| 4K | ~1GB |
| 32K | ~8GB |
| 64K | ~16GB |
| 128K | ~32GB |

**Tip**: Enable `OLLAMA_KV_CACHE_TYPE=q8_0` to reduce KV cache by ~50%

---

## 4. Code Generation Models

### Top Models for Code Generation (2025)

| Model | Sizes | Best For | Max Context | Ollama |
|-------|-------|----------|-------------|--------|
| **Qwen2.5-Coder** | 0.5B-32B | Best overall balance | 128K | Yes |
| **DeepSeek-Coder-V2** | 16B/236B MoE | SOTA code capability | 128K | Yes |
| **Codestral** | 22B | Code completion | 32K | Yes |
| **CodeLlama** | 7B-70B | Multi-language support | 100K | Yes |
| **Devstral** | 24B | Coding agents | 32K+ | Yes |
| **StarCoder2** | 3B-15B | Fill-in-middle | 16K | Yes |
| **Granite-Code** | 3B-34B | Enterprise | 128K | Yes |

### Benchmark Scores (HumanEval Pass@1)

| Model | Score | Notes |
|-------|-------|-------|
| DeepSeek-Coder-V2 236B | ~90% | SOTA |
| Qwen2.5-Coder 32B | ~85% | Best value |
| Codestral 22B | ~73% | Good all-around |
| CodeLlama 70B | ~67% | Proven, multi-language |
| StarCoder2 15B | ~70% | Fill-in-middle |
| Granite-Code 34B | ~72% | Enterprise |
| Qwen2.5-Coder 7B | ~75% | Small model champion |

### Model Selection by VRAM

| VRAM | Recommended Models |
|------|-------------------|
| 6-8GB | qwen2.5-coder:3b, stable-code:3b, starcoder2:3b |
| 10-16GB | qwen2.5-coder:7b, codellama:13b, granite-code:8b |
| 20-32GB | qwen2.5-coder:14b, codellama:34b, deepseek-coder-v2:16b |
| 40GB+ | qwen2.5-coder:32b, codellama:70b, devstral:24b |
| 80GB+ | deepseek-coder-v2:236b, codellama:70b-Q8 |

### Quick Ollama Commands

```bash
# Best all-around (14B)
ollama run qwen2.5-coder:14b

# Best for large projects (128K context)
ollama run qwen2.5-coder:32b

# Best for coding agents
ollama run devstral:24b

# Best multi-language
ollama run codellama:70b

# Best small model
ollama run qwen2.5-coder:7b

# DeepSeek for SOTA code
ollama run deepseek-coder-v2:16b
```

---

## 5. Quantization Guide

### Quantization Types

| Type | Size vs FP16 | Quality Impact | Use Case |
|------|--------------|----------------|----------|
| **Q4_K_S** | ~60% | Small loss | Maximum memory savings |
| **Q4_K_M** | ~60% | Minimal loss (recommended) | Best balance |
| **Q5_K_S** | ~55% | Very small loss | Better quality |
| **Q5_K_M** | ~50% | Very small loss | When quality > size |
| **Q8_0** | ~30% | Near FP16 | When quality is critical |
| **FP16** | 100% | Full precision | Training, fine-tuning |

### For Code Generation - Quantization Recommendations

| Model Size | Recommended | Alternative |
|------------|-------------|-------------|
| 7B | Q4_K_M | Q5_K_M if VRAM allows |
| 13B | Q4_K_M | Q8_0 for max quality |
| 34B | Q4_K_M | Q5_K_M for quality |
| 70B | Q4_K_M | Q8_0 if 80GB+ VRAM |

### Creating Quantized Models

```bash
# Pull base model
ollama pull codellama:13b

# Create quantized version
curl http://localhost:11434/api/create -d '{
  "model": "codellama:13b-q4_K_M",
  "from": "codellama:13b",
  "quantize": "q4_K_M"
}'
```

### Quantization Impact on Quality

| Quantization | HumanEval Drop | Acceptable? |
|--------------|----------------|-------------|
| Q8_0 | <1% | Yes |
| Q4_K_M | 2-5% | Yes (recommended) |
| Q4_K_S | 5-8% | Acceptable for memory constrained |
| Q4_0 | 8-12% | Use only if necessary |

---

## 6. Ollama Configuration

### Environment Variables

| Variable | Default | Code Generation Recommendation |
|----------|---------|--------------------------------|
| `OLLAMA_FLASH_ATTENTION` | 0 | `1` - Enable |
| `OLLAMA_KV_CACHE_TYPE` | f16 | `q8_0` - ~50% memory reduction |
| `OLLAMA_CONTEXT_LENGTH` | varies | `64000` or `128000` for code |
| `OLLAMA_NUM_PARALLEL` | 1 | `1-2` (higher = more VRAM) |
| `OLLAMA_MAX_LOADED_MODELS` | 3 | Based on VRAM capacity |
| `OLLAMA_KEEP_ALIVE` | 5m | `24h` for frequently used |
| `OLLAMA_MAX_QUEUE` | 512 | Default usually fine |

### Recommended Configurations

#### High-VRAM System (32GB+)
```bash
OLLAMA_FLASH_ATTENTION=1 \
OLLAMA_KV_CACHE_TYPE=q8_0 \
OLLAMA_CONTEXT_LENGTH=128000 \
OLLAMA_NUM_PARALLEL=2 \
OLLAMA_MAX_LOADED_MODELS=2 \
OLLAMA_KEEP_ALIVE=24h \
ollama serve
```

#### Moderate VRAM (16-24GB)
```bash
OLLAMA_FLASH_ATTENTION=1 \
OLLAMA_KV_CACHE_TYPE=q8_0 \
OLLAMA_CONTEXT_LENGTH=64000 \
OLLAMA_NUM_PARALLEL=1 \
OLLAMA_MAX_LOADED_MODELS=1 \
OLLAMA_KEEP_ALIVE=12h \
ollama serve
```

#### Limited VRAM (8-16GB)
```bash
OLLAMA_FLASH_ATTENTION=1 \
OLLAMA_KV_CACHE_TYPE=q4_0 \
OLLAMA_CONTEXT_LENGTH=4096 \
OLLAMA_NUM_PARALLEL=1 \
OLLAMA_MAX_LOADED_MODELS=1 \
OLLAMA_KEEP_ALIVE=2h \
ollama serve
```

### Context Length by VRAM

| VRAM | Recommended Context | Use Case |
|------|-------------------|----------|
| <24GB | 4K-16K | Simple completions |
| 24-48GB | 32K-64K | Single large files |
| 48GB+ | 128K+ | Full project context |

### Keep Alive Settings

```bash
# Keep model loaded for 24 hours
OLLAMA_KEEP_ALIVE=24h

# Keep permanently loaded
OLLAMA_KEEP_ALIVE=-1

# Per-request override
curl http://localhost:11434/api/generate -d '{
  "model": "codellama",
  "keep_alive": -1
}'
```

### Multi-Model Serving

```bash
# Limit to specific GPUs
CUDA_VISIBLE_DEVICES=0,1

# Max concurrent models based on VRAM
OLLAMA_MAX_LOADED_MODELS=2  # Two 24GB models on 48GB VRAM
```

### CPU Offloading (Limited VRAM)

```bash
# Force CPU mode with AVX2
OLLAMA_LLM_LIBRARY=cpu_avx2

# Check what's loaded where
ollama ps
# 100% GPU = fully on GPU (best)
# 48%/52% CPU/GPU = partial offloading
```

---

## 7. Benchmarking and Evaluation

### Key Benchmarks for Code Generation

| Benchmark | Description | Strong Score |
|-----------|-------------|--------------|
| **HumanEval** | Pass@1 code generation (164 problems) | >60% |
| **MBPP** | Python programming problems (974 tasks) | >70% |
| **MultiPL-E** | HumanEval in 18+ languages | >50% |

### lm-evaluation-harness Setup

```bash
# Install
pip install "lm_eval[api,hf]"

# Run against Ollama server
lm_eval --model local-completions \
    --model_args model=codellama:13b,base_url=http://localhost:11434/v1/completions \
    --tasks humaneval,mbpp \
    --batch_size 16 \
    --output_path ./results/
```

### Tokens Per Second Measurement

```bash
# Simple timing
time curl -s http://localhost:11434/api/generate -d '{
  "model": "codellama:13b",
  "prompt": "Write a quicksort implementation",
  "stream": false
}' | jq '{eval_count, eval_duration}'

# Calculate: tokens_per_sec = eval_count / (eval_duration * 1e-9)
```

### Expected Tokens/sec by Hardware

| Model Size | Quantization | CPU (64GB RAM) | RTX 4090 | A100 80GB |
|------------|-------------|----------------|----------|-----------|
| 7B | Q4_K_M | 15-25 t/s | 80-150 t/s | 80-100 t/s |
| 13B | Q4_K_M | 10-18 t/s | 50-100 t/s | 50-70 t/s |
| 34B | Q4_K_M | 5-10 t/s | 30-60 t/s | 25-35 t/s |
| 70B | Q4_K_M | 2-5 t/s | 15-35 t/s | 12-18 t/s |

### Quick Model Comparison Script

```python
import requests
import json

MODELS = ["qwen2.5-coder:7b", "codellama:13b", "deepseek-coder-v2:16b"]
PROMPT = "Write a function to check if a string is a palindrome"

def benchmark_model(model):
    resp = requests.post(
        "http://localhost:11434/api/generate",
        json={"model": model, "prompt": PROMPT, "stream": False}
    ).json()

    tokens = resp.get("eval_count", 0)
    duration_ns = resp.get("eval_duration", 0)
    tokens_per_sec = tokens / (duration_ns * 1e-9) if duration_ns else 0

    return {
        "model": model,
        "tokens_per_sec": round(tokens_per_sec, 2),
        "response_length": len(resp.get("response", ""))
    }

for model in MODELS:
    result = benchmark_model(model)
    print(f"{result['model']}: {result['tokens_per_sec']} tokens/sec")
```

### Quantization Quality Testing

```bash
#!/bin/bash
# test_quantization.sh - Compare base vs quantized

BASE_MODEL="codellama:13b-fp16"
QUANTIZED_MODEL="codellama:13b-q4_K_M"

lm_eval --model local-completions \
    --model_args model=$BASE_MODEL,base_url=http://localhost:11434/v1/completions \
    --tasks humaneval \
    --output_path ./results/base/

lm_eval --model local-completions \
    --model_args model=$QUANTIZED_MODEL,base_url=http://localhost:11434/v1/completions \
    --tasks humaneval \
    --output_path ./results/quantized/
```

### Acceptable Quantization Impact

| Aspect | Acceptable Delta |
|--------|------------------|
| Code Correctness (HumanEval) | <5% absolute drop |
| Perplexity | <10% increase |
| Speed | >2x improvement for Q4 |
| Memory | >50% reduction |

---

## 8. Efficiency Tips

### Top 10 Optimizations

1. **Enable Flash Attention** - `OLLAMA_FLASH_ATTENTION=1`
   - Reduces memory usage significantly at long contexts

2. **Quantize KV Cache** - `OLLAMA_KV_CACHE_TYPE=q8_0`
   - ~50% memory reduction with minimal quality impact

3. **Set Appropriate Context Length** - Don't over-provision
   - 4K for simple completions, 64K+ for full project context

4. **Keep Models Loaded** - `OLLAMA_KEEP_ALIVE=24h` or `-1`
   - Avoids reload latency for frequently used models

5. **Use Q4_K_M Quantization** - Best size/quality balance
   - Works well for code generation with minimal quality loss

6. **Match Model to Hardware** - Don't try to run 70B on 24GB VRAM
   - 70B requires quantization + CPU offload or multi-GPU

7. **Limit Parallel Requests** - `OLLAMA_NUM_PARALLEL=1-2`
   - Higher = more VRAM usage, only increase if beneficial

8. **Use Appropriate Batch Sizes** - For benchmarking, 8-16 is typical
   - Larger batches = more memory, adjust for your VRAM

9. **Monitor with `ollama ps`** - Check GPU vs CPU usage
   - 100% GPU = best performance for code generation

10. **Consider Multi-GPU for 70B+** - Split across GPUs if available
    - Ollama automatically spreads models across GPUs

### For Your 64GB/128GB Servers

**Recommended Starting Configuration:**
- Start with RTX 4090 (24GB VRAM)
- Run 7B-14B models at full performance
- Run 34B with quantization
- Run 70B with heavy quantization + CPU RAM (slower but workable)

**Upgrade Path:**
1. Add second RTX 4090 for 70B Q4_K_M
2. Or move to 2x A100 80GB for FP16/Q8 on 70B
3. Or H200 for best long-context performance

### GPU Selection for Code Generation

| Priority | Feature | Why |
|----------|---------|-----|
| 1 | High VRAM | Long contexts, large models |
| 2 | Memory Bandwidth | Generation speed |
| 3 | Transformer Engine | Attention acceleration |
| 4 | PCIe/NVLink | Multi-GPU scaling |
| 5 | INT8/FP8 Support | Faster inference |

---

## 9. Quick Reference

### Ollama API Endpoints

```bash
# Generate completion
POST /api/generate

# Chat completion
POST /api/chat

# List models
GET /api/tags

# Create quantized model
POST /api/create

# Show model info
POST /api/show
```

### Model VRAM Quick Reference

| Model | Q4_K_M VRAM | Q8_0 VRAM | FP16 VRAM |
|-------|-------------|-----------|-----------|
| 7B | 4-5GB | 7GB | 14GB |
| 13B | 7-8GB | 13GB | 26GB |
| 32B | 18-20GB | 32GB | 64GB |
| 70B | 40GB | 70GB | 140GB |

### Essential Commands

```bash
# Start Ollama
ollama serve

# Run a model
ollama run qwen2.5-coder:14b

# List running models
ollama ps

# Pull a model
ollama pull codellama:13b

# Check GPU
nvidia-smi -L

# Benchmark speed
curl http://localhost:11434/api/generate -d '{"model": "qwen2.5-coder:7b", "prompt": "Hello", "stream": false}'
```

### Performance Tiers

| Use Case | Model | VRAM | Expected t/s |
|----------|-------|------|--------------|
| Budget 7B | qwen2.5-coder:7b | 6GB | 60-100 |
| Mid 13B | codellama:13b | 10GB | 40-70 |
| Mid+ 14B | qwen2.5-coder:14b | 16GB | 35-60 |
| High 32B | qwen2.5-coder:32b | 24GB | 20-40 |
| Enthusiast 70B | codellama:70b | 48GB | 15-30 |

---

## Summary: Recommended Starting Point

For your 64GB/128GB DDR4 servers with code generation focus:

**Step 1**: Buy RTX 4090 (~$2,000) to establish workflow

**Step 2**: Start with `ollama run qwen2.5-coder:14b`

**Step 3**: Benchmark with `lm_eval --tasks humaneval,mbpp`

**Step 4**: Upgrade to multi-GPU or H200/A100 when needed for 70B+

**Optimal Config for Code Generation**:
```bash
OLLAMA_FLASH_ATTENTION=1 \
OLLAMA_KV_CACHE_TYPE=q8_0 \
OLLAMA_CONTEXT_LENGTH=128000 \
OLLAMA_KEEP_ALIVE=24h \
ollama serve
```

---

*Document compiled: May 2025*
*Last updated: Add date as needed*