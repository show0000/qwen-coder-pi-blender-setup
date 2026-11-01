#!/usr/bin/env bash
# Second llama-server for the vision model.  --bg | --stop | (foreground)
source "$(dirname "$0")/common.sh"
mkdir -p "$(dirname "$VISION_LOG")"
if [[ "${1:-}" == "--stop" ]]; then
  if [[ -f "$VISION_PID" ]] && kill -0 "$(cat "$VISION_PID")" 2>/dev/null; then kill "$(cat "$VISION_PID")" && info "vision 서버 종료"; else warn "실행 중인 vision 서버 없음"; fi
  rm -f "$VISION_PID"; exit 0
fi
curl -fsS --max-time 2 "$VISION_BASE_URL/models" >/dev/null 2>&1 && { info "이미 실행 중: $VISION_BASE_URL"; exit 0; }
have llama-server || fail "llama-server 없음"
g=$(vision_gguf); m=$(vision_mmproj)
[[ -n "$g" && -n "$m" ]] || fail "비전 모델이 없습니다 (06_setup_vision.sh)"
cmd=(llama-server --model "$g" --mmproj "$m" --alias "$VISION_MODEL_ID"
     --host 127.0.0.1 --port "$VISION_PORT" --ctx-size "$VISION_CTX" --n-predict 8192
     -ngl 999 --flash-attn on --jinja --temp 0.7 --top-p 0.8 --top-k 20 --min-p 0.0 --parallel 1)
info "vision 서버: $VISION_BASE_URL  ctx=$VISION_CTX"
if [[ "${1:-}" == "--bg" ]]; then
  nohup "${cmd[@]}" >"$VISION_LOG" 2>&1 & echo $! >"$VISION_PID"
  for _ in $(seq 1 60); do curl -fsS --max-time 2 "$VISION_BASE_URL/models" >/dev/null 2>&1 && break; sleep 2; done
  curl -fsS --max-time 2 "$VISION_BASE_URL/models" >/dev/null 2>&1 && info "vision 서버 OK" || warn "아직 로딩 중: tail -f $VISION_LOG"
else
  exec "${cmd[@]}"
fi
