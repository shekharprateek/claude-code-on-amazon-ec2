# Multi-Model Support via LiteLLM Proxy

Run Claude Code with **any foundation model on Amazon Bedrock** — not just Qwen. Switch between DeepSeek, Llama, Mistral, Kimi, MiniMax, Nova, and more with a single command.

## How it works

Claude Code speaks the Anthropic Messages API. Bedrock third-party models speak the OpenAI Chat Completions API. LiteLLM translates between them.

```
Claude Code → LiteLLM Proxy (:4000) → Amazon Bedrock → Any Model
```

## Supported Models

### Fully Working

These models are tested end-to-end with Claude Code via the LiteLLM proxy:

| Alias | Provider | Best For | Status |
|-------|----------|----------|--------|
| `qwen-coder-next` | Qwen | Code generation | ✅ |
| `qwen-coder-30b` | Qwen | Fast coding | ✅ |
| `qwen-32b` | Qwen | General purpose | ✅ |
| `qwen-vl-235b` | Qwen | Vision + language | ✅ |
| `qwen-next-80b` | Qwen | Efficient MoE | ✅ |
| `deepseek-v3` | DeepSeek | Coding + reasoning | ✅ |
| `deepseek-r1` | DeepSeek | Chain-of-thought | ✅ |
| `devstral-123b` | Mistral | Code specialist | ✅ |
| `mistral-large-3` | Mistral | Flagship MoE | ✅ |
| `kimi-k2.5` | Moonshot AI | Coding + reasoning | ✅ |
| `kimi-k2-thinking` | Moonshot AI | Chain-of-thought | ✅ |
| `minimax-m2.1` | MiniMax | General purpose | ✅ |

### Limited Support

These models work via direct API (curl) but fail with Claude Code due to a Bedrock limitation — they reject requests that combine streaming with tool definitions, which Claude Code always sends together.

| Alias | Provider | Best For | Status |
|-------|----------|----------|--------|
| `llama4-scout` | Meta | Efficient MoE | ⚠️ No streaming + tools |
| `llama4-maverick` | Meta | Multimodal chat | ⚠️ No streaming + tools |
| `llama3-70b` | Meta | General purpose | ⚠️ No streaming + tools |
| `nova-pro` | Amazon | Multimodal | ⚠️ No streaming + tools |
| `nova-lite` | Amazon | Fast, lightweight | ⚠️ No streaming + tools |

> **Note:** Llama and Nova models can still be used via direct curl calls to the proxy. The limitation is specific to Claude Code's streaming + tool use request pattern.

## Quick Start

```bash
# Step 1: Start the proxy (one-time)
./scripts/setup-proxy.sh

# Step 2: Run Claude Code with any model
./scripts/claude-model.sh --model deepseek-v3
./scripts/claude-model.sh --model qwen-coder-next
./scripts/claude-model.sh --model kimi-k2.5

# Or set env vars directly
export ANTHROPIC_BASE_URL=http://localhost:4000
export ANTHROPIC_API_KEY=bedrock-proxy
export ANTHROPIC_MODEL=deepseek-v3
export DISABLE_PROMPT_CACHING=1
claude
```

## Prerequisites

- AWS credentials with Bedrock model access enabled in `us-east-1`
- Python 3.9+ (LiteLLM installs automatically via `setup-proxy.sh`)
