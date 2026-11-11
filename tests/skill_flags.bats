# Checks that SKILL.md documents every long flag delegate.sh and
# collect.sh advertise, so an orchestrator that only loads the skill never
# meets a flag it has no instructions for. Flags are read from the
# "Usage:" synopsis line each script prints with --help, so a new flag
# added there is covered without editing this file.

load helpers

setup() {
  REPO_ROOT="$(fw_repo_root)"
  SKILL="${REPO_ROOT}/SKILL.md"
}

# Print the long flags on the Usage line of a script's --help output, one
# per line. --help exits 1 by design, so the status is ignored.
usage_flags() {
  { "$1" --help 2>&1 || true; } | sed -n '/^Usage:/{p;q;}' |
    grep -oE -- '--[a-z][a-z-]*' | sort -u
}

@test "SKILL.md documents every long flag of delegate.sh and collect.sh" {
  local script flag flags missing=""
  for script in delegate.sh collect.sh; do
    flags="$(usage_flags "${REPO_ROOT}/scripts/${script}")"
    # Guard against a silently empty extraction passing the test.
    [ -n "$flags" ] || {
      echo "no flags extracted from ${script} usage"
      return 1
    }
    while IFS= read -r flag; do
      if ! grep -qE -- "${flag}([^a-z-]|\$)" "$SKILL"; then
        missing="${missing} ${script}:${flag}"
      fi
    done <<<"$flags"
  done
  if [ -n "$missing" ]; then
    echo "flags missing from SKILL.md:${missing}"
    return 1
  fi
}
