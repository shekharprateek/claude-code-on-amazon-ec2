# Multi-Model Support via LiteLLM Proxy

Run Claude Code with **any foundation model on Amazon Bedrock** — not just Qwen. Switch between DeepSeek, Llama, Mistral, Kimi, MiniMax, Nova, and more with a single command.

## How it works

Claude Code speaks the Anthropic Messages API. Bedrock third-party models speak the OpenAI Chat Completions API. LiteLLM translates between them.

```
Claude Code → LiteLLM Proxy (:4000) → Amazon Bedrock → Any Model
```

## Supported Models

| Alias | Provider | Best For |
|-------|----------|----------|
| `qwen-coder-next` | Qwen | Code generation |
| `qwen-coder-30b` | Qwen | Fast coding |
| `qwen-32b` | Qwen | General purpose |
| `qwen-vl-235b` | Qwen | Vision + language |
| `qwen-next-80b` | Qwen | Efficient MoE |
| `deepseek-v3` | DeepSeek | Coding + reasoning |
| `deepseek-r1` | DeepSeek | Chain-of-thought |
| `devstral-123b` | Mistral | Code specialist |
| `mistral-large-3` | Mistral | Flagship MoE |
| `kimi-k2.5` | Moonshot AI | Coding + reasoning |
| `kimi-k2-thinking` | Moonshot AI | Chain-of-thought |
| `minimax-m2.1` | MiniMax | General purpose |
| `nova-pro` | Amazon | Multimodal |
| `nova-lite` | Amazon | Fast, lightweight |

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
