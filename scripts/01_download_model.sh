#!/usr/bin/env bash
# Download Qwen3-Coder-Next MLX weights from Hugging Face into LM Studio's model layout.
source "$(dirname "$0")/common.sh"

have hf || fail "hf CLI가 없습니다. 먼저 ./scripts/00_prereqs.sh 를 실행하세요."

info "다운로드: $HF_REPO"
info "경로:     $MODEL_DIR"
info "(약 46GB. 중단되면 같은 명령으로 이어받기 됩니다.)"

mkdir -p "$MODEL_DIR"
# hf_xet 가속 전송; HF_TOKEN 이 있으면 자동 사용 (gated 모델 아님, 없어도 됨)
HF_HUB_ENABLE_HF_TRANSFER=1 hf download "$HF_REPO" --local-dir "$MODEL_DIR"

# sanity check
[[ -f "$MODEL_DIR/config.json" ]] || fail "config.json 이 없습니다. 다운로드 실패."
ls "$MODEL_DIR"/*.safetensors >/dev/null 2>&1 || fail "safetensors 파일이 없습니다."

size=$(du -sh "$MODEL_DIR" | cut -f1)
info "완료 ($size). 다음: ./scripts/02_serve_model.sh"
