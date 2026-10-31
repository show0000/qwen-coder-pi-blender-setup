#!/usr/bin/env bash
# Start an OpenAI-compatible server on 127.0.0.1:8080 for the downloaded model.
#   ./scripts/02_serve_model.sh            foreground (Ctrl+C to stop) — run in a 2nd terminal / tmux
#   ./scripts/02_serve_model.sh --bg       background; log at ~/.local/state/qwen-coder/server.log
#   ./scripts/02_serve_model.sh --stop     stop background server
#   BACKEND=mlx ...                        use mlx-lm instead of llama.cpp
#   CTX=262144 ...                         full native context
source "$(dirname "$0")/common.sh"

mkdir -p "$(dirname "$SERVER_LOG")"

if [[ "${1:-}" == "--stop" ]]; then
  if [[ -f "$SERVER_PID" ]] && kill -0 "$(cat "$SERVER_PID")" 2>/dev/null; then
    kill "$(cat "$SERVER_PID")" && rm -f "$SERVER_PID" && info "서버 종료"
  else
    warn "실행 중인 백그라운드 서버 없음"; rm -f "$SERVER_PID"
  fi
  exit 0
fi

if curl -fsS --max-time 2 "$BASE_URL/models" >/dev/null 2>&1; then
  info "이미 서버가 응답 중: $BASE_URL"; exit 0
fi

case "$BACKEND" in
  llama)
    have llama-server || fail "llama-server 없음 (00_prereqs.sh)"
    main=$(gguf_main_file)
    [[ -n "$main" ]] || fail "GGUF 가 없습니다: $MODEL_DIR (01_download_model.sh 먼저)"
    # Sampling per Qwen/unsloth recommendation for Qwen3-Coder-Next: temp 1.0, top_p 0.95, top_k 40, min_p 0.01
    cmd=(llama-server
      --model "$main" --alias "$MODEL_ID"
      --host 127.0.0.1 --port "$PORT"
      --ctx-size "$CTX" --n-predict "$MAX_TOKENS"
      -ngl 999 --flash-attn on --jinja
      --temp 1.0 --top-p 0.95 --top-k 40 --min-p 0.01 --repeat-penalty 1.0
      --parallel 1 --cache-reuse 256)
    ;;
  mlx)
    have mlx_lm.server || fail "mlx_lm.server 없음 (uv tool install mlx-lm)"
    [[ -f "$MODEL_DIR/config.json" ]] || fail "모델이 없습니다: $MODEL_DIR (01_download_model.sh 먼저)"
    cmd=(mlx_lm.server --model "$MODEL_DIR" --host 127.0.0.1 --port "$PORT" --max-tokens "$MAX_TOKENS" --log-level INFO)
    ;;
esac

info "백엔드: $BACKEND  |  $BASE_URL  |  ctx=$CTX"
if [[ "${1:-}" == "--bg" ]]; then
  nohup "${cmd[@]}" >"$SERVER_LOG" 2>&1 &
  echo $! >"$SERVER_PID"
  info "백그라운드 기동 (pid $(cat "$SERVER_PID")). 로그: $SERVER_LOG"
  for _ in $(seq 1 90); do
    curl -fsS --max-time 2 "$BASE_URL/models" >/dev/null 2>&1 && break
    sleep 2
  done
  if curl -fsS --max-time 2 "$BASE_URL/models" >/dev/null 2>&1; then
    info "서버 OK"; curl -fsS "$BASE_URL/models" | jq -r '.data[].id' 2>/dev/null | sed 's/^/     - /'
    info "다음: ./scripts/03_setup_pi.sh"
  else
    warn "아직 응답 없음. 큰 모델은 첫 로드에 1~2분 걸립니다: tail -f $SERVER_LOG"
  fi
else
  info "포그라운드 실행. 다른 터미널에서 ./scripts/03_setup_pi.sh 를 진행하세요."
  exec "${cmd[@]}"
fi
