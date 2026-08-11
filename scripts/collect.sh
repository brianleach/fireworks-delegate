#!/usr/bin/env bash
# Review and merge (or reject) a worktree produced by delegate.sh.
#
# Usage:
#   collect.sh <name>            show the full diff; if run interactively,
#                                prompt to merge; otherwise print next steps
#   collect.sh <name> --merge    merge fw/<name> into the base branch and
#                                remove the worktree
#   collect.sh <name> --reject   discard the worktree and its branch
set -euo pipefail

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -9
  exit 1
}

name=""
mode="show"

while [ $# -gt 0 ]; do
  case "$1" in
    --merge) mode="merge"; shift ;;
    --reject) mode="reject"; shift ;;
    -h | --help) usage ;;
    *)
      if [ -z "$name" ]; then
        name="$1"; shift
      else
        echo "error: unexpected argument: $1" >&2
        usage
      fi
      ;;
  esac
done

[ -n "$name" ] || usage

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

wt_dir="$repo_root/.fw-worktrees/$name"
branch="fw/$name"
base_file="$repo_root/.fw-worktrees/$name.base"

if [ ! -d "$wt_dir" ]; then
  echo "error: no such worktree: $wt_dir" >&2
  exit 1
fi

base_branch="$(git rev-parse --abbrev-ref HEAD)"
if [ -f "$base_file" ]; then
  base_branch="$(cat "$base_file")"
fi

cleanup() {
  git worktree remove --force "$wt_dir"
  git branch -D "$branch" >/dev/null 2>&1 || true
  rm -f "$base_file"
}

if [ "$mode" = "reject" ]; then
  echo "==> rejecting $name: removing worktree and branch $branch"
  cleanup
  echo "done"
  exit 0
fi

echo "==> diff of $branch vs $base_branch"
echo
git diff "$base_branch...$branch"
echo
git diff --stat "$base_branch...$branch"
echo

if [ "$mode" = "show" ]; then
  if [ -t 0 ]; then
    printf 'Merge %s into %s? [y/N] ' "$branch" "$base_branch"
    read -r answer
    case "$answer" in
      y | Y | yes) mode="merge" ;;
      *)
        echo "not merged. rerun with --merge to accept or --reject to discard."
        exit 0
        ;;
    esac
  else
    echo "review the diff above, then rerun with --merge to accept or --reject to discard."
    exit 0
  fi
fi

current_branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$current_branch" != "$base_branch" ]; then
  echo "error: you are on $current_branch but the worktree was based on $base_branch." >&2
  echo "       check out $base_branch first, then rerun." >&2
  exit 1
fi

echo "==> merging $branch into $base_branch"
git merge --no-ff -m "Merge delegated task $name (branch $branch)" "$branch"
cleanup
echo "==> merged and cleaned up. Log was removed with the worktree; commit or amend as needed."
