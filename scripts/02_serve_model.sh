#!/usr/bin/env bash
# Start an OpenAI-compatible server for the downloaded model.
#   ./scripts/02_serve_model.sh              -> LM Studio (port 1234)
#   BACKEND=mlx ./scripts/02_serve_model.sh  -> mlx_lm.server (port 8080)
#   CTX=262144 ...                           -> full native context
source "$(dirname "$0")/common.sh"

[[ -f "$MODEL_DIR/config.json" ]] || fail "모델이 없습니다: $MODEL_DIR  (01_download_model.sh 먼저)"

case "$BACKEND" in
  lmstudio)
    have lms || fail "lms CLI 없음. LM Studio 앱 실행 후 '~/.lmstudio/bin/lms bootstrap'"
    info "LM Studio 서버 기동 (port $PORT)"
    lms server start --port "$PORT" >/dev/null 2>&1 || true

    # LM Studio indexes $LMSTUDIO_MODELS_DIR/<publisher>/<model>; key is "<publisher>/<model>"
    model_key="$HF_REPO"
    if lms ps 2>/dev/null | grep -q "$MODEL_ID"; then
      info "이미 로드됨: $MODEL_ID"
    else
      info "모델 로드: $model_key  (ctx=$CTX, identifier=$MODEL_ID)"
      lms load "$model_key" --context-length "$CTX" --identifier "$MODEL_ID" --gpu max -y
    fi
    ;;
  mlx)
    have mlx_lm.server || fail "mlx_lm.server 없음 (uv tool install mlx-lm)"
    info "mlx_lm.server 기동 (port $PORT, 모델 경로 $MODEL_DIR)"
    info "pi 의 models.json 에서 id 는 '$MODEL_ID' 로 등록되지만 mlx_lm.server 는 요청의 model 필드를"
    info "로드된 모델로 매핑하므로 그대로 동작합니다. Ctrl+C 로 종료."
    exec mlx_lm.server \
      --model "$MODEL_DIR" \
      --host 127.0.0.1 --port "$PORT" \
      --max-tokens "$MAX_TOKENS" \
      --log-level INFO
    ;;
esac

# quick probe
sleep 1
if curl -fsS "$BASE_URL/models" >/dev/null; then
  info "서버 OK: $BASE_URL"
  curl -fsS "$BASE_URL/models" | (jq -r '.data[].id' 2>/dev/null || cat)
else
  warn "서버 응답 없음. 'lms log stream' 으로 로그를 확인하세요."
fi
info "다음: ./scripts/03_setup_pi.sh"
