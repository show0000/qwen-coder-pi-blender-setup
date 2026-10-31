# Qwen3-Coder-Next + pi + orca + Blender MCP (MacBook M3 Max 128GB)

Hugging Face에서 Qwen3-Coder-Next(80B-A3B) 가중치를 받아 llama.cpp 로 로컬 OpenAI 호환 서버를 띄우고,
pi 코딩 에이전트를 Claude Code처럼 터미널에서 쓰고, orca 오케스트레이터와 Blender(선택: OrcaSlicer)를 MCP로 연결하는 셋업입니다.
GUI 모델 앱(LM Studio, Ollama)은 쓰지 않습니다. 전부 brew / uv tool 로 설치되는 CLI 입니다.

```
터미널 ── pi (coding agent) ──▶ http://127.0.0.1:8080/v1  (llama-server, 또는 mlx_lm.server)
            │                          └─ Qwen3-Coder-Next GGUF UD-Q6_K_XL (~68GB, 262K ctx)
            ├─ MCP: blender    ──▶ uvx mcp-for-blender  ──▶ Blender addon (port 9876)
            ├─ MCP: orca       ──▶ orca mcp serve       ──▶ 워크트리/run 상태 (~/.orca/orca.db)
            └─ MCP: orcaslicer ──▶ uvx orcaslicer-mcp   ──▶ OrcaSlicer Remote API (선택)
orca ── run 마다 git worktree 생성 ──▶ pi-local "<task>" (비대화형 pi, 같은 로컬 모델)
```

## 하드웨어 기준

| 항목 | 값 |
|---|---|
| 모델 | Qwen/Qwen3-Coder-Next (80B total / 3B active MoE), Apache 2.0 |
| 가중치 | unsloth/Qwen3-Coder-Next-GGUF, UD-Q6_K_XL 약 68GB (대안: mlx-community/Qwen3-Coder-Next-6bit) |
| 컨텍스트 | 네이티브 262,144 토큰. 기본 셋업은 131,072로 로드 |
| 예상 속도 | M3 Max 기준 약 20~30 tok/s |
| 메모리 | 모델 68GB + KV 캐시 수 GB. Blender와 OrcaSlicer를 동시에 띄워도 128GB 안에서 여유 있음 (UE5까지 동시에 띄우면 4bit 권장) |

## 빠른 시작

```bash
git clone https://github.com/show0000/qwen-coder-pi-blender-setup.git && cd qwen-coder-pi-blender-setup
chmod +x scripts/*.sh

./scripts/00_prereqs.sh              # Homebrew, uv, Node 22, pi, llama.cpp, hf CLI
./scripts/01_download_model.sh       # Hugging Face에서 GGUF UD-Q6_K_XL 다운로드 (~68GB)
./scripts/02_serve_model.sh --bg     # llama-server 백그라운드 기동 (포트 8080)
./scripts/03_setup_pi.sh             # ~/.pi/agent/models.json 에 로컬 provider 등록
./scripts/04_setup_blender_mcp.sh    # Blender 애드온 설치 + pi MCP 등록
./scripts/05_setup_orca.sh           # orca 설치 + pi MCP 등록 + pi-local 래퍼
./scripts/check.sh                   # 전체 연결 상태 점검
# 선택: 3D 프린팅 슬라이싱까지 에이전트로 다룰 때
ORCA_API_TOKEN=... ./scripts/07_setup_orcaslicer_mcp.sh
```

또는 `make all` 로 00~05를 순서대로 실행합니다 (서버는 `make serve`, OrcaSlicer 는 `make orcaslicer`). 각 스크립트는 멱등적이라 다시 실행해도 안전합니다.

## 단계별 설명

### 0. 사전 준비 (00_prereqs.sh)

- Homebrew, uv, Node.js 22, jq
- pi 코딩 에이전트: 공식 설치 스크립트 `curl -fsSL https://pi.dev/install.sh | sh`
  (npm 패키지 이름은 `@earendil-works/pi-coding-agent`, 예전 `@mariozechner/...`는 deprecated)
- llama.cpp: `brew install llama.cpp` (Metal 기본 활성, `llama-server` 포함). Qwen3-Next 아키텍처는 최신 빌드가 필요하므로 이미 설치돼 있으면 `brew upgrade` 합니다.
- `hf` CLI (huggingface_hub, uv tool)
- `BACKEND=mlx` 일 때는 llama.cpp 대신 `uv tool install mlx-lm`

### 1. 모델 다운로드 (01_download_model.sh)

기본값은 `unsloth/Qwen3-Coder-Next-GGUF` 에서 `UD-Q6_K_XL` 양자화만 골라 `~/models/unsloth/Qwen3-Coder-Next-GGUF/` 로 받습니다 (`--include "*UD-Q6_K_XL*"`). 분할 샤드(00001-of-N)는 스크립트가 자동으로 찾습니다.

다른 양자화나 백엔드:

```bash
QUANT=UD-Q4_K_XL ./scripts/01_download_model.sh     # ~50GB, 더 빠름. Blender+UE5 동시 작업 시 권장
QUANT=UD-Q5_K_XL ./scripts/01_download_model.sh     # ~57GB, 중간
QUANT=Q8_0       ./scripts/01_download_model.sh     # ~85GB, 거의 무손실이지만 느림
BACKEND=mlx      ./scripts/01_download_model.sh     # mlx-community/Qwen3-Coder-Next-6bit (safetensors)
```

