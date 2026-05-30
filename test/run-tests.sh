#!/usr/bin/env bash
#
# Local tests for compute-version.sh: exercises tag lookup, the bump maths,
# the version override, the prerelease suffix and the strict-semver tag
# filter. Label resolution needs a live GitHub API and is covered end-to-end
# in the test repository, not here.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${here}/compute-version.sh"
pass=0 fail=0

# Run the script in a throwaway git repo seeded with the given tags, and
# assert the computed `tag` output. Tags are passed as remaining args.
#   check <desc> <expected-tag> <env-assignments> -- <tags...>
check() {
  local desc="$1" expected="$2"; shift 2
  local -a env_kv=() tags=()
  local seen_sep=0
  for a in "$@"; do
    if [ "$a" = "--" ]; then seen_sep=1; continue; fi
    if [ "$seen_sep" = 1 ]; then tags+=("$a"); else env_kv+=("$a"); fi
  done

  local repo out got
  repo="$(mktemp -d)"
  out="$(mktemp)"
  (
    cd "$repo"
    git init -q
    git config user.email t@t && git config user.name t
    git commit -q --allow-empty -m init
    for t in "${tags[@]:-}"; do [ -n "$t" ] && git tag "$t"; done
    env -i PATH="$PATH" HOME="$HOME" GITHUB_OUTPUT="$out" "${env_kv[@]}" \
      bash "$script" >/dev/null
  )
  got="$(grep '^tag=' "$out" | cut -d= -f2-)"
  if [ "$got" = "$expected" ]; then
    printf '  ok   %-48s -> %s\n' "$desc" "$got"; pass=$((pass + 1))
  else
    printf '  FAIL %-48s -> %s (expected %s)\n' "$desc" "$got" "$expected"; fail=$((fail + 1))
  fi
  rm -rf "$repo" "$out"
}

echo "compute-version.sh"
check "no tags, default patch"        v0.0.1 INPUT_BUMP=patch --
check "patch bump"                    v1.2.4 INPUT_BUMP=patch -- v1.2.3
check "minor bump"                    v1.3.0 INPUT_BUMP=minor -- v1.2.3
check "major bump"                    v2.0.0 INPUT_BUMP=major -- v1.2.3
check "picks highest, not newest"     v2.0.1 INPUT_BUMP=patch -- v2.0.0 v1.9.9 v1.0.0
check "ignores prerelease tags"       v1.2.4 INPUT_BUMP=patch -- v1.2.3 v1.3.0-beta.1
check "ignores stray tags"            v1.0.1 INPUT_BUMP=patch -- v1.0.0 vbanana v1.x
check "prerelease suffix"             v1.2.4-beta.7 "INPUT_BUMP=patch" INPUT_PRERELEASE=beta.7 -- v1.2.3
check "version override"              v2.5.0 INPUT_VERSION=2.5.0 -- v1.2.3
check "version override with v"       v2.5.0 INPUT_VERSION=v2.5.0 -- v1.2.3
check "custom prefix"                 r3.1.0 INPUT_BUMP=minor INPUT_TAG_PREFIX=r -- r3.0.4

echo
echo "passed: ${pass}, failed: ${fail}"
[ "$fail" -eq 0 ]
