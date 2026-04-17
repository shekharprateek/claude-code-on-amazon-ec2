#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# claude-model.sh — Run Claude Code with any Bedrock model
#
# For Anthropic models: connects directly to Bedrock (no proxy needed)
# For third-party models: routes through LiteLLM proxy
#
# Usage:
#   ./scripts/claude-model.sh                      # interactive: pick a model
#   ./scripts/claude-model.sh --model qwen-coder-next
#   ./scripts/claude-model.sh --model claude-opus   # native Bedrock
#   ./scripts/claude-model.sh --model claude-sonnet -p "explain this code"
#   ./scripts/claude-model.sh --list                # list available models
#
# Environment:
#   PROXY_PORT       LiteLLM proxy port (default: 4000)
#   AWS_REGION       AWS region for Bedrock (default: us-east-1)
# ---------------------------------------------------------------------------

PROXY_PORT="${PROXY_PORT:-4000}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# ── Model Registry ────────────────────────────────────────────────
# Format: alias|type|model_id|description
# type: "native" = direct Bedrock, "proxy" = via LiteLLM
MODELS=(
    # Anthropic (native — no proxy needed, using cross-region inference profile IDs)
    "claude-opus|native|us.anthropic.claude-opus-4-6-v1|Claude Opus 4.6 — flagship, best reasoning"
    "claude-sonnet|native|us.anthropic.claude-sonnet-4-6|Claude Sonnet 4.6 — balanced speed/quality"
    "claude-haiku|native|us.anthropic.claude-haiku-4-5-20251001-v1:0|Claude Haiku 4.5 — fast, lightweight"
    "claude-opus-4.5|native|us.anthropic.claude-opus-4-5-20251101-v1:0|Claude Opus 4.5 — previous gen flagship"
    "claude-sonnet-4.5|native|us.anthropic.claude-sonnet-4-5-20250929-v1:0|Claude Sonnet 4.5 — previous gen balanced"

    # Qwen — Coding (proxy required)
    "qwen-coder-next|proxy|qwen-coder-next|Qwen3 Coder Next — latest coding model"
    "qwen-coder-480b|proxy|qwen-coder-480b|Qwen3 Coder 480B — largest coding MoE"
    "qwen-coder-30b|proxy|qwen-coder-30b|Qwen3 Coder 30B — compact coding MoE"

    # Qwen — General (proxy required)
    "qwen-235b|proxy|qwen-235b|Qwen3 235B — general purpose MoE"
    "qwen-32b|proxy|qwen-32b|Qwen3 32B — dense, hybrid thinking"
    "qwen-vl-235b|proxy|qwen-vl-235b|Qwen3 VL 235B — vision + language"
    "qwen-next-80b|proxy|qwen-next-80b|Qwen3 Next 80B — efficient MoE"

    # DeepSeek (proxy required)
    "deepseek-v3|proxy|deepseek-v3|DeepSeek V3.2 — coding + reasoning MoE"
    "deepseek-r1|proxy|deepseek-r1|DeepSeek R1 — chain-of-thought reasoning"

    # Meta Llama (proxy required)
    "llama4-maverick|proxy|llama4-maverick|Llama 4 Maverick 17B — 128 experts MoE"
    "llama4-scout|proxy|llama4-scout|Llama 4 Scout 17B — 16 experts MoE"
    "llama3-70b|proxy|llama3-70b|Llama 3.3 70B — strong general model"

    # Mistral (proxy required)
    "devstral-123b|proxy|devstral-123b|Devstral 2 123B — coding specialist"
    "mistral-large-3|proxy|mistral-large-3|Mistral Large 3 675B — flagship MoE"

    # Amazon Nova (proxy required)
    "nova-pro|proxy|nova-pro|Nova Pro — multimodal, balanced"
    "nova-lite|proxy|nova-lite|Nova Lite — fast, lightweight"

    # Moonshot AI — Kimi (proxy required)
    "kimi-k2.5|proxy|kimi-k2.5|Kimi K2.5 — coding + reasoning"
    "kimi-k2-thinking|proxy|kimi-k2-thinking|Kimi K2 Thinking — chain-of-thought"

    # MiniMax (proxy required)
    "minimax-m2.1|proxy|minimax-m2.1|MiniMax M2.1 — general purpose"

    # Self-hosted via Ollama (proxy required, SSH tunnel must be active)
    # Uncomment after starting tunnel: ./scripts/tunnel.sh start
    # "qwen-local|proxy|qwen-local|Qwen 3.5 35B — self-hosted on GPU server"
)

