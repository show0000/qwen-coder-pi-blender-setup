# Qwen3-Coder-Next + pi + orca + Blender MCP (MacBook M3 Max 128GB)

Hugging Face에서 Qwen3-Coder-Next(80B-A3B) 가중치를 받아 llama.cpp 로 로컬 OpenAI 호환 서버를 띄우고,
pi 코딩 에이전트를 Claude Code처럼 터미널에서 쓰고, orca 오케스트레이터와 Blender(선택: OrcaSlicer)를 MCP로 연결하는 셋업입니다.
GUI 모델 앱(LM Studio, Ollama)은 쓰지 않습니다. 전부 brew / uv tool 로 설치되는 CLI 입니다.

```
터미널 ── pi (coding agent) ──▶ http://127.0.0.1:8080/v1  (llama-server, 또는 mlx_lm.server)
            │                          └─ Qwen3-Coder-Next GGUF UD-Q6_K_XL (~68GB, 262K ctx)
            ├─ MCP: blender    ──▶ uvx mcp-for-blender  ──▶ Blender addon (port 9876)
            ├─ MCP: orcaslicer ──▶ uvx orcaslicer-mcp   ──▶ OrcaSlicer Remote API (선택)
            ├─ MCP: atlassian  ──▶ mcp-atlassian        ──▶ 사내 Jira / Confluence (PAT)
            └─ MCP: gitlab     ──▶ @zereight/mcp-gitlab ──▶ 사내 GitLab (PAT)
Orca 앱 ── worktree 마다 에이전트로 pi 실행 (Settings → Agents → Pi) ──▶ 같은 로컬 모델
```

## 하드웨어 기준

| 항목 | 값 |
|---|---|
| 모델 | Qwen/Qwen3-Coder-Next (80B total / 3B active MoE), Apache 2.0 |
| 가중치 | unsloth/Qwen3-Coder-Next-GGUF, UD-Q6_K_XL 약 68GB (대안: mlx-community/Qwen3-Coder-Next-6bit) |
| 컨텍스트 | 262,144 토큰 (네이티브 최대). 하이브리드 어텐션이라 전체를 채워도 KV 캐시 약 6GB |
| 예상 속도 | M3 Max 기준 약 20~30 tok/s |
| 메모리 | 모델 68GB + KV 캐시 최대 약 6GB. Blender와 OrcaSlicer를 동시에 띄워도 128GB 안에서 여유 있음 (UE5까지 동시에 띄우면 4bit 권장) |

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

방화벽 때문에 대상 Mac 에서 다운로드가 안 되면 docs/OFFLINE.md 를 보세요. 인터넷이 되는 Mac 에서 `scripts/offline/make_bundle.sh` 로 번들을 만들어 USB 로 옮기고 `scripts/offline/install_offline.sh` 로 설치합니다 (Homebrew 없이 `~/.local` 에 설치).

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
- 기본 컨텍스트는 네이티브 최대인 262144 입니다. 메모리를 아끼려면 `CTX=131072` 로 낮출 수 있습니다 (03_setup_pi.sh 도 같은 값으로 다시 실행). 모델 alias 는 `qwen3-coder-next` 로 pi 설정과 맞물립니다.
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
          "contextWindow": 262144,
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

### 5. Orca 연동 (05_setup_orca.sh)

"orca" 라는 이름의 도구가 둘 있어 스크립트가 설치된 쪽을 감지해 처리합니다.

Orca 데스크톱 앱 (onorca.dev, stablyai/orca): 에이전트 워크스페이스 매니저로 Pi 를 공식 지원합니다(훅, 상태 표시, 네이티브 채팅). 이 경우 Pi 가 Orca 의 에이전트가 되고, Pi 는 이미 로컬 qwen 을 쓰므로 추가 연결이 없습니다.

1. Orca 앱 → Settings → Agents → Pi 활성화. 자동 감지가 안 되면 Command 에 `~/.local/bin/pi` 경로 입력
2. Arguments 에 `--model local/qwen3-coder-next` (pi 에서 /model → Ctrl+S 로 기본 저장했다면 생략 가능)
3. `qwen start` 로 서버를 띄운 뒤 Orca 에서 worktree 생성 또는 CLI:

```bash
orca worktree create --name my-task --agent pi --prompt "작업 설명"
orca agent launch --agent pi --model local/qwen3-coder-next --worktree <selector>
```

pi 가 worktree 안에서 실행되므로 `~/.pi/agent` 의 모델·MCP·스킬·AGENTS.md 설정이 그대로 적용됩니다.

orca-cli/orca (Go 오케스트레이터): `orca mcp serve` 를 pi 에 MCP 서버로 등록해 pi 세션 안에서 run/worktree 를 관리합니다. repo 에서 `orca init` 후 `templates/orca/AGENTS.md` 를 `.orca/` 에 복사하세요.

