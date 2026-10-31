#!/usr/bin/env bash
# Register orcaslicer-mcp with pi.
#   ORCA_API_TOKEN=<token from OrcaSlicer Preferences → Remote API> ./scripts/07_setup_orcaslicer_mcp.sh
#   ORCA_API_URL defaults to http://127.0.0.1:13130
source "$(dirname "$0")/common.sh"

have pi || fail "pi 가 없습니다."
[[ "$OFFLINE" == "1" ]] || have uvx || fail "uv/uvx 가 없습니다."

: "${ORCA_API_TOKEN:?ORCA_API_TOKEN 을 설정하세요. OrcaSlicer → Preferences → Remote API 에서 활성화 후 토큰 복사}"
ORCA_API_URL="${ORCA_API_URL:-http://127.0.0.1:13130}"

info "pi MCP 등록: orcaslicer ($ORCA_API_URL)"
cmdjson="$(mcp_cmd_json orcaslicer)"
patch=$(CMDJSON="$cmdjson" ORCA_API_URL="$ORCA_API_URL" python3 -c 'import json,os;c=json.loads("{"+os.environ["CMDJSON"]+"}");c["env"]={"ORCA_API_TOKEN":os.environ["ORCA_API_TOKEN"],"ORCA_API_URL":os.environ["ORCA_API_URL"]};print(json.dumps({"mcpServers":{"orcaslicer":c}}))')
merge_json "$PI_AGENT_DIR/mcp.json" "$patch"

cat <<EOF

OrcaSlicer 쪽 체크리스트:
  - Remote API 가 포함된 OrcaSlicer MCP 빌드를 사용 중인지 (일반 릴리스에는 API 없음)
  - Preferences → Remote API 활성화, 포트 13130
  - OrcaSlicer 가 실행 중이어야 MCP 도구가 응답합니다

Blender → OrcaSlicer 파이프라인 예시 (pi 프롬프트):
  "현재 Blender 씬의 활성 오브젝트를 ./out/part.stl 로 내보내고, OrcaSlicer에 로드해서
   플레이트에 자동 배치한 뒤 0.2mm 레이어로 슬라이스하고 예상 시간과 필라멘트 사용량을 알려줘"
EOF
info "다음: ./scripts/check.sh"
