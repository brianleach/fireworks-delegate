# fireworks-delegate

A Claude Code skill that lets Claude plan work and delegate implementation
tasks to OSS models on Fireworks AI via OpenCode, instead of spawning Claude
subagents.

## Repo layout

- `SKILL.md` - the skill definition Claude Code loads (this repo is symlinked
  into `~/.claude/skills/fireworks-delegate`)
- `scripts/` - helper scripts invoked by the skill
  - `check-env.sh` - preflight: OpenCode installed, Fireworks key present,
    provider resolvable, smoke test
  - `delegate.sh` - run a task spec in an isolated git worktree via OpenCode
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
- Default model is the Kimi K3 US router, in OpenCode provider/model format:
  `fireworks-ai/accounts/fireworks/routers/kimi-k3-us`
- AGENTS.md is a symlink to this file. Edit CLAUDE.md only.
