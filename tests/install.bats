# Tests for install.sh. HOME points at a temp dir so the real
# ~/.claude/skills is never touched.

load helpers

setup() {
  REPO_ROOT="$(fw_repo_root)"
  INSTALL="${REPO_ROOT}/install.sh"
  FAKE_HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$FAKE_HOME"
  LINK="${FAKE_HOME}/.claude/skills/fireworks-delegate"
}

@test "fresh HOME: creates a symlink pointing at the repo" {
  run env "HOME=$FAKE_HOME" "$INSTALL"
  [ "$status" -eq 0 ]
  [ -L "$LINK" ]
  [ "$(readlink "$LINK")" = "$REPO_ROOT" ]
}

@test "second run: still exits 0 and reports already installed" {
  run env "HOME=$FAKE_HOME" "$INSTALL"
  [ "$status" -eq 0 ]
  run env "HOME=$FAKE_HOME" "$INSTALL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already installed"* ]]
  [ -L "$LINK" ]
  [ "$(readlink "$LINK")" = "$REPO_ROOT" ]
}

@test "existing non-symlink directory at the target path: exits nonzero" {
  mkdir -p "$LINK"
  run env "HOME=$FAKE_HOME" "$INSTALL"
  [ "$status" -ne 0 ]
  [[ "$output" == *"exists and is not a symlink"* ]]
  [ -d "$LINK" ]
  [ ! -L "$LINK" ]
}
