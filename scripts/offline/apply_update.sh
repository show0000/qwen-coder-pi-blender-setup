#!/usr/bin/env bash
# OFFLINE Mac: apply an update.tgz made by make_update.sh. Safe to re-run.
#   tar -xzf ~/update.tgz -C ~ && ~/update/repo/scripts/offline/apply_update.sh ~/update
#   QWEN_REPO=~/Dev/Lab/qwen-coder-pi-blender-setup ...   # scripts live somewhere other than ~/qwen-coder-pi-blender-setup
set -euo pipefail
U="${1:?usage: apply_update.sh <update-dir>}"; U="$(cd "$U" && pwd)"
[[ -f "$U/VERSION" ]] || { echo "update 폴더가 아닙니다: $U" >&2; exit 1; }
ENVF="$HOME/.config/qwen-coder/env.sh"
[[ -f "$ENVF" ]] && source "$ENVF"
export OFFLINE=1 UV_PYTHON_DOWNLOADS=never UV_OFFLINE=1
BIN="$HOME/.local/bin"; OPT="$HOME/.local/opt"
# where the scripts live on this Mac: QWEN_REPO env > existing `qwen` symlink target > default
REPO="${QWEN_REPO:-}"
if [[ -z "$REPO" && -L "$BIN/qwen" ]]; then
  t="$(readlink "$BIN/qwen")"; [[ -f "$t" ]] && REPO="$(cd "$(dirname "$t")/.." && pwd)"
fi
REPO="${REPO:-$HOME/qwen-coder-pi-blender-setup}"
mkdir -p "$REPO" "$BIN" "$OPT"
unq() { xattr -dr com.apple.quarantine "$@" 2>/dev/null || true; }
step() { printf '\033[32m[%s]\033[0m %s\n' "$1" "$2"; }

step 1/7 "스크립트/설정 갱신 → $REPO  (버전: $(head -1 "$U/VERSION") $(tail -1 "$U/VERSION"))"
tar -C "$U/repo" -cf - . | tar -C "$REPO" -xf -
chmod +x "$REPO"/scripts/*.sh "$REPO"/scripts/offline/*.sh
source "$REPO/scripts/common.sh"

step 2/7 "mcp-atlassian 설치 (wheelhouse)"
if ls "$U"/wheels/mcp_atlassian-*.whl >/dev/null 2>&1; then
  UV_NO_INDEX=1 UV_FIND_LINKS="$U/wheels" "$BIN/uv" tool install -q --reinstall mcp-atlassian && echo "  ok: $BIN/mcp-atlassian"
else echo "  (wheels 없음, 건너뜀)"; fi

step 3/7 "mcp-gitlab 설치"
if [[ -f "$U/npm/mcp-gitlab-prefix.tgz" ]]; then
  rm -rf "$OPT/mcp-gitlab"; mkdir -p "$OPT/mcp-gitlab"
  tar -xzf "$U/npm/mcp-gitlab-prefix.tgz" -C "$OPT/mcp-gitlab" --strip-components 1; unq "$OPT/mcp-gitlab"
  echo "  ok: $OPT/mcp-gitlab/bin/zereight-mcp-gitlab"
else echo "  (npm tgz 없음, 건너뜀)"; fi

step 4/7 "env.sh 갱신"
touch "$ENVF"
grep -q 'ATLASSIAN_MCP_CMD' "$ENVF" || echo "export ATLASSIAN_MCP_CMD=\"$BIN/mcp-atlassian\" GITLAB_MCP_CMD=\"$OPT/mcp-gitlab/bin/zereight-mcp-gitlab\"" >> "$ENVF"
grep -q 'export CTX=' "$ENVF" || echo "export CTX=262144" >> "$ENVF"
grep -q 'export QWEN_REPO=' "$ENVF" && sed -i '' "s|^export QWEN_REPO=.*|export QWEN_REPO=\"$REPO\"|" "$ENVF" || echo "export QWEN_REPO=\"$REPO\"" >> "$ENVF"
source "$ENVF"

step 5/7 "비전 모델 (있으면)"
if [[ -d "$U/models/vision" ]]; then
  mkdir -p "$VISION_MODEL_DIR"; cp -v "$U/models/vision/"*.gguf "$VISION_MODEL_DIR/"
fi

step 6/7 "pi 설정: models.json(ctx), qwen 명령, 스킬, 비전 provider"
"$REPO/scripts/03_setup_pi.sh" >/dev/null && echo "  ok: models.json ctx=$CTX, ~/.local/bin/qwen"
"$REPO/scripts/08_setup_pi_config.sh" --with-superpowers | grep -E 'superpowers|설치됨' | sed 's/^/  /'
if [[ -n "$(vision_gguf)" && -n "$(vision_mmproj)" ]]; then "$REPO/scripts/06_setup_vision.sh" >/dev/null && echo "  ok: local-vision provider"; fi

step 7/7 "사내 MCP (Jira/Confluence/GitLab)"
ENT="$HOME/.config/qwen-coder/enterprise.env"
if [[ -f "$ENT" ]] && grep -qE '^(JIRA_PERSONAL_TOKEN|GITLAB_PERSONAL_ACCESS_TOKEN)="[^"]+"' "$ENT"; then
  "$REPO/scripts/09_setup_enterprise_mcp.sh" | tail -n +1 | grep -E 'updated|warn' | sed 's/^/  /' || true
else
  "$REPO/scripts/09_setup_enterprise_mcp.sh" >/dev/null 2>&1 || true
  echo "  토큰 미설정. 다음을 채운 뒤 한 줄만 실행하세요:"
  echo "    vi $ENT   &&   $REPO/scripts/09_setup_enterprise_mcp.sh"
fi

echo
echo "적용 완료. 새 터미널을 열거나:  source $ENVF"
echo "  qwen restart      # ctx 변경 반영 (서버 재시작, 1~2분)"
echo "  qwen status / qwen check"
echo "  pi mcp list       # blender, orca, (atlassian, gitlab) 확인"
