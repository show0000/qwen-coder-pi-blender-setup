#!/usr/bin/env bash
# Install the Blender MCP addon and register the MCP server with pi.
source "$(dirname "$0")/common.sh"

have uvx || fail "uv/uvx 가 없습니다 (brew install uv)."
have pi  || fail "pi 가 없습니다."

info "Blender 애드온 설치 (uvx mcp-for-blender install-addon)"
uvx mcp-for-blender install-addon || {
  warn "자동 설치 실패. 수동: uvx mcp-for-blender addon-paths 로 경로 확인 후 Blender Preferences → Add-ons → Install"
}

info "pi MCP 등록: blender"
merge_json "$PI_AGENT_DIR/mcp.json" '{
  "mcpServers": {
    "blender": {
      "command": "uvx",
      "args": ["mcp-for-blender"],
      "env": { "DISABLE_TELEMETRY": "true" }
    }
  }
}'

cat <<'EOF'

다음을 Blender에서 한 번만 하면 됩니다:
  1) Blender 실행 → Edit → Preferences → Add-ons → "MCP for Blender" (또는 "Blender MCP") 체크
  2) 3D 뷰포트에서 N 키 → BlenderMCP 탭 → Connect to MCP server (포트 9876)
     (최신 애드온은 Blender 시작 시 자동으로 서버를 엽니다)

터미널에서 uvx mcp-for-blender 를 직접 실행하지 마세요. pi 가 stdio 로 띄웁니다.
pi 에서 확인:  pi mcp list
EOF
info "다음: ./scripts/05_setup_orca.sh (orca 오케스트레이터)"
