#!/usr/bin/env bash
# Delegate a task spec to an OSS model on Fireworks via OpenCode, in an
# isolated git worktree of the current repo.
#
# Usage:
#   delegate.sh <task-spec.md> [--model <provider/model>] [--name <worktree-name>]
#
# Behavior:
#   - creates a worktree under .fw-worktrees/<name> on branch fw/<name>,
#     branched off the current branch
#   - runs `opencode run` in that worktree with the task spec as the prompt
#   - captures all output to .fw-worktrees/<name>/delegate.log
#   - auto-commits any changes the model left uncommitted
#   - prints the worktree path and a diff --stat against the base branch
#
# Safe to run multiple times in parallel with distinct names.
set -euo pipefail

DEFAULT_MODEL="fireworks-ai/accounts/fireworks/routers/kimi-k3-us"
RUN_TIMEOUT_SECS="${FW_DELEGATE_TIMEOUT_SECS:-1800}"

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -16
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

spec_file=""
model="$DEFAULT_MODEL"
name=""

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
[ -n "$name" ] || {
  echo "error: could not derive a valid worktree name" >&2
  exit 1
}

wt_dir="$repo_root/.fw-worktrees/$name"
branch="fw/$name"

if [ -e "$wt_dir" ]; then
  echo "error: worktree already exists: $wt_dir (collect or reject it first)" >&2
  exit 1
fi
if git show-ref --verify --quiet "refs/heads/$branch"; then
  echo "error: branch $branch already exists (collect or reject it first)" >&2
  exit 1
fi

mkdir -p "$repo_root/.fw-worktrees"

# Keep delegate.log and meta files out of git for every worktree of this repo,
# without touching the committed .gitignore.
exclude_file="$(git rev-parse --git-common-dir)/info/exclude"
for pattern in "delegate.log" ".fw-worktrees/" ".fw-tasks/"; do
  grep -qxF "$pattern" "$exclude_file" 2>/dev/null || echo "$pattern" >>"$exclude_file"
done

echo "==> creating worktree $wt_dir on branch $branch (base: $base_branch)"
git worktree add -b "$branch" "$wt_dir" "$base_branch" >/dev/null

printf '%s\n' "$base_branch" >"$repo_root/.fw-worktrees/$name.base"

log_file="$wt_dir/delegate.log"
prompt="$(cat "$spec_file")"

echo "==> running opencode (model: $model, timeout: ${RUN_TIMEOUT_SECS}s)"
echo "==> log: $log_file"

run_status=0
(
  cd "$wt_dir"
  with_timeout "$RUN_TIMEOUT_SECS" opencode run -m "$model" "$prompt"
) >"$log_file" 2>&1 || run_status=$?

if [ "$run_status" -ne 0 ]; then
  echo "WARNING: opencode exited with status $run_status (timeout or error)." >&2
  echo "         Inspect the log before trusting the result: $log_file" >&2
fi

# Commit anything the model left uncommitted so the branch fully captures
# its work and collect.sh can merge it.
if [ -n "$(git -C "$wt_dir" status --porcelain)" ]; then
  git -C "$wt_dir" add -A
  git -C "$wt_dir" commit -q -m "fw-delegate: $name (auto-commit of delegated work)"
fi

echo
echo "==> worktree: $wt_dir"
echo "==> diff --stat vs $base_branch:"
if ! git -C "$wt_dir" diff --stat "$base_branch...$branch"; then
  echo "(no diff available)"
fi
if [ -z "$(git -C "$wt_dir" diff --stat "$base_branch...$branch")" ]; then
  echo "(no changes were made)"
fi
echo
echo "next: scripts/collect.sh $name        # review and merge"
echo "      scripts/collect.sh $name --reject  # discard"
exit "$run_status"
