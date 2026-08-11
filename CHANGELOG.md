# Changelog

All notable changes to this project are documented in this file. The
format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project adheres to [Semantic Versioning](https://semver.org/).

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

[0.1.0]: https://github.com/brianleach/fireworks-delegate/releases/tag/v0.1.0
