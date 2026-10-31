#!/usr/bin/env bash
# Register the local server as a provider in pi's models.json.
source "$(dirname "$0")/common.sh"

have pi || fail "pi 가 없습니다 (00_prereqs.sh)."

patch=$(cat <<JSON
{
  "\$schema": "https://pi.dev/schemas/models.schema.json",
  "providers": {
    "local": {
      "baseUrl": "$BASE_URL",
      "api": "openai-completions",
      "apiKey": "local",
      "models": [
        {
          "id": "$MODEL_ID",
          "name": "Qwen3-Coder-Next 80B-A3B (local, $BACKEND)",
          "contextWindow": $CTX,
          "maxTokens": $MAX_TOKENS,
          "input": ["text"],
          "samplingParams": { "temperature": 1.0, "top_p": 0.95, "top_k": 40, "min_p": 0.01 }
        }
      ]
    }
  }
}
JSON
)
merge_json "$PI_AGENT_DIR/models.json" "$patch"

# sensible compaction headroom for a 131K window
merge_json "$PI_AGENT_DIR/settings.json" '{"compaction": {"reserveTokens": 16384}}'

info "등록 완료. 실행 예:"
echo "    cd ~/your-project && pi --model local/$MODEL_ID"
echo "    (pi 안에서 /model 선택 후 Ctrl+S 로 기본 모델 저장)"
info "다음: ./scripts/04_setup_blender_mcp.sh"
