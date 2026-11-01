#!/usr/bin/env bash
# qwen — control the local Qwen3-Coder-Next server and launch pi on it.
#
#   qwen start [--fg]     start llama-server in background (or foreground with --fg)
#   qwen stop             stop it
#   qwen restart
#   qwen status           server / model / memory at a glance
#   qwen logs [-n N]      tail server log (follows)
#   qwen pi [args...]     start pi on the local model in the current directory (starts server if needed)
#   qwen check            full health check (check.sh)
#
# Installed as ~/.local/bin/qwen by 03_setup_pi.sh / install_offline.sh.
HERE="$(cd "$(dirname "$(readlink "$0" || echo "$0")")" && pwd)"
[[ -f "$HOME/.config/qwen-coder/env.sh" ]] && source "$HOME/.config/qwen-coder/env.sh"
source "$HERE/common.sh"
set +e

server_pid() {
  local p
  [[ -f "$SERVER_PID" ]] && p=$(cat "$SERVER_PID") && kill -0 "$p" 2>/dev/null && { echo "$p"; return; }
  pgrep -f "llama-server .*--port $PORT" | head -1
}
server_up() { curl -fsS --max-time 2 "$BASE_URL/models" >/dev/null 2>&1; }

cmd_start() {
  if server_up; then info "이미 실행 중: $BASE_URL (pid $(server_pid))"; return 0; fi
  if [[ "${1:-}" == "--fg" ]]; then exec "$HERE/02_serve_model.sh"; fi
  "$HERE/02_serve_model.sh" --bg
}

cmd_stop() {
  local p; p=$(server_pid)
  if [[ -z "$p" ]]; then warn "실행 중인 서버 없음"; rm -f "$SERVER_PID"; return 0; fi
  info "종료 중 (pid $p)…"
  kill "$p" 2>/dev/null
  for _ in $(seq 1 30); do kill -0 "$p" 2>/dev/null || break; sleep 0.5; done
  kill -0 "$p" 2>/dev/null && { warn "응답 없음, 강제 종료"; kill -9 "$p" 2>/dev/null; }
  rm -f "$SERVER_PID"
  info "종료됨"
}

cmd_status() {
  local p; p=$(server_pid)
  echo "backend : $BACKEND   url: $BASE_URL   ctx: $CTX"
  echo "model   : $HF_REPO ${QUANT:+($QUANT)}"
  if [[ -n "$p" ]]; then
    local rss; rss=$(ps -o rss= -p "$p" 2>/dev/null | awk '{printf "%.1f GB", $1/1048576}')
    echo "process : running (pid $p, RSS $rss)"
  else
    echo "process : stopped"
  fi
  if server_up; then
    echo "api     : up — $(curl -fsS "$BASE_URL/models" | jq -r '[.data[].id]|join(", ")' 2>/dev/null)"
  else
    [[ -n "$p" ]] && echo "api     : loading… (tail: qwen logs)" || echo "api     : down"
  fi
  if [[ "$(uname -s)" == "Darwin" ]]; then
    local free total
    total=$(sysctl -n hw.memsize | awk '{printf "%.0f", $1/1073741824}')
    free=$(vm_stat | awk '/Pages free/{f=$3} /Pages inactive/{i=$3} END{gsub(/\./,"",f);gsub(/\./,"",i); printf "%.1f", (f+i)*16384/1073741824}')
    echo "memory  : ~${free} GB free of ${total} GB"
  fi
}

cmd_logs() { local n=100; [[ "${1:-}" == "-n" ]] && n="${2:-100}"; [[ -f "$SERVER_LOG" ]] || { warn "로그 없음: $SERVER_LOG"; return 1; }; tail -n "$n" -f "$SERVER_LOG"; }

cmd_pi() {
  server_up || { info "서버가 꺼져 있어 먼저 시작합니다."; "$HERE/02_serve_model.sh" --bg || return 1; }
  exec pi --model "local/$MODEL_ID" "$@"
}

case "${1:-}" in
  start)   shift; cmd_start "$@" ;;
  stop)    cmd_stop ;;
  restart) cmd_stop; cmd_start ;;
  status|st) cmd_status ;;
  logs|log) shift; cmd_logs "$@" ;;
  pi)      shift; cmd_pi "$@" ;;
  check)   exec "$HERE/check.sh" ;;
  *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
