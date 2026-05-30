# create-version

A GitHub composite action that computes the next semantic version:

```
next = max( <latest vX.Y.Z tag> with patch + 1 , <VERSION file> )
```

**Patches need nothing** — with the `VERSION` file unchanged, the latest tag
drives a patch bump and overtakes the floor, so it is self-correcting and never
needs resetting. **A minor or major release is cut by raising the `VERSION`
file** to the target number in a PR.

It is **pure computation**: no tag is created, no GitHub API is called, no
token is needed. Tagging stays with the caller (typically `gh release create`
on the release branch), which is what seeds the next run's tag lookup.

## Why a code-owned VERSION file

Make `VERSION` (and your release workflow) code-owned and turn on **Require
review from Code Owners**. Then a minor/major bump — which *is* an edit to
`VERSION` — requires the code owner's approval, while ordinary patch PRs (which
don't touch `VERSION`) need no review and can auto-merge. The bump and its
approval become the same, fully auditable act, enforced by GitHub natively with
no custom status check. See [Gating bumps](#gating-bumps-with-codeowners).

## Usage

```yaml
- uses: actions/checkout@v6
  with:
    fetch-depth: 0          # full history + tags, so the latest tag is visible

- id: version
  uses: degory/create-version@v1
  with:
    # non-release builds get a prerelease suffix so they can never collide
    # with a real release:
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

## Inputs

| Input          | Default   | Description |
|----------------|-----------|-------------|
| `version`      | `''`      | Explicit version override (`1.4.0` or `v1.4.0`); wins outright. |
| `version-file` | `VERSION` | Path to the floor file. Higher-than-tag strict `X.Y.Z` is used; missing/non-semver is ignored. |
| `prerelease`   | `''`      | Suffix appended as `-<prerelease>` (e.g. `beta.17`). |
| `tag-prefix`   | `v`       | Tag prefix. |

## Outputs

| Output         | Example  | Description |
|----------------|----------|-------------|
| `tag`          | `v1.4.0` | Version with the prefix. |
| `package`      | `1.4.0`  | Version without the prefix. |
| `bump`         | `minor`  | Level vs the previous release (`major`/`minor`/`patch`/`manual`). |
| `previous-tag` | `v1.3.7` | Tag the version was computed from (empty before the first release). |

## Gating bumps with CODEOWNERS

1. Commit a `VERSION` file containing the current released version (e.g.
   `1.3.0`).
2. Add a **narrowly scoped** `CODEOWNERS` — own only the release-sensitive
   paths, *not* the whole repo (a `*` owner would require review on every PR):

   ```
   /VERSION              @your-handle
   /.github/workflows/   @your-handle
   /.github/CODEOWNERS   @your-handle
   ```

3. In branch protection for the release branch: **Require a pull request before
   merging**, **Require review from Code Owners**, and set **required approvals
   to 0**. Code-owner approval is then required only when an owned file
   changes; all other PRs need no review and auto-merge.

Result: a patch PR touches none of those paths and merges freely; a PR raising
`VERSION` (or editing the release workflow) is held for the code owner. A code
owner cannot approve their own PR, so non-patch bumps should come from a PR
authored by someone else (e.g. a bot) and approved by the owner.

## Tests

`bash test/run-tests.sh` exercises tag lookup, the VERSION floor, the
patch-bump maths, strict-semver filtering, the override and the prerelease
suffix in throwaway repos.