양자화 비교 (80B-A3B, 활성 3B라 비트 수가 속도에 주는 영향은 밀집 모델보다 작음):

| 양자화 | 크기 | 특징 |
|---|---|---|
| UD-Q4_K_XL | ~50GB | 속도 최우선, 메모리 여유 최대 |
| UD-Q5_K_XL | ~57GB | 중간 |
| UD-Q6_K_XL (기본) | ~68GB | 품질/속도 균형. 128GB 환경 권장 |
| Q8_0 / UD-Q8_K_XL | ~85GB | 거의 무손실, 속도 저하와 메모리 여유 감소

```bash
# 서버/점검 스크립트도 같은 QUANT 로 호출해야 같은 파일을 찾습니다 (기본값이면 생략)
QUANT=UD-Q4_K_XL ./scripts/02_serve_model.sh --bg
```

### 2. 모델 서버 (02_serve_model.sh)

| 백엔드 | 명령 | 비고 |
|---|---|---|
| llama.cpp (기본) | `./scripts/02_serve_model.sh --bg` | `llama-server --jinja -ngl 999 --flash-attn on`. Qwen3-Coder 툴콜 파싱이 안정화된 백엔드. pi 공식 지원 |
| mlx-lm | `BACKEND=mlx ./scripts/02_serve_model.sh --bg` | MLX 가중치. 툴콜 파싱은 mlx-lm 버전에 따라 다르므로 에이전트 용도에선 llama.cpp 권장 |

- `--bg` 없이 실행하면 포그라운드(Ctrl+C 로 종료)라 tmux 나 두 번째 터미널에서 쓰면 됩니다.
- `--stop` 으로 백그라운드 서버를 끕니다. 로그는 `~/.local/state/qwen-coder/server.log`.
- 샘플링은 Qwen/unsloth 권장값(temp 1.0, top_p 0.95, top_k 40, min_p 0.01, repeat penalty 끔)으로 고정돼 있습니다.
- `CTX=262144` 로 네이티브 전체 컨텍스트를 쓸 수 있습니다. 모델 alias 는 `qwen3-coder-next` 로 pi 설정과 맞물립니다.
- 첫 로드는 1~2분 걸립니다. 그 전엔 `/v1/models` 가 응답하지 않습니다.

pi 에는 llama.cpp 라우터 모드(`--models-dir`, `/llama` 명령)도 내장돼 있지만, 이 셋업은 단일 모델을 고정 포트로 띄우는 단순한 방식을 씁니다. 여러 GGUF 를 pi 안에서 바꿔가며 쓰고 싶으면 pi 문서의 llama-cpp.md 를 참고하세요.

### 3. pi 설정 (03_setup_pi.sh)

`~/.pi/agent/models.json` 에 아래 provider를 병합합니다 (기존 내용은 보존).

```json
{
  "$schema": "https://pi.dev/schemas/models.schema.json",
  "providers": {
    "local": {
      "baseUrl": "http://127.0.0.1:8080/v1",
      "api": "openai-completions",
      "apiKey": "local",
      "models": [
        {
          "id": "qwen3-coder-next",
          "name": "Qwen3-Coder-Next 80B-A3B (local, llama)",
          "contextWindow": 131072,
          "maxTokens": 32768,
          "input": ["text"],
          "samplingParams": { "temperature": 1.0, "top_p": 0.95, "top_k": 40, "min_p": 0.01 }
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
- 첫 토큰 지연: 긴 컨텍스트를 처음 넣을 때 prefill이 수십 초 걸릴 수 있습니다. llama-server 는 `--cache-reuse` 로 프롬프트 캐시를 재사용하므로 같은 세션에서는 빨라집니다.
- 컴팩션: pi는 contextWindow − reserveTokens(기본 16384)에서 요약을 시작합니다. 131K 창이면 충분합니다.
- 오프라인: `PI_OFFLINE=1 pi` 로 pi.dev 카탈로그 갱신과 버전 체크를 끕니다.
- 안전: pi는 도구 호출 전에 승인을 묻지 않습니다. 중요한 디렉터리에서는 git으로 작업 상태를 자주 커밋하세요.
- Blender 버전: bpy API가 버전마다 바뀌므로 AGENTS.md에 사용 중인 Blender 버전을 적어두면 코드 품질이 눈에 띄게 좋아집니다.

## 참고 링크

- pi: https://github.com/earendil-works/pi (docs/models.md, docs/mcp.md)
- Qwen3-Coder-Next: https://huggingface.co/Qwen/Qwen3-Coder-Next
- GGUF: https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF
- MLX 4bit: https://huggingface.co/mlx-community/Qwen3-Coder-Next-4bit
- orca: https://github.com/orca-cli/orca
- MCP for Blender: https://github.com/ahujasid/mcp-for-blender
- OrcaSlicer MCP: https://pypi.org/project/orcaslicer-mcp
- llama.cpp server: https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
- unsloth Qwen3-Coder-Next 가이드: https://unsloth.ai/docs/models/qwen3-coder-next
