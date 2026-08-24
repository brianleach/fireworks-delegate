#!/usr/bin/env bash
# Preflight check for the fireworks-delegate skill.
# Verifies: claude CLI installed, Fireworks API key available, the
# Fireworks Anthropic compatibility endpoint reachable, and a live smoke
# test through claude -p against the default model. Exits nonzero with
# fix instructions if anything is missing.
set -euo pipefail

DEFAULT_MODEL="accounts/fireworks/routers/kimi-k3-us"
SMOKE_TIMEOUT_SECS="${FW_SMOKE_TIMEOUT_SECS:-120}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load the gitignored .env from the skill repo root, tracking where the
# key came from so the report can say so. Environment variables win.
key_source="environment"
if [ -z "${FIREWORKS_API_KEY:-}" ]; then
  key_source=""
fi
# shellcheck source=/dev/null
. "$SCRIPT_DIR/load-env.sh"
if [ -z "$key_source" ] && [ -n "${FIREWORKS_API_KEY:-}" ]; then
  key_source=".env file"
fi
FW_BASE_URL="${FW_BASE_URL:-https://api.fireworks.ai/inference}"

failures=0

# Portable timeout: prefer coreutils timeout/gtimeout, fall back to perl alarm.
with_timeout() {
  local secs="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  else
    perl -e 'alarm shift; exec @ARGV' "$secs" "$@"
  fi
}

pass() { printf 'ok    %s\n' "$1"; }
warn() {
  printf 'warn  %s\n' "$1"
  printf '      note: %s\n' "$2"
}
fail() {
  printf 'FAIL  %s\n' "$1"
  printf '      fix: %s\n' "$2"
  failures=$((failures + 1))
}

# 1. claude CLI installed
if command -v claude >/dev/null 2>&1; then
  pass "claude CLI found: $(command -v claude) ($(claude --version 2>/dev/null || echo 'version unknown'))"
else
  fail "claude CLI not found on PATH" \
    "install Claude Code: npm install -g @anthropic-ai/claude-code   (or see https://code.claude.com/docs/en/setup)"
fi

# 2. Fireworks API key present
if [ -n "${FIREWORKS_API_KEY:-}" ]; then
  pass "FIREWORKS_API_KEY present via $key_source"
else
  fail "FIREWORKS_API_KEY is not set" \
    "export FIREWORKS_API_KEY=<key>, or put FIREWORKS_API_KEY=<key> in the skill repo's gitignored .env file (get one at https://app.fireworks.ai/settings/users/api-keys)"
fi

# 3. Conflicting auth overrides in Claude Code settings files. An env block
# in a settings file outranks the environment fw-claude.sh sets, so a
# stored token or custom header for another provider would be sent to
# Fireworks and fail auth. Warn, do not fail: the smoke test below is the
# authoritative verdict.
for settings_file in "${HOME}/.claude/settings.json" ".claude/settings.json" ".claude/settings.local.json"; do
  if [ -f "$settings_file" ] &&
    grep -Eq '"ANTHROPIC_(AUTH_TOKEN|API_KEY|CUSTOM_HEADERS)"' "$settings_file" 2>/dev/null; then
    warn "auth override found in $settings_file" \
      "an ANTHROPIC_AUTH_TOKEN / ANTHROPIC_API_KEY / ANTHROPIC_CUSTOM_HEADERS env entry there outranks this skill's per-run environment; if the smoke test fails, remove it (fireconnect users: fireconnect claude off)"
  fi
done

# 4. The Fireworks Anthropic compatibility endpoint answers with this key
# and model. Uses curl directly so an endpoint or key problem is separated
# from claude CLI configuration problems.
if [ -n "${FIREWORKS_API_KEY:-}" ]; then
  if command -v curl >/dev/null 2>&1; then
    body_file="$(mktemp "${TMPDIR:-/tmp}/fw-check-env.XXXXXX")"
    err_file="$(mktemp "${TMPDIR:-/tmp}/fw-check-env.XXXXXX")"
    trap 'rm -f "$body_file" "$err_file"' EXIT
    http_code="$(curl -sS -o "$body_file" -w '%{http_code}' --max-time 30 \
      -X POST "${FW_BASE_URL}/v1/messages" \
      -H "Authorization: Bearer ${FIREWORKS_API_KEY}" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      -d '{"model":"'"$DEFAULT_MODEL"'","max_tokens":16,"messages":[{"role":"user","content":"Reply with the single word: ready"}]}' \
      2>"$err_file")" || http_code="000"
    if [ "$http_code" = "200" ]; then
      pass "Fireworks endpoint answered: ${FW_BASE_URL}/v1/messages (model $DEFAULT_MODEL)"
    else
      fail "Fireworks endpoint check failed (HTTP $http_code) at ${FW_BASE_URL}/v1/messages" \
        "check the key is valid and has serverless access; response was: $(cat "$err_file" "$body_file" | tail -c 300 | tr '\n' ' ')"
    fi
  else
    warn "curl not found, skipping the direct endpoint check" \
      "the claude smoke test below still exercises the endpoint"
  fi
fi

# 5. Smoke test: one-shot claude -p through fw-claude.sh, the exact path
# delegate.sh uses.
if [ "$failures" -eq 0 ]; then
  printf '...   smoke test: claude -p via fw-claude.sh (model %s, timeout %ss)\n' "$DEFAULT_MODEL" "$SMOKE_TIMEOUT_SECS"
  smoke_output=""
  if smoke_output=$(with_timeout "$SMOKE_TIMEOUT_SECS" "$SCRIPT_DIR/fw-claude.sh" "$DEFAULT_MODEL" \
    -p "Reply with the single word: ready" </dev/null 2>&1) && [ -n "$smoke_output" ]; then
    pass "smoke test succeeded (model responded: $(printf '%s' "$smoke_output" | tail -c 200 | tr '\n' ' '))"
  else
    fail "smoke test against $DEFAULT_MODEL failed" \
      "if the endpoint check above passed, look for conflicting ANTHROPIC_* env entries in ~/.claude/settings.json or .claude/settings.json (see any warnings above). Try manually: scripts/fw-claude.sh $DEFAULT_MODEL -p \"say hello\". Output was: $(printf '%s' "$smoke_output" | tail -c 300 | tr '\n' ' ')"
  fi
else
  printf 'skip  smoke test (fix the failures above first)\n'
fi

echo
if [ "$failures" -gt 0 ]; then
  echo "check-env: NOT READY ($failures problem(s) found)"
  exit 1
fi
echo "check-env: ready to delegate"
