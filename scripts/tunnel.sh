#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# tunnel.sh — Manage SSH tunnel to GPU server running Ollama
#
# Usage:
#   ./tunnel.sh start    # Open tunnel (localhost:11434 → ec2:11434)
#   ./tunnel.sh stop     # Close tunnel
#   ./tunnel.sh status   # Check if tunnel is active
# ---------------------------------------------------------------------------

G6E_IP="${G6E_IP:-}"
KEY="${G6E_KEY:-$HOME/.ssh/id_rsa}"
LOCAL_PORT=11434
REMOTE_PORT=11434

if [[ "${1:-status}" == "start" ]] && [[ -z "$G6E_IP" ]]; then
    echo "Error: G6E_IP not set. Export it first:"
    echo "  export G6E_IP=<your-gpu-server-ip>"
    echo "  export G6E_KEY=<path-to-your-key.pem>  # optional, defaults to ~/.ssh/id_rsa"
    exit 1
fi

case "${1:-status}" in
    start)
        if lsof -ti :$LOCAL_PORT >/dev/null 2>&1; then
            echo "Port $LOCAL_PORT already in use. Run './tunnel.sh stop' first."
            exit 1
        fi
        echo "Opening SSH tunnel: localhost:$LOCAL_PORT → $G6E_IP:$REMOTE_PORT"
        ssh -N -f -L $LOCAL_PORT:localhost:$REMOTE_PORT -i "$KEY" ubuntu@"$G6E_IP"
        sleep 2
        if curl -sf http://localhost:$LOCAL_PORT/v1/models >/dev/null 2>&1; then
            echo "Tunnel active. Model reachable at http://localhost:$LOCAL_PORT"
        else
            echo "Tunnel opened but model not responding. Check g6e instance."
        fi
        ;;
    stop)
        PIDS=$(lsof -ti :$LOCAL_PORT 2>/dev/null || echo "")
        if [[ -n "$PIDS" ]]; then
            echo "Killing tunnel (PIDs: $PIDS)"
            echo "$PIDS" | xargs kill 2>/dev/null || true
            echo "Tunnel closed."
        else
            echo "No tunnel running on port $LOCAL_PORT."
        fi
        ;;
    status)
        if curl -sf http://localhost:$LOCAL_PORT/v1/models >/dev/null 2>&1; then
            echo "Tunnel active. Model responding on localhost:$LOCAL_PORT"
            curl -s http://localhost:$LOCAL_PORT/v1/models | python3 -c "
import json, sys
data = json.load(sys.stdin)
models = data.get('data', [])
for m in models:
    print(f\"  Model: {m.get('id', 'unknown')}\")
"
        else
            echo "No tunnel or model not responding on localhost:$LOCAL_PORT"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|status}"
        exit 1
        ;;
esac
