# Qwen3-Coder-Next + pi + orca + Blender MCP (MacBook M3 Max 128GB)

Hugging Face에서 Qwen3-Coder-Next(80B-A3B) MLX 4bit 가중치를 받아 로컬 OpenAI 호환 서버로 띄우고,
pi 코딩 에이전트를 Claude Code처럼 터미널에서 쓰고, orca 오케스트레이터와 Blender(선택: OrcaSlicer)를 MCP로 연결하는 셋업입니다.

```
터미널 ── pi (coding agent) ──▶ http://127.0.0.1:1234/v1  (LM Studio 또는 mlx_lm.server)
            │                          └─ Qwen3-Coder-Next-MLX-4bit (~46GB, 262K ctx)
            ├─ MCP: blender    ──▶ uvx mcp-for-blender  ──▶ Blender addon (port 9876)
            ├─ MCP: orca       ──▶ orca mcp serve       ──▶ 워크트리/run 상태 (~/.orca/orca.db)
            └─ MCP: orcaslicer ──▶ uvx orcaslicer-mcp   ──▶ OrcaSlicer Remote API (선택)
orca ── run 마다 git worktree 생성 ──▶ pi-local "<task>" (비대화형 pi, 같은 로컬 모델)
```

## 하드웨어 기준

| 항목 | 값 |
|---|---|
| 모델 | Qwen/Qwen3-Coder-Next (80B total / 3B active MoE), Apache 2.0 |
| 가중치 | lmstudio-community/Qwen3-Coder-Next-MLX-4bit, 약 46GB |
| 컨텍스트 | 네이티브 262,144 토큰. 기본 셋업은 131,072로 로드 |
| 예상 속도 | M3 Max 기준 약 20~30 tok/s (MLX) |
| 메모리 | 모델 46GB + KV 캐시 수 GB. Blender와 OrcaSlicer를 동시에 띄워도 128GB 안에서 여유 있음 |

## 빠른 시작

```bash
git clone <this-repo> && cd qwen-coder-pi-blender-setup
chmod +x scripts/*.sh

./scripts/00_prereqs.sh          # Homebrew, uv, Node 22, pi, LM Studio CLI, hf CLI
./scripts/01_download_model.sh   # Hugging Face에서 MLX 4bit 가중치 다운로드 (~46GB)
./scripts/02_serve_model.sh      # 모델 서버 기동 (기본: LM Studio, 포트 1234)
./scripts/03_setup_pi.sh         # ~/.pi/agent/models.json 에 로컬 provider 등록
./scripts/04_setup_blender_mcp.sh    # Blender 애드온 설치 + pi MCP 등록
./scripts/05_setup_orca.sh           # orca 설치 + pi MCP 등록 + pi-local 래퍼
./scripts/check.sh                   # 전체 연결 상태 점검
# 선택: 3D 프린팅 슬라이싱까지 에이전트로 다룰 때
ORCA_API_TOKEN=... ./scripts/07_setup_orcaslicer_mcp.sh
```

또는 `make all` 로 00~05를 순서대로 실행합니다 (OrcaSlicer 는 `make orcaslicer`). 각 스크립트는 멱등적이라 다시 실행해도 안전합니다.

## 단계별 설명

### 0. 사전 준비 (00_prereqs.sh)

- Homebrew, uv, Node.js 22 설치
- pi 코딩 에이전트: 공식 설치 스크립트 `curl -fsSL https://pi.dev/install.sh | sh`
  (npm 패키지 이름은 `@earendil-works/pi-coding-agent`, 예전 `@mariozechner/...`는 deprecated)
- LM Studio 앱과 `lms` CLI (기본 백엔드)
- `hf` CLI (huggingface_hub) 와 mlx-lm (대체 백엔드용)

### 1. 모델 다운로드 (01_download_model.sh)

Hugging Face에서 `lmstudio-community/Qwen3-Coder-Next-MLX-4bit`을
`~/.lmstudio/models/lmstudio-community/Qwen3-Coder-Next-MLX-4bit` 경로로 받습니다.
이 경로는 LM Studio가 자동 인식하는 레이아웃이면서 mlx_lm.server에서도 그대로 쓸 수 있습니다.

다른 양자화를 쓰려면 환경변수로 바꿉니다.

