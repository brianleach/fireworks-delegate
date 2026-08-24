#!/usr/bin/env bash
# Delegate a task spec to an OSS model on Fireworks via a headless Claude
# Code session (claude -p pointed at the Fireworks Anthropic compatibility
# endpoint), in an isolated git worktree of the current repo. Run with
# --help for usage.
set -euo pipefail

DEFAULT_MODEL="accounts/fireworks/routers/kimi-k3-us"
RUN_TIMEOUT_SECS="${FW_DELEGATE_TIMEOUT_SECS:-1800}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: delegate.sh <task-spec.md> [--model <fireworks-model-id>] [--name <worktree-name>] [--pr]

Delegate a task spec to an OSS model on Fireworks via a headless Claude
Code session, in an isolated git worktree of the current repo.

The model is a Fireworks model ID such as
accounts/fireworks/routers/kimi-k3-us (a legacy fireworks-ai/ prefix is
accepted and stripped).

Behavior:
  - creates a worktree under .fw-worktrees/<name> on branch fw/<name>,
    branched off the current branch
  - copies the spec into the worktree as .fw-task.md and runs `claude -p`
    there (via fw-claude.sh) with a short prompt pointing at that file;
    the log is the session transcript in stream-json format, one JSON
    event per line
  - captures all output to .fw-worktrees/<name>.log (next to the worktree)
  - auto-commits any changes the model left uncommitted
  - with --pr: pushes fw/<name> to origin and opens a draft PR against the
    base branch (needs an origin remote and the gh CLI; warns and
    continues without failing when either is missing)
  - prints the worktree path and a diff --stat against the base branch

Safe to run multiple times in parallel with distinct names.
EOF
  exit 1
}

with_timeout() {
  local secs="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  else
    perl -e 'alarm shift; exec @ARGV' "$secs" "$@"
  fi
}

# Redaction filter for the log tail that goes into a PR body: the on-disk
# log stays complete, but a public PR must not leak local details. Replaces
# every literal occurrence of $HOME with "~" and swaps any line matching a
# secret-shaped pattern for the single line "[redacted]". Key prefixes
# (fw_, fpk_, sk-) match case-sensitively; keyword patterns (api key,
# authorization:, bearer, token=, _KEY=, _SECRET=, _TOKEN=) match
# case-insensitively. Reads stdin, writes stdout.
redact_log() {
  awk '
    BEGIN { home = ENVIRON["HOME"] }
    {
      if (home != "") {
        rebuilt = ""
        rest = $0
        while ((i = index(rest, home)) > 0) {
          rebuilt = rebuilt substr(rest, 1, i - 1) "~"
          rest = substr(rest, i + length(home))
        }
        $0 = rebuilt rest
      }
      lower = tolower($0)
      if ($0 ~ /fw_[A-Za-z0-9]/ || $0 ~ /fpk_[A-Za-z0-9]/ ||
          $0 ~ /sk-[A-Za-z0-9]/ ||
          lower ~ /api[_-]?key/ || lower ~ /authorization:/ ||
          lower ~ /bearer / || lower ~ /token=/ ||
          lower ~ /_key=/ || lower ~ /_secret=/ || lower ~ /_token=/) {
        print "[redacted]"
      } else {
        print
      }
    }'
}

# Hidden test hook: pipe text through the redaction filter and exit.
if [ "${1:-}" = "--redact-filter" ]; then
  redact_log
  exit 0
fi

spec_file=""
model="$DEFAULT_MODEL"
name=""
pr_requested=0

while [ $# -gt 0 ]; do
  case "$1" in
    --model)
      [ $# -ge 2 ] || usage
      model="$2"
      shift 2
      ;;
    --name)
      [ $# -ge 2 ] || usage
      name="$2"
      shift 2
      ;;
    --pr)
      pr_requested=1
      shift
      ;;
    -h | --help)
      usage
      ;;
    *)
      if [ -z "$spec_file" ]; then
        spec_file="$1"
        shift
      else
        echo "error: unexpected argument: $1" >&2
        usage
      fi
      ;;
  esac
done

[ -n "$spec_file" ] || usage

# Back-compat: strip the OpenCode-era provider prefix from model IDs.
model="${model#fireworks-ai/}"
if [ ! -f "$spec_file" ]; then
  echo "error: task spec not found: $spec_file" >&2
  exit 1
fi
spec_file="$(cd "$(dirname "$spec_file")" && pwd)/$(basename "$spec_file")"

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"
base_branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$base_branch" = "HEAD" ]; then
  echo "error: detached HEAD; check out a branch first" >&2
  exit 1
fi

if [ -z "$name" ]; then
  name="$(basename "$spec_file" .md)"
fi
# Sanitize the name for use as a branch/directory component.
name="$(printf '%s' "$name" | tr -c 'a-zA-Z0-9._-' '-' | sed 's/^-*//;s/-*$//')"
if [ -z "$name" ]; then
  echo "error: could not derive a valid worktree name" >&2
  exit 1
fi
if [ "$name" = "." ] || [ "$name" = ".." ]; then
  echo "error: invalid worktree name: '$name'" >&2
  exit 1
fi
# The name becomes branch fw/<name>; reject names git cannot use (..,
# trailing .lock, and friends) before any side effects.
if ! git check-ref-format "refs/heads/fw/$name"; then
  echo "error: '$name' is not usable as a git branch name (refs/heads/fw/$name is invalid)" >&2
  exit 1
fi

wt_dir="$repo_root/.fw-worktrees/$name"
branch="fw/$name"

if [ -e "$wt_dir" ]; then
  echo "error: worktree already exists: $wt_dir (collect or reject it first)" >&2
  exit 1
