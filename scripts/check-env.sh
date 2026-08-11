#!/usr/bin/env bash
# Preflight check for the fireworks-delegate skill.
# Verifies: opencode installed, Fireworks API key available, fireworks-ai
# provider resolvable, and a live smoke test against the default model.
# Exits nonzero with fix instructions if anything is missing.
set -euo pipefail

DEFAULT_MODEL="fireworks-ai/accounts/fireworks/routers/kimi-k3-us"
SMOKE_TIMEOUT_SECS="${FW_SMOKE_TIMEOUT_SECS:-120}"

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
fail() {
  printf 'FAIL  %s\n' "$1"
  printf '      fix: %s\n' "$2"
  failures=$((failures + 1))
}

# 1. opencode CLI installed
if command -v opencode >/dev/null 2>&1; then
  pass "opencode CLI found: $(command -v opencode) ($(opencode --version 2>/dev/null || echo 'version unknown'))"
else
  fail "opencode CLI not found on PATH" \
    "install with: npm install -g opencode-ai   (or: brew install sst/tap/opencode)"
fi

# 2. Fireworks API key present: env var or opencode auth store
key_source=""
if [ -n "${FIREWORKS_API_KEY:-}" ]; then
  key_source="FIREWORKS_API_KEY environment variable"
elif [ -f "${HOME}/.local/share/opencode/auth.json" ] &&
  grep -q '"fireworks' "${HOME}/.local/share/opencode/auth.json" 2>/dev/null; then
  key_source="opencode auth store (~/.local/share/opencode/auth.json)"
fi

if [ -n "$key_source" ]; then
  pass "Fireworks API key present via $key_source"
else
  fail "no Fireworks API key found" \
    "run: fireconnect opencode on (install: https://github.com/fw-ai/fireconnect), or export FIREWORKS_API_KEY=<key> (get one at https://app.fireworks.ai/settings/users/api-keys), or run: opencode auth login  and pick Fireworks."
fi

# 3. opencode can resolve the fireworks-ai provider
if command -v opencode >/dev/null 2>&1; then
  if opencode models 2>/dev/null | grep -q '^fireworks-ai/'; then
    pass "opencode resolves the fireworks-ai provider"
  else
    fail "opencode does not list any fireworks-ai models" \
      "run: opencode auth login  and select Fireworks, or add a fireworks-ai provider block to ~/.config/opencode/opencode.json"
  fi
fi

# 4. Smoke test: one-shot prompt against the default model
if [ "$failures" -eq 0 ]; then
  printf '...   smoke test: opencode run -m %s (timeout %ss)\n' "$DEFAULT_MODEL" "$SMOKE_TIMEOUT_SECS"
  smoke_output=""
  if smoke_output=$(with_timeout "$SMOKE_TIMEOUT_SECS" opencode run -m "$DEFAULT_MODEL" \
    "Reply with the single word: ready" </dev/null 2>&1) && [ -n "$smoke_output" ]; then
    pass "smoke test succeeded (model responded: $(printf '%s' "$smoke_output" | tail -c 200 | tr '\n' ' '))"
  else
    fail "smoke test against $DEFAULT_MODEL failed" \
      "check your Fireworks key is valid and has serverless access; try manually: opencode run -m $DEFAULT_MODEL \"say hello\". Output was: $(printf '%s' "$smoke_output" | tail -c 300 | tr '\n' ' ')"
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
