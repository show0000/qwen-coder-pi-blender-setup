#!/usr/bin/env bash
# Register Jira/Confluence (mcp-atlassian) and GitLab (@zereight/mcp-gitlab) MCP servers in pi.
# Secrets live only in ~/.config/qwen-coder/enterprise.env; wrapper scripts source it at launch.
#
#   ./scripts/09_setup_enterprise_mcp.sh            # online: uvx / npx fetch on demand
#   OFFLINE=1 ...                                   # uses binaries installed by install_offline.sh
source "$(dirname "$0")/common.sh"
have pi || fail "pi 가 없습니다."

ENVF="$HOME/.config/qwen-coder/enterprise.env"
if [[ ! -f "$ENVF" ]]; then
  mkdir -p "$(dirname "$ENVF")"
  cp "$(dirname "$0")/../config/enterprise.env.example" "$ENVF"; chmod 600 "$ENVF"
  warn "설정 파일을 만들었습니다. URL 과 토큰을 채운 뒤 다시 실행하세요: $ENVF"
  exit 0
fi
# shellcheck disable=SC1090
set -a; source "$ENVF"; set +a

BIN="$HOME/.local/bin"; mkdir -p "$BIN"

# ---- resolve launch commands ----------------------------------------------------
if [[ "$OFFLINE" == "1" ]]; then
  ATL_CMD="${ATLASSIAN_MCP_CMD:-$BIN/mcp-atlassian}"
  GL_CMD="${GITLAB_MCP_CMD:-$HOME/.local/opt/mcp-gitlab/bin/zereight-mcp-gitlab}"
  [[ -x "$ATL_CMD" ]] || fail "오프라인: mcp-atlassian 없음 ($ATL_CMD). 번들을 ENTERPRISE=1 로 다시 만드세요."
  [[ -x "$GL_CMD"  ]] || fail "오프라인: mcp-gitlab 없음 ($GL_CMD). 번들을 ENTERPRISE=1 로 다시 만드세요."
  ATL_LAUNCH="exec \"$ATL_CMD\" \"\$@\""
  GL_LAUNCH="export PATH=\"$HOME/.local/opt/node/bin:\$PATH\"; exec \"$GL_CMD\" \"\$@\""
else
  have uvx || fail "uvx 없음"; have npx || fail "npx 없음 (node)"
  ATL_LAUNCH='exec uvx mcp-atlassian "$@"'
  GL_LAUNCH='exec npx -y @zereight/mcp-gitlab@latest "$@"'
fi

# ---- wrappers: source secrets at launch, keep mcp.json clean ----------------------
cat > "$BIN/atlassian-mcp" <<EOF
#!/usr/bin/env bash
set -a; source "$ENVF"; set +a
# drop empty optional vars so the server uses its defaults
for v in JIRA_PROJECTS_FILTER CONFLUENCE_SPACES_FILTER ENABLED_TOOLS HTTP_PROXY HTTPS_PROXY; do [[ -z "\${!v:-}" ]] && unset \$v; done
[[ -n "\${CONFLUENCE_PERSONAL_TOKEN:-}" ]] || unset CONFLUENCE_URL   # Confluence 미사용 시 Jira 만
$ATL_LAUNCH
EOF
cat > "$BIN/gitlab-mcp" <<EOF
#!/usr/bin/env bash
set -a; source "$ENVF"; set +a
for v in NODE_EXTRA_CA_CERTS HTTP_PROXY HTTPS_PROXY; do [[ -z "\${!v:-}" ]] && unset \$v; done
$GL_LAUNCH
EOF
chmod 700 "$BIN/atlassian-mcp" "$BIN/gitlab-mcp"

# ---- register in pi ----------------------------------------------------------------
patch='{"mcpServers":{}}'
[[ -n "${JIRA_PERSONAL_TOKEN:-}" ]] && patch=$(printf '%s' "$patch" | python3 -c 'import json,sys;d=json.load(sys.stdin);d["mcpServers"]["atlassian"]={"command":sys.argv[1],"args":[]};print(json.dumps(d))' "$BIN/atlassian-mcp") || warn "JIRA_PERSONAL_TOKEN 비어 있음 → atlassian 건너뜀"
[[ -n "${GITLAB_PERSONAL_ACCESS_TOKEN:-}" ]] && patch=$(printf '%s' "$patch" | python3 -c 'import json,sys;d=json.load(sys.stdin);d["mcpServers"]["gitlab"]={"command":sys.argv[1],"args":[]};print(json.dumps(d))' "$BIN/gitlab-mcp") || warn "GITLAB_PERSONAL_ACCESS_TOKEN 비어 있음 → gitlab 건너뜀"
merge_json "$PI_AGENT_DIR/mcp.json" "$patch"

# many tools → let pi defer them (tool_search) and compose via codemode
merge_json "$PI_AGENT_DIR/settings.json" '{"defaultTools": ["read","bash","edit","write","grep","find","ls","+codemode","+tool_search"]}'

cat <<EOF

등록 완료. 확인:
  pi mcp list
  pi 안에서: "JIRA 에서 내게 할당된 열린 이슈 5개 요약해줘" / "gitlab 프로젝트 X 의 열린 MR 목록"

연결 테스트 (토큰/URL/인증서 문제를 pi 밖에서 먼저 확인):
  curl -sS -H "Authorization: Bearer \$JIRA_PERSONAL_TOKEN" "\$JIRA_URL/rest/api/2/myself" | head -c 300
  curl -sS -H "PRIVATE-TOKEN: \$GITLAB_PERSONAL_ACCESS_TOKEN" "\$GITLAB_API_URL/user" | head -c 300

도구가 100개 가까이 되므로 $ENVF 의 ENABLED_TOOLS / GITLAB_TOOLSETS 로 쓰는 것만 남기는 편이
로컬 모델의 도구 선택 정확도와 컨텍스트에 유리합니다. 수정 후 pi 재시작만 하면 됩니다 (재등록 불필요).
EOF