fi
if git show-ref --verify --quiet "refs/heads/$branch"; then
  echo "error: branch $branch already exists" >&2
  echo "       recover with: scripts/collect.sh $name --reject" >&2
  exit 1
fi

mkdir -p "$repo_root/.fw-worktrees"

# Keep the runtime state dirs out of git status in repos that do not
# gitignore them, without touching the committed .gitignore.
exclude_file="$(git rev-parse --git-common-dir)/info/exclude"
for pattern in ".fw-worktrees/" ".fw-tasks/"; do
  grep -qxF "$pattern" "$exclude_file" 2>/dev/null || echo "$pattern" >>"$exclude_file"
done

echo "==> creating worktree $wt_dir on branch $branch (base: $base_branch)"
git worktree add -b "$branch" "$wt_dir" "$base_branch" >/dev/null

printf '%s\n' "$base_branch" >"$repo_root/.fw-worktrees/$name.base"

# Deliver the spec as a file inside the worktree instead of as a single
# argv string: large specs can exceed ARG_MAX.
cp "$spec_file" "$wt_dir/.fw-task.md"

log_file="$repo_root/.fw-worktrees/$name.log"
prompt="Read the file .fw-task.md in the current directory and complete the task it describes. Do not modify or delete .fw-task.md."

echo "==> running claude -p (model: $model, timeout: ${RUN_TIMEOUT_SECS}s)"
echo "==> log: $log_file"

# The delegate needs to edit files and run the spec's verification
# commands, so edits are auto-accepted and the Bash tool is pre-approved.
# This is not a blanket bypass: deny rules from the user's Claude Code
# settings still apply, and the worktree keeps the blast radius to a
# branch that is reviewed before merge. stream-json keeps the full
# transcript (tool calls, test output, final summary) in the log.
run_status=0
(
  cd "$wt_dir"
  with_timeout "$RUN_TIMEOUT_SECS" "$SCRIPT_DIR/fw-claude.sh" "$model" \
    -p --permission-mode acceptEdits --allowedTools Bash \
    --no-session-persistence \
    --output-format stream-json --verbose \
    "$prompt"
) <"/dev/null" >"$log_file" 2>&1 || run_status=$?

if [ "$run_status" -ne 0 ]; then
  echo "WARNING: claude exited with status $run_status (timeout or error)." >&2
  echo "         Inspect the log before trusting the result: $log_file" >&2
fi

# Surface permission denials loudly. With acceptEdits plus an allowed Bash
# tool these are rare (a configured deny/ask rule firing, or a write
# outside the worktree), and they would otherwise hide inside the
# transcript. The patterns match the exact denial texts the claude CLI
# puts in tool_result entries.
denial_count="$(grep -cE "Claude requested permissions|Permission to use .* has been denied|was blocked by a deny rule|doesn.t want to proceed with this tool use" "$log_file" 2>/dev/null || true)"
if [ "${denial_count:-0}" -gt 0 ]; then
  echo "WARNING: $denial_count permission denial(s) occurred during the delegate run." >&2
  echo "         The model may have worked around them; review the log: $log_file" >&2
fi

# The spec copy must never land on the branch: remove it before the
# auto-commit, even if the model rewrote it.
rm -f "$wt_dir/.fw-task.md"

# Commit anything the model left uncommitted so the branch fully captures
# its work and collect.sh can merge it.
if [ -n "$(git -C "$wt_dir" status --porcelain)" ]; then
  git -C "$wt_dir" add -A
  git -C "$wt_dir" commit -q -m "fw-delegate: $name (auto-commit of delegated work)"
fi

if [ "$pr_requested" -eq 1 ]; then
  if [ "$(git -C "$wt_dir" rev-list --count "$base_branch..$branch")" -eq 0 ]; then
    echo "==> --pr requested but $branch has no commits beyond $base_branch; skipping PR creation"
  elif ! git -C "$wt_dir" remote get-url origin >/dev/null 2>&1; then
    echo "WARNING: --pr requested but this repo has no origin remote; skipping PR creation." >&2
  elif ! command -v gh >/dev/null 2>&1; then
    echo "WARNING: --pr requested but the GitHub CLI (gh) is not on PATH; skipping PR creation." >&2
  else
    pr_body="$(mktemp "${TMPDIR:-/tmp}/fw-delegate-pr.XXXXXX")"
    {
      printf '## Task spec\n\n'
      cat "$spec_file"
      printf '\n## Delegate log (tail)\n\n```\n'
      # stream-json events can be arbitrarily long lines; truncate after
      # redaction so the PR body stays under GitHub's size limit.
      tail -n 100 "$log_file" | redact_log | cut -c -400
      printf '```\n'
    } >"$pr_body"
    if (cd "$wt_dir" && git push -u origin "$branch"); then
      if pr_url="$(
        cd "$wt_dir" && gh pr create --draft \
          --base "$base_branch" --head "$branch" \
          --title "fw-delegate: $name" --body-file "$pr_body"
      )"; then
        echo "==> draft PR: $pr_url"
      else
        echo "WARNING: --pr requested but gh pr create failed; branch $branch is pushed, open the PR by hand." >&2
      fi
    else
      echo "WARNING: --pr requested but git push -u origin $branch failed; skipping PR creation." >&2
    fi
    rm -f "$pr_body"
  fi
fi

echo
echo "==> worktree: $wt_dir"
echo "==> diff --stat vs $base_branch:"
diff_stat=""
if ! diff_stat="$(git -C "$wt_dir" diff --stat "$base_branch...$branch")"; then
  echo "(no diff available)"
elif [ -n "$diff_stat" ]; then
  printf '%s\n' "$diff_stat"
else
  echo "(no changes were made)"
fi
echo
echo "next: scripts/collect.sh $name        # review and merge"
echo "      scripts/collect.sh $name --reject  # discard"
exit "$run_status"
