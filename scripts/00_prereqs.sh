#!/usr/bin/env bash
# Install everything needed on a fresh Apple Silicon Mac. CLI tools only — no GUI model apps.
source "$(dirname "$0")/common.sh"
require_macos_arm
[[ "$OFFLINE" == "1" ]] && fail "오프라인 모드에서는 00_prereqs.sh 대신 scripts/offline/install_offline.sh 를 사용하세요."

# Homebrew
if ! have brew; then
  info "Homebrew 설치"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

info "brew 패키지 설치 (uv, node@22, jq)"
brew list uv      >/dev/null 2>&1 || brew install uv
brew list node@22 >/dev/null 2>&1 || brew install node@22
brew list jq      >/dev/null 2>&1 || brew install jq
brew link --overwrite --force node@22 >/dev/null 2>&1 || true

# pi coding agent (official installer pins deps; `pi update` handles upgrades)
if ! have pi; then
  info "pi 코딩 에이전트 설치"
  curl -fsSL https://pi.dev/install.sh | sh
else
  info "pi 이미 설치됨: $(pi --version 2>/dev/null || echo '?')"
fi

# Hugging Face CLI
info "hf CLI 설치 (uv tool)"
uv tool install --upgrade "huggingface_hub[cli,hf_xet]" >/dev/null

case "$BACKEND" in
  llama)
    # llama.cpp from Homebrew: Metal enabled, ships llama-server. Qwen3-Next arch needs a recent build.
    info "llama.cpp 설치/업데이트 (brew)"
    if brew list llama.cpp >/dev/null 2>&1; then brew upgrade llama.cpp || true; else brew install llama.cpp; fi
    have llama-server || fail "llama-server 가 PATH 에 없습니다."
    info "llama-server: $(llama-server --version 2>&1 | head -1)"
    ;;
  mlx)
    info "mlx-lm 설치 (uv tool)"
    uv tool install --upgrade mlx-lm >/dev/null
    ;;
esac

# Blender is a GUI app; only warn if missing
[[ -d "/Applications/Blender.app" ]] || warn "Blender가 /Applications 에 없습니다 (blender.org 또는 brew install --cask blender)."

info "완료. 다음: ./scripts/01_download_model.sh"
