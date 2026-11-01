---
name: repo-map
description: Build a compact map of an unfamiliar codebase (structure, entry points, key symbols) in a few hundred tokens before touching code. Use at the start of any task in a repo you have not read in this session, or when asked "how is this project organized".
---

# repo-map

Goal: understand the repo in ≤ 600 tokens of tool output, not by reading files.

## Steps

1. Shape (one command, truncated):
   ```bash
   find . -type f -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.venv/*' \
     -not -path '*/build/*' -not -path '*/dist/*' -not -path '*/out/*' | sed 's|/[^/]*$||' | sort | uniq -c | sort -rn | head -25
   ```
2. Manifests only: `read` the first 40 lines of whichever exist: `pyproject.toml`, `package.json`, `Cargo.toml`, `go.mod`, `CMakeLists.txt`, `Makefile`, `README.md`. Note language, build/test commands, main dependencies.
3. Entry points and symbols without opening files:
   ```bash
   grep -rn --include='*.py' -E '^(def|class) ' . | grep -v -E 'test|/\.' | cut -d: -f1,3 | head -40
   grep -rn --include='*.ts' --include='*.tsx' -E '^export (default )?(function|class|const)' . | cut -d: -f1,3 | head -40
   grep -rln -E "if __name__ == .__main__.|def main\(" --include='*.py' . | head
   ```
   Adjust the include globs to the language found in step 2.
4. Tests: `ls tests test spec 2>/dev/null | head` and the test command from the manifest.
5. Write a 10–15 line map to `.pi/REPO_MAP.md` (create `.pi/` if needed): language + build/test commands, top-level layout (one line per dir), 5–10 key files with one-phrase purpose each, and anything unusual (generated code, vendored deps, monorepo packages). Later turns read this file instead of re-exploring.

## Rules
- Never `cat` a file to "see what it is"; use `head -20` or grep for the symbol you need.
- Stop exploring as soon as you can name the file(s) the task will touch.
- If `.pi/REPO_MAP.md` already exists and is < 7 days old, read it and skip steps 1–4.
