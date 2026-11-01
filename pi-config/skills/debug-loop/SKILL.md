---
name: debug-loop
description: Fix a failing test, traceback, or build error with minimal context. Use whenever the user pastes an error, says tests fail, or a command you ran exits non-zero.
---

# debug-loop

1. Reproduce once, narrowly: run the single failing test or command, capture only the last 40 lines (`2>&1 | tail -40`). Do not run the whole suite yet.
2. Read the traceback bottom-up. Identify the one file:line where the assumption broke. `read` only that function (use the line range), plus the call site if the bug is in the arguments.
3. Form one hypothesis and state it in one sentence. If you need more evidence, add a single targeted `print`/log or `grep` for the symbol; do not open neighboring files "just in case".
4. Apply the smallest fix with `edit`. No drive-by refactors in the same change.
5. Re-run the same narrow command. Only when it passes, run the broader suite once (`| tail -20`).
6. If the same error appears after two attempts, stop: summarize what you tried, what you observed, and the two most likely causes, and ask the user.

Report format (≤ 8 lines): root cause · fix (file:line) · verification command and result.
