# Tests for scripts/check-env.sh. Offline failure paths only: no claude
# on PATH, no Fireworks key, no network. The endpoint check and smoke test
# are never exercised. FW_ENV_FILE points at a nonexistent file so a real
# .env in the developer's checkout cannot leak into the tests.

load helpers

setup() {
  REPO_ROOT="$(fw_repo_root)"
  CHECK_ENV="${REPO_ROOT}/scripts/check-env.sh"
  FAKE_HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$FAKE_HOME"
  # A PATH with the standard unix tools but no claude.
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  OFFLINE_PATH="${BATS_TEST_TMPDIR}/bin:/usr/bin:/bin"
  NO_ENV_FILE="${BATS_TEST_TMPDIR}/no-env"
}

@test "PATH without claude: exits nonzero with an install hint" {
  run env -u FIREWORKS_API_KEY "PATH=$OFFLINE_PATH" "HOME=$FAKE_HOME" \
    "FW_ENV_FILE=$NO_ENV_FILE" "$CHECK_ENV"
  [ "$status" -ne 0 ]
  [[ "$output" == *"claude CLI not found"* ]]
  [[ "$output" == *"npm install -g @anthropic-ai/claude-code"* ]]
}

@test "PATH without claude: summary says NOT READY" {
  run env -u FIREWORKS_API_KEY "PATH=$OFFLINE_PATH" "HOME=$FAKE_HOME" \
    "FW_ENV_FILE=$NO_ENV_FILE" "$CHECK_ENV"
  [ "$status" -ne 0 ]
  [[ "$output" == *"NOT READY"* ]]
}

@test "missing key: reports FIREWORKS_API_KEY fix" {
  run env -u FIREWORKS_API_KEY "PATH=$OFFLINE_PATH" "HOME=$FAKE_HOME" \
    "FW_ENV_FILE=$NO_ENV_FILE" "$CHECK_ENV"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FIREWORKS_API_KEY is not set"* ]]
  [[ "$output" == *"export FIREWORKS_API_KEY"* ]]
}

@test "auth override in user settings: prints a warning" {
  mkdir -p "${FAKE_HOME}/.claude"
  printf '{"env":{"ANTHROPIC_AUTH_TOKEN":"other"}}\n' >"${FAKE_HOME}/.claude/settings.json"
  run env -u FIREWORKS_API_KEY "PATH=$OFFLINE_PATH" "HOME=$FAKE_HOME" \
    "FW_ENV_FILE=$NO_ENV_FILE" "$CHECK_ENV"
  [ "$status" -ne 0 ]
  [[ "$output" == *"auth override found in"* ]]
}

@test "key from .env file: key check passes and names the source" {
  printf 'FIREWORKS_API_KEY=fw_from_dotenv\n' >"${BATS_TEST_TMPDIR}/dotenv"
  # A minimal PATH without claude and without curl, so neither the
  # endpoint check nor the smoke test can reach the network.
  local safe_bin="${BATS_TEST_TMPDIR}/safe-bin"
  mkdir -p "$safe_bin"
  local tool
  for tool in bash env dirname grep; do
    ln -sf "$(command -v "$tool")" "$safe_bin/$tool"
  done
  run env -u FIREWORKS_API_KEY "PATH=$safe_bin" "HOME=$FAKE_HOME" \
    "FW_ENV_FILE=${BATS_TEST_TMPDIR}/dotenv" "$CHECK_ENV"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FIREWORKS_API_KEY present via .env file"* ]]
  [[ "$output" == *"curl not found"* ]]
  [[ "$output" == *"claude CLI not found"* ]]
}
