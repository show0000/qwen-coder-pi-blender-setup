# Agent instructions (Blender + OrcaSlicer project)

## Environment
- Blender version: 4.x  ← 실제 사용 버전으로 바꾸세요 (bpy API가 버전별로 다름)
- Python inside Blender: 3.11
- OrcaSlicer MCP build with Remote API enabled on 127.0.0.1:13130
- Local model: Qwen3-Coder-Next via pi. Keep tool calls small and sequential.

## Blender (bpy) rules
- Prefer the `blender` MCP tools for live scene changes (get_scene_info, execute_blender_code, get_viewport_screenshot).
- Before writing bpy code, call get_scene_info to confirm object names and the active collection.
- Write bpy scripts as idempotent functions; never rely on selection state unless you set it explicitly.
- Use `bpy.data` APIs over `bpy.ops` when a data-level API exists (ops depend on UI context and fail headless).
- After execute_blender_code, verify with get_viewport_screenshot or get_object_info rather than assuming success.
- Export for printing: STL (`bpy.ops.wm.stl_export` in 4.x; `export_mesh.stl` in 3.x) or 3MF; apply scale and modifiers first.

## OrcaSlicer rules
- Pipeline: load_model → arrange_plate / auto_orient → set_layer_height / set_config → slice_and_wait → get_slice_breakdown.
- Always run check_profile_physics before slicing after changing temperature/speed settings.
- Report estimated time and filament usage after every slice.

## Repo hygiene
- Put generated STL/3MF/G-code under ./out/ (gitignored).
- Keep reusable bpy helpers in ./tools/bpy_utils.py.
