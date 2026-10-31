# 오프라인(방화벽) 설치

방화벽 안의 Mac 에서는 Hugging Face, GitHub, npm, PyPI 가 모두 막혀 있다고 가정합니다.
인터넷이 되는 다른 Apple Silicon Mac(또는 같은 Mac 을 잠시 외부망에 연결)에서 번들을 만들어 USB 로 옮깁니다.
Homebrew 는 오프라인에서 사실상 쓸 수 없으므로 이 경로에서는 전혀 사용하지 않고, 모든 것을 `~/.local` 아래에 설치합니다 (sudo 불필요).

```
[온라인 Mac]  make_bundle.sh  ──▶  bundle/  ──(USB)──▶  [오프라인 Mac]  install_offline.sh
                                   ├─ node/      Node 22 tarball (nodejs.org)
                                   ├─ pi/        pi + 전체 node_modules (npm prefix tarball)
                                   ├─ bin/       uv, uvx, jq, orca
                                   ├─ python.tgz uv 관리 Python 3.12 (python-build-standalone)
                                   ├─ wheels/    mcp-for-blender, orcaslicer-mcp, huggingface_hub + 의존성 wheel
                                   ├─ llama/     llama.cpp macOS arm64 prebuilt (Metal 포함)
                                   ├─ repo/      이 저장소 사본
                                   ├─ models/    (--with-model 일 때) GGUF
                                   └─ manifest.env
```

## 1. 온라인 Mac 에서 번들 만들기

필요한 것: macOS Apple Silicon, curl, python3(시스템 기본), rsync. Homebrew 나 Node 가 없어도 됩니다 (스크립트가 Node 를 내려받아 번들 안에서만 씁니다).

```bash
git clone https://github.com/show0000/qwen-coder-pi-blender-setup.git
cd qwen-coder-pi-blender-setup
./scripts/offline/make_bundle.sh ./bundle                 # 바이너리/패키지만 (수백 MB)
./scripts/offline/make_bundle.sh ./bundle --with-model    # 모델까지 (+68GB, UD-Q6_K_XL)
```

옵션 (환경변수):

| 변수 | 기본 | 설명 |
|---|---|---|
| `QUANT` | UD-Q6_K_XL | `--with-model` 일 때 받을 GGUF 양자화 |
| `NODE_VERSION` | v22 최신 | 예: `v22.20.0` |
| `LLAMA_TAG` | 최신 nightly | 예: `b11669`. Qwen3-Next 지원이 필요하므로 오래된 태그는 피하세요 |
| `PY_VERSION` | 3.12 | uv 관리 Python |
| `WITH_MLX` | 0 | 1 이면 mlx-lm wheel 도 포함 (BACKEND=mlx 용, 수백 MB 추가) |

orca 는 공개 릴리스 바이너리가 없어서, 번들 머신에 `orca`(brew install orca-cli/tap/orca) 또는 `go` 가 있을 때만 포함됩니다. 없으면 경고만 내고 건너뜁니다 (orca 는 선택 항목).

모델을 번들에 넣지 않았다면 가중치는 따로 받아 USB 에 담으세요. 같은 머신에서 `hf download unsloth/Qwen3-Coder-Next-GGUF --include "*UD-Q6_K_XL*" --local-dir <USB>/Qwen3-Coder-Next-GGUF` 가 가장 간단합니다 (`uvx --from "huggingface_hub[cli]" hf download ...`).

## 2. 오프라인 Mac 에서 설치

전제: Xcode Command Line Tools 가 깔려 있어야 합니다 (git 때문). 없으면 Apple 개발자 사이트에서 CLT 설치 패키지(.dmg)를 미리 받아 두세요. Blender 도 설치 파일을 따로 가져가야 합니다.

```bash
cp -r /Volumes/USB/bundle ~/qwen-bundle          # 또는 tar -xzf /Volumes/USB/bundle.tgz -C ~ && mv ~/bundle ~/qwen-bundle
~/qwen-bundle/repo/scripts/offline/install_offline.sh ~/qwen-bundle /Volumes/USB/Qwen3-Coder-Next-GGUF
#                                                      ^ 번들 경로        ^ 가중치 폴더 (번들에 models/ 가 있으면 생략)
```

설치 스크립트가 하는 일:

1. Node, pi 를 `~/.local/opt/` 에 풀고 `~/.local/bin/pi` 래퍼 생성 (PI_OFFLINE=1 고정)
2. uv, Python, wheelhouse 로 `mcp-for-blender`, `orcaslicer-mcp`, `hf` 를 `uv tool install --offline` 설치
3. llama.cpp prebuilt 를 풀고 `~/.local/bin/llama-server` 래퍼 생성
4. jq, orca 복사. 모든 바이너리의 quarantine 속성 제거 (Gatekeeper 차단 방지)
5. `~/.config/qwen-coder/env.sh` 에 PATH 와 `OFFLINE=1`, MCP 실행 파일 경로를 기록하고 `.zprofile`/`.zshrc` 에서 source
6. 가중치를 `~/models/unsloth/Qwen3-Coder-Next-GGUF/` 로 복사
7. `03_setup_pi.sh`, `04_setup_blender_mcp.sh`, (orca 가 있으면) `05_setup_orca.sh` 실행

이후는 온라인과 동일합니다.

