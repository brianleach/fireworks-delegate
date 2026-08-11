# fireworks-delegate

A Claude Code skill that lets Claude act as a pure orchestrator: it plans
and decomposes work, then delegates implementation tasks to OSS models on
Fireworks AI via [OpenCode](https://opencode.ai), instead of spawning Claude
subagents. Each task runs in an isolated git worktree, Claude reviews the
diff, and merges or rejects it.

The point: implementation tokens are billed to Fireworks serverless pricing
(default model is the Kimi K3 US router,
`accounts/fireworks/routers/kimi-k3-us`), while your Anthropic subscription
only pays for planning and review.

## How it works

1. Claude runs `scripts/check-env.sh` to verify the toolchain.
2. Claude writes self-contained task specs to `.fw-tasks/`.
3. `scripts/delegate.sh <spec>` creates a git worktree under
   `.fw-worktrees/<name>`, runs `opencode run` there with the spec as the
   prompt, captures the log to `.fw-worktrees/<name>.log`, and prints a
   diff stat. With `--pr` it also pushes the branch and opens a draft
   GitHub PR whose body carries the task spec and the log tail.
4. Claude reviews the diff and either merges it with
   `scripts/collect.sh <name> --merge`, sends the task back for one
   revision, or takes it over. Claude posts its review to the PR and only
   auto-merges small, low-risk diffs; larger diffs wait for the human to
   decide on the PR.

Independent tasks run in parallel worktrees.

## Install

1. Install OpenCode:

   ```sh
   npm install -g opencode-ai
   # or: brew install sst/tap/opencode
   ```

2. Connect Fireworks. Recommended: install
   [FireConnect](https://github.com/fw-ai/fireconnect) and enable OpenCode
   support:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/fw-ai/fireconnect/main/install.sh | bash
   fireconnect opencode on
   ```

   FireConnect handles browser sign-in and API key management
   automatically.

   Alternatively, set up manually. Either authenticate through OpenCode:

   ```sh
   opencode auth login   # select Fireworks, paste your API key
   ```

   or export the key directly (get one at
   https://app.fireworks.ai/settings/users/api-keys):

   ```sh
   export FIREWORKS_API_KEY=fw_...
   ```

   Any tool that populates either the `FIREWORKS_API_KEY` environment
   variable or OpenCode's auth store
   (`~/.local/share/opencode/auth.json`) also works.

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
  --model fireworks-ai/accounts/fireworks/models/deepseek-v3

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

## Cost note

Delegated implementation runs on Fireworks serverless pricing through the
`kimi-k3-us` router. You pay Fireworks per token for every delegated task;
only Claude's planning and review turns consume your Anthropic plan. Check
current rates at https://fireworks.ai/pricing before running large batches.

## License

MIT
