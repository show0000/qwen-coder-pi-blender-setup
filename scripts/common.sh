#!/usr/bin/env bash
# Shared helpers. Source this from the other scripts.

set -euo pipefail

# --- user-tunable defaults (override via env) -------------------------------
export HF_REPO="${HF_REPO:-lmstudio-community/Qwen3-Coder-Next-MLX-4bit}"
export MODEL_ID="${MODEL_ID:-qwen3-coder-next}"             # id used by server + pi
export LMSTUDIO_MODELS_DIR="${LMSTUDIO_MODELS_DIR:-$HOME/.lmstudio/models}"
export MODEL_DIR="${MODEL_DIR:-$LMSTUDIO_MODELS_DIR/$HF_REPO}"
export BACKEND="${BACKEND:-lmstudio}"                      # lmstudio | mlx
export CTX="${CTX:-131072}"
export MAX_TOKENS="${MAX_TOKENS:-32768}"
export PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"

case "$BACKEND" in
  lmstudio) export PORT="${PORT:-1234}" ;;
  mlx)      export PORT="${PORT:-8080}" ;;
  *) echo "BACKEND must be lmstudio or mlx (got: $BACKEND)" >&2; exit 1 ;;
esac
export BASE_URL="http://127.0.0.1:${PORT}/v1"

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
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$HOME/.lmstudio/bin:$HOME/.pi/bin:$PATH"

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
