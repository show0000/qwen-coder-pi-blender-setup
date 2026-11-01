# orca run instructions (local Qwen3-Coder-Next via pi)

- You are running inside an orca-managed git worktree. Commit on the worktree branch only; never switch branches.
- Local model with a 256K window, but accuracy drops when it fills: read only the files you need, prefer `grep`/`find` over dumping whole directories.
- When the task is done: run the project's tests, commit with a clear message, and end your final message with one line:
  `DECISION: merge` | `DECISION: needs_review` | `DECISION: abandon` followed by a one-sentence reason.
- Do not modify files outside the worktree. Do not run `git push`; orca ships runs.
- Blender/OrcaSlicer MCP tools are available if the task involves bpy or slicing; verify results with a screenshot or scene query.
