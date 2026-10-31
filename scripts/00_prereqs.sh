#!/usr/bin/env bash
# Install everything needed on a fresh Apple Silicon Mac.
source "$(dirname "$0")/common.sh"
require_macos_arm

# Homebrew
if ! have brew; then
  info "Homebrew 설치"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

info "brew 패키지 설치 (uv, node@22, git, jq)"
brew list uv     >/dev/null 2>&1 || brew install uv
brew list node@22 >/dev/null 2>&1 || brew install node@22
brew list jq     >/dev/null 2>&1 || brew install jq
brew link --overwrite --force node@22 >/dev/null 2>&1 || true

# pi coding agent (official installer pins deps; `pi update` handles upgrades)
if ! have pi; then
  info "pi 코딩 에이전트 설치"
  curl -fsSL https://pi.dev/install.sh | sh
else
  info "pi 이미 설치됨: $(pi --version 2>/dev/null || echo '?')"
fi

# Hugging Face CLI (hf) + mlx-lm as uv tools
info "hf CLI / mlx-lm 설치 (uv tool)"
uv tool install --upgrade "huggingface_hub[cli,hf_xet]" >/dev/null
uv tool install --upgrade mlx-lm >/dev/null

# LM Studio (app + lms CLI) — default backend
if [[ "$BACKEND" == "lmstudio" ]]; then
  if ! brew list --cask lm-studio >/dev/null 2>&1 && [[ ! -d "/Applications/LM Studio.app" ]]; then
    info "LM Studio 설치 (cask)"
    brew install --cask lm-studio
  fi
  if ! have lms; then
    warn "lms CLI가 PATH에 없습니다. LM Studio 앱을 한 번 실행한 뒤:"
    warn "  ~/.lmstudio/bin/lms bootstrap"
    warn "를 실행하고 새 터미널을 여세요."
  fi
fi

# Blender / OrcaSlicer are GUI apps; only warn if missing
[[ -d "/Applications/Blender.app" ]] || warn "Blender가 /Applications 에 없습니다 (brew install --cask blender 또는 blender.org)."
[[ -d "/Applications/OrcaSlicer.app" ]] || warn "OrcaSlicer가 없습니다. MCP 기능은 Remote API가 포함된 OrcaSlicer MCP 빌드가 필요합니다."

info "완료. 다음: ./scripts/01_download_model.sh"
