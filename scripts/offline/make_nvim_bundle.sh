#!/usr/bin/env bash
# ONLINE Mac: snapshot the CURRENT Neovim setup so it can be reproduced on an offline Mac.
#   - official nvim release tarball matching the installed version (brew's binary is not relocatable)
#   - ~/.config/nvim            (your config, untouched)
#   - ~/.local/share/nvim       (lazy/packer plugins, mason servers, treesitter parsers)
#   - ripgrep / fd release binaries (telescope & friends need them)
#   - optional: lua/plugins/local-ai.lua (minuet + codecompanion → local qwen server), with --with-ai
#
#   ./scripts/offline/make_nvim_bundle.sh <out-dir> [--with-ai]
# Called by make_update.sh --with-nvim; output lands in <out-dir>/nvim/.
set -euo pipefail
OUT="${1:?out-dir}"; WITH_AI=0; [[ "${2:-}" == "--with-ai" ]] && WITH_AI=1
N="$OUT/nvim"; rm -rf "$N"; mkdir -p "$N/bin"
info() { printf '\033[32m[nvim]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[nvim]\033[0m %s\n' "$*"; }
command -v nvim >/dev/null || { echo "nvim 이 없습니다" >&2; exit 1; }

VER=$(nvim --version | head -1 | sed -E 's/^NVIM v([0-9.]+).*/\1/')
info "현재 nvim v$VER ($(command -v nvim))"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"; DATA="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
[[ -d "$CFG" ]] || { echo "설정 없음: $CFG" >&2; exit 1; }

# ---- optional: add local-AI plugin spec to the user's lazy.nvim config, then sync ----------
if [[ "$WITH_AI" == "1" ]]; then
  if [[ -f "$CFG/lazy-lock.json" || -d "$DATA/lazy" ]]; then
    mkdir -p "$CFG/lua/plugins"
    SRC_AI="$(cd "$(dirname "$0")/../.." && pwd)/config/nvim/local-ai.lua"
    if [[ ! -f "$CFG/lua/plugins/local-ai.lua" ]]; then cp "$SRC_AI" "$CFG/lua/plugins/local-ai.lua"; info "추가: lua/plugins/local-ai.lua (minuet + codecompanion → :8080)"; else info "lua/plugins/local-ai.lua 이미 있음 (유지)"; fi
    info "플러그인 동기화 (lazy.nvim)…"; nvim --headless "+Lazy! sync" +qa 2>&1 | tail -2 || warn "Lazy sync 경고 (계속)"
  else
    warn "lazy.nvim 구성이 아니라 --with-ai 를 건너뜁니다. config/nvim/local-ai.lua 를 수동으로 플러그인 매니저에 맞게 추가하세요."
  fi
fi

# ---- 1. official release matching the version ------------------------------------------------
TGZ="nvim-macos-arm64.tar.gz"
URL="https://github.com/neovim/neovim/releases/download/v${VER}/${TGZ}"
info "GET $URL"
if ! curl -fL --retry 3 --progress-bar -o "$N/$TGZ" "$URL"; then
  warn "v$VER 릴리스 자산을 못 받았습니다 (nightly 빌드?). stable 로 대체합니다."
  curl -fL --retry 3 --progress-bar -o "$N/$TGZ" "https://github.com/neovim/neovim/releases/download/stable/${TGZ}"
fi

# ---- 2. config + data (plugins, mason, parsers) ------------------------------------------------
info "config → nvim-config.tgz"; tar -C "$(dirname "$CFG")" --exclude '.git' -czf "$N/nvim-config.tgz" nvim
info "data   → nvim-data.tgz ($(du -sh "$DATA" | cut -f1))"
tar -C "$(dirname "$DATA")" --exclude 'nvim/lazy/*/.git' --exclude 'nvim/mason/packages/*/node_modules/.cache' -czf "$N/nvim-data.tgz" nvim
[[ -d "$HOME/.local/state/nvim" ]] && { info "state  → nvim-state.tgz (shada/undo, 선택)"; tar -C "$HOME/.local/state" --exclude 'nvim/swap' -czf "$N/nvim-state.tgz" nvim || true; }

# ---- 3. helper binaries the config likely needs ------------------------------------------------
rel() { # rel <name> <url> <tar member glob>
  local name="$1" url="$2" glob="$3" t; t=$(mktemp -d)
  if curl -fL --retry 3 -s -o "$t/a.tgz" "$url"; then
    tar -xzf "$t/a.tgz" -C "$t" && f=$(find "$t" -type f -name "$glob" -perm -u+x | head -1) && [[ -n "$f" ]] && cp "$f" "$N/bin/$name" && chmod +x "$N/bin/$name" && info "bin: $name" || warn "$name 추출 실패"
  else warn "$name 다운로드 실패 (건너뜀)"; fi; rm -rf "$t"
}
RG_V=$(curl -fsSL https://api.github.com/repos/BurntSushi/ripgrep/releases/latest 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["tag_name"])' 2>/dev/null || echo 14.1.1)
FD_V=$(curl -fsSL https://api.github.com/repos/sharkdp/fd/releases/latest 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["tag_name"])' 2>/dev/null || echo v10.2.0)
rel rg "https://github.com/BurntSushi/ripgrep/releases/download/${RG_V}/ripgrep-${RG_V}-aarch64-apple-darwin.tar.gz" rg
rel fd "https://github.com/sharkdp/fd/releases/download/${FD_V}/fd-${FD_V}-aarch64-apple-darwin.tar.gz" fd
if grep -rqs "lazygit" "$CFG"; then
  LG_V=$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["tag_name"].lstrip("v"))' 2>/dev/null || true)
  [[ -n "$LG_V" ]] && rel lazygit "https://github.com/jesseduffield/lazygit/releases/download/v${LG_V}/lazygit_${LG_V}_darwin_arm64.tar.gz" lazygit
fi

# ---- 4. manifest + hints -----------------------------------------------------------------------
{
  echo "NVIM_VERSION=$VER"; echo "WITH_AI=$WITH_AI"; echo "CREATED=$(date -u +%FT%TZ)"
  echo "PLUGIN_MANAGER=$([[ -d "$DATA/lazy" ]] && echo lazy || ([[ -d "$DATA/site/pack/packer" ]] && echo packer || echo unknown))"
  echo "MASON_PKGS=$(ls "$DATA/mason/packages" 2>/dev/null | tr '\n' ' ')"
} > "$N/manifest.env"
# external tools referenced by the config that we do NOT bundle (user should check on the offline Mac)
grep -rhoE "\b(python3|node|npm|go|cargo|java|gcc|clang|make|cmake|tmux|git|gh|black|ruff|prettier|eslint|stylua|shfmt)\b" "$CFG" 2>/dev/null | sort -u | tr '\n' ' ' > "$N/EXTERNAL_TOOLS.txt" || true
info "완료: $N ($(du -sh "$N" | cut -f1)). 설정이 참조하는 외부 도구: $(cat "$N/EXTERNAL_TOOLS.txt")"
