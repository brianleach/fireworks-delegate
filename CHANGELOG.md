# Changelog

All notable changes to this project are documented in this file. The
format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project adheres to [Semantic Versioning](https://semver.org/).

## [0.3.0] - 2026-08-23

### Changed

- Delegation now runs on headless Claude Code sessions instead of
  OpenCode: `delegate.sh` invokes `claude -p` pointed at Fireworks'
  Anthropic compatibility endpoint (`api.fireworks.ai/inference`),
  scoped per invocation through the new `scripts/fw-claude.sh` wrapper.
  The orchestrator session stays on Anthropic; global Claude Code
  settings are never modified.
- Default model ID drops the OpenCode provider prefix:
  `accounts/fireworks/routers/kimi-k3-us`. A legacy `fireworks-ai/`
  prefix on `--model` is accepted and stripped.
- Delegate logs are now the session transcript in stream-json format
  (one JSON event per line, including every tool call and its output).
  The PR body log tail truncates long lines to stay under GitHub's
  size limit.
- `check-env.sh` now verifies the claude CLI, the `FIREWORKS_API_KEY`
  environment variable, and the compatibility endpoint via curl before
  smoke-testing through the same wrapper delegate.sh uses; it also
  warns about conflicting `ANTHROPIC_*` env entries in Claude Code
  settings files (as left by `fireconnect claude on`).

### Removed

- The OpenCode dependency, its auth-store detection, and the OpenCode
  gitignore entries.

## [0.2.1] - 2026-08-11

### Fixed

- PR bodies redact the embedded log tail: `$HOME` becomes `~` and
  secret-shaped lines (API keys, bearer tokens, `*_KEY=` style
  assignments) are replaced with `[redacted]`. The on-disk log stays
  complete.
- `collect.sh --merge` survives a rejected base-branch push (branch
  protection): it warns with recovery steps, keeps the remote branch so
  an open PR stays intact, and still cleans up locally.
- Task specs reach the model as a `.fw-task.md` file in the worktree
  instead of one giant argv string, avoiding ARG_MAX limits and letting
  the model re-read the spec mid-run. The file is removed before
  auto-commit and can never land on the branch.

### Changed

- Script header comments no longer duplicate usage(); `--help` is the
  single source of truth.

## [0.2.0] - 2026-08-11

### Added

- `--pr` flag on delegate.sh: pushes the branch and opens a draft PR
  with the task spec and log tail as the body; degrades gracefully
  without an origin remote or gh.
- `--base <branch>` flag on collect.sh to state the base branch when
  the recorded one is missing or wrong.
- SKILL.md: PR-based review protocol and a human approval rule; Claude
  auto-merges only small, low-risk diffs.
- collect.sh keeps PR state in sync: merge pushes the base branch and
  deletes the remote branch, reject closes the PR.

### Changed

- delegate.log moved from inside the worktree to
  `.fw-worktrees/<name>.log`; logs are kept after merge or reject.
- usage() output of both scripts is now proper help text.

### Fixed

- collect.sh no longer falls back to the current branch when the base
  record is missing; missing or deleted base branches are hard errors.
- Names are sanitized and validated as git refs in both scripts,
  rejecting traversal-shaped and git-invalid names.
- Task specs starting with a hyphen are no longer parsed as opencode
  flags.
- check-env.sh provider check is time-bounded and immune to pipefail
  SIGPIPE false failures.
- Recovery path when a branch exists but its worktree directory is
  gone (`collect.sh <name> --reject`).

## [0.1.0] - 2026-08-11

Initial release.

### Added

- `SKILL.md`: the orchestration protocol Claude Code follows, covering
  preflight, task spec authoring, complexity routing between Kimi and
  Claude, parallel delegation, mandatory diff review with one revision
  round, and per-task commits.
- `scripts/check-env.sh`: preflight verifying the OpenCode CLI, a
  Fireworks API key (env var or OpenCode auth store), provider
  resolution, and a live smoke test against the default Kimi K3 US
  router, with actionable fix instructions on failure.
- `scripts/delegate.sh`: runs a task spec in an isolated git worktree
  under `.fw-worktrees/<name>` via `opencode run`, with model override,
  configurable timeout, full logging to `delegate.log`, and auto-commit
  of the delegated work. Parallel-safe across worktrees.
- `scripts/collect.sh`: reviews a finished worktree's diff and merges
  (`--merge`) or discards (`--reject`) it.
- `install.sh`: idempotent symlink install into `~/.claude/skills/`.
- Offline bats test suite (18 tests) covering the scripts' argument
  handling, happy paths, failure paths, and cleanup, using a stubbed
  `opencode` binary and fixture git repos.
- GitHub Actions CI running shellcheck and the bats suite on Ubuntu and
  macOS.
- README with FireConnect-first setup instructions and a cost note on
  Fireworks serverless pricing.

[0.3.0]: https://github.com/brianleach/fireworks-delegate/releases/tag/v0.3.0
[0.2.1]: https://github.com/brianleach/fireworks-delegate/releases/tag/v0.2.1
[0.2.0]: https://github.com/brianleach/fireworks-delegate/releases/tag/v0.2.0
[0.1.0]: https://github.com/brianleach/fireworks-delegate/releases/tag/v0.1.0
