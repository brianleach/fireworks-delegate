# Tests for scripts/delegate.sh. Fully offline: opencode is a stub on PATH.

load helpers

setup() {
  REPO_ROOT="$(fw_repo_root)"
  DELEGATE="${REPO_ROOT}/scripts/delegate.sh"
  setup_fixture_repo
  stub_opencode
  SPEC="$(write_task_spec)"
}

@test "no arguments: exits nonzero" {
  run "$DELEGATE"
  [ "$status" -ne 0 ]
}

@test "missing spec file: exits nonzero and mentions the path" {
  local missing="${BATS_TEST_TMPDIR}/no-such-spec.md"
  run "$DELEGATE" "$missing"
  [ "$status" -ne 0 ]
  [[ "$output" == *"task spec not found"* ]]
  [[ "$output" == *"$missing"* ]]
}

@test "happy path: worktree, branch, log, auto-commit, diff stat, base file" {
  run "$DELEGATE" "$SPEC" --name happy
  [ "$status" -eq 0 ]
  [[ "$output" == *"diff --stat vs main"* ]]
  [[ "$output" == *"KIMI_WAS_HERE.txt"* ]]

  [ -d .fw-worktrees/happy ]
  git show-ref --verify --quiet refs/heads/fw/happy

  [ -f .fw-worktrees/happy.log ]
  grep -q "fake transcript line from stub opencode" .fw-worktrees/happy.log
  [ ! -f .fw-worktrees/happy/delegate.log ]

  [ "$(git show fw/happy:KIMI_WAS_HERE.txt)" = "KIMI WAS HERE" ]
  [[ "$(git log -1 --format=%s fw/happy)" == *"fw-delegate: happy"* ]]

  [ "$(cat .fw-worktrees/happy.base)" = "main" ]
}

@test "--name with unsafe characters is sanitized" {
  run "$DELEGATE" "$SPEC" --name "hello world!"
  [ "$status" -eq 0 ]
  [ -d .fw-worktrees/hello-world ]
  git show-ref --verify --quiet refs/heads/fw/hello-world
  [ ! -e ".fw-worktrees/hello world!" ]
}

@test "duplicate name: second run exits nonzero" {
  run "$DELEGATE" "$SPEC" --name dup
  [ "$status" -eq 0 ]
  run "$DELEGATE" "$SPEC" --name dup
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "detached HEAD: exits nonzero" {
  git checkout -q --detach HEAD
  run "$DELEGATE" "$SPEC" --name detached
  [ "$status" -ne 0 ]
  [[ "$output" == *"detached HEAD"* ]]
}

@test "stub exiting nonzero: status propagates, worktree and log remain" {
  stub_opencode '#!/usr/bin/env bash
printf "partial transcript before failure\n"
exit 1'
  run "$DELEGATE" "$SPEC" --name failrun
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARNING"* ]]
  [ -d .fw-worktrees/failrun ]
  git show-ref --verify --quiet refs/heads/fw/failrun
  [ -f .fw-worktrees/failrun.log ]
  grep -q "partial transcript before failure" .fw-worktrees/failrun.log
}

@test "name sanitizing to an invalid git ref is rejected before side effects" {
  run "$DELEGATE" "$SPEC" --name "v1..2"
  [ "$status" -ne 0 ]
  [[ "$output" == *"v1..2"* ]]
  [ ! -e ".fw-worktrees/v1..2" ]
  ! git show-ref --verify --quiet refs/heads/fw/v1..2
}

@test "name of .. is rejected" {
  run "$DELEGATE" "$SPEC" --name ".."
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid worktree name"* ]]
}

@test "name sanitizing to empty is rejected" {
  run "$DELEGATE" "$SPEC" --name "!!!"
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not derive a valid worktree name"* ]]
}

@test "existing branch without worktree: error names the recovery command" {
  git branch fw/orphan
  run "$DELEGATE" "$SPEC" --name orphan
  [ "$status" -ne 0 ]
  [[ "$output" == *"scripts/collect.sh orphan --reject"* ]]
}

@test "-h prints usage starting with Usage: and no shebang" {
  run "$DELEGATE" -h
  [ "$status" -ne 0 ]
  [[ "$output" == Usage:* ]]
  [[ "$output" != *"#!/usr/bin/env"* ]]
}
