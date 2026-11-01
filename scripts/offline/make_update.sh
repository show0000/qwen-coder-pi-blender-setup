#!/usr/bin/env bash
# ONLINE Mac: build a single update.tgz for an offline Mac that already ran install_offline.sh.
# Contains: current scripts/config/pi-config/templates/docs + enterprise MCP packages
# (mcp-atlassian wheels, @zereight/mcp-gitlab npm prefix). Model weights are NOT included;
# add --with-vision to also pack the Qwen3.8-27B VL weights (~22GB).
#
#   ./scripts/offline/make_update.sh [out-dir]      (default ~/Downloads)  -> <out-dir>/update.tgz
#   ./scripts/offline/make_update.sh --with-vision
set -euo pipefail
source "$(dirname "$0")/../common.sh"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$HOME/Downloads"; WITH_VISION=0
for a in "$@"; do case "$a" in --with-vision) WITH_VISION=1 ;; *) OUT="$a" ;; esac; done
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

if [[ "$WITH_VISION" == "1" ]]; then
  info "3b/4 비전 모델 ($VISION_HF_REPO $VISION_QUANT + $VISION_MMPROJ, ~22GB)"
  mkdir -p "$W/models/vision"
  B="https://huggingface.co/$VISION_HF_REPO/resolve/main"
  for f in "Qwen3.8-27B-${VISION_QUANT}.gguf" "$VISION_MMPROJ"; do
    curl -fL -C - --retry 20 --progress-bar -o "$W/models/vision/$f" "$B/$f"
  done
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
