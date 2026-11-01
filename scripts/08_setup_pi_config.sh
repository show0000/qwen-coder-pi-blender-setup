#!/usr/bin/env bash
# Install context-efficient global instructions, skills and prompt templates into ~/.pi/agent.
#   ./scripts/08_setup_pi_config.sh            # copy (backs up an existing AGENTS.md)
#   ./scripts/08_setup_pi_config.sh --link     # symlink so `git pull` updates them in place
source "$(dirname "$0")/common.sh"
SRC="$(cd "$(dirname "$0")/../pi-config" && pwd)"
DST="$PI_AGENT_DIR"
mkdir -p "$DST/skills" "$DST/prompts"

put() { # put <src> <dst>
  if [[ "${1:-}" == "--link" ]]; then shift; ln -sfn "$1" "$2"; else rm -rf "$2"; cp -R "$1" "$2"; fi
}
MODE=""; [[ "${1:-}" == "--link" ]] && MODE="--link"

if [[ -f "$DST/AGENTS.md" && ! -L "$DST/AGENTS.md" ]] && ! cmp -s "$SRC/AGENTS.md" "$DST/AGENTS.md"; then
  cp "$DST/AGENTS.md" "$DST/AGENTS.md.bak.$(date +%Y%m%d%H%M%S)"; info "기존 AGENTS.md 백업"
fi
put $MODE "$SRC/AGENTS.md" "$DST/AGENTS.md"
for d in "$SRC"/skills/*/; do put $MODE "${d%/}" "$DST/skills/$(basename "$d")"; done
for f in "$SRC"/prompts/*.md; do put $MODE "$f" "$DST/prompts/$(basename "$f")"; done
merge_json "$DST/settings.json" "$(cat "$SRC/settings.snippet.json")"

info "설치됨 → $DST"
echo "  AGENTS.md            전역 작업 규칙 (컨텍스트 절약 + 코딩 방식)"
echo "  skills/              repo-map, bpy-modeling, print-pipeline, debug-loop"
echo "  prompts/             /review, /plan <task>"
echo "  settings.json        compaction, 기본 도구(grep/find/ls 포함)"
echo "pi 를 재시작하면 적용됩니다. 프로젝트별 규칙은 프로젝트 루트의 AGENTS.md 에 추가하세요 (전역 뒤에 이어 붙습니다)."
