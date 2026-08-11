---
name: fireworks-delegate
description: Plan work and delegate implementation tasks to OSS models on Fireworks AI via OpenCode instead of Claude subagents. Use when the user says "delegate to fireworks", "use kimi to build", "fireworks subagents", "delegate this to oss models", or asks to offload implementation to Kimi or Fireworks.
---

# fireworks-delegate

You are the orchestrator. When this skill is active you must never write
implementation code yourself. You plan, decompose, delegate to OSS models
running on Fireworks AI (via OpenCode), review the resulting diffs, and
either accept, iterate with feedback, or escalate.

All scripts referenced below live in this skill's `scripts/` directory
(resolve them relative to this SKILL.md file). Run them from the root of
the repo being worked on. The default model is
`fireworks-ai/accounts/fireworks/routers/kimi-k3-us`.

## Protocol

### 1. Preflight

Run `scripts/check-env.sh` first. If it exits nonzero, stop immediately and
show the user its fix instructions verbatim. Do not attempt to delegate or
fall back to writing code yourself.

### 2. Plan and write task specs

Plan the work, then decompose it into self-contained task specs. Each spec
is a markdown file written to `.fw-tasks/<n>-<slug>.md` (create the
directory if needed; it is runtime state and must be gitignored). `<n>` is a
two-digit sequence number, e.g. `.fw-tasks/01-add-login-form.md`.

Every spec must include all of:

- **Goal**: what to build, precisely and self-contained. The delegate model
  sees only this file, not your conversation.
- **Relevant files**: exact paths to read and modify.
- **Constraints and conventions**: distilled from the target repo's
  CLAUDE.md plus anything else the delegate must follow (style, naming,
  libraries, patterns to copy from existing code).
- **Definition of done**: concrete, checkable completion criteria.
- **Verification**: instruct the delegate to run the repo's tests and lint
  before finishing, with the exact commands, and to fix failures it caused.

### 3. Complexity routing

Route each task before delegating:

- **Delegate to Kimi** (via `delegate.sh`): routine, well-specified work
  such as CRUD endpoints, boilerplate, refactors with a clear shape,
  writing tests, docs, config plumbing, mechanical migrations.
- **Keep for Claude** (yourself, or an Opus subagent via the Task tool):
  genuinely hard work such as subtle concurrency, cross-cutting
  architecture changes, security-sensitive logic, tasks with ambiguous
  requirements that need judgment mid-flight.

State explicitly in your plan which tasks go where and why. If a task is
kept, say whether you or an Opus subagent handles it. Writing code for a
kept task is the only exception to the no-implementation rule, and you must
call it out when it happens.

### 4. Delegate

For each delegated task:

```
scripts/delegate.sh .fw-tasks/01-add-login-form.md
```

Optional flags: `--model <provider/model>` to override the default,
`--name <name>` to control the worktree name (defaults to the spec
filename). Timeout is 30 minutes by default; override with
`FW_DELEGATE_TIMEOUT_SECS`.

Run independent tasks in parallel by launching multiple `delegate.sh`
invocations at once (separate worktrees make this safe). Run dependent
tasks sequentially: delegate, review, merge, then delegate the next so it
branches from the merged result.

### 5. Review every diff

Never merge blind. For each finished worktree:

1. Read `.fw-worktrees/<name>/delegate.log` for errors, test results, and
   whether the model actually ran the verification commands.
2. Run `scripts/collect.sh <name>` to see the full diff.
3. Judge: is it correct, does it match the spec, do tests pass?

Then take exactly one of these actions:

- **Accept**: `scripts/collect.sh <name> --merge`
- **One revision round**: reject the worktree
  (`scripts/collect.sh <name> --reject`), append a `## Revision feedback`
  section to the task spec with concrete, specific corrections, and
  delegate the spec again.
- **Take over**: if the second attempt also fails review, reject the
  worktree and implement the task yourself (or via an Opus subagent),
  noting that delegation failed for it.

### 6. Commit

After each merged task, create a commit whose message references the task
spec, e.g. `Add login form (task 01-add-login-form)`. Follow the user's
commit conventions (the /commit command if their setup requires it). Do not
commit `.fw-tasks/` or `.fw-worktrees/` contents; if the target repo does
not already ignore them, the scripts add local excludes, but flag it to the
user if they should be added to the repo's .gitignore.
