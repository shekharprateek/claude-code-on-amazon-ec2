#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# bench.sh — Benchmark Claude Code: Bedrock (Claude) vs self-hosted Qwen 3.5
#
# Usage:
#   ./bench.sh bedrock       # Test A: Claude via Amazon Bedrock
#   ./bench.sh qwen          # Test B: Qwen 3.5 via SSH tunnel (localhost:8131)
#   ./bench.sh both          # Run both back-to-back
#
# Prerequisites:
#   - Claude Code CLI installed
#   - For "bedrock": AWS credentials configured (profile or env vars)
#   - For "qwen": SSH tunnel active (ssh -N -L 8131:localhost:8131 ...)
#   - Run from any directory (uses ~/AI-registry as test repo)
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$PROJECT_DIR/results"
REPO_DIR="$HOME/AI-registry"
RUNS=3  # repetitions per task

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

info()   { echo -e "${BLUE}[info]${RESET}  $1"; }
ok()     { echo -e "${GREEN}[ok]${RESET}    $1"; }
warn()   { echo -e "${YELLOW}[warn]${RESET}  $1"; }
fail()   { echo -e "${RED}[fail]${RESET}  $1"; exit 1; }
header() { echo -e "\n${BOLD}═══ $1 ═══${RESET}"; }

# ---------------------------------------------------------------------------
# Tasks — same prompts for both backends
# ---------------------------------------------------------------------------
declare -a TASK_NAMES
declare -a TASK_PROMPTS

# Tier 1 — Simple (single tool call expected)
TASK_NAMES+=("t1_explain_function")
TASK_PROMPTS+=("Read registry/core/telemetry.py and explain what the _build_payload function does. Be concise.")

TASK_NAMES+=("t1_find_fastapi_imports")
TASK_PROMPTS+=("Find all Python files that import FastAPI. List just the file paths.")

TASK_NAMES+=("t1_health_endpoint")
TASK_PROMPTS+=("What does the /health endpoint return? Show me the code.")

# Tier 2 — Medium (multi-step, 3-5 tool calls expected)
TASK_NAMES+=("t2_documentdb_flow")
TASK_PROMPTS+=("Find where DOCUMENTDB_HOST is used and explain the database connection flow. Trace it from config to actual connection.")

TASK_NAMES+=("t2_list_api_routes")
TASK_PROMPTS+=("List all API routes in the registry, their HTTP methods, and which file defines them. Output as a table.")

TASK_NAMES+=("t2_find_long_functions")
TASK_PROMPTS+=("Find any Python functions longer than 50 lines in the registry/ directory. List them with file path, function name, and line count.")

# Tier 3 — Complex (agentic, 10+ tool calls expected)
TASK_NAMES+=("t3_telemetry_tests")
TASK_PROMPTS+=("Read registry/core/telemetry.py, understand it fully, then write a comprehensive pytest test file for it. Include tests for _build_payload, opt-in/opt-out logic, and error handling. Output the complete test file.")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
_setup_backend() {
    local backend="$1"
    if [[ "$backend" == "qwen" ]]; then
        # Verify tunnel is active
        if ! curl -sf http://localhost:8131/v1/models >/dev/null 2>&1; then
            fail "SSH tunnel not active. Run: ./tunnel.sh start"
        fi
        # Clear Bedrock settings
        unset CLAUDE_CODE_USE_BEDROCK 2>/dev/null || true
        unset AWS_PROFILE 2>/dev/null || true
        unset AWS_REGION 2>/dev/null || true
        # Set Qwen/llama.cpp backend
        export ANTHROPIC_BASE_URL="http://127.0.0.1:8131"
        export ANTHROPIC_AUTH_TOKEN="local"
        export ANTHROPIC_MODEL="unsloth/Qwen3.5-35B-A3B-GGUF:Q4_K_M"
        unset ANTHROPIC_API_KEY 2>/dev/null || true
        info "Backend: Qwen 3.5-35B via localhost:8131"
    elif [[ "$backend" == "bedrock" ]]; then
        # Clear Qwen/local settings
        unset ANTHROPIC_BASE_URL 2>/dev/null || true
        unset ANTHROPIC_AUTH_TOKEN 2>/dev/null || true
        unset ANTHROPIC_MODEL 2>/dev/null || true
        unset ANTHROPIC_API_KEY 2>/dev/null || true
        # Set Bedrock
        export CLAUDE_CODE_USE_BEDROCK=1
        # AWS credentials should already be configured (profile, env vars, or instance role)
        if ! aws sts get-caller-identity >/dev/null 2>&1; then
            fail "AWS credentials not configured. Check AWS_PROFILE or credentials."
        fi
        local identity
        identity=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null)
        info "Backend: Amazon Bedrock (Claude) — $identity"
    else
        fail "Unknown backend: $backend. Use 'bedrock' or 'qwen'."
    fi
}