두 경우 모두 `~/.local/bin/pi-local` (비대화형 pi 래퍼, `pi --model local/qwen3-coder-next -p "<prompt>"`) 을 만들어 자동화나 다른 도구에서 호출할 수 있게 합니다.

### 6. (선택) 비전 모델: 뷰포트 스크린샷 보기 (06_setup_vision.sh)

Qwen3-Coder-Next 는 텍스트 전용이라 Blender 의 get_viewport_screenshot 결과를 볼 수 없습니다. 시각 검증이 필요하면 Qwen3.8-27B(비전-언어, dense)를 두 번째 llama-server 로 8081 포트에 띄우고 pi 에 `local-vision` provider 로 등록합니다.

```bash
./scripts/06_setup_vision.sh        # unsloth/Qwen3.8-27B-GGUF UD-Q5_K_XL (~21GB) + mmproj-F16 다운로드, pi 등록
qwen vision start                    # 두 번째 서버 기동
```

pi 안에서 `/model` 로 `qwen3.8-27b-vl` 을 고르면(또는 Ctrl+P 순환) 그 턴부터 스크린샷을 모델이 직접 봅니다. Orca 에서 띄울 때는 `orca agent launch --agent pi --model local-vision/qwen3.8-27b-vl`, 또는 `~/.local/bin/pi-vision` 래퍼를 별도 에이전트로 등록하면 됩니다. Orca 쪽에 VLM 을 따로 등록할 필요는 없습니다(pi 의 provider 일 뿐). 확인이 끝나면 다시 coder 로 돌아오면 됩니다. 코딩 품질은 Coder-Next 가 위이므로 메인은 그대로 두고 눈 역할만 맡기는 구성입니다. 메모리는 coder 68GB + vision 21GB 로 약 90GB 가 상주하니 UE5 와 병행할 땐 `qwen vision stop` 으로 내려두세요.

오프라인 번들에 포함하려면 `WITH_VISION=1 ./scripts/offline/make_bundle.sh --with-model`, 또는 가중치 폴더를 `VISION_SRC=<폴더> install_offline.sh ...` 로 넘기면 됩니다. 수동 다운로드 링크는 https://huggingface.co/unsloth/Qwen3.8-27B-GGUF 의 `Qwen3.8-27B-UD-Q5_K_XL.gguf` 와 `mmproj-F16.gguf` 두 파일입니다.

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

## 일상 사용: qwen 명령

03_setup_pi.sh(또는 install_offline.sh)가 `~/.local/bin/qwen` 을 설치합니다.

```bash
qwen start            # llama-server 백그라운드 기동 (이미 떠 있으면 아무것도 안 함)
qwen status           # 프로세스/API/모델/메모리 상태
qwen logs             # 서버 로그 follow
qwen pi               # 현재 디렉터리에서 pi 를 로컬 모델로 실행. 서버가 꺼져 있으면 먼저 띄움
qwen pi -p "요약해줘"   # pi 인자는 그대로 전달
qwen restart
qwen stop             # 서버 종료, 메모리 반환
qwen check            # check.sh
qwen vision start|stop|status   # 비전 모델 서버 (06 설치 시)
```

68GB 가 메모리에 상주하므로 Blender/UE5 작업을 길게 할 때는 `qwen stop` 으로 내려두는 편이 좋습니다.

### 9. 사내 Jira / Confluence / GitLab MCP (09_setup_enterprise_mcp.sh)

| 대상 | 서버 | 인증 |
|---|---|---|
| Jira + Confluence (Server/Data Center) | mcp-atlassian (PyPI) | Personal Access Token (`JIRA_PERSONAL_TOKEN`, `CONFLUENCE_PERSONAL_TOKEN`) |
| GitLab (self-hosted) | @zereight/mcp-gitlab (npm) | Personal Access Token, `GITLAB_API_URL=https://gitlab.../api/v4` |

```bash
./scripts/09_setup_enterprise_mcp.sh      # 1회차: ~/.config/qwen-coder/enterprise.env 템플릿 생성
vi ~/.config/qwen-coder/enterprise.env    # URL, 토큰, 필터 입력 (chmod 600)
./scripts/09_setup_enterprise_mcp.sh      # 2회차: 래퍼 생성 + pi 등록
```

토큰은 enterprise.env 에만 있고, `~/.local/bin/atlassian-mcp`, `~/.local/bin/gitlab-mcp` 래퍼가 실행 시점에 읽어 환경변수로 넘깁니다. mcp.json 에는 래퍼 경로만 기록됩니다. 오프라인 번들에는 두 서버가 기본 포함됩니다.

기본값은 읽기 전용(`READ_ONLY_MODE=true`, `GITLAB_PERMISSION_MODE=readonly`)입니다. 두 서버 합쳐 도구가 100개 가까이 되므로 `ENABLED_TOOLS`, `JIRA_PROJECTS_FILTER`, `GITLAB_TOOLSETS=core` 로 범위를 좁히는 것이 로컬 모델의 도구 선택 정확도에 중요합니다. 스크립트가 pi 의 `tool_search` 와 `codemode` 를 켜서 도구 설명이 매 턴 프롬프트에 전부 올라가지 않게 합니다. 자체 서명 인증서면 `JIRA_SSL_VERIFY=false` 또는 `NODE_EXTRA_CA_CERTS=<사내 CA PEM>` 을 설정하세요.

