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

@test "--reject removes worktree, branch, and base file" {
  run "$COLLECT" task1 --reject </dev/null
  [ "$status" -eq 0 ]
  [ ! -d .fw-worktrees/task1 ]
  ! git show-ref --verify --quiet refs/heads/fw/task1
  [ ! -f .fw-worktrees/task1.base ]
}

@test "--merge lands the delegated change on main and cleans up" {
  run "$COLLECT" task1 --merge </dev/null
  [ "$status" -eq 0 ]
  [ -f KIMI_WAS_HERE.txt ]
  grep -q "KIMI WAS HERE" KIMI_WAS_HERE.txt
  [ ! -d .fw-worktrees/task1 ]
  ! git show-ref --verify --quiet refs/heads/fw/task1
  [ ! -f .fw-worktrees/task1.base ]
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
