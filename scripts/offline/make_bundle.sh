#!/usr/bin/env bash
# Build an offline install bundle on an INTERNET-CONNECTED Apple Silicon Mac.
# Everything except model weights goes into one folder you can copy via USB.
#
#   ./scripts/offline/make_bundle.sh [bundle-dir]        (default: ./bundle)
#   ./scripts/offline/make_bundle.sh --with-model        also download the GGUF (uses QUANT/HF_REPO)
#
# No Homebrew needed: fetches release binaries directly (nodejs.org, GitHub releases, PyPI).
# Pin versions with env: NODE_VERSION=v22.x.y  LLAMA_TAG=bNNNN  PY_VERSION=3.12
set -euo pipefail
source "$(dirname "$0")/../common.sh"
[[ "$(uname -s)/$(uname -m)" == "Darwin/arm64" ]] || fail "Apple Silicon Mac 에서 실행하세요 (대상 머신과 같은 아키텍처여야 npm/uv 패키지가 호환됩니다)."

WITH_MODEL=0
for a in "$@"; do [[ "$a" == "--with-model" ]] && WITH_MODEL=1; done
B="${1:-./bundle}"; [[ "$B" == --* ]] && B=./bundle
B="$(mkdir -p "$B" && cd "$B" && pwd)"
PY_VERSION="${PY_VERSION:-3.12}"
mkdir -p "$B"/{bin,node,pi,python,wheels,llama,repo}

dl() { # dl <url> <dest>
  info "GET $1"; curl -fL --retry 3 --progress-bar -o "$2" "$1"
}

