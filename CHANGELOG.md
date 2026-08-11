# Changelog

All notable changes to this project are documented in this file. The
format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project adheres to [Semantic Versioning](https://semver.org/).

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

[0.2.0]: https://github.com/brianleach/fireworks-delegate/releases/tag/v0.2.0
[0.1.0]: https://github.com/brianleach/fireworks-delegate/releases/tag/v0.1.0
