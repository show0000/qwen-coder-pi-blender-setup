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

step 3b/7 "orca 바이너리"
if command -v orca >/dev/null 2>&1 || [[ -e "$BIN/orca" ]]; then
  echo "  이미 설치됨: $(command -v orca || echo "$BIN/orca") — 건너뜀 (Orca 앱이 설치한 CLI 는 덮어쓰지 않음)"
elif [[ -f "$U/bin/orca" ]]; then
  cp "$U/bin/orca" "$BIN/orca" && chmod +x "$BIN/orca" && unq "$BIN/orca" && echo "  ok: $BIN/orca" || echo "  복사 실패 (무시)"
else echo "  (번들에 없음, 건너뜀)"; fi

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

set +e   # from here on, a failing optional step must not abort the rest
step 6/7 "pi 설정: models.json(ctx), qwen 명령, 스킬, 비전 provider"
"$REPO/scripts/03_setup_pi.sh" >/dev/null && echo "  ok: models.json ctx=$CTX, ~/.local/bin/qwen"
"$REPO/scripts/08_setup_pi_config.sh" --with-superpowers | grep -E 'superpowers|설치됨' | sed 's/^/  /'
if [[ -n "$(vision_gguf)" && -n "$(vision_mmproj)" ]]; then "$REPO/scripts/06_setup_vision.sh" >/dev/null && echo "  ok: local-vision provider"; fi

step 6a/7 "Neovim (번들에 있으면)"
if [[ -f "$U/nvim/manifest.env" ]]; then
  # shellcheck disable=SC1091
  source "$U/nvim/manifest.env"
  rm -rf "$OPT/nvim"; mkdir -p "$OPT/nvim"; tar -xzf "$U/nvim/nvim-macos-arm64.tar.gz" -C "$OPT/nvim" --strip-components 1; unq "$OPT/nvim"
  ln -sf "$OPT/nvim/bin/nvim" "$BIN/nvim"
  CFG="${XDG_CONFIG_HOME:-$HOME/.config}"; DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
  if [[ -d "$CFG/nvim" && ! -L "$CFG/nvim" ]]; then mv "$CFG/nvim" "$CFG/nvim.bak.$(date +%Y%m%d%H%M%S)"; echo "  기존 ~/.config/nvim 백업"; fi
  mkdir -p "$CFG" "$DATA"; tar -xzf "$U/nvim/nvim-config.tgz" -C "$CFG"
  rm -rf "$DATA/nvim"; tar -xzf "$U/nvim/nvim-data.tgz" -C "$DATA"; unq "$DATA/nvim"
  [[ -f "$U/nvim/nvim-state.tgz" ]] && { mkdir -p "$HOME/.local/state"; tar -xzf "$U/nvim/nvim-state.tgz" -C "$HOME/.local/state" 2>/dev/null || true; }
  for b in "$U"/nvim/bin/*; do [[ -f "$b" ]] && { cp "$b" "$BIN/"; chmod +x "$BIN/$(basename "$b")"; unq "$BIN/$(basename "$b")"; }; done
  # keep lazy.nvim quiet offline
  grep -q 'QWEN_BASE_URL' "$ENVF" || echo "export QWEN_BASE_URL=\"http://127.0.0.1:${PORT:-8080}\" QWEN_MODEL_ID=\"${MODEL_ID:-qwen3-coder-next}\"" >> "$ENVF"
  echo "  ok: nvim v$NVIM_VERSION → $BIN/nvim, config/data 복원, 도구: $(ls "$U/nvim/bin" 2>/dev/null | tr '\n' ' ')"
  [[ -s "$U/nvim/EXTERNAL_TOOLS.txt" ]] && echo "  설정이 참조하는 외부 도구(이 Mac 에 있는지 확인): $(cat "$U/nvim/EXTERNAL_TOOLS.txt")"
  echo "  첫 실행 후 :checkhealth 로 확인. lazy.nvim 업데이트 체크가 켜져 있으면 네트워크 오류가 뜰 수 있음 → checker.enabled=false"
else echo "  (번들에 없음, 건너뜀)"; fi

step 6b/7 "orca MCP 등록"
if command -v orca >/dev/null 2>&1; then "$REPO/scripts/05_setup_orca.sh" >/dev/null 2>&1 && echo "  ok: mcp.json orca, ~/.local/bin/pi-local"; else echo "  (orca 없음, 건너뜀)"; fi

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
