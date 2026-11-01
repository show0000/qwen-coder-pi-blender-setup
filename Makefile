SHELL := /bin/bash
S := scripts

.PHONY: all prereqs download serve pi blender orca vision orcaslicer check bundle

all: prereqs download pi blender orca check

prereqs:  ; $(S)/00_prereqs.sh
download: ; $(S)/01_download_model.sh
serve:    ; $(S)/02_serve_model.sh --bg
pi:       ; $(S)/03_setup_pi.sh
blender:  ; $(S)/04_setup_blender_mcp.sh
orca:     ; $(S)/05_setup_orca.sh
vision:   ; $(S)/06_setup_vision.sh
orcaslicer: ; $(S)/07_setup_orcaslicer_mcp.sh
check:    ; $(S)/check.sh
bundle:   ; $(S)/offline/make_bundle.sh ./bundle
