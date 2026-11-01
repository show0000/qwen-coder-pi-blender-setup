# Superpowers (curated subset for pi)

Vendored from https://github.com/obra/superpowers (MIT). Only process skills that do not depend on
Claude Code subagents or hooks. Each has `disable-model-invocation: true`, so they are NOT listed in
the system prompt (zero per-turn cost) and are used explicitly:

    /skill:test-driven-development
    /skill:systematic-debugging
    /skill:verification-before-completion
    /skill:brainstorming
    /skill:writing-plans
    /skill:finishing-a-development-branch
    /skill:receiving-code-review
    /skill:using-git-worktrees

Not included (need subagents / hooks): subagent-driven-development, dispatching-parallel-agents,
executing-plans, requesting-code-review, using-superpowers, diagnosing-superpowers, writing-skills.
Install: ./scripts/08_setup_pi_config.sh --with-superpowers
