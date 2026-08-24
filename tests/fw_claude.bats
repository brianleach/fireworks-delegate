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

@test "missing FIREWORKS_API_KEY: exits nonzero" {
  run env -u FIREWORKS_API_KEY "$FW_CLAUDE" "accounts/fireworks/routers/kimi-k3-us" -p "hi"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FIREWORKS_API_KEY is not set"* ]]
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
printf "auth_token: %s\n" "${ANTHROPIC_AUTH_TOKEN:-}"
printf "model_env: %s\n" "${ANTHROPIC_MODEL:-}"
printf "api_key_unset: %s\n" "${ANTHROPIC_API_KEY-unset}"
exit 0'
  run env FIREWORKS_API_KEY=fw_test ANTHROPIC_API_KEY=leftover \
    "$FW_CLAUDE" "accounts/fireworks/routers/kimi-k3-us" -p "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--model accounts/fireworks/routers/kimi-k3-us"* ]]
  [[ "$output" == *"--settings"* ]]
  [[ "$output" == *"--disallowedTools WebSearch,WebFetch"* ]]
  [[ "$output" == *"-p hello"* ]]
  [[ "$output" == *"base_url: https://api.fireworks.ai/inference"* ]]
  [[ "$output" == *"auth_token: fw_test"* ]]
  [[ "$output" == *"model_env: accounts/fireworks/routers/kimi-k3-us"* ]]
  [[ "$output" == *"api_key_unset: unset"* ]]
}
