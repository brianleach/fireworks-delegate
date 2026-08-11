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
filename), `--pr` to push the branch and open a draft GitHub PR whose
body carries the task spec and the tail of the run log. Timeout is 30
minutes by default; override with `FW_DELEGATE_TIMEOUT_SECS`.

Use `--pr` whenever the target repo has a GitHub origin remote and the
gh CLI is available: it gives the user a first-class review surface and
preserves the task spec and log in the PR body. Fall back to the local
flow otherwise.

Run independent tasks in parallel by launching multiple `delegate.sh`
invocations at once (separate worktrees make this safe). Run dependent
tasks sequentially: delegate, review, merge, then delegate the next so it
branches from the merged result.

### 5. Review every diff

Never merge blind. For each finished worktree:

1. Read `.fw-worktrees/<name>.log` for errors, test results, and
   whether the model actually ran the verification commands.
2. Run `scripts/collect.sh <name>` to see the full diff.
3. Judge: is it correct, does it match the spec, do tests pass?

When the task was delegated with `--pr`, also post your review to the
PR so the human sees it where they review: inline comments for concrete
findings (the code-review tooling's comment mode if available, or
`gh api` review comments), plus one summary comment via `gh pr comment`
stating what you checked, the test results from the log, and an explicit
"recommend merge" or "recommend revision" line. Formal Approve or
Request-changes verdicts are impossible when the PR author and reviewer
are the same account, so the summary comment is the verdict.

**Human approval rule**: never merge without explicit human approval.
For every finished task, post your review, give the user the PR URL
(or the diff summary in local-only mode) with your recommendation
(merge, revise, or take over), and wait for their decision. A standing
instruction from earlier in the session does not count as approval for
a specific diff; ask each time. The only autonomous actions permitted
are rejecting a worktree and sending a task back for revision.

Then take exactly one of these actions:

- **Accept**: `scripts/collect.sh <name> --merge`, only after the user
  has approved that specific diff
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
