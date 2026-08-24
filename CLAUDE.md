# fireworks-delegate

A Claude Code skill that lets Claude plan work and delegate implementation
tasks to OSS models on Fireworks AI via headless Claude Code sessions
(claude -p pointed at Fireworks' Anthropic compatibility endpoint), instead
of spawning Claude subagents.

## Repo layout

- `SKILL.md` - the skill definition Claude Code loads (this repo is symlinked
  into `~/.claude/skills/fireworks-delegate`)
- `scripts/` - helper scripts invoked by the skill
  - `check-env.sh` - preflight: claude CLI installed, Fireworks key present,
    endpoint reachable, smoke test
  - `fw-claude.sh` - shared wrapper that runs claude against the Fireworks
    endpoint with a scoped, per-invocation environment
  - `load-env.sh` - sourced helper that fills FIREWORKS_API_KEY and
    FW_BASE_URL from the gitignored .env at this repo's root when they
    are not already set (environment variables win)
  - `delegate.sh` - run a task spec in an isolated git worktree via a
    headless claude -p session
  - `collect.sh` - review, merge, or reject a finished worktree
- `install.sh` - idempotently symlinks this repo into `~/.claude/skills/`
- `README.md` - install and usage docs

## Conventions

- Bash scripts use `set -euo pipefail` and must be shellcheck clean.
- No em dashes anywhere in generated docs. Use hyphens, commas, or colons.
- Never write API keys or absolute home paths into committed files. Use
  `$HOME`, `$FIREWORKS_API_KEY`, and relative paths.
- Runtime state lives under `.fw-worktrees/` (worktrees plus logs) and
  `.fw-tasks/` (task specs). Both are gitignored and must stay that way.
- Default model is the Kimi K3 US router, as a Fireworks model ID:
  `accounts/fireworks/routers/kimi-k3-us`
- Delegate runs reach Fireworks only through per-invocation environment
  variables set by `fw-claude.sh`. Never flip the user's global Claude Code
  configuration (no fireconnect-style rewrites of `~/.claude/settings.json`).
- Secrets come from the environment or the gitignored `.env` at this
  repo's root, loaded by `scripts/load-env.sh`. The environment wins.
- Delegate sessions use `--permission-mode acceptEdits --allowedTools Bash`,
  never `--dangerously-skip-permissions`.
- AGENTS.md is a symlink to this file. Edit CLAUDE.md only.
