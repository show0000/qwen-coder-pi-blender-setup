#!/usr/bin/env bash
# Health check for the whole stack.
source "$(dirname "$0")/common.sh"
set +e

ok()   { printf '  %s✔%s %s\n' "$c_green" "$c_reset" "$*"; }
bad()  { printf '  %s✘%s %s\n' "$c_red"   "$c_reset" "$*"; }
port_open() { nc -z -G 1 127.0.0.1 "$1" >/dev/null 2>&1; }

echo "== 모델"
[[ -f "$MODEL_DIR/config.json" ]] && ok "가중치 있음: $MODEL_DIR" || bad "가중치 없음 ($MODEL_DIR)"

echo "== 모델 서버 ($BACKEND, $BASE_URL)"
if models=$(curl -fsS --max-time 3 "$BASE_URL/models" 2>/dev/null); then
  ok "응답 OK"
  echo "$models" | jq -r '.data[].id' 2>/dev/null | sed 's/^/     - /'
  # one tiny completion to confirm the model actually answers
  if curl -fsS --max-time 120 "$BASE_URL/chat/completions" -H 'Content-Type: application/json' \
     -d "{\"model\":\"$MODEL_ID\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with OK\"}],\"max_tokens\":8}" \
     | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
    ok "chat/completions 동작"
  else
    bad "chat/completions 실패 (로그: $SERVER_LOG)"
  fi
else
  bad "서버 응답 없음 → ./scripts/02_serve_model.sh"
fi

echo "== pi"
if have pi; then
  ok "pi $(pi --version 2>/dev/null)"
  grep -q "\"$MODEL_ID\"" "$PI_AGENT_DIR/models.json" 2>/dev/null && ok "models.json 에 $MODEL_ID 등록" || bad "models.json 미등록 → 03_setup_pi.sh"
  grep -q '"blender"'    "$PI_AGENT_DIR/mcp.json" 2>/dev/null && ok "mcp.json: blender"    || bad "mcp.json: blender 없음 → 04_setup_blender_mcp.sh"
  grep -q '"orca"'       "$PI_AGENT_DIR/mcp.json" 2>/dev/null && ok "mcp.json: orca"       || bad "mcp.json: orca 없음 → 05_setup_orca.sh"
  grep -q '"orcaslicer"' "$PI_AGENT_DIR/mcp.json" 2>/dev/null && ok "mcp.json: orcaslicer" || warn "  mcp.json: orcaslicer 없음 (선택, 07_setup_orcaslicer_mcp.sh)"
else
  bad "pi 없음"
fi

echo "== orca"
have orca && ok "orca $(orca version 2>/dev/null || orca --version 2>/dev/null)" || bad "orca 없음 → 05_setup_orca.sh"
[[ -x "$HOME/.local/bin/pi-local" ]] && ok "pi-local 래퍼 있음" || bad "pi-local 없음 → 05_setup_orca.sh"

echo "== Blender (addon socket 9876)"
port_open 9876 && ok "Blender MCP 애드온 서버 열림" || bad "9876 닫힘 → Blender 실행 후 애드온 활성화/Connect"

echo "== OrcaSlicer (Remote API 13130, 선택)"
port_open 13130 && ok "OrcaSlicer Remote API 열림" || warn "  13130 닫힘 (OrcaSlicer 를 쓸 때만: MCP 빌드 실행 + Remote API 활성화)"

echo
echo "실행:  cd ~/your-project && pi --model local/$MODEL_ID"
