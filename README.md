# fireworks-delegate

A Claude Code skill that lets Claude act as a pure orchestrator: it plans
and decomposes work, then delegates implementation tasks to OSS models on
Fireworks AI, instead of spawning Claude subagents. Each delegated task
runs in a headless Claude Code session (`claude -p`) pointed at Fireworks'
[Anthropic compatibility endpoint](https://docs.fireworks.ai/tools-sdks/anthropic-compatibility),
inside an isolated git worktree. Claude reviews the diff and merges or
rejects it.

The point: implementation tokens are billed to Fireworks serverless pricing
(default model is the Kimi K3 US router,
`accounts/fireworks/routers/kimi-k3-us`), while your Anthropic subscription
only pays for planning and review. No second harness to install: the
delegate is the same `claude` CLI you already run, and it picks up the
target repo's CLAUDE.md, hooks, and skills natively.

## How it works

1. Claude runs `scripts/check-env.sh` to verify the toolchain.
2. Claude writes self-contained task specs to `.fw-tasks/`.
3. `scripts/delegate.sh <spec>` creates a git worktree under
   `.fw-worktrees/<name>`, runs `claude -p` there with the spec as the
   prompt, captures the session transcript to `.fw-worktrees/<name>.log`,
   and prints a diff stat. With `--pr` it also pushes the branch and opens
   a draft GitHub PR whose body carries the task spec and the log tail.
4. Claude reviews the diff and either merges it with
   `scripts/collect.sh <name> --merge`, sends the task back for one
   revision, or takes it over. Claude posts its review to the PR and only
   auto-merges small, low-risk diffs; larger diffs wait for the human to
   decide on the PR.

Independent tasks run in parallel worktrees.

The Fireworks connection is scoped to each delegate run:
`scripts/fw-claude.sh` sets `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`,
and the model slots in the child process environment only. Your
interactive Claude Code sessions and global `~/.claude/settings.json` are
never touched, so there is nothing to switch back afterwards. Delegate
sessions run with edits auto-accepted and the Bash tool pre-approved
(they must run your test suite), not with a blanket permission bypass:
deny rules from your Claude Code settings still apply. In the rare case
a delegate does hit a denial (a configured deny rule firing, or a write
outside its worktree), `delegate.sh` prints a warning next to the diff
stat and the full denial text is in the transcript log. Two
trade-offs of the compatibility endpoint to know about: Anthropic's
server-side WebSearch and WebFetch tools are unavailable (the scripts
disallow them), and prompt caching is not applied.

## Install

1. Make sure the `claude` CLI is installed (it is, if you're reading this
   as a Claude Code user; otherwise see
   https://code.claude.com/docs/en/setup).

2. Provide a Fireworks API key (get one at
   https://app.fireworks.ai/settings/users/api-keys). Either export it:

   ```sh
   export FIREWORKS_API_KEY=fw_...
   ```

   or put it in a `.env` file at the root of your fireworks-delegate
   checkout, where it is gitignored:

   ```sh
   echo 'FIREWORKS_API_KEY=fw_...' >> /path/to/fireworks-delegate/.env
   ```

   The scripts read that `.env` (resolved relative to the scripts
   themselves, not the repo you are working on) only for values missing
   from the environment; a real environment variable always wins.
   `FW_BASE_URL` can live there too.

   Note for [FireConnect](https://github.com/fw-ai/fireconnect) users:
   `fireconnect claude on` is not needed and is best left off. It rewrites
   your global Claude Code settings so every session runs on Fireworks;
   this skill instead scopes Fireworks to delegate runs only and just
   needs the environment variable. If a leftover fireconnect env block is
   present, `check-env.sh` warns about it.

3. Clone this repo anywhere and symlink it into your Claude Code skills:

   ```sh
   git clone https://github.com/brianleach/fireworks-delegate.git
   cd fireworks-delegate
   ./install.sh
   ```

4. Verify:

   ```sh
   ./scripts/check-env.sh
   ```

## Usage

In any Claude Code session, trigger the skill with phrases like:

- "delegate to fireworks: add pagination to the orders list"
- "use kimi to build the settings screen"
- "delegate this to oss models"

Claude then plans, writes task specs, and drives the scripts. You can also
run the scripts by hand:

```sh
# delegate a task spec
scripts/delegate.sh .fw-tasks/01-add-pagination.md

# with a different Fireworks model
scripts/delegate.sh .fw-tasks/01-add-pagination.md \
  --model accounts/fireworks/models/deepseek-v3

# delegate and open a draft GitHub PR for review: the branch is pushed
# and the PR body carries the task spec and the log tail
scripts/delegate.sh .fw-tasks/01-add-pagination.md --pr

# review, then merge or discard
scripts/collect.sh 01-add-pagination           # show diff
scripts/collect.sh 01-add-pagination --merge   # accept
scripts/collect.sh 01-add-pagination --reject  # discard

# state the base branch explicitly when the recorded one is missing
# or wrong
scripts/collect.sh 01-add-pagination --base main
```

When a PR exists, `collect.sh` keeps it in sync: `--merge` pushes the
base branch to origin (when the repo has one) so the PR flips to merged,
and `--reject` closes the PR.

Environment knobs:

- `FW_DELEGATE_TIMEOUT_SECS`: per-task wall clock limit (default 1800)
- `FW_SMOKE_TIMEOUT_SECS`: check-env smoke test limit (default 120)
- `FW_BASE_URL`: override the Fireworks endpoint (default
  `https://api.fireworks.ai/inference`)

## Cost note

Delegated implementation runs on Fireworks serverless pricing through the
`kimi-k3-us` router. You pay Fireworks per token for every delegated task;
only Claude's planning and review turns consume your Anthropic plan. Check
current rates at https://fireworks.ai/pricing before running large batches.

## Related projects

- [phi-delegate](https://github.com/brianleach/phi-delegate): the same
  orchestrate-and-delegate pattern, but the delegate is an isolated headless
  Claude Code session on a BAA / zero-data-retention Anthropic key, for PHI work.

## License

MIT
