# Shared helpers for the fireworks-delegate bats suite.
# Load from a .bats file with: load helpers

# Print the absolute path of the repo under test (the parent of tests/).
fw_repo_root() {
  cd "${BATS_TEST_DIRNAME}/.." && pwd
}

# Create an isolated fixture git repo at ${BATS_TEST_TMPDIR}/repo with one
# commit on branch main, then make it the working directory.
setup_fixture_repo() {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.email "bats@example.invalid"
  git -C "$repo" config user.name "Bats Test"
  printf 'fixture seed\n' >"${repo}/seed.txt"
  git -C "$repo" add seed.txt
  git -C "$repo" commit -q -m "seed commit"
  cd "$repo" || return 1
}

# Write a fake task spec to ${BATS_TEST_TMPDIR}/task.md and print its path.
write_task_spec() {
  local spec="${BATS_TEST_TMPDIR}/task.md"
  printf 'do an offline task\n' >"$spec"
  printf '%s\n' "$spec"
}

# Install a stub opencode at ${BATS_TEST_TMPDIR}/bin/opencode and prepend
# that directory to PATH. The default stub creates KIMI_WAS_HERE.txt in the
# current directory, echoes a fake transcript line, and exits 0. Pass a full
# replacement script (including the shebang line) as $1 to override the
# behavior, for example a stub that exits nonzero or sleeps.
stub_opencode() {
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  local body="${1:-}"
  mkdir -p "$bin_dir"
  if [ -z "$body" ]; then
    body='#!/usr/bin/env bash
printf "KIMI WAS HERE\n" > KIMI_WAS_HERE.txt
printf "fake transcript line from stub opencode\n"
exit 0'
  fi
  printf '%s\n' "$body" >"${bin_dir}/opencode"
  chmod +x "${bin_dir}/opencode"
  export PATH="${bin_dir}:${PATH}"
}
