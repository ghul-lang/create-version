#!/usr/bin/env bash
#
# Compute the next semantic version from the latest Git tag and a checked-in
# VERSION floor file.
#
#   next = max( <latest vX.Y.Z tag> with patch+1 , <VERSION file> )
#
# Patches need nothing: with VERSION unchanged the tag drives a patch bump and
# overtakes the floor, so it is self-correcting and never needs resetting. A
# minor/major release is cut by raising the VERSION file to the target number
# in a PR — and since VERSION is code-owned, that edit requires the code
# owner's review. The bump level is thus gated by GitHub's native required
# review, not by this action.
#
# Pure computation: no tags created, no GitHub API, no token. Tagging is the
# caller's job (e.g. `gh release create`), which seeds the next run.
#
# Inputs arrive as INPUT_* environment variables (see action.yml). Runnable
# locally for tests: when GITHUB_OUTPUT is unset the key=value lines go to
# stdout.

set -euo pipefail

prefix="${INPUT_TAG_PREFIX:-v}"
version_file="${INPUT_VERSION_FILE:-VERSION}"
out="${GITHUB_OUTPUT:-/dev/stdout}"

semver_re='^[0-9]+\.[0-9]+\.[0-9]+$'

# Echo the larger of two X.Y.Z versions.
semver_max() {
  local -a A B
  IFS=. read -r -a A <<< "$1"
  IFS=. read -r -a B <<< "$2"
  local i
  for i in 0 1 2; do
    if   (( ${A[i]:-0} > ${B[i]:-0} )); then echo "$1"; return; fi
    if   (( ${A[i]:-0} < ${B[i]:-0} )); then echo "$2"; return; fi
  done
  echo "$1"
}

emit() {
  local tag="$1" package="$2" bump="$3" previous="$4"
  {
    printf 'tag=%s\n'          "$tag"
    printf 'package=%s\n'      "$package"
    printf 'bump=%s\n'         "$bump"
    printf 'previous-tag=%s\n' "$previous"
  } >> "$out"
  echo "Version: ${tag} (bump: ${bump}, previous: ${previous:-none})"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '**Version:** `%s` — %s bump from `%s`\n' \
      "$tag" "$bump" "${previous:-<none>}" >> "$GITHUB_STEP_SUMMARY"
  fi
}

# 1. Explicit version override wins outright.
if [ -n "${INPUT_VERSION:-}" ]; then
  v="${INPUT_VERSION#"$prefix"}"
  v="${v#v}"
  emit "${prefix}${v}" "${v}" manual ""
  exit 0
fi

# 2. Highest released version, defaulting to 0.0.0 before the first tag.
#    Read the whole sorted list into a variable (no pipe to `head`, which
#    would SIGPIPE git under `set -o pipefail`) and take the first ref that
#    is a strict X.Y.Z — ignoring prereleases and any stray tags.
tags="$(git for-each-ref --sort=-v:refname --format='%(refname:short)' "refs/tags/${prefix}*" || true)"
previous_tag=""
prev="0.0.0"
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  candidate="${ref#"$prefix"}"
  if [[ "$candidate" =~ $semver_re ]]; then
    previous_tag="$ref"
    prev="$candidate"
    break
  fi
done <<< "$tags"

# 3. VERSION floor (optional). Ignored unless it is a strict X.Y.Z.
floor="0.0.0"
if [ -f "$version_file" ]; then
  raw="$(tr -d '[:space:]' < "$version_file" || true)"
  raw="${raw#"$prefix"}"
  raw="${raw#v}"
  [[ "$raw" =~ $semver_re ]] && floor="$raw"
fi

# 4. next = max(patch-bump of the latest tag, the floor).
IFS=. read -r pmaj pmin ppat <<< "$prev"
patch_candidate="${pmaj}.${pmin}.$((ppat + 1))"
next="$(semver_max "$patch_candidate" "$floor")"

# 5. Classify the bump relative to the previous release, for reporting.
IFS=. read -r nmaj nmin _ <<< "$next"
if   (( nmaj > pmaj )); then level="major"
elif (( nmin > pmin )); then level="minor"
else level="patch"
fi

# 6. Optional prerelease suffix (e.g. a build number), for non-release builds.
if [ -n "${INPUT_PRERELEASE:-}" ]; then
  next="${next}-${INPUT_PRERELEASE}"
fi

emit "${prefix}${next}" "${next}" "$level" "$previous_tag"
