---
name: bpy-modeling
description: Blender modeling and scene work through the blender MCP server (bpy). Use whenever the task mentions Blender, bpy, meshes, modifiers, materials, scenes, or exporting STL/3MF/GLB. Covers how to inspect the scene cheaply, write idempotent bpy, and verify results numerically without screenshots.
---

# bpy-modeling

The coder model cannot see pixels; the vision-bridge extension turns any screenshot into a text description from the local VLM. Verify with numbers first, use screenshots for shape/placement questions.

## Session start (once)
1. `get_scene_info` → note Blender version, unit scale, object names, active collection. Do not call it again unless the user changed the scene outside your control.
2. Ask the Blender version into memory: bpy API differs between 3.x and 4.x (e.g. STL export is `bpy.ops.wm.stl_export` in 4.x, `bpy.ops.export_mesh.stl` in 3.x).

## Writing bpy code (execute_blender_code)
- One function per step, idempotent: look up by name, delete/replace if it exists, then create. Never depend on current selection or active object; set them explicitly if an operator needs them.
- Prefer data API over operators: `bpy.data.meshes.new`, `bmesh`, `obj.modifiers.new`, `obj.data.materials.append`. Use `bpy.ops` only when there is no data-level equivalent (boolean apply, UV unwrap), and then set `bpy.context.view_layer.objects.active` first.
- Units: work in meters internally; if the user speaks in mm, convert once at the boundary and say so.
- Keep each `execute_blender_code` call under ~60 lines. End every call with a `print()` of the facts you will verify: name, `obj.dimensions`, `obj.location`, `len(obj.data.vertices)`, `len(obj.data.polygons)`, modifier list.
- Apply modifiers and scale before boolean operations and before export.

## Verification (every change)
- `get_object_info(name)` or a print of `dimensions`/`location`/vertex counts. Compare against the spec you were given; state the comparison in one line.
- After a boolean: face count must change and the result must still be manifold. Check with:
  ```python
  import bmesh; bm = bmesh.new(); bm.from_mesh(obj.data)
  nm = [e for e in bm.edges if not e.is_manifold]; print("non_manifold_edges", len(nm)); bm.free()
  ```
- Visual check: call `get_viewport_screenshot`. The vision-bridge extension sends the image to the local VLM and you receive a text description in its place (you never see pixels). Requires `qwen vision start`; if the result says the vision server is down, say so and continue with numeric checks. Ask a targeted follow-up by saving a render and querying from bash when you need a specific question answered:
  ```python
  # inside execute_blender_code — quick viewport-style render to the project
  import bpy, os; os.makedirs("out", exist_ok=True)
  bpy.context.scene.render.filepath = os.path.abspath("out/view.png")
  bpy.context.scene.render.resolution_x = 1280; bpy.context.scene.render.resolution_y = 720
  bpy.ops.render.opengl(write_still=True); print(os.path.abspath("out/view.png"))
  ```
  ```bash
  vision-describe out/view.png "Is the 6 mm hole on the TOP face, centered? Do the two parts overlap?"
  ```
  Treat any visual description as a second opinion: confirm dimensions and placement numerically with get_object_info before acting on it.

## Export
- STL for printing: apply scale, triangulate is automatic. 3MF keeps units and multiple objects. GLB for UE5/web.
- Export to `./out/` relative to the project; print the absolute path and file size.

## Common failures
- "context is incorrect": operator needs an active object/area → switch to data API or set `view_layer.objects.active`.
- Object appears at origin with scale (0.001): unit mismatch; check `scene.unit_settings.scale_length`.
- Boolean produced nothing: operand normals flipped or non-manifold → `bpy.ops.mesh.normals_make_consistent` in edit mode, or use `solver='EXACT'`.
