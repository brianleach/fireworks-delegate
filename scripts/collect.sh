#!/usr/bin/env bash
# Review and merge (or reject) a worktree produced by delegate.sh.
#
# Usage:
#   collect.sh <name> [--base <branch>] [--merge | --reject]
#
# Modes:
#   (default)   show the full diff; if run interactively, prompt to merge;
#               otherwise print next steps
#   --merge     merge fw/<name> into the base branch and remove the worktree
#   --reject    discard the worktree, its branch, and its base record
#
# The base branch comes from .fw-worktrees/<name>.base, written by
# delegate.sh; --base overrides that record. The run log lives at
# .fw-worktrees/<name>.log and is never deleted here.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: collect.sh <name> [--base <branch>] [--merge | --reject]

Review and merge (or reject) a worktree produced by delegate.sh.

Modes:
  (default)   show the full diff; if run interactively, prompt to merge;
              otherwise print next steps
  --merge     merge fw/<name> into the base branch and remove the worktree
  --reject    discard the worktree, its branch, and its base record

Options:
  --base <branch>   base branch to diff and merge against; overrides the
                    recorded .fw-worktrees/<name>.base file
EOF
  exit 1
}

name=""
mode="show"
base_override=""

while [ $# -gt 0 ]; do
  case "$1" in
    --merge) mode="merge"; shift ;;
    --reject) mode="reject"; shift ;;
    --base)
      [ $# -ge 2 ] || usage
      base_override="$2"
      shift 2
      ;;
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

# Sanitize exactly like delegate.sh so `collect.sh "hello world!"` finds the
# worktree delegate.sh actually created, and reject names that could escape
# .fw-worktrees when fed to `git worktree remove --force` or `rm -f`.
name="$(printf '%s' "$name" | tr -c 'a-zA-Z0-9._-' '-' | sed 's/^-*//;s/-*$//')"
if [ -z "$name" ]; then
  echo "error: worktree name is empty after sanitizing" >&2
  exit 1
fi
if [ "$name" = "." ] || [ "$name" = ".." ]; then
  echo "error: invalid worktree name: '$name'" >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

wt_dir="$repo_root/.fw-worktrees/$name"
branch="fw/$name"
base_file="$repo_root/.fw-worktrees/$name.base"
log_file="$repo_root/.fw-worktrees/$name.log"

if [ "$mode" = "reject" ]; then
  # Works even if the worktree directory was deleted by hand: prune stale
  # worktree records, then drop whatever pieces remain. Error only when
  # there is nothing at all to reject.
  git worktree prune
  if [ ! -d "$wt_dir" ] &&
    ! git show-ref --verify --quiet "refs/heads/$branch" &&
    [ ! -f "$base_file" ]; then
    echo "error: nothing to reject for '$name': no worktree, branch, or base file found" >&2
    exit 1
  fi
  echo "==> rejecting $name: removing worktree, branch $branch, and base record"
  if [ -d "$wt_dir" ]; then
    git worktree remove --force "$wt_dir"
  fi
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git branch -D "$branch" >/dev/null
  fi
  rm -f "$base_file"
  echo "done (log kept at $log_file)"
  exit 0
fi

if [ ! -d "$wt_dir" ]; then
  echo "error: no such worktree: $wt_dir" >&2
  exit 1
fi

# The recorded base branch is required for diffing and merging. A missing
# record used to silently fall back to the current branch, which could merge
# into the wrong place; fail instead unless --base states it explicitly.
if [ -n "$base_override" ]; then
  base_branch="$base_override"
elif [ -f "$base_file" ]; then
  base_branch="$(cat "$base_file")"
else
  echo "error: no base branch recorded for '$name': $base_file is missing." >&2
  echo "       pass --base <branch> to state the base branch explicitly." >&2
  exit 1
fi

if ! git show-ref --verify --quiet "refs/heads/$base_branch"; then
  echo "error: recorded base branch '$base_branch' no longer exists." >&2
  echo "       pass --base <branch> to point at the right one." >&2
  exit 1
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
git worktree remove --force "$wt_dir"
git branch -D "$branch" >/dev/null 2>&1 || true
rm -f "$base_file"
echo "==> merged and cleaned up (log kept at $log_file). Commit or amend as needed."
