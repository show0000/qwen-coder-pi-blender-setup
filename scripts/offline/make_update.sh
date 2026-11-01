#!/usr/bin/env bash
# ONLINE Mac: build a single update.tgz for an offline Mac that already ran install_offline.sh.
# Contains: current scripts/config/pi-config/templates/docs + enterprise MCP packages
# (mcp-atlassian wheels, @zereight/mcp-gitlab npm prefix). Model weights are NOT included;
# add --with-vision to also pack the Qwen3.8-27B VL weights (~22GB).
#
#   ./scripts/offline/make_update.sh [out-dir]      (default ~/Downloads)  -> <out-dir>/update.tgz
#   ./scripts/offline/make_update.sh --with-vision
#   ./scripts/offline/make_update.sh --with-nvim [--with-ai]   # snapshot this Mac's Neovim (+ local-AI plugins)
set -euo pipefail
source "$(dirname "$0")/../common.sh"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$HOME/Downloads"; WITH_VISION=0; WITH_NVIM=0; WITH_AI=""
for a in "$@"; do case "$a" in --with-vision) WITH_VISION=1 ;; --with-nvim) WITH_NVIM=1 ;; --with-ai) WITH_AI="--with-ai" ;; *) OUT="$a" ;; esac; done
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
W="$OUT/update"; rm -rf "$W"; mkdir -p "$W"/{repo,wheels,npm}

info "1/4 저장소 파일"
tar -C "$REPO_ROOT" --exclude .git --exclude bundle --exclude '*.gguf' -cf - scripts config pi-config templates docs README.md Makefile | tar -C "$W/repo" -xf -

info "2/4 mcp-atlassian wheels"
if command -v uv >/dev/null 2>&1; then
  uv tool run --from pip python -m pip download -q -d "$W/wheels" --only-binary=:all: mcp-atlassian \
    || uv tool run --from pip python -m pip download -q -d "$W/wheels" --prefer-binary mcp-atlassian
else
  python3 -m pip download -q -d "$W/wheels" --only-binary=:all: mcp-atlassian
fi

info "3/4 @zereight/mcp-gitlab (npm prefix)"
command -v npm >/dev/null 2>&1 || fail "npm 이 없습니다 (node 설치 필요)"
npm_config_prefix="$W/npm/gl-prefix" npm install -g --ignore-scripts --no-fund --no-audit @zereight/mcp-gitlab >/dev/null
tar -C "$W/npm" -czf "$W/npm/mcp-gitlab-prefix.tgz" gl-prefix && rm -rf "$W/npm/gl-prefix"

info "3a/4 orca 바이너리 (있으면)"
mkdir -p "$W/bin"
if command -v orca >/dev/null 2>&1 && orca --help 2>&1 | grep -qE 'agent launch|agent-context'; then echo "  Orca 데스크톱 앱 CLI 감지 — 앱과 함께 설치되는 것이므로 번들에 넣지 않음"
elif command -v orca >/dev/null 2>&1; then cp "$(command -v orca)" "$W/bin/orca"; echo "  ok: $(orca version 2>/dev/null || orca --version 2>/dev/null | head -1)"
elif command -v go >/dev/null 2>&1; then GOBIN="$W/bin" GOFLAGS=-trimpath go install github.com/orca-cli/orca/cmd/orca@latest && echo "  ok: go install"
elif command -v brew >/dev/null 2>&1; then brew install orca-cli/tap/orca >/dev/null 2>&1 && cp "$(command -v orca)" "$W/bin/orca" && echo "  ok: brew" || warn "  orca 설치 실패 (선택 항목)"
else warn "  orca 없음: 이 Mac 에 brew/go 가 없어 건너뜀"; fi

if [[ "$WITH_VISION" == "1" ]]; then
  info "3b/4 비전 모델 ($VISION_HF_REPO $VISION_QUANT + $VISION_MMPROJ, ~22GB)"
  mkdir -p "$W/models/vision"
  B="https://huggingface.co/$VISION_HF_REPO/resolve/main"
  for f in "Qwen3.8-27B-${VISION_QUANT}.gguf" "$VISION_MMPROJ"; do
    curl -fL -C - --retry 20 --progress-bar -o "$W/models/vision/$f" "$B/$f"
  done
fi

if [[ "$WITH_NVIM" == "1" ]]; then
  info "3c/4 Neovim 스냅샷"
  "$(dirname "$0")/make_nvim_bundle.sh" "$W" $WITH_AI
fi

info "4/4 묶는 중"
date -u +%FT%TZ > "$W/VERSION"; (cd "$REPO_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo nogit) >> "$W/VERSION"
tar -C "$OUT" -czf "$OUT/update.tgz" update && rm -rf "$W"
info "완료: $OUT/update.tgz ($(du -sh "$OUT/update.tgz" | cut -f1))"
cat <<EOF

HTTP 로 넘기기:   cd "$OUT" && python3 -m http.server 8000
오프라인 Mac:     curl -C - -o ~/update.tgz http://<이 Mac IP>:8000/update.tgz
                  tar -xzf ~/update.tgz -C ~ && ~/update/repo/scripts/offline/apply_update.sh ~/update
EOF
