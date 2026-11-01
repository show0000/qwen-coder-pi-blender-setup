#!/usr/bin/env bash
# vision-describe — ask the local VLM (Qwen3.8-27B VL on :8081) about an image and print text.
# Lets the text-only coder model "see" without switching models (no context compaction).
#
#   vision-describe <image.png|jpg> ["question"] [--max-tokens N] [--json]
#   vision-describe --check           # server reachable?
#
# Env: VISION_BASE_URL (default http://127.0.0.1:8081/v1), VISION_MODEL_ID, VISION_MAX_TOKENS (600)
set -euo pipefail
[[ -f "$HOME/.config/qwen-coder/env.sh" ]] && source "$HOME/.config/qwen-coder/env.sh"
URL="${VISION_BASE_URL:-http://127.0.0.1:${VISION_PORT:-8081}/v1}"
MODEL="${VISION_MODEL_ID:-qwen3.8-27b-vl}"
MAXTOK="${VISION_MAX_TOKENS:-600}"
JSON=0; IMG=""; Q=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) curl -fsS --max-time 2 "$URL/models" >/dev/null && { echo "vision server up: $URL ($MODEL)"; exit 0; } || { echo "vision server DOWN: $URL  → qwen vision start" >&2; exit 1; } ;;
    --max-tokens) MAXTOK="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    *) if [[ -z "$IMG" ]]; then IMG="$1"; else Q="${Q:+$Q }$1"; fi; shift ;;
  esac
done
[[ -n "$IMG" ]] || { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
[[ -f "$IMG" ]] || { echo "no such image: $IMG" >&2; exit 1; }
curl -fsS --max-time 2 "$URL/models" >/dev/null || { echo "vision server not running: $URL  → qwen vision start" >&2; exit 2; }

Q="${Q:-Describe this image precisely. If it is a 3D viewport, report: objects visible, their relative placement and orientation, any holes/cuts/features and which face they are on, and anything that looks wrong (overlaps, gaps, flipped parts). Give approximate proportions. Be concrete and brief.}"

case "${IMG##*.}" in jpg|jpeg|JPG|JPEG) MIME=image/jpeg ;; webp) MIME=image/webp ;; *) MIME=image/png ;; esac
# downscale large screenshots to keep the request small (sips is built into macOS)
TMP=""; W=$(sips -g pixelWidth "$IMG" 2>/dev/null | awk '/pixelWidth/{print $2}')
if [[ -n "${W:-}" && "$W" -gt 1280 ]]; then
  TMP=$(mktemp -t vd).jpg; sips -Z 1280 -s format jpeg -s formatOptions 80 "$IMG" --out "$TMP" >/dev/null 2>&1 && { IMG="$TMP"; MIME=image/jpeg; }
fi
B64=$(base64 < "$IMG" | tr -d '\n'); [[ -n "$TMP" ]] && rm -f "$TMP"

PAYLOAD=$(IMG_MIME="$MIME" IMG_B64="$B64" QUESTION="$Q" MODEL="$MODEL" MAXTOK="$MAXTOK" python3 - <<'PY'
import json, os
print(json.dumps({
  "model": os.environ["MODEL"], "max_tokens": int(os.environ["MAXTOK"]), "temperature": 0.2,
  "messages": [{"role": "user", "content": [
    {"type": "text", "text": os.environ["QUESTION"]},
    {"type": "image_url", "image_url": {"url": f"data:{os.environ['IMG_MIME']};base64,{os.environ['IMG_B64']}"}}
  ]}]}))
PY
)
RESP=$(curl -fsS --max-time 300 "$URL/chat/completions" -H 'Content-Type: application/json' -d "$PAYLOAD")
if [[ "$JSON" == "1" ]]; then printf '%s\n' "$RESP"; else
  printf '%s' "$RESP" | python3 -c 'import json,sys; d=json.load(sys.stdin); c=d["choices"][0]["message"]["content"]; print(c.strip() if isinstance(c,str) else "".join(p.get("text","") for p in c).strip())'
fi
