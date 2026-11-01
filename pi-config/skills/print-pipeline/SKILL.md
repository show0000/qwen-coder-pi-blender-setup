---
name: print-pipeline
description: Take a Blender object to a sliced, print-ready job through the orcaslicer MCP server. Use when the user mentions printing, slicing, OrcaSlicer, layer height, filament, G-code, or print time estimates.
---

# print-pipeline

Order of operations (do not skip the checks):

1. Blender side (see `bpy-modeling`): apply scale and modifiers, confirm the mesh is manifold, export STL or 3MF to `./out/<name>.stl`. Print dimensions in mm.
2. `load_model(path)` → `list_objects` to confirm it arrived with the expected size (OrcaSlicer reports mm). A 1000× size difference means a unit problem; fix in Blender, not by scaling in the slicer.
3. Orientation and placement: `auto_orient` then `arrange_plate`; `check_placement` must pass. If the user specified an orientation, use `transform_object` instead of auto_orient.
4. Settings: change only what the user asked (`set_layer_height`, `set_config` for infill, walls, supports). After any temperature/speed change run `check_profile_physics`. Use `describe_setting` when unsure what a key does instead of guessing.
5. `slice_and_wait` → `get_slice_warnings` (resolve or report every warning) → `get_slice_breakdown`.
6. Report: estimated time, filament grams/meters, layer height, supports yes/no, and warnings. One short table, nothing else.
7. Only `save_gcode` when the user asks; say where it was written.

Never start a print or send to a printer; printer tools are read-only in this setup.
