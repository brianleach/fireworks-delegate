# Tests for scripts/collect.sh. Each test first produces a worktree by
# running delegate.sh against the stub opencode.

load helpers

setup() {
  REPO_ROOT="$(fw_repo_root)"
  DELEGATE="${REPO_ROOT}/scripts/delegate.sh"
  COLLECT="${REPO_ROOT}/scripts/collect.sh"
  setup_fixture_repo
  stub_opencode
  SPEC="$(write_task_spec)"
  "$DELEGATE" "$SPEC" --name task1 >/dev/null
}

@test "no arguments: exits nonzero" {
  run "$COLLECT"
  [ "$status" -ne 0 ]
}

@test "unknown worktree name: exits nonzero" {
  run "$COLLECT" ghost </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"no such worktree"* ]]
}

@test "show mode without a tty: prints diff and rerun instructions, keeps worktree" {
  run "$COLLECT" task1 </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"KIMI_WAS_HERE.txt"* ]]
  [[ "$output" == *"rerun with --merge"* ]]
  [ -d .fw-worktrees/task1 ]
  git show-ref --verify --quiet refs/heads/fw/task1
}

@test "--reject removes worktree, branch, and base file but keeps the log" {
  run "$COLLECT" task1 --reject </dev/null
  [ "$status" -eq 0 ]
  [ ! -d .fw-worktrees/task1 ]
  ! git show-ref --verify --quiet refs/heads/fw/task1
  [ ! -f .fw-worktrees/task1.base ]
  [ -f .fw-worktrees/task1.log ]
}

@test "--merge lands the delegated change on main and cleans up, keeping the log" {
  run "$COLLECT" task1 --merge </dev/null
  [ "$status" -eq 0 ]
  [ -f KIMI_WAS_HERE.txt ]
  grep -q "KIMI WAS HERE" KIMI_WAS_HERE.txt
  [ ! -d .fw-worktrees/task1 ]
  ! git show-ref --verify --quiet refs/heads/fw/task1
  [ ! -f .fw-worktrees/task1.base ]
  [ -f .fw-worktrees/task1.log ]
}

@test "--merge from a different branch than the base fails and merges nothing" {
  local before
  before="$(git rev-parse main)"
  git checkout -q -b other
  run "$COLLECT" task1 --merge </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"you are on other"* ]]
  [ "$(git rev-parse main)" = "$before" ]
  [ -d .fw-worktrees/task1 ]
  git show-ref --verify --quiet refs/heads/fw/task1
}

@test "missing .base file is a hard error mentioning --base" {
  rm .fw-worktrees/task1.base
  run "$COLLECT" task1 </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"no base branch recorded"* ]]
  [[ "$output" == *"--base"* ]]
  [ -d .fw-worktrees/task1 ]
  git show-ref --verify --quiet refs/heads/fw/task1
}

@test "--base allows --merge when the .base file is missing" {
  rm .fw-worktrees/task1.base
  run "$COLLECT" task1 --merge --base main </dev/null
  [ "$status" -eq 0 ]
  [ -f KIMI_WAS_HERE.txt ]
  [ ! -d .fw-worktrees/task1 ]
  ! git show-ref --verify --quiet refs/heads/fw/task1
}

@test "--base overrides a present .base file" {
  git branch altbase
  printf 'altbase\n' >.fw-worktrees/task1.base
  run "$COLLECT" task1 --merge --base main </dev/null
  [ "$status" -eq 0 ]
  [ -f KIMI_WAS_HERE.txt ]
  ! git show-ref --verify --quiet refs/heads/fw/task1
}

@test "recorded base branch that no longer exists is a hard error" {
  git branch gonebase
  printf 'gonebase\n' >.fw-worktrees/task1.base
  git branch -D gonebase >/dev/null
  run "$COLLECT" task1 </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"no longer exists"* ]]
  [[ "$output" == *"--base"* ]]
  [ -d .fw-worktrees/task1 ]
  git show-ref --verify --quiet refs/heads/fw/task1
}

@test "resolves a name that needed sanitizing" {
  "$DELEGATE" "$SPEC" --name "hello world!" >/dev/null
  run "$COLLECT" "hello world!" --reject </dev/null
  [ "$status" -eq 0 ]
  [ ! -d .fw-worktrees/hello-world ]
  ! git show-ref --verify --quiet refs/heads/fw/hello-world
  [ ! -f .fw-worktrees/hello-world.base ]
}

@test "name .. is rejected without touching any state" {
  run "$COLLECT" ".." --reject </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid worktree name"* ]]
  [ -d .fw-worktrees/task1 ]
  git show-ref --verify --quiet refs/heads/fw/task1
  [ -f .fw-worktrees/task1.base ]
}

@test "--reject recovers when the worktree dir was deleted but the branch remains" {
  rm -rf .fw-worktrees/task1
  run "$COLLECT" task1 --reject </dev/null
  [ "$status" -eq 0 ]
  ! git show-ref --verify --quiet refs/heads/fw/task1
  [ ! -f .fw-worktrees/task1.base ]
  [ -f .fw-worktrees/task1.log ]
}

@test "--reject with no worktree, branch, or base file errors" {
  run "$COLLECT" ghost --reject </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"nothing to reject"* ]]
}

@test "-h prints usage starting with Usage: and no shebang" {
  run "$COLLECT" -h
  [ "$status" -ne 0 ]
  [[ "$output" == Usage:* ]]
  [[ "$output" != *"#!/usr/bin/env"* ]]
}

@test "--merge with an origin remote pushes base and deletes the remote fw branch" {
  local origin
  origin="$(setup_origin_remote)"
  # Simulate delegate.sh --pr having pushed the fw branch.
  git push -q origin fw/task1
  run "$COLLECT" task1 --merge </dev/null
  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$origin" rev-parse main)" = "$(git rev-parse main)" ]
  ! git --git-dir="$origin" show-ref --verify --quiet refs/heads/fw/task1
  [ -f KIMI_WAS_HERE.txt ]
  [ ! -d .fw-worktrees/task1 ]
  ! git show-ref --verify --quiet refs/heads/fw/task1
  [ -f .fw-worktrees/task1.log ]
}

@test "--reject without an origin remote behaves exactly as before" {
  run "$COLLECT" task1 --reject </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"rejecting task1"* ]]
  [[ "$output" == *"done"* ]]
  [ ! -d .fw-worktrees/task1 ]
  ! git show-ref --verify --quiet refs/heads/fw/task1
  [ ! -f .fw-worktrees/task1.base ]
  [ -f .fw-worktrees/task1.log ]
}