# ── Functions ─────────────────────────────────────────────────────

list_models() {
    echo ""
    echo "Available Models for Claude Code + Bedrock"
    echo "==========================================="
    echo ""
    printf "  %-20s %-8s %s\n" "ALIAS" "TYPE" "DESCRIPTION"
    printf "  %-20s %-8s %s\n" "-----" "----" "-----------"
    for entry in "${MODELS[@]}"; do
        IFS='|' read -r alias type model_id desc <<< "$entry"
        printf "  %-20s %-8s %s\n" "$alias" "$type" "$desc"
    done
    echo ""
    echo "native = direct Bedrock (no proxy needed)"
    echo "proxy  = via LiteLLM proxy (start with: ./scripts/setup-proxy.sh)"
}

lookup_model() {
    local search="$1"
    for entry in "${MODELS[@]}"; do
        IFS='|' read -r alias type model_id desc <<< "$entry"
        if [[ "$alias" == "$search" ]]; then
            echo "$alias|$type|$model_id|$desc"
            return 0
        fi
    done
    return 1
}

pick_model_interactive() {
    echo ""
    echo "Select a model:"
    echo ""
    local i=1
    for entry in "${MODELS[@]}"; do
        IFS='|' read -r alias type model_id desc <<< "$entry"
        printf "  %2d) %-20s [%s] %s\n" "$i" "$alias" "$type" "$desc"
        ((i++))
    done
    echo ""
    read -rp "Enter number (1-${#MODELS[@]}): " choice

    if [[ "$choice" -ge 1 && "$choice" -le "${#MODELS[@]}" ]]; then
        echo "${MODELS[$((choice-1))]}"
    else
        echo "[error] Invalid choice" >&2
        exit 1
    fi
}

check_proxy() {
    if ! curl -sf "http://localhost:${PROXY_PORT}/health" &>/dev/null; then
        echo "[error] LiteLLM proxy not running on port $PROXY_PORT"
        echo "        Start it: ./scripts/setup-proxy.sh"
        exit 1
    fi
}

# ── Parse args ────────────────────────────────────────────────────

MODEL_ALIAS=""
CLAUDE_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --model|-m)  MODEL_ALIAS="$2"; shift 2 ;;
        --list|-l)   list_models; exit 0 ;;
        -h|--help)
            echo "Usage: $0 [--model ALIAS] [--list] [claude args...]"
            echo "       $0 --model qwen-coder-next -p 'write a function'"
            echo "       $0 --list"
            exit 0
            ;;
        *)  CLAUDE_ARGS+=("$1"); shift ;;
    esac
done

# Interactive selection if no model specified
if [[ -z "$MODEL_ALIAS" ]]; then
    SELECTED=$(pick_model_interactive)
else
    SELECTED=$(lookup_model "$MODEL_ALIAS") || {
        echo "[error] Unknown model: $MODEL_ALIAS"
        echo "        Run: $0 --list"
        exit 1
    }
fi

IFS='|' read -r ALIAS TYPE MODEL_ID DESC <<< "$SELECTED"
echo ""
echo "[model] $ALIAS — $DESC"

# ── Launch Claude Code ────────────────────────────────────────────

if [[ "$TYPE" == "native" ]]; then
    # Anthropic models: direct Bedrock connection
    echo "[mode] Native Bedrock (no proxy)"
    echo ""
    CLAUDE_CODE_USE_BEDROCK=1 \
    AWS_REGION="$AWS_REGION" \
    ANTHROPIC_MODEL="$MODEL_ID" \
    claude ${CLAUDE_ARGS[@]+"${CLAUDE_ARGS[@]}"}

elif [[ "$TYPE" == "proxy" ]]; then
    # Third-party models: via LiteLLM proxy
    check_proxy
    echo "[mode] LiteLLM proxy (localhost:$PROXY_PORT)"
    echo ""
    ANTHROPIC_BASE_URL="http://localhost:${PROXY_PORT}" \
    ANTHROPIC_API_KEY="bedrock-proxy" \
    ANTHROPIC_MODEL="$MODEL_ID" \
    CLAUDE_CODE_USE_BEDROCK=0 \
    DISABLE_PROMPT_CACHING=1 \
    claude ${CLAUDE_ARGS[@]+"${CLAUDE_ARGS[@]}"}
fi