```bash
source ~/.config/qwen-coder/env.sh      # 또는 새 터미널
~/qwen-bundle/repo/scripts/02_serve_model.sh --bg
~/qwen-bundle/repo/scripts/check.sh
cd ~/your-project && pi --model local/qwen3-coder-next
```

## USB 대신 내부망으로 옮기기 (더 빠름)

두 Mac 이 같은 내부망(또는 Thunderbolt 케이블 직결)에 있으면 USB 없이 옮길 수 있습니다. SSH 나 rsync 가 막혀 있어도 되는 방법은 온라인 Mac 에서 Python 내장 HTTP 서버를 띄우고 curl 로 받는 것입니다. 둘 다 macOS 기본 내장이고 curl 은 `-C -` 로 이어받기가 됩니다.

온라인 Mac:

```bash
cd ~/Downloads                     # bundle.tgz 와 Qwen3-Coder-Next-GGUF/ 가 있는 디렉터리
python3 -m http.server 8000        # 방화벽 알림이 뜨면 허용. IP: ipconfig getifaddr en0
```

오프라인 Mac:

```bash
SRV=http://192.168.0.10:8000
curl -C - -o ~/bundle.tgz "$SRV/bundle.tgz" && tar -xzf ~/bundle.tgz -C ~ && mv ~/bundle ~/qwen-bundle
mkdir -p ~/models/unsloth/Qwen3-Coder-Next-GGUF && cd ~/models/unsloth/Qwen3-Coder-Next-GGUF
for i in 1 2 3; do f="Qwen3-Coder-Next-UD-Q6_K_XL-0000${i}-of-00003.gguf"; curl -C - --retry 20 -o "$f" "$SRV/Qwen3-Coder-Next-GGUF/$f"; done
~/qwen-bundle/repo/scripts/offline/install_offline.sh ~/qwen-bundle     # 모델이 제자리에 있으니 두 번째 인자 생략
```

전송이 끝나면 온라인 Mac 에서 Ctrl+C 로 서버를 끕니다. 73GB 기준 유선 1GbE 약 12분, Thunderbolt 브리지(10Gbps+) 2~3분, Wi-Fi 6 20~40분. rsync 를 쓸 수 있다면 모델 경로 인자에 `user@host:path` 를 넘겨도 됩니다 (내부적으로 rsync 사용).

모델 파일 자체는 hf CLI 없이 브라우저나 curl 로 받을 수 있습니다 (UD-Q6_K_XL 은 3개 샤드, 총 73GB):

```bash
BASE=https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF/resolve/main/UD-Q6_K_XL
for i in 1 2 3; do f="Qwen3-Coder-Next-UD-Q6_K_XL-0000${i}-of-00003.gguf"; curl -L -C - --retry 20 -o "$f" "$BASE/$f"; done
```

## 오프라인 모드에서 달라지는 점

- `OFFLINE=1` 이면 `00_prereqs.sh`, `01_download_model.sh` 는 실행을 거부합니다.
- MCP 설정(`~/.pi/agent/mcp.json`)의 command 가 `uvx ...` 대신 설치된 절대 경로(`~/.local/bin/mcp-for-blender` 등)로 기록됩니다. uvx 는 실행 시마다 PyPI 를 조회하므로 오프라인에서 쓸 수 없습니다.
- pi 는 `PI_OFFLINE=1`, `PI_SKIP_VERSION_CHECK=1` 로 동작하여 pi.dev 카탈로그 갱신과 버전 체크를 하지 않습니다.
- Blender 애드온 설치(`install-addon`)는 패키지 안의 파일을 복사하는 것이라 네트워크 없이 동작합니다.

## 업데이트

번들을 다시 만들어 같은 명령으로 설치하면 됩니다. `install_offline.sh` 는 rsync 없이도 동작하며 기존 설치를 덮어쓰고(`--reinstall`), `models.json`/`mcp.json` 은 병합하므로 다른 설정을 지우지 않습니다. 가중치가 이미 있으면 두 번째 인자를 생략하세요.

## 문제 해결

- USB 복사 중 `cpython-3.12-macos-aarch64-none: No such file or directory`: exFAT/FAT32 는 심볼릭 링크를 저장하지 못해 생기는 메시지로, 구버전 번들의 python/ 디렉터리에만 해당합니다. 실제 Python 은 버전이 붙은 폴더에 있어 설치에는 영향이 없습니다. 현재 번들은 python.tgz 로 묶여 이 문제가 없고, 폴더 전체를 `tar -czf bundle.tgz bundle` 로 한 파일로 옮기면 어떤 파일시스템에서도 안전합니다.

- `llama-server` 가 "killed" 또는 "cannot be opened": quarantine 제거가 안 된 경우입니다. `xattr -dr com.apple.quarantine ~/.local/opt/llama.cpp` 후 재시도.
- `unknown model architecture: qwen3next`: llama.cpp 태그가 오래됐습니다. 최신 `LLAMA_TAG` 로 번들을 다시 만드세요.
- `uv tool install` 이 네트워크를 시도: `UV_OFFLINE=1 UV_NO_INDEX=1` 이 안 잡힌 상태입니다. `source ~/.config/qwen-coder/env.sh` 후 재실행.
- pi 에서 `/model` 에 로컬 모델이 안 보임: 서버가 아직 안 떴거나 `~/.pi/agent/models.json` 의 baseUrl 포트(8080)가 다릅니다. `check.sh` 로 확인.
