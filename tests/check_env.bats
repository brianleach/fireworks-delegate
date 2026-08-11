# Tests for scripts/check-env.sh. Offline failure paths only: no opencode
# on PATH, no Fireworks key, no network. The smoke test is never exercised.

load helpers

setup() {
  REPO_ROOT="$(fw_repo_root)"
  CHECK_ENV="${REPO_ROOT}/scripts/check-env.sh"
  FAKE_HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$FAKE_HOME"
  # A PATH with the standard unix tools but no opencode.
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  OFFLINE_PATH="${BATS_TEST_TMPDIR}/bin:/usr/bin:/bin"
}

@test "PATH without opencode: exits nonzero with an install hint" {
  run env -u FIREWORKS_API_KEY "PATH=$OFFLINE_PATH" "HOME=$FAKE_HOME" "$CHECK_ENV"
  [ "$status" -ne 0 ]
  [[ "$output" == *"opencode CLI not found"* ]]
  [[ "$output" == *"install with: npm install -g opencode-ai"* ]]
}

@test "PATH without opencode: summary says NOT READY" {
  run env -u FIREWORKS_API_KEY "PATH=$OFFLINE_PATH" "HOME=$FAKE_HOME" "$CHECK_ENV"
  [ "$status" -ne 0 ]
  [[ "$output" == *"NOT READY"* ]]
}
