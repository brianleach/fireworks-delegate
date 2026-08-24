# Tests for scripts/fw-claude.sh. Fully offline: claude is a stub on PATH.

load helpers

setup() {
  REPO_ROOT="$(fw_repo_root)"
  FW_CLAUDE="${REPO_ROOT}/scripts/fw-claude.sh"
}

@test "no arguments: exits nonzero with usage" {
  run "$FW_CLAUDE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage: fw-claude.sh"* ]]
}

@test "missing FIREWORKS_API_KEY and no .env: exits nonzero" {
  run env -u FIREWORKS_API_KEY "FW_ENV_FILE=${BATS_TEST_TMPDIR}/no-env" \
    "$FW_CLAUDE" "accounts/fireworks/routers/kimi-k3-us" -p "hi"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FIREWORKS_API_KEY is not set"* ]]
}

@test "key and base URL are loaded from the .env file" {
  cd "$BATS_TEST_TMPDIR"
  printf 'FIREWORKS_API_KEY=fw_from_dotenv\nFW_BASE_URL=https://example.test/inference\n' >dotenv
  stub_claude '#!/usr/bin/env bash
printf "api_key: %s\n" "${ANTHROPIC_API_KEY:-}"
printf "base_url: %s\n" "${ANTHROPIC_BASE_URL:-}"
exit 0'
  run env -u FIREWORKS_API_KEY -u FW_BASE_URL "FW_ENV_FILE=${BATS_TEST_TMPDIR}/dotenv" \
    "$FW_CLAUDE" "accounts/fireworks/routers/kimi-k3-us" -p "hi"
  [ "$status" -eq 0 ]
  [[ "$output" == *"api_key: fw_from_dotenv"* ]]
  [[ "$output" == *"base_url: https://example.test/inference"* ]]
}

@test "environment key wins over the .env file" {
  cd "$BATS_TEST_TMPDIR"
  printf 'FIREWORKS_API_KEY=fw_from_dotenv\n' >dotenv
  stub_claude '#!/usr/bin/env bash
printf "api_key: %s\n" "${ANTHROPIC_API_KEY:-}"
exit 0'
  run env FIREWORKS_API_KEY=fw_from_environment "FW_ENV_FILE=${BATS_TEST_TMPDIR}/dotenv" \
    "$FW_CLAUDE" "accounts/fireworks/routers/kimi-k3-us" -p "hi"
  [ "$status" -eq 0 ]
  [[ "$output" == *"api_key: fw_from_environment"* ]]
}

@test "model with unexpected characters is rejected" {
  run env FIREWORKS_API_KEY=fw_test "$FW_CLAUDE" 'bad"model' -p "hi"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unexpected characters"* ]]
}

@test "invokes claude with the scoped environment and standard flags" {
  cd "$BATS_TEST_TMPDIR"
  stub_claude '#!/usr/bin/env bash
printf "argv: %s\n" "$*"
printf "base_url: %s\n" "${ANTHROPIC_BASE_URL:-}"
printf "api_key: %s\n" "${ANTHROPIC_API_KEY:-}"
printf "model_env: %s\n" "${ANTHROPIC_MODEL:-}"
printf "auth_token_unset: %s\n" "${ANTHROPIC_AUTH_TOKEN-unset}"
printf "model_window: %s\n" "${CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT:-}"
exit 0'
  run env FIREWORKS_API_KEY=fw_test ANTHROPIC_AUTH_TOKEN=leftover \
    "$FW_CLAUDE" "accounts/fireworks/routers/kimi-k3-us" -p "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--model accounts/fireworks/routers/kimi-k3-us"* ]]
  [[ "$output" == *"--settings"* ]]
  [[ "$output" == *"--disallowedTools WebSearch,WebFetch"* ]]
  [[ "$output" == *"-p hello"* ]]
  [[ "$output" == *"base_url: https://api.fireworks.ai/inference"* ]]
  [[ "$output" == *"api_key: fw_test"* ]]
  [[ "$output" == *"model_env: accounts/fireworks/routers/kimi-k3-us"* ]]
  [[ "$output" == *"auth_token_unset: unset"* ]]
  [[ "$output" == *"model_window: 1"* ]]
}