## 컨텍스트 절약형 작업 규칙과 스킬 (08_setup_pi_config.sh)

로컬 모델은 컨텍스트를 채울수록 느려지고 정확도가 떨어지므로, "필요한 것만 읽고 짧게 보고하는" 규칙을 pi 전역에 깔아 둡니다. `pi-config/` 의 내용을 `~/.pi/agent/` 에 설치합니다.

```bash
./scripts/08_setup_pi_config.sh          # 복사 (기존 AGENTS.md 는 백업)
./scripts/08_setup_pi_config.sh --link   # 심볼릭 링크: git pull 만으로 갱신
./scripts/08_setup_pi_config.sh --with-claude-skills   # ~/.claude/skills 의 스킬도 pi 에서 로드
./scripts/08_setup_pi_config.sh --with-superpowers     # obra/superpowers 중 pi 에서 동작하는 8개 (슬래시 호출 전용)
```

| 항목 | 내용 |
|---|---|
| AGENTS.md | 전역 규칙: grep/find 로 찾은 뒤 필요한 범위만 read, 도구 출력은 head/tail 로 제한, 같은 파일 재독 금지, edit 우선, 10줄 이내 보고, 추측성 추상화 금지, 실패 2회면 중단 |
| skills/repo-map | 낯선 저장소를 파일을 열지 않고 600토큰 안에 파악해 `.pi/REPO_MAP.md` 로 저장. 이후 턴은 그 파일만 읽음 |
| skills/bpy-modeling | 이미지 없이 bpy 로 모델링: 멱등 함수, data API 우선, dimensions/정점수/manifold 검사로 수치 검증, 3.x/4.x API 차이 |
| skills/print-pipeline | Blender 내보내기 → OrcaSlicer 로드/배치/슬라이스/경고 확인 → 시간·필라멘트 보고 순서 |
| skills/debug-loop | 실패 테스트 하나만 재현, 트레이스백 아래부터, 가설 하나, 최소 수정, 2회 실패 시 중단 |
| skills/karpathy-guidelines | forrestchang/andrej-karpathy-skills (MIT) 원문. 핵심 4원칙은 AGENTS.md 에도 요약돼 항상 적용 |
| skills-optional/superpowers | obra/superpowers (MIT) 중 서브에이전트/훅에 의존하지 않는 8개: TDD, systematic-debugging, verification-before-completion, brainstorming, writing-plans 등. `disable-model-invocation` 이라 평소 비용 0, `/skill:이름` 으로만 호출 |
| prompts/ | `/review` (uncommitted diff 만 리뷰), `/plan <task>` (구현 전 12줄 계획) |
| settings | compaction keepRecentTokens 24000, 기본 도구에 grep/find/ls 추가 |

스킬은 pi 가 시작할 때 이름과 설명만 시스템 프롬프트에 넣고 본문은 작업이 맞을 때 읽는 점진 로딩 방식이라 평소 컨텍스트 비용이 거의 없습니다. 모델이 스스로 안 읽으면 `/skill:bpy-modeling` 처럼 직접 호출할 수 있습니다. 프로젝트별 규칙(Blender 버전, 테스트 명령 등)은 프로젝트 루트 AGENTS.md 에 적으면 전역 규칙 뒤에 이어 붙습니다.

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
- 컴팩션: pi는 contextWindow − reserveTokens(기본 16384)에서 요약을 시작합니다. 긴 창은 안전망일 뿐이고, 200K 를 넘게 채우면 prefill 이 분 단위로 길어지고 뒷부분 정확도도 떨어지므로 AGENTS.md 에 '필요한 파일만 grep/read 로 읽기' 규칙을 두는 편이 결과가 좋습니다.
- 오프라인: `PI_OFFLINE=1 pi` 로 pi.dev 카탈로그 갱신과 버전 체크를 끕니다.
- 안전: pi는 도구 호출 전에 승인을 묻지 않습니다. 중요한 디렉터리에서는 git으로 작업 상태를 자주 커밋하세요.
- Blender 버전: bpy API가 버전마다 바뀌므로 AGENTS.md에 사용 중인 Blender 버전을 적어두면 코드 품질이 눈에 띄게 좋아집니다.

## 오프라인 설치

[docs/OFFLINE.md](docs/OFFLINE.md) 참고. 모델 가중치를 제외한 모든 구성요소(Node, pi, uv, Python, MCP 서버 wheel, llama.cpp, jq, orca)를 번들로 만들어 네트워크 없이 설치할 수 있습니다. `--with-model` 로 가중치까지 번들에 포함할 수도 있습니다.

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
