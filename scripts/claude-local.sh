#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# claude-local.sh — Launch Claude Code against local Qwen 3.5 (llama-server)
#
# Temporarily swaps ~/.claude/settings.json to point at localhost:8131,
# then restores the original Bedrock config on exit.
#
# Usage:
#   ./claude-local.sh              # interactive session
#   ./claude-local.sh -p "prompt"  # print mode
# ---------------------------------------------------------------------------

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
BACKUP_FILE="$HOME/.claude/settings.json.bedrock-backup"

# Restore original settings on exit (even on Ctrl+C)
_restore() {
    if [[ -f "$BACKUP_FILE" ]]; then
        cp "$BACKUP_FILE" "$CLAUDE_SETTINGS"
        rm -f "$BACKUP_FILE"
        echo ""
        echo "[restored] Bedrock settings restored."
    fi
}
trap _restore EXIT INT TERM

# Check tunnel
if ! curl -sf http://localhost:8131/v1/models >/dev/null 2>&1; then
    echo "[error] Qwen not reachable on localhost:8131."
    echo "        Start tunnel: ~/llm-benchmark-lab/scripts/tunnel.sh start"
    exit 1
fi

# Backup current settings
cp "$CLAUDE_SETTINGS" "$BACKUP_FILE"
echo "[swap] Backed up Bedrock settings."

# Write local Qwen settings
cat > "$CLAUDE_SETTINGS" << 'SETTINGS'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:8131",
    "ANTHROPIC_AUTH_TOKEN": "local",
    "ANTHROPIC_MODEL": "unsloth/qwen3.5-35b-a3b",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "unsloth/qwen3.5-35b-a3b",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "unsloth/qwen3.5-35b-a3b",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "unsloth/qwen3.5-35b-a3b",
    "CLAUDE_CODE_SUBAGENT_MODEL": "unsloth/qwen3.5-35b-a3b",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "128000",
    "DISABLE_PROMPT_CACHING": "1",
    "DISABLE_AUTOUPDATER": "1",
    "DISABLE_TELEMETRY": "1",
    "DISABLE_ERROR_REPORTING": "1",
    "DISABLE_NON_ESSENTIAL_MODEL_CALLS": "1"
  },
  "permissions": {
    "allow": [
      "Bash(git *)", "Bash(npm *)", "Bash(npx *)", "Bash(node *)",
      "Bash(python *)", "Bash(python3 *)", "Bash(pip *)", "Bash(pip3 *)",
      "Bash(ls *)", "Bash(cat *)", "Bash(head *)", "Bash(tail *)",
      "Bash(find *)", "Bash(grep *)", "Bash(rg *)", "Bash(mkdir *)",
      "Bash(cp *)", "Bash(mv *)", "Bash(echo *)", "Bash(curl *)",
      "Bash(which *)", "Bash(pwd)", "Bash(wc *)", "Bash(sort *)",
      "Bash(diff *)", "Bash(chmod *)", "Bash(touch *)",
      "Read", "Edit", "Write", "Glob", "Grep"
    ],
    "deny": [
      "Read(./.env)", "Read(./.env.*)", "Read(./secrets/**)"
    ]
  }
}
SETTINGS

echo "[swap] Loaded Qwen 3.5 local settings."
echo "[info] Starting Claude Code → Qwen 3.5 (localhost:8131)"
echo ""

# Launch claude with all args passed through
claude "$@"