_run_task() {
    local backend="$1"
    local task_name="$2"
    local prompt="$3"
    local run_num="$4"
    local output_dir="$RESULTS_DIR/${backend}/${task_name}"
    mkdir -p "$output_dir"

    local output_file="$output_dir/run_${run_num}.json"
    local timing_file="$output_dir/run_${run_num}.timing"
    local text_file="$output_dir/run_${run_num}.txt"

    # Reset repo state
    cd "$REPO_DIR"
    git checkout . 2>/dev/null || true

    info "  Run $run_num/$RUNS — $task_name"

    # Capture wall-clock time and output
    local start_time
    start_time=$(python3 -c "import time; print(time.time())")

    # Run claude in print mode
    local exit_code=0
    if [[ "$backend" == "qwen" ]]; then
        ANTHROPIC_BASE_URL="http://127.0.0.1:8131" \
        ANTHROPIC_AUTH_TOKEN="local" \
        ANTHROPIC_MODEL="unsloth/Qwen3.5-35B-A3B-GGUF:Q4_K_M" \
        claude -p "$prompt" \
            --output-format json \
            --no-session-persistence \
            > "$output_file" 2>"$output_dir/run_${run_num}.stderr" || exit_code=$?
    elif [[ "$backend" == "bedrock" ]]; then
        CLAUDE_CODE_USE_BEDROCK=1 \
        claude -p "$prompt" \
            --output-format json \
            --no-session-persistence \
            > "$output_file" 2>"$output_dir/run_${run_num}.stderr" || exit_code=$?
    fi

    local end_time
    end_time=$(python3 -c "import time; print(time.time())")

    local elapsed
    elapsed=$(python3 -c "print(round($end_time - $start_time, 2))")

    # Save timing
    cat > "$timing_file" << TIMING_EOF
{
    "backend": "$backend",
    "task": "$task_name",
    "run": $run_num,
    "wall_clock_seconds": $elapsed,
    "exit_code": $exit_code,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
TIMING_EOF

    # Extract text from JSON output
    if [[ -s "$output_file" ]]; then
        python3 -c "
import json, sys
try:
    data = json.load(open('$output_file'))
    if isinstance(data, dict):
        print(data.get('result', data.get('content', json.dumps(data, indent=2))))
    elif isinstance(data, list):
        for item in data:
            if isinstance(item, dict) and item.get('type') == 'text':
                print(item.get('text', ''))
    else:
        print(data)
except:
    sys.stdout.write(open('$output_file').read())
" > "$text_file" 2>/dev/null
    fi

    # Status line
    if [[ $exit_code -eq 0 ]]; then
        ok "  ${elapsed}s — $task_name (run $run_num)"
    else
        warn "  ${elapsed}s — $task_name (run $run_num) [exit: $exit_code]"
    fi
}

# ---------------------------------------------------------------------------
# Summary generator
# ---------------------------------------------------------------------------
_generate_summary() {
    local backend="$1"
    header "Summary: $backend"

    printf "%-30s %10s %10s %10s %8s\n" "Task" "Run 1 (s)" "Run 2 (s)" "Run 3 (s)" "Avg (s)"
    printf "%-30s %10s %10s %10s %8s\n" "-----" "--------" "--------" "--------" "------"

    for task_name in "${TASK_NAMES[@]}"; do
        local times=()
        for run in $(seq 1 $RUNS); do
            local tf="$RESULTS_DIR/${backend}/${task_name}/run_${run}.timing"
            if [[ -f "$tf" ]]; then
                local t
                t=$(python3 -c "import json; print(json.load(open('$tf'))['wall_clock_seconds'])")
                times+=("$t")
            else
                times+=("-")
            fi
        done

        local avg="-"
        if [[ ${#times[@]} -eq $RUNS ]]; then
            avg=$(python3 -c "
vals = [float(x) for x in '${times[*]}'.split() if x != '-']
print(round(sum(vals)/len(vals), 2)) if vals else print('-')
")
        fi

        printf "%-30s %10s %10s %10s %8s\n" "$task_name" "${times[0]:-'-'}" "${times[1]:-'-'}" "${times[2]:-'-'}" "$avg"
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local mode="${1:-}"

    if [[ -z "$mode" ]]; then
        echo "Usage: $0 {bedrock|qwen|both}"
        echo ""
        echo "  bedrock    — Run benchmarks against Amazon Bedrock (Claude)"
        echo "  qwen       — Run benchmarks against Qwen 3.5 via SSH tunnel"
        echo "  both       — Run both, back-to-back"
        echo ""
        echo "Prerequisites:"
        echo "  - Run from any directory (uses ~/AI-registry as test repo)"
        echo "  - For 'qwen': SSH tunnel must be active on localhost:8131"
        echo "  - For 'bedrock': AWS credentials must be configured"
        exit 1
    fi

    # Ensure we're not inside a Claude Code session
    if [[ -n "${CLAUDECODE:-}" ]]; then
        fail "Cannot run inside a Claude Code session. Open a new terminal."
    fi

    header "LLM Benchmark Lab"
    info "Results directory: $RESULTS_DIR"
    info "Test repo: $REPO_DIR"
    info "Tasks: ${#TASK_NAMES[@]}"
    info "Runs per task: $RUNS"

    local backends=()
    if [[ "$mode" == "both" ]]; then
        backends=("bedrock" "qwen")
    else
        backends=("$mode")
    fi

    for backend in "${backends[@]}"; do
        header "Backend: $backend"
        _setup_backend "$backend"

        for i in "${!TASK_NAMES[@]}"; do
            local task_name="${TASK_NAMES[$i]}"
            local prompt="${TASK_PROMPTS[$i]}"

            header "Task: $task_name"
            for run in $(seq 1 $RUNS); do
                _run_task "$backend" "$task_name" "$prompt" "$run"
            done
        done

        _generate_summary "$backend"
    done

    # If both were run, generate comparison
    if [[ "$mode" == "both" ]]; then
        header "Comparison: Bedrock vs Qwen"

        printf "%-30s %12s %12s %10s\n" "Task" "Bedrock(s)" "Qwen(s)" "Ratio"
        printf "%-30s %12s %12s %10s\n" "-----" "--------" "-------" "-----"

        for task_name in "${TASK_NAMES[@]}"; do
            local avg_a avg_q
            avg_a=$(python3 -c "
import json, glob
files = glob.glob('$RESULTS_DIR/bedrock/$task_name/run_*.timing')
vals = [json.load(open(f))['wall_clock_seconds'] for f in files]
print(round(sum(vals)/len(vals), 2)) if vals else print(0)
")
            avg_q=$(python3 -c "
import json, glob
files = glob.glob('$RESULTS_DIR/qwen/$task_name/run_*.timing')
vals = [json.load(open(f))['wall_clock_seconds'] for f in files]
print(round(sum(vals)/len(vals), 2)) if vals else print(0)
")
            local ratio
            ratio=$(python3 -c "
a, q = $avg_a, $avg_q
print(f'{q/a:.1f}x' if a > 0 and q > 0 else '-')
")
            printf "%-30s %12s %12s %10s\n" "$task_name" "$avg_a" "$avg_q" "$ratio"
        done
    fi

    header "Done"
    info "Results saved to: $RESULTS_DIR"
    info "Review output quality: ls $RESULTS_DIR/{bedrock,qwen}/*/run_*.txt"
}

main "$@"
