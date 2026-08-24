# Tests for scripts/check-env.sh. Offline failure paths only: no claude
# on PATH, no Fireworks key, no network. The endpoint check and smoke test
# are never exercised.

load helpers

setup() {
  REPO_ROOT="$(fw_repo_root)"
  CHECK_ENV="${REPO_ROOT}/scripts/check-env.sh"
  FAKE_HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$FAKE_HOME"
  # A PATH with the standard unix tools but no claude.
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  OFFLINE_PATH="${BATS_TEST_TMPDIR}/bin:/usr/bin:/bin"
}

@test "PATH without claude: exits nonzero with an install hint" {
  run env -u FIREWORKS_API_KEY "PATH=$OFFLINE_PATH" "HOME=$FAKE_HOME" "$CHECK_ENV"
  [ "$status" -ne 0 ]
  [[ "$output" == *"claude CLI not found"* ]]
  [[ "$output" == *"npm install -g @anthropic-ai/claude-code"* ]]
}

@test "PATH without claude: summary says NOT READY" {
  run env -u FIREWORKS_API_KEY "PATH=$OFFLINE_PATH" "HOME=$FAKE_HOME" "$CHECK_ENV"
  [ "$status" -ne 0 ]
  [[ "$output" == *"NOT READY"* ]]
}

@test "missing key: reports FIREWORKS_API_KEY fix" {
  run env -u FIREWORKS_API_KEY "PATH=$OFFLINE_PATH" "HOME=$FAKE_HOME" "$CHECK_ENV"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FIREWORKS_API_KEY is not set"* ]]
  [[ "$output" == *"export FIREWORKS_API_KEY"* ]]
}

@test "auth override in user settings: prints a warning" {
  mkdir -p "${FAKE_HOME}/.claude"
  printf '{"env":{"ANTHROPIC_AUTH_TOKEN":"other"}}\n' >"${FAKE_HOME}/.claude/settings.json"
  run env -u FIREWORKS_API_KEY "PATH=$OFFLINE_PATH" "HOME=$FAKE_HOME" "$CHECK_ENV"
  [ "$status" -ne 0 ]
  [[ "$output" == *"auth override found in"* ]]
}