# ---- 1. Node.js (pi runtime) -------------------------------------------------
if [[ -z "${NODE_VERSION:-}" ]]; then
  NODE_VERSION=$(curl -fsSL https://nodejs.org/dist/index.json | python3 -c 'import json,sys;print([x["version"] for x in json.load(sys.stdin) if x["version"].startswith("v22.")][0])')
fi
NODE_TGZ="node-${NODE_VERSION}-darwin-arm64.tar.gz"
[[ -f "$B/node/$NODE_TGZ" ]] || dl "https://nodejs.org/dist/${NODE_VERSION}/${NODE_TGZ}" "$B/node/$NODE_TGZ"
NODE_TMP="$B/.node"; rm -rf "$NODE_TMP"; mkdir -p "$NODE_TMP"
tar -xzf "$B/node/$NODE_TGZ" -C "$NODE_TMP" --strip-components 1
export PATH="$NODE_TMP/bin:$PATH"
info "node $(node -v) / npm $(npm -v)"

# ---- 2. pi coding agent as a relocatable npm prefix ---------------------------
info "pi (npm global prefix) 설치"
rm -rf "$B/pi/prefix"; mkdir -p "$B/pi/prefix"
npm_config_prefix="$B/pi/prefix" npm install -g --ignore-scripts --no-fund --no-audit @earendil-works/pi-coding-agent >/dev/null
PI_VERSION=$("$B/pi/prefix/bin/pi" --version 2>/dev/null || echo unknown)
# make the shebangs/symlinks relative-safe: ship as tarball
tar -C "$B/pi" -czf "$B/pi/pi-prefix.tgz" prefix && rm -rf "$B/pi/prefix"
info "pi $PI_VERSION"

# ---- 2b. GitLab MCP (npm) as a relocatable prefix --------------------------------
info "mcp-gitlab (npm prefix) 설치"
rm -rf "$B/pi/gl-prefix"; mkdir -p "$B/pi/gl-prefix"
npm_config_prefix="$B/pi/gl-prefix" npm install -g --ignore-scripts --no-fund --no-audit @zereight/mcp-gitlab >/dev/null \
  && tar -C "$B/pi" -czf "$B/pi/mcp-gitlab-prefix.tgz" gl-prefix || warn "mcp-gitlab 설치 실패 (선택 항목)"
rm -rf "$B/pi/gl-prefix"

# ---- 3. uv + managed Python --------------------------------------------------
UV_TGZ="uv-aarch64-apple-darwin.tar.gz"
[[ -f "$B/bin/$UV_TGZ" ]] || dl "https://github.com/astral-sh/uv/releases/latest/download/$UV_TGZ" "$B/bin/$UV_TGZ"
tar -xzf "$B/bin/$UV_TGZ" -C "$B/bin" --strip-components 1 uv-aarch64-apple-darwin/uv uv-aarch64-apple-darwin/uvx 2>/dev/null || tar -xzf "$B/bin/$UV_TGZ" -C "$B/bin" --strip-components 1
chmod +x "$B/bin/uv" "$B/bin/uvx" 2>/dev/null || true
UV_VERSION=$("$B/bin/uv" --version)
info "$UV_VERSION"
info "Python $PY_VERSION (uv managed) 다운로드"
UV_PYTHON_INSTALL_DIR="$B/python" "$B/bin/uv" python install "$PY_VERSION" >/dev/null
PY_BIN=$(UV_PYTHON_INSTALL_DIR="$B/python" "$B/bin/uv" python find "$PY_VERSION")

# ---- 4. Python wheels (MCP servers + hf CLI) ---------------------------------
info "wheelhouse 작성 (mcp-for-blender, orcaslicer-mcp, huggingface_hub)"
VENV="$B/.venv"; rm -rf "$VENV"
UV_PYTHON_INSTALL_DIR="$B/python" "$B/bin/uv" venv -q --python "$PY_BIN" "$VENV"
UV_PYTHON_INSTALL_DIR="$B/python" "$B/bin/uv" pip install -q --python "$VENV/bin/python" pip
PKGS=(mcp-for-blender orcaslicer-mcp mcp-atlassian "huggingface_hub[cli,hf_xet]")
[[ "${WITH_MLX:-0}" == "1" ]] && PKGS+=(mlx-lm)
"$VENV/bin/python" -m pip download -q -d "$B/wheels" --only-binary=:all: "${PKGS[@]}" \
  || "$VENV/bin/python" -m pip download -q -d "$B/wheels" --prefer-binary "${PKGS[@]}" setuptools wheel hatchling
# resolve entry-point names so the offline installer doesn't have to guess
BLENDER_EP=$(unzip -p "$B"/wheels/mcp_for_blender-*.whl '*/entry_points.txt' | awk -F= '/^[a-zA-Z0-9_-]+ *=/{gsub(/ /,"",$1); print $1; exit}')
ORCASLICER_EP=$(unzip -p "$B"/wheels/orcaslicer_mcp-*.whl '*/entry_points.txt' | awk -F= '/^[a-zA-Z0-9_-]+ *=/{gsub(/ /,"",$1); print $1; exit}')
info "entry points: blender=$BLENDER_EP orcaslicer=$ORCASLICER_EP"

# ---- 5. llama.cpp prebuilt (Metal) -------------------------------------------
if [[ -z "${LLAMA_TAG:-}" ]]; then
  LLAMA_TAG=$(curl -fsSL https://github.com/ggml-org/llama.cpp/releases/latest/download/nightly-tag.txt | tr -d '[:space:]')
fi
LLAMA_TGZ="llama-${LLAMA_TAG}-bin-macos-arm64.tar.gz"
[[ -f "$B/llama/$LLAMA_TGZ" ]] || dl "https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_TAG}/${LLAMA_TGZ}" "$B/llama/$LLAMA_TGZ"

# ---- 6. jq, orca ---------------------------------------------------------------
[[ -f "$B/bin/jq" ]] || dl "https://github.com/jqlang/jq/releases/latest/download/jq-macos-arm64" "$B/bin/jq"; chmod +x "$B/bin/jq"
if command -v orca >/dev/null 2>&1; then
  cp "$(command -v orca)" "$B/bin/orca"; info "orca: 로컬 바이너리 복사"
elif command -v go >/dev/null 2>&1; then
  info "orca: go install 로 빌드"; GOBIN="$B/bin" GOFLAGS=-trimpath go install github.com/orca-cli/orca/cmd/orca@latest || warn "orca 빌드 실패 (선택 항목)"
else
  warn "orca 생략: 이 머신에 orca 도 go 도 없습니다. 필요하면 brew install orca-cli/tap/orca 후 다시 실행하세요."
fi

# ---- 7. this repo + manifest --------------------------------------------------
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
rm -rf "$B/repo"; mkdir -p "$B/repo"
tar -C "$REPO_ROOT" --exclude .git --exclude bundle --exclude '*.gguf' -cf - . | tar -C "$B/repo" -xf -
cat > "$B/manifest.env" <<EOF
BUNDLE_CREATED="$(date -u +%FT%TZ)"
NODE_VERSION="$NODE_VERSION"
NODE_TGZ="$NODE_TGZ"
PI_VERSION="$PI_VERSION"
UV_VERSION="$UV_VERSION"
PY_VERSION="$PY_VERSION"
LLAMA_TAG="$LLAMA_TAG"
LLAMA_TGZ="$LLAMA_TGZ"
BLENDER_EP="$BLENDER_EP"
ORCASLICER_EP="$ORCASLICER_EP"
HF_REPO="$HF_REPO"
QUANT="$QUANT"
VISION_QUANT="$VISION_QUANT"
EOF

# ---- 8. optional: model --------------------------------------------------------
if [[ "$WITH_MODEL" == "1" ]]; then
  info "모델 다운로드 → $B/models/$HF_REPO"
  mkdir -p "$B/models/$HF_REPO"
  UV_PYTHON_INSTALL_DIR="$B/python" "$B/bin/uv" tool run --python "$PY_BIN" --from "huggingface_hub[cli,hf_xet]" hf download "$HF_REPO" --local-dir "$B/models/$HF_REPO" ${QUANT:+--include "*${QUANT}*"}
fi

if [[ "${WITH_VISION:-0}" == "1" ]]; then
  info "비전 모델 다운로드 → $B/models/$VISION_HF_REPO"
  mkdir -p "$B/models/$VISION_HF_REPO"
  UV_PYTHON_INSTALL_DIR="$B/python" "$B/bin/uv" tool run --python "$PY_BIN" --from "huggingface_hub[cli,hf_xet]" hf download "$VISION_HF_REPO" --local-dir "$B/models/$VISION_HF_REPO" --include "*${VISION_QUANT}*" --include "$VISION_MMPROJ"
fi

# pack the uv python dir: it contains symlinks, which exFAT/FAT32 USB sticks cannot store
tar -C "$B" -czf "$B/python.tgz" python && rm -rf "$B/python"
rm -rf "$NODE_TMP" "$VENV"
info "번들 완료: $B  ($(du -sh "$B" | cut -f1))"
if [[ "${NO_TGZ:-0}" != "1" ]]; then
  info "한 파일로 묶는 중: $(dirname "$B")/$(basename "$B").tgz  (USB/HTTP 전송용)"
  tar -C "$(dirname "$B")" -czf "$(dirname "$B")/$(basename "$B").tgz" "$(basename "$B")"
fi
cat <<EOF

대상(오프라인) Mac 에서:
  cp -r "$B" ~/qwen-bundle           # USB 등으로 복사
  ~/qwen-bundle/repo/scripts/offline/install_offline.sh ~/qwen-bundle [MODEL_SRC_DIR]
EOF
