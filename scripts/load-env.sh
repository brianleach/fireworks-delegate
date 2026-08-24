# shellcheck shell=bash
# Sourced helper (not executable): load FIREWORKS_API_KEY and FW_BASE_URL
# from the skill repo's gitignored .env file when they are not already set
# in the environment. Real environment variables always win. Override the
# file location with FW_ENV_FILE.
#
# The .env lives at the root of the fireworks-delegate checkout (next to
# this scripts/ directory), NOT in the repo being worked on: the scripts
# run from the target repo, so the file is resolved relative to this
# script's own location.

fw_load_env() {
  local script_dir env_file prev_key prev_url
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  env_file="${FW_ENV_FILE:-${script_dir}/../.env}"
  [ -f "$env_file" ] || return 0
  prev_key="${FIREWORKS_API_KEY:-}"
  prev_url="${FW_BASE_URL:-}"
  set -a
  # shellcheck source=/dev/null
  . "$env_file"
  set +a
  if [ -n "$prev_key" ]; then
    FIREWORKS_API_KEY="$prev_key"
  fi
  if [ -n "$prev_url" ]; then
    FW_BASE_URL="$prev_url"
  fi
  return 0
}

fw_load_env