```bash
HF_REPO=mlx-community/Qwen3-Coder-Next-4bit ./scripts/01_download_model.sh
# 더 높은 품질(~62GB): HF_REPO=mlx-community/Qwen3-Coder-Next-6bit
# 8bit(~85GB)도 128GB에서 동작하지만 속도가 떨어짐
```

### 2. 모델 서버 (02_serve_model.sh)

두 가지 백엔드를 지원합니다.

| 백엔드 | 명령 | 포트 | 비고 |
|---|---|---|---|
| LM Studio (기본) | `./scripts/02_serve_model.sh` | 1234 | Qwen3-Coder 툴콜 파서 내장. 에이전트 용도에 가장 안정적 |
| mlx_lm.server | `BACKEND=mlx ./scripts/02_serve_model.sh` | 8080 | 앱 없이 CLI만으로 운용. 툴콜 파싱은 mlx-lm 버전에 따라 다름 |

컨텍스트 길이는 `CTX=262144` 처럼 바꿀 수 있습니다. 모델 식별자는 `qwen3-coder-next` 로 고정되어 pi 설정과 맞물립니다.

### 3. pi 설정 (03_setup_pi.sh)

`~/.pi/agent/models.json` 에 아래 provider를 병합합니다 (기존 내용은 보존).

```json
{
  "$schema": "https://pi.dev/schemas/models.schema.json",
  "providers": {
    "local": {
      "baseUrl": "http://127.0.0.1:1234/v1",
      "api": "openai-completions",
      "apiKey": "local",
      "models": [
        {
          "id": "qwen3-coder-next",
          "name": "Qwen3-Coder-Next 80B-A3B (MLX 4bit)",
          "contextWindow": 131072,
          "maxTokens": 32768,
          "input": ["text"]
        }
      ]
    }
  }
}
```

실행:

```bash
cd ~/your-project
pi --model local/qwen3-coder-next
```

pi 안에서 `/model` 로 고른 뒤 Ctrl+S 를 누르면 기본 모델로 저장됩니다.
`BACKEND=mlx` 로 서버를 띄웠다면 `BACKEND=mlx ./scripts/03_setup_pi.sh` 로 포트 8080을 등록하세요.

### 4. Blender MCP (04_setup_blender_mcp.sh)

PyPI 패키지는 `blender-mcp`에서 `mcp-for-blender`로 이름이 바뀌었습니다 (기존 이름도 계속 동작).

1. `uvx mcp-for-blender install-addon` 으로 Blender 애드온 파일을 애드온 폴더에 복사
2. Blender 실행 → Edit → Preferences → Add-ons → "MCP for Blender" 활성화
   (3D 뷰포트 사이드바 N 패널에 BlenderMCP 탭이 생기고, 애드온이 포트 9876으로 소켓 서버를 엽니다)
3. 스크립트가 `~/.pi/agent/mcp.json` 에 `blender` 서버를 등록

주의: `uvx mcp-for-blender` 를 터미널에서 직접 실행하지 마세요. MCP 클라이언트(pi)가 stdio로 띄웁니다.

### 5. orca 오케스트레이터 (05_setup_orca.sh)

orca(github.com/orca-cli/orca)는 run 마다 git worktree를 만들고 상태를 SQLite에 기록하면서 여러 코딩 에이전트를 병렬로 돌리는 Go 바이너리입니다. MCP를 지원하는 어떤 에이전트와도 붙습니다.

스크립트가 하는 일:

1. `brew install orca-cli/tap/orca`
2. `~/.pi/agent/mcp.json` 에 `orca` 서버 등록 (`orca mcp serve`, stdio). pi 세션 안에서 orca의 run/pod 도구를 호출해 워크트리 생성과 상태 추적을 맡길 수 있습니다.
3. `~/.local/bin/pi-local` 래퍼 생성. `pi --model local/qwen3-coder-next -p "<prompt>"` 를 감싼 비대화형 실행기라서 orca가 run 을 띄울 때 에이전트 커맨드로 지정할 수 있습니다.

repo 쪽:

```bash
cd ~/your-repo
orca init                             # .orca/ 생성 (설치된 버전의 명령은 orca --help 로 확인)
cp templates/orca/AGENTS.md .orca/    # 모든 run 에 주입되는 지침
orca run "Add retry logic to the MQTT client"
```

