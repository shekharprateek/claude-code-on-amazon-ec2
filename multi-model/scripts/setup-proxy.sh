#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# setup-proxy.sh — Install and start the LiteLLM proxy for Bedrock models
#
# This proxy translates the Anthropic Messages API (Claude Code) to the
# OpenAI Chat Completions API (Bedrock third-party models).
#
# Prerequisites:
#   - Python 3.9+
#   - AWS credentials configured (aws configure / IAM role / SSO)
#   - Bedrock model access enabled in your AWS account
#
# Usage:
#   ./scripts/setup-proxy.sh              # install + start on port 4000
#   ./scripts/setup-proxy.sh --port 8080  # custom port
#   ./scripts/setup-proxy.sh --stop       # stop running proxy
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/config/litellm-config.yaml"
DEFAULT_PORT=4000
PID_FILE="$PROJECT_DIR/.litellm.pid"

usage() {
    echo "Usage: $0 [--port PORT] [--stop] [--status]"
    echo ""
    echo "Options:"
    echo "  --port PORT   Port to run proxy on (default: $DEFAULT_PORT)"
    echo "  --stop        Stop running proxy"
    echo "  --status      Check if proxy is running"
    exit 1
}

PORT=$DEFAULT_PORT
ACTION="start"

while [[ $# -gt 0 ]]; do
    case $1 in
        --port)   PORT="$2"; shift 2 ;;
        --stop)   ACTION="stop"; shift ;;
        --status) ACTION="status"; shift ;;
        -h|--help) usage ;;
        *) echo "[error] Unknown option: $1"; usage ;;
    esac
done

stop_proxy() {
    if [[ -f "$PID_FILE" ]]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            kill "$PID"
            rm -f "$PID_FILE"
            echo "[stopped] LiteLLM proxy (PID $PID)"
        else
            rm -f "$PID_FILE"
            echo "[info] Proxy was not running (stale PID file cleaned)"
        fi
    else
        echo "[info] No proxy running"
    fi
}

check_status() {
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "[running] LiteLLM proxy PID $(cat "$PID_FILE")"
        curl -sf "http://localhost:${PORT}/health" 2>/dev/null && echo " - health: OK" || echo " - health: unreachable"
    else
        echo "[stopped] No proxy running"
    fi
}

start_proxy() {
    # Check prerequisites
    if ! command -v python3 &>/dev/null; then
        echo "[error] Python 3 is required. Install it first."
        exit 1
    fi

    # Check AWS credentials — try AWS CLI first, fall back to boto3 (instance profile)
    if ! aws sts get-caller-identity &>/dev/null 2>&1; then
        if ! python3 -c "import boto3; boto3.client('sts').get_caller_identity()" &>/dev/null 2>&1; then
            echo "[error] AWS credentials not configured."
            echo "        Run: aws configure, or attach an IAM instance profile with Bedrock access."
            exit 1
        fi
        echo "[info] Using IAM instance profile credentials"
    fi

    # Install litellm if not present
    if ! python3 -c "import litellm" 2>/dev/null; then
        echo "[install] Installing litellm[proxy]..."
        python3 -m pip install "litellm[proxy]" --quiet
    fi

    # Stop existing proxy if running
    stop_proxy 2>/dev/null

    echo "[start] LiteLLM proxy on port $PORT"
    echo "[config] $CONFIG_FILE"
    echo ""

    # Start in background
    nohup litellm --config "$CONFIG_FILE" --port "$PORT" > "$PROJECT_DIR/.litellm.log" 2>&1 &
    echo $! > "$PID_FILE"

    # Wait for proxy to be ready
    echo -n "[wait] Proxy starting"
    for i in $(seq 1 15); do
        if curl -sf "http://localhost:${PORT}/health" &>/dev/null; then
            echo ""
            echo "[ready] Proxy running on http://localhost:${PORT}"
            echo "[pid] $(cat "$PID_FILE")"
            echo "[log] $PROJECT_DIR/.litellm.log"
            echo ""
            echo "Available models:"
            curl -s "http://localhost:${PORT}/v1/models" | python3 -c "
import json, sys
data = json.load(sys.stdin).get('data', [])
for m in data:
    print(f'  - {m[\"id\"]}')
" 2>/dev/null || echo "  (could not list models)"
            return 0
        fi
        echo -n "."
        sleep 2
    done

    echo ""
    echo "[error] Proxy did not start in time. Check logs:"
    echo "        tail -f $PROJECT_DIR/.litellm.log"
    exit 1
}

case $ACTION in
    start)  start_proxy ;;
    stop)   stop_proxy ;;
    status) check_status ;;
esac
