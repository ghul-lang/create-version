#!/usr/bin/env bash
#
# Compute the next semantic version from the latest Git tag.
#
# The bump level is, in order of precedence:
#   1. the `version` input         — an explicit version, used verbatim;
#   2. the `bump` input            — an explicit major|minor|patch level;
#   3. a label on the associated PR — `major` / `minor` (configurable);
#   4. the `default-bump` input    — used when no label is present.
#
# Pure computation: this never creates a tag or a release. Tagging is the
# caller's job (e.g. `gh release create`), which is what seeds the next run's
# tag lookup.
#
# Inputs arrive as INPUT_* environment variables (see action.yml). The script
# also reads the standard GITHUB_* variables. It is runnable locally for
# tests: when GITHUB_OUTPUT is unset the key=value lines go to stdout.

set -euo pipefail

prefix="${INPUT_TAG_PREFIX:-v}"
default_bump="${INPUT_DEFAULT_BUMP:-patch}"
major_label="${INPUT_MAJOR_LABEL:-major}"
minor_label="${INPUT_MINOR_LABEL:-minor}"
out="${GITHUB_OUTPUT:-/dev/stdout}"

semver_re='^[0-9]+\.[0-9]+\.[0-9]+$'

die() { echo "::error::$*" >&2; exit 1; }

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

IFS=. read -r major minor patch <<< "$prev"

# 3. Bump level: explicit input, else a label on the associated PR, else default.
level="${INPUT_BUMP:-}"
if [ -z "$level" ]; then
  pr=""
  case "${GITHUB_EVENT_NAME:-}" in
    pull_request|pull_request_target)
      pr="$(jq -r '.pull_request.number // empty' "${GITHUB_EVENT_PATH}")"
      ;;
    push)
      # The squash-merge subject ends with "(#N)" under GitHub's default
      # squash strategy; fall back to the commit→PR API if it is absent.
      pr="$(git log -1 --format='%s' | grep -oE '\(#[0-9]+\)$' | tr -dc '0-9' || true)"
      if [ -z "$pr" ]; then
        pr="$(gh api "repos/${GITHUB_REPOSITORY}/commits/${GITHUB_SHA}/pulls" \
                --jq 'first(.[].number) // empty' 2>/dev/null || true)"
      fi
      ;;
  esac

  level="$default_bump"
  if [ -n "$pr" ]; then
    labels="$(gh api "repos/${GITHUB_REPOSITORY}/issues/${pr}/labels" \
                --jq '.[].name' 2>/dev/null || true)"
    if   grep -qxF "$major_label" <<< "$labels"; then level="major"
    elif grep -qxF "$minor_label" <<< "$labels"; then level="minor"
    fi
  fi
fi

# 4. Apply the bump.
case "$level" in
  major) next="$((major + 1)).0.0" ;;
  minor) next="${major}.$((minor + 1)).0" ;;
  patch) next="${major}.${minor}.$((patch + 1))" ;;
  *)     die "invalid bump level '${level}' (expected major, minor or patch)" ;;
esac

# 5. Optional prerelease suffix (e.g. beta.17), for non-release builds.
if [ -n "${INPUT_PRERELEASE:-}" ]; then
  next="${next}-${INPUT_PRERELEASE}"
fi

emit "${prefix}${next}" "${next}" "$level" "$previous_tag"
