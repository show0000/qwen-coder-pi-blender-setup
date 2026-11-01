#!/usr/bin/env bash
# Install context-efficient global instructions, skills and prompt templates into ~/.pi/agent.
#   ./scripts/08_setup_pi_config.sh            # copy (backs up an existing AGENTS.md)
#   ./scripts/08_setup_pi_config.sh --link     # symlink so `git pull` updates them in place
#   ./scripts/08_setup_pi_config.sh --with-claude-skills [dir]   # also load your Claude Code skills (default ~/.claude/skills)
#   ./scripts/08_setup_pi_config.sh --with-superpowers         # curated obra/superpowers process skills (slash-invoked only)
source "$(dirname "$0")/common.sh"
SRC="$(cd "$(dirname "$0")/../pi-config" && pwd)"
DST="$PI_AGENT_DIR"
mkdir -p "$DST/skills" "$DST/prompts"

put() { # put <src> <dst>
  if [[ "${1:-}" == "--link" ]]; then shift; ln -sfn "$1" "$2"; else rm -rf "$2"; cp -R "$1" "$2"; fi
}
MODE=""; CLAUDE_SKILLS=""; SUPERPOWERS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --link) MODE="--link"; shift ;;
    --with-superpowers) SUPERPOWERS=1; shift ;;
    --with-claude-skills) CLAUDE_SKILLS="${2:-$HOME/.claude/skills}"; [[ "$CLAUDE_SKILLS" == --* ]] && CLAUDE_SKILLS="$HOME/.claude/skills"; shift; [[ "${1:-}" != --* && -n "${1:-}" ]] && shift ;;
    *) shift ;;
  esac
done

if [[ -f "$DST/AGENTS.md" && ! -L "$DST/AGENTS.md" ]] && ! cmp -s "$SRC/AGENTS.md" "$DST/AGENTS.md"; then
  cp "$DST/AGENTS.md" "$DST/AGENTS.md.bak.$(date +%Y%m%d%H%M%S)"; info "기존 AGENTS.md 백업"
fi
put $MODE "$SRC/AGENTS.md" "$DST/AGENTS.md"
for d in "$SRC"/skills/*/; do put $MODE "${d%/}" "$DST/skills/$(basename "$d")"; done
for f in "$SRC"/prompts/*.md; do put $MODE "$f" "$DST/prompts/$(basename "$f")"; done
merge_json "$DST/settings.json" "$(cat "$SRC/settings.snippet.json")"
if [[ "$SUPERPOWERS" == "1" ]]; then
  put $MODE "$SRC/skills-optional/superpowers" "$DST/skills/superpowers"
  info "superpowers 하위 집합 설치 (슬래시 호출 전용): $(ls "$SRC/skills-optional/superpowers" | grep -v -E 'LICENSE|README' | tr '\n' ' ')"
fi
if [[ -n "$CLAUDE_SKILLS" ]]; then
  if [[ -d "$CLAUDE_SKILLS" ]]; then
    n=$(find "$CLAUDE_SKILLS" -name SKILL.md | wc -l | tr -d ' ')
    merge_json "$DST/settings.json" "$(python3 -c 'import json,sys;print(json.dumps({"skills":[sys.argv[1]]}))' "$CLAUDE_SKILLS")"
    info "Claude 스킬 디렉터리 연결: $CLAUDE_SKILLS ($n 개 SKILL.md)"
    warn "Claude 전용 도구(Artifact, Skill 툴 등)를 호출하는 스킬은 pi 에서 동작하지 않습니다. 목록: find $CLAUDE_SKILLS -name SKILL.md"
  else
    warn "디렉터리 없음: $CLAUDE_SKILLS"
  fi
fi

info "설치됨 → $DST"
echo "  AGENTS.md            전역 작업 규칙 (컨텍스트 절약 + 코딩 방식)"
echo "  skills/              repo-map, bpy-modeling, print-pipeline, debug-loop, karpathy-guidelines"
echo "  prompts/             /review, /plan <task>"
echo "  settings.json        compaction, 기본 도구(grep/find/ls 포함)"
echo "pi 를 재시작하면 적용됩니다. 프로젝트별 규칙은 프로젝트 루트의 AGENTS.md 에 추가하세요 (전역 뒤에 이어 붙습니다)."
