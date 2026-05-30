# create-version

A GitHub composite action that computes the next semantic version from the
latest Git tag. The bump level is driven by a **label on the pull request** —
`minor` or `major`, otherwise patch.

It is **pure computation**: it never creates a tag or a release. Tagging stays
with the caller (typically `gh release create` on the release branch), which is
what seeds the next run's tag lookup.

## Why labels

A label is explicit, visible in the PR UI, and requires write access to apply,
so it can't be tripped by accident the way a commit-message marker (`#minor`)
can — a marker mentioned in passing in a PR description has caused an
unintended major release before. Labels also compose with an approval gate: a
required status check can demand maintainer approval before a `minor`/`major`
PR may merge, while patch PRs auto-merge untouched (see
[`examples/version-bump-approval.yml`](examples/version-bump-approval.yml)).

## Usage

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0          # full history + tags, so the latest tag is visible

- id: version
  uses: degory/create-version@v1
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
    # On non-release builds, append a prerelease suffix so the version can
    # never collide with a real release:
    prerelease: ${{ github.event_name == 'pull_request' && format('beta.{0}', github.run_number) || '' }}

- run: echo "Building ${{ steps.version.outputs.tag }}"
```

On a push to the release branch the same step produces the release version;
create the tag/release yourself once the build is green:

```yaml
- run: gh release create "${{ steps.version.outputs.tag }}" --generate-notes
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## How the bump is decided

In order of precedence:

1. `version` input — an explicit version, used verbatim.
2. `bump` input — an explicit `major` / `minor` / `patch` level.
3. A `major` / `minor` label on the associated PR. The PR is read from the
   `pull_request` event payload, or — on a push — from the squash-merge
   subject `(#N)`, falling back to the commit→PR API.
4. `default-bump` (patch) when no label is present.

## Inputs

| Input          | Default  | Description |
|----------------|----------|-------------|
| `token`        | —        | **Required.** Token used to read PR labels. |
| `version`      | `''`     | Explicit version override (`1.4.0` or `v1.4.0`); wins outright. |
| `bump`         | `''`     | Explicit `major`/`minor`/`patch`; skips the label lookup. |
| `default-bump` | `patch`  | Bump level when no label is present. |
| `prerelease`   | `''`     | Suffix appended as `-<prerelease>` (e.g. `beta.17`). |
| `tag-prefix`   | `v`      | Tag prefix. |
| `major-label`  | `major`  | Label that selects a major bump. |
| `minor-label`  | `minor`  | Label that selects a minor bump. |

## Outputs

| Output         | Example  | Description |
|----------------|----------|-------------|
| `tag`          | `v1.4.0` | Version with the prefix. |
| `package`      | `1.4.0`  | Version without the prefix. |
| `bump`         | `minor`  | Level applied (`major`/`minor`/`patch`/`manual`). |
| `previous-tag` | `v1.3.7` | Tag the version was computed from (empty before the first release). |

## Tests

`bash test/run-tests.sh` exercises the tag lookup, bump maths, override,
prerelease suffix and strict-semver tag filtering in throwaway repos. Label
resolution needs a live GitHub API and is covered end-to-end in the test
repository.
