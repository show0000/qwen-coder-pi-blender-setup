#!/usr/bin/env bash
# Shared helpers. Source this from the other scripts.

set -euo pipefail

# --- user-tunable defaults (override via env) -------------------------------
# Backend: both are plain CLI tools, no GUI app.
#   llama  (default) : llama.cpp llama-server (brew), GGUF weights, pi-supported, robust tool-call parsing
#   mlx              : mlx-lm server (uv tool), MLX safetensors weights
export BACKEND="${BACKEND:-llama}"
export MODEL_ID="${MODEL_ID:-qwen3-coder-next}"             # id used by server alias + pi
export MODELS_ROOT="${MODELS_ROOT:-$HOME/models}"
export CTX="${CTX:-262144}"                                # native max for Qwen3-Coder-Next; KV cache ~6GB at full
export MAX_TOKENS="${MAX_TOKENS:-32768}"
export PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
export PORT="${PORT:-8080}"
export OFFLINE="${OFFLINE:-0}"                              # 1 = installed via scripts/offline/, no network tools

# How to launch the MCP servers. Online: uvx fetches on demand. Offline: absolute entry points
# installed by install_offline.sh (exported from ~/.config/qwen-coder/env.sh).
mcp_cmd_json() { # mcp_cmd_json <blender|orcaslicer> -> '"command": "...", "args": [...]'
  local pkg="$1" cmd
  case "$pkg" in
    blender)    cmd="${BLENDER_MCP_CMD:-}";    [[ -z "$cmd" && "$OFFLINE" == "0" ]] && { printf '"command": "uvx", "args": ["mcp-for-blender"]'; return; } ;;
    orcaslicer) cmd="${ORCASLICER_MCP_CMD:-}"; [[ -z "$cmd" && "$OFFLINE" == "0" ]] && { printf '"command": "uvx", "args": ["orcaslicer-mcp"]'; return; } ;;
  esac
  [[ -n "$cmd" && -x "$cmd" ]] || { echo "오프라인 모드인데 ${pkg} MCP 실행 파일을 모릅니다 (BLENDER_MCP_CMD / ORCASLICER_MCP_CMD). install_offline.sh 를 다시 실행하세요." >&2; exit 1; }
  printf '"command": "%s", "args": []' "$cmd"
}

case "$BACKEND" in
  llama)
    export HF_REPO="${HF_REPO:-unsloth/Qwen3-Coder-Next-GGUF}"
    export QUANT="${QUANT:-UD-Q6_K_XL}"                      # ~68GB. UD-Q4_K_XL (~50GB, faster) / Q8_0 (~85GB) also fit in 128GB
    ;;
  mlx)
    export HF_REPO="${HF_REPO:-mlx-community/Qwen3-Coder-Next-6bit}"
    export QUANT=""
    ;;
  *) echo "BACKEND must be llama or mlx (got: $BACKEND)" >&2; exit 1 ;;
esac
export MODEL_DIR="${MODEL_DIR:-$MODELS_ROOT/$HF_REPO}"

# Optional second model: Qwen3.8-27B (vision-language, dense) as "eyes" for viewport screenshots.
# Served by a second llama-server on VISION_PORT, registered in pi as provider "local-vision".
export VISION_HF_REPO="${VISION_HF_REPO:-unsloth/Qwen3.8-27B-GGUF}"
export VISION_QUANT="${VISION_QUANT:-UD-Q5_K_XL}"            # ~21GB. UD-Q6_K_XL ~25GB, UD-Q4_K_XL ~18GB
export VISION_MMPROJ="${VISION_MMPROJ:-mmproj-F16.gguf}"
export VISION_MODEL_ID="${VISION_MODEL_ID:-qwen3.8-27b-vl}"
export VISION_PORT="${VISION_PORT:-8081}"
export VISION_CTX="${VISION_CTX:-32768}"
export VISION_MODEL_DIR="${VISION_MODEL_DIR:-$MODELS_ROOT/$VISION_HF_REPO}"
export VISION_BASE_URL="http://127.0.0.1:${VISION_PORT}/v1"
export VISION_LOG="${VISION_LOG:-$HOME/.local/state/qwen-coder/vision.log}"
export VISION_PID="${VISION_PID:-$HOME/.local/state/qwen-coder/vision.pid}"
vision_gguf() { find "$VISION_MODEL_DIR" -type f -name "*${VISION_QUANT}*.gguf" ! -name "mmproj*" 2>/dev/null | sort | head -1; }
vision_mmproj() { find "$VISION_MODEL_DIR" -type f -name "$VISION_MMPROJ" 2>/dev/null | head -1; }
export BASE_URL="http://127.0.0.1:${PORT}/v1"
export SERVER_LOG="${SERVER_LOG:-$HOME/.local/state/qwen-coder/server.log}"
export SERVER_PID="${SERVER_PID:-$HOME/.local/state/qwen-coder/server.pid}"

# first GGUF shard for the chosen quant (unsloth stores big quants in a subfolder, split into -00001-of-N)
gguf_main_file() {
  local f
  f=$(find "$MODEL_DIR" -type f -name "*${QUANT}*00001-of-*.gguf" 2>/dev/null | head -1)
  [[ -n "$f" ]] || f=$(find "$MODEL_DIR" -type f -name "*${QUANT}*.gguf" 2>/dev/null | head -1)
  printf '%s' "$f"
}

# --- output helpers ---------------------------------------------------------
c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_reset=$'\033[0m'
info()  { printf '%s[info]%s %s\n'  "$c_green"  "$c_reset" "$*"; }
warn()  { printf '%s[warn]%s %s\n'  "$c_yellow" "$c_reset" "$*"; }
fail()  { printf '%s[fail]%s %s\n'  "$c_red"    "$c_reset" "$*" >&2; exit 1; }
have()  { command -v "$1" >/dev/null 2>&1; }

require_macos_arm() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "macOS 전용 스크립트입니다."
  [[ "$(uname -m)" == "arm64" ]]  || fail "Apple Silicon(arm64) 전용입니다."
}

# Make Homebrew + uv tool bins visible in this shell
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$HOME/.pi/bin:$PATH"

# merge_json <target-file> <python-expr-producing-dict> : deep-merge into JSON file
merge_json() {
  local target="$1" patch="$2"
  mkdir -p "$(dirname "$target")"
  python3 - "$target" "$patch" <<'PY'
import json, sys, pathlib
target = pathlib.Path(sys.argv[1]); patch = json.loads(sys.argv[2])
data = {}
if target.exists() and target.read_text().strip():
    data = json.loads(target.read_text())
def merge(a, b):
    for k, v in b.items():
        if isinstance(v, dict) and isinstance(a.get(k), dict):
            merge(a[k], v)
        elif k == "models" and isinstance(v, list) and isinstance(a.get(k), list):
            ids = {m.get("id") for m in v}
            a[k] = [m for m in a[k] if m.get("id") not in ids] + v
        else:
            a[k] = v
    return a
merge(data, patch)
target.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
print(f"updated {target}")
PY
}
