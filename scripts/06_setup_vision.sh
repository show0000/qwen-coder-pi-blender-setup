#!/usr/bin/env bash
# Optional: add Qwen3.8-27B (vision-language) as a second local model so pi can look at
# Blender viewport screenshots. Downloads (online) or verifies (offline) the GGUF + mmproj,
# registers provider "local-vision" in pi, and installs `qwen vision start|stop|status`.
#
#   ./scripts/06_setup_vision.sh                      # download + register
#   VISION_QUANT=UD-Q6_K_XL ./scripts/06_setup_vision.sh
#   OFFLINE=1 VISION_SRC=/path/with/ggufs ./scripts/06_setup_vision.sh   # copy from local folder
source "$(dirname "$0")/common.sh"
have pi || fail "pi 가 없습니다."

mkdir -p "$VISION_MODEL_DIR"
if [[ -n "${VISION_SRC:-}" ]]; then
  info "가중치 복사: $VISION_SRC → $VISION_MODEL_DIR"
  cp -v "$VISION_SRC"/*"$VISION_QUANT"*.gguf "$VISION_SRC"/"$VISION_MMPROJ" "$VISION_MODEL_DIR/"
elif [[ -z "$(vision_gguf)" || -z "$(vision_mmproj)" ]]; then
  [[ "$OFFLINE" == "1" ]] && fail "오프라인: $VISION_MODEL_DIR 에 *${VISION_QUANT}*.gguf 와 $VISION_MMPROJ 를 넣거나 VISION_SRC=<폴더> 로 지정하세요."
  have hf || fail "hf CLI 없음 (00_prereqs.sh)"
  info "다운로드: $VISION_HF_REPO ($VISION_QUANT + $VISION_MMPROJ)"
  hf download "$VISION_HF_REPO" --local-dir "$VISION_MODEL_DIR" --include "*${VISION_QUANT}*" --include "$VISION_MMPROJ"
fi
[[ -n "$(vision_gguf)" ]]   || fail "비전 모델 GGUF 없음 ($VISION_QUANT)"
[[ -n "$(vision_mmproj)" ]] || fail "mmproj 없음 ($VISION_MMPROJ)"
info "모델:   $(vision_gguf)"
info "mmproj: $(vision_mmproj)"

patch=$(cat <<JSON
{
  "providers": {
    "local-vision": {
      "baseUrl": "$VISION_BASE_URL",
      "api": "openai-completions",
      "apiKey": "local",
      "models": [
        {
          "id": "$VISION_MODEL_ID",
          "name": "Qwen3.8-27B VL (local, viewport eyes)",
          "contextWindow": $VISION_CTX,
          "maxTokens": 8192,
          "input": ["text", "image"],
          "inputLimits": { "images": { "resize": { "maxWidth": 1280, "maxHeight": 1280, "maxBytes": 1048576, "jpegQuality": 80 } } }
        }
      ]
    }
  }
}
JSON
)
merge_json "$PI_AGENT_DIR/models.json" "$patch"

cat <<EOF2

등록 완료. 사용법:
  qwen vision start              # 두 번째 서버 (port $VISION_PORT, 약 21GB 추가 상주)
  pi 안에서 /model → "$VISION_MODEL_ID" 선택 (또는 Ctrl+P 로 순환)
  → get_viewport_screenshot 결과를 모델이 직접 봅니다. 확인이 끝나면 /model 로 coder 로 복귀.
  qwen vision stop

메모리: coder 68GB + vision 21GB ≈ 90GB. UE5 를 같이 띄울 땐 vision 은 필요할 때만 켜세요.
EOF2
