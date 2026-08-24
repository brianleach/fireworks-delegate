#!/usr/bin/env bash
# Shared wrapper: run the claude CLI against the Fireworks Anthropic
# compatibility endpoint with a scoped, per-invocation environment.
# Used by check-env.sh and delegate.sh. Run with no arguments for usage.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/load-env.sh"
FW_BASE_URL="${FW_BASE_URL:-https://api.fireworks.ai/inference}"

if [ $# -lt 1 ]; then
  echo "usage: fw-claude.sh <model> [claude args...]" >&2
  echo "  <model> is a Fireworks model ID, e.g. accounts/fireworks/routers/kimi-k3-us" >&2
  exit 1
fi
model="$1"
shift

# Both values are interpolated into a JSON literal below; reject anything
# outside the characters Fireworks model IDs and https URLs actually use.
case "$model" in
  *[!A-Za-z0-9/._-]*)
    echo "error: model contains unexpected characters: $model" >&2
    exit 1
    ;;
esac
case "$FW_BASE_URL" in
  *[!A-Za-z0-9:/._-]*)
    echo "error: FW_BASE_URL contains unexpected characters: $FW_BASE_URL" >&2
    exit 1
    ;;
esac

if [ -z "${FIREWORKS_API_KEY:-}" ]; then
  echo "error: FIREWORKS_API_KEY is not set (export it, or put it in the skill repo's gitignored .env)" >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "error: claude CLI not found on PATH" >&2
  exit 1
fi

# Command-line settings outrank the user and project settings files, so a
# stale env block in ~/.claude/settings.json (fireconnect and friends)
# cannot redirect this run. Every model slot points at the delegate model
# so alias lookups and background tasks stay on Fireworks. The API key is
# passed only through the environment: settings JSON lands on argv, which
# is visible in the process list, so it must never carry the key.
settings_json="$(printf '{"env":{"ANTHROPIC_BASE_URL":"%s","ANTHROPIC_MODEL":"%s","ANTHROPIC_DEFAULT_OPUS_MODEL":"%s","ANTHROPIC_DEFAULT_SONNET_MODEL":"%s","ANTHROPIC_DEFAULT_HAIKU_MODEL":"%s","CLAUDE_CODE_SUBAGENT_MODEL":"%s"}}' \
  "$FW_BASE_URL" "$model" "$model" "$model" "$model" "$model")"

# WebSearch and WebFetch are Anthropic server-side tools that the Fireworks
# compatibility endpoint rejects, so they are disallowed for every run.
# ANTHROPIC_AUTH_TOKEN and the cloud-provider switches are dropped so they
# cannot fight the API key or reroute the request.
#
# The key travels as ANTHROPIC_API_KEY (the x-api-key header), not as
# ANTHROPIC_AUTH_TOKEN: claude 2.1.x prefers its own subscription OAuth
# bearer over ANTHROPIC_AUTH_TOKEN, so a bearer-only run reaches Fireworks
# with the wrong credential and comes back 401. Fireworks accepts x-api-key.
#
# CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT keeps claude from
# blocking on the context-window lookup for a model ID it does not know.
# Every Fireworks model ID is unknown to it, so without this the run hangs
# instead of returning.
exec env \
  -u ANTHROPIC_AUTH_TOKEN \
  -u CLAUDE_CODE_USE_BEDROCK \
  -u CLAUDE_CODE_USE_VERTEX \
  -u CLAUDE_CODE_USE_FOUNDRY \
  ANTHROPIC_BASE_URL="$FW_BASE_URL" \
  ANTHROPIC_API_KEY="$FIREWORKS_API_KEY" \
  ANTHROPIC_MODEL="$model" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="$model" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="$model" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="$model" \
  ANTHROPIC_SMALL_FAST_MODEL="$model" \
  CLAUDE_CODE_SUBAGENT_MODEL="$model" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
  CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT=1 \
  claude --model "$model" --settings "$settings_json" \
  --disallowedTools "WebSearch,WebFetch" "$@"