주의: orca 저장소의 adapter 는 claude-code, codex, aider, opencode 등 이름으로 등록되며, custom command adapter 의 설정 필드명은 설치된 버전의 `.orca/orca.toml` 문서를 따릅니다. 해당 필드가 없으면 pi 안에서 orca MCP 도구로 run 을 관리하는 방식(2번)만 사용하면 됩니다.

### 7. (선택) OrcaSlicer MCP (07_setup_orcaslicer_mcp.sh)

`orcaslicer-mcp` 는 OrcaSlicer의 로컬 Remote API에 붙어 모델 로드, 플레이트 배치, 설정 변경, 슬라이싱, G-code 분석을 수행합니다.

전제 조건:

- Remote API가 포함된 OrcaSlicer MCP 빌드가 필요합니다 (일반 배포판에는 API가 없음).
  https://pypi.org/project/orcaslicer-mcp 의 안내에 따라 해당 빌드를 받으세요.
- OrcaSlicer → Preferences → Remote API 에서 API 활성화 후 토큰 복사

```bash
ORCA_API_TOKEN=<복사한 토큰> ./scripts/07_setup_orcaslicer_mcp.sh
```

토큰은 `~/.pi/agent/mcp.json` 의 env 항목에만 저장되며 이 저장소에는 커밋되지 않습니다.

Blender에서 STL/3MF를 내보낸 뒤 OrcaSlicer MCP의 `load_model` → `arrange_plate` → `slice_and_wait` 로 이어지는
모델링 → 슬라이싱 파이프라인을 pi 한 세션에서 돌릴 수 있습니다.

## 프로젝트별 설정

`templates/` 아래 파일을 프로젝트 루트에 복사하면 됩니다.

- `templates/AGENTS.md`: Blender(bpy) 작업용 에이전트 지침. pi가 프로젝트 루트의 AGENTS.md를 읽습니다.
- `templates/.pi/mcp.json`: 프로젝트 단위 MCP 설정 (사용자 전역 설정 대신 쓰고 싶을 때)
- `templates/orca/AGENTS.md`: orca run 에 주입할 지침 (`.orca/AGENTS.md` 로 복사)

```bash
cp -r templates/AGENTS.md templates/.pi ~/your-blender-project/
```

## 점검 (check.sh)

```bash
./scripts/check.sh
```

모델 서버 `/v1/models` 응답과 실제 chat completion, pi 설치 여부, models.json / mcp.json 등록 상태(blender, orca, orcaslicer), orca 바이너리, Blender 애드온 포트(9876), OrcaSlicer API 포트(13130)를 순서대로 확인합니다.

## 운영 팁

- 메모리: Activity Monitor에서 "메모리 압박"이 노란색 이상이면 `CTX=65536` 으로 낮추세요.
- 첫 토큰 지연: 긴 컨텍스트를 처음 넣을 때 prefill이 수십 초 걸릴 수 있습니다. LM Studio는 prompt cache를 유지하므로 같은 세션에서는 빨라집니다.
- 컴팩션: pi는 contextWindow − reserveTokens(기본 16384)에서 요약을 시작합니다. 131K 창이면 충분합니다.
- 오프라인: `PI_OFFLINE=1 pi` 로 pi.dev 카탈로그 갱신과 버전 체크를 끕니다.
- 안전: pi는 도구 호출 전에 승인을 묻지 않습니다. 중요한 디렉터리에서는 git으로 작업 상태를 자주 커밋하세요.
- Blender 버전: bpy API가 버전마다 바뀌므로 AGENTS.md에 사용 중인 Blender 버전을 적어두면 코드 품질이 눈에 띄게 좋아집니다.

## 참고 링크

- pi: https://github.com/earendil-works/pi (docs/models.md, docs/mcp.md)
- Qwen3-Coder-Next: https://huggingface.co/Qwen/Qwen3-Coder-Next
- MLX 4bit: https://huggingface.co/lmstudio-community/Qwen3-Coder-Next-MLX-4bit
- orca: https://github.com/orca-cli/orca
- MCP for Blender: https://github.com/ahujasid/mcp-for-blender
- OrcaSlicer MCP: https://pypi.org/project/orcaslicer-mcp
- LM Studio CLI: https://lmstudio.ai/docs/cli
