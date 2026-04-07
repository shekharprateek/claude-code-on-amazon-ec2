#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# ec2-setup.sh — One-shot setup for the GPU server (g6e.xlarge or similar)
#
# Run this on the EC2 GPU instance after launch:
#
#   curl -fsSL https://raw.githubusercontent.com/shekharprateek/claude-code-on-amazon-ec2/main/scripts/ec2-setup.sh | bash
#
# Or clone the repo and run:
#
#   bash scripts/ec2-setup.sh
#
# What it does:
#   1. Installs Ollama
#   2. Pulls Qwen 3.5-35B (or any model via MODEL env var)
#   3. Confirms GPU is being used and model is serving
#
# Usage:
#   bash ec2-setup.sh                    # Default: qwen3.5:35b
#   MODEL=qwen3.5:7b bash ec2-setup.sh  # Smaller model (fits in 8GB VRAM)
# ---------------------------------------------------------------------------

MODEL="${MODEL:-qwen3.5:35b}"
PORT=11434

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

info()   { echo -e "${BLUE}[info]${RESET}  $1"; }
ok()     { echo -e "${GREEN}[ok]${RESET}    $1"; }
fail()   { echo -e "${RED}[fail]${RESET}  $1"; exit 1; }
header() { echo -e "\n${BOLD}=== $1 ===${RESET}"; }

# ---------------------------------------------------------------------------
header "Step 1 — Check GPU"
# ---------------------------------------------------------------------------
if ! command -v nvidia-smi &>/dev/null; then
    fail "nvidia-smi not found. This script requires an NVIDIA GPU instance with drivers installed.
Use an EC2 Deep Learning AMI or install drivers manually."
fi

nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
ok "GPU detected"

# ---------------------------------------------------------------------------
header "Step 2 — Install Ollama"
# ---------------------------------------------------------------------------
if command -v ollama &>/dev/null; then
    ok "Ollama already installed: $(ollama --version)"
else
    info "Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
    ok "Ollama installed: $(ollama --version)"
fi

# Ensure Ollama service is running
if ! systemctl is-active --quiet ollama 2>/dev/null; then
    info "Starting Ollama service..."
    sudo systemctl enable ollama 2>/dev/null || true
    sudo systemctl start ollama 2>/dev/null || ollama serve &>/tmp/ollama.log &
    sleep 3
fi

ok "Ollama service running"

# ---------------------------------------------------------------------------
header "Step 3 — Pull model: $MODEL"
# ---------------------------------------------------------------------------
if ollama list 2>/dev/null | grep -q "^${MODEL}"; then
    ok "Model already present: $MODEL"
else
    info "Pulling $MODEL (this may take a few minutes)..."
    ollama pull "$MODEL"
    ok "Model pulled: $MODEL"
fi

# ---------------------------------------------------------------------------
header "Step 4 — Create Claude model alias"
# ---------------------------------------------------------------------------
# Claude Code sends model names like 'claude-3-5-sonnet-20241022' to the API.
# Creating an alias lets Ollama accept those requests and route to the local model.
info "Creating alias: claude-3-5-sonnet-20241022 → $MODEL"
ollama cp "$MODEL" claude-3-5-sonnet-20241022
ok "Alias created"

# ---------------------------------------------------------------------------
header "Step 5 — Verify"
# ---------------------------------------------------------------------------
info "Sending test prompt to verify GPU inference..."

RESPONSE=$(curl -sf --max-time 120 "http://localhost:$PORT/api/generate" \
    -d "{\"model\":\"$MODEL\",\"prompt\":\"Reply with: ready\",\"stream\":false}" 2>/dev/null || echo "")

if [[ -z "$RESPONSE" ]]; then
    fail "No response from Ollama after 120s. Check: journalctl -u ollama -n 50"
fi

REPLY=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('response','').strip()[:50])")
EVAL_RATE=$(echo "$RESPONSE" | python3 -c "
import json, sys
d = json.load(sys.stdin)
ec = d.get('eval_count', 0)
ed = d.get('eval_duration', 1)
print(f'{ec / ed * 1e9:.0f}')
" 2>/dev/null || echo "?")

ok "Model responded: $REPLY"
ok "Generation speed: ~${EVAL_RATE} tokens/sec"

VRAM_USED=$(nvidia-smi --query-compute-apps=used_memory --format=csv,noheader 2>/dev/null | head -1 | xargs || echo "?")
ok "VRAM in use: ${VRAM_USED}"

# ---------------------------------------------------------------------------
header "Setup complete"
# ---------------------------------------------------------------------------
echo ""
echo "  Model:      $MODEL"
echo "  Serving at: http://localhost:$PORT"
echo "  API:        http://localhost:$PORT/v1 (OpenAI-compatible)"
echo ""
THIS_IP=$(curl -sf http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "<this-instance-public-ip>")

echo "Next step — run these commands on your local machine to open the SSH tunnel:"
echo ""
echo "  export G6E_IP=${THIS_IP}"
echo "  export G6E_KEY=~/.ssh/<your-key>.pem"
echo "  ./scripts/tunnel.sh start"
echo ""
