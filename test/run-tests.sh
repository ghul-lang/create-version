#!/usr/bin/env bash
#
# Local tests for compute-version.sh: tag lookup, the VERSION floor, the
# patch-bump-from-tag maths, the strict-semver filtering, the version override
# and the prerelease suffix — all in throwaway repos.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${here}/compute-version.sh"
pass=0 fail=0

# check <desc> <expected-tag> <env...> [-- <tags...>] [// <VERSION-file-content>]
# Builds a throwaway repo with the given tags and optional VERSION file, runs
# the script, and asserts the computed `tag` output.
check() {
  local desc="$1" expected="$2"; shift 2
  local -a env_kv=() tags=()
  local mode=env vfile=""
  for a in "$@"; do
    case "$a" in
      --) mode=tags; continue ;;
      //) mode=vfile; continue ;;
    esac
    case "$mode" in
      env)   env_kv+=("$a") ;;
      tags)  tags+=("$a") ;;
      vfile) vfile="$a" ;;
    esac
  done

  local repo out got
  repo="$(mktemp -d)"; out="$(mktemp)"
  (
    cd "$repo"
    git init -q; git config user.email t@t; git config user.name t
    git commit -q --allow-empty -m init
    for t in "${tags[@]:-}"; do [ -n "$t" ] && git tag "$t"; done
    [ -n "$vfile" ] && printf '%s\n' "$vfile" > VERSION
    env -i PATH="$PATH" HOME="$HOME" GITHUB_OUTPUT="$out" "${env_kv[@]}" \
      bash "$script" >/dev/null
  )
  got="$(grep '^tag=' "$out" | cut -d= -f2-)"
  if [ "$got" = "$expected" ]; then
    printf '  ok   %-46s -> %s\n' "$desc" "$got"; pass=$((pass + 1))
  else
    printf '  FAIL %-46s -> %s (expected %s)\n' "$desc" "$got" "$expected"; fail=$((fail + 1))
  fi
  rm -rf "$repo" "$out"
}

echo "compute-version.sh"
check "no tags, no floor"               v0.0.1 --
check "patch from tag, no floor"        v1.2.4 -- v1.2.3
check "floor at last release -> patch"  v1.2.4 -- v1.2.3 // 1.2.3
check "floor declares minor"            v1.3.0 -- v1.2.3 // 1.3.0
check "floor declares major"            v2.0.0 -- v1.2.3 // 2.0.0
check "tag has overtaken stale floor"   v1.3.1 -- v1.3.0 // 1.2.0
check "floor below tag ignored"         v1.2.4 -- v1.2.3 // 1.0.0
check "floor with v prefix tolerated"   v1.5.0 -- v1.2.3 // v1.5.0
check "non-semver floor ignored"        v1.2.4 -- v1.2.3 // wip
check "picks highest tag, not newest"   v2.0.1 -- v2.0.0 v1.9.9 v1.0.0
check "ignores prerelease tags"         v1.2.4 -- v1.2.3 v1.3.0-beta.1
check "prerelease suffix"               v1.3.0-beta.7 INPUT_PRERELEASE=beta.7 -- v1.2.3 // 1.3.0
check "version override wins"           v2.5.0 INPUT_VERSION=2.5.0 -- v1.2.3 // 1.3.0
check "custom prefix floor"             r3.1.0 INPUT_TAG_PREFIX=r -- r3.0.4 // 3.1.0

# bump-level classification
bump_of() {
  local repo out; repo="$(mktemp -d)"; out="$(mktemp)"
  ( cd "$repo"; git init -q; git config user.email t@t; git config user.name t
    git commit -q --allow-empty -m init
    for t in "$@"; do [ "$t" = "//" ] && break; git tag "$t"; done
    for ((i=1;i<=$#;i++)); do [ "${!i}" = "//" ] && { j=$((i+1)); printf '%s\n' "${!j}" > VERSION; }; done
    env -i PATH="$PATH" HOME="$HOME" GITHUB_OUTPUT="$out" bash "$script" >/dev/null )
  grep '^bump=' "$out" | cut -d= -f2-; rm -rf "$repo" "$out"
}
echo "bump classification"
for spec in "v1.2.3//1.2.3:patch" "v1.2.3//1.3.0:minor" "v1.2.3//2.0.0:major"; do
  tagver="${spec%%:*}"; want="${spec##*:}"
  tag="${tagver%%//*}"; fl="${tagver##*//}"
  got="$(bump_of "$tag" // "$fl")"
  if [ "$got" = "$want" ]; then printf '  ok   %-20s -> %s\n' "$tag//$fl" "$got"; pass=$((pass+1))
  else printf '  FAIL %-20s -> %s (expected %s)\n' "$tag//$fl" "$got" "$want"; fail=$((fail+1)); fi
done

echo
echo "passed: ${pass}, failed: ${fail}"
[ "$fail" -eq 0 ]
