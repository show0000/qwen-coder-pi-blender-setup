#!/usr/bin/env bash
# Download Qwen3-Coder-Next weights from Hugging Face.
#   default (BACKEND=llama): unsloth/Qwen3-Coder-Next-GGUF, quant UD-Q6_K_XL (~68GB)
#   BACKEND=mlx            : mlx-community/Qwen3-Coder-Next-6bit (~65GB)
source "$(dirname "$0")/common.sh"

have hf || fail "hf CLI가 없습니다. 먼저 ./scripts/00_prereqs.sh 를 실행하세요."

mkdir -p "$MODEL_DIR"
info "다운로드: $HF_REPO ${QUANT:+(quant: $QUANT)}"
info "경로:     $MODEL_DIR"
info "(6bit 기준 약 65~70GB. 중단되면 같은 명령으로 이어받기 됩니다.)"

case "$BACKEND" in
  llama)
    # only the chosen quant (files live either at repo root or in a <QUANT>/ subfolder)
    hf download "$HF_REPO" --local-dir "$MODEL_DIR" --include "*${QUANT}*"
    main=$(gguf_main_file)
    [[ -n "$main" ]] || fail "GGUF 파일을 찾지 못했습니다 ($QUANT). hf download 출력을 확인하세요."
    info "메인 샤드: $main"
    ;;
  mlx)
    hf download "$HF_REPO" --local-dir "$MODEL_DIR"
    [[ -f "$MODEL_DIR/config.json" ]] || fail "config.json 이 없습니다. 다운로드 실패."
    ls "$MODEL_DIR"/*.safetensors >/dev/null 2>&1 || fail "safetensors 파일이 없습니다."
    ;;
esac

size=$(du -sh "$MODEL_DIR" | cut -f1)
info "완료 ($size). 다음: ./scripts/02_serve_model.sh"
