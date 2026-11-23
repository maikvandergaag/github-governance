# Keep your copy in sync with upstream

[Setup guide](SETUP.md) · [Home](../../README.md)

The optional workflow below keeps an organization's private or internal copy of GitHub Governance
up to date with the public repository. It proposes upstream changes in a pull request; it does not
merge the PR, modify your target branch directly, or send your internal changes upstream.

## Before you begin

1. [Create your private or internal copy](SETUP.md#create-your-repository) from the upstream `main`
   branch, preserving its Git history. An unrelated repository cannot use this workflow until it
   shares a common ancestor with upstream.
2. Create a **separate GitHub App** for synchronization and install it on the copy, with repository
   permissions **Contents: read and write**, **Pull requests: read and write**, and **Workflows:
   read and write**. The read-only inventory App is not suitable. The sync App can introduce
   workflow changes, so restrict its installation to this repository and protect its key.
3. In the copy's **Settings > Secrets and variables > Actions**, add the repository variable
   `SYNC_APP_CLIENT_ID` with the App's client ID and the repository secret `SYNC_APP_PRIVATE_KEY` with
   its complete PEM private key. Do not commit the key. These are separate from the inventory
   App credentials.
4. Ensure Actions may use the two pinned actions in the example, and that your branch rules permit
   the App to push the dedicated `feature/sync-upstream` branch and open PRs. It does not need
   permission to bypass protection on the target branch. App-created PRs can trigger normal CI,
   subject to repository and organization policy.
5. This example targets `main`. If your copy uses another target branch, set the repository
   variable `SYNC_TARGET_BRANCH` to that branch. The workflow must be present on the default
   branch for scheduled runs, and that default branch must be the configured target branch.

The sync App is needed because updating workflow files requires workflow write permission, and
PRs opened with `GITHUB_TOKEN` do not trigger ordinary PR workflows.

## Install the workflow

Add the following as `.github/workflows/sync-upstream.yml` **in your private/internal copy**,
review it, and merge it into the target branch. It runs each Monday at 05:17 UTC and can also be
started from **Actions > Sync upstream > Run workflow** on the target branch. This example is
opt-in; it is not installed automatically by GitHub Governance. It preserves the target branch's
`.github/workflows/governance-assessment.yml`, `.github/workflows/deploy-pages.yml`, `pages/`, and
`docs/output/` rather than taking their upstream versions. Review and apply upstream updates to
these paths separately, including security fixes and changes needed for compatibility.

The example uses a managed commit and a lease-protected push to update its sync branch. It refuses
to replace a branch that does not match the expected managed commit. Reserve the branch for this
workflow; do not make manual commits on it.

```yaml
name: Sync upstream

on:
  schedule:
    - cron: '17 5 * * 1'
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: sync-upstream
  cancel-in-progress: false

env:
  UPSTREAM_URL: https://github.com/maikvandergaag/github-governance.git
  UPSTREAM_BRANCH: main
  TARGET_BRANCH: ${{ vars.SYNC_TARGET_BRANCH || 'main' }}
  SYNC_BRANCH: feature/sync-upstream

jobs:
  validate:
    if: ${{ github.ref == format('refs/heads/{0}', vars.SYNC_TARGET_BRANCH || 'main') }}
    runs-on: ubuntu-latest
    permissions: {}
    steps:
      - name: Validate GitHub App configuration
        shell: bash
        env:
          SYNC_APP_CLIENT_ID: ${{ vars.SYNC_APP_CLIENT_ID }}
          SYNC_APP_PRIVATE_KEY: ${{ secrets.SYNC_APP_PRIVATE_KEY }}
        run: |
          set -euo pipefail
          missing=0
          if [[ -z "$SYNC_APP_CLIENT_ID" ]]; then
            echo "::error::Required Actions variable SYNC_APP_CLIENT_ID is missing."
            missing=1
          fi
          if [[ -z "$SYNC_APP_PRIVATE_KEY" ]]; then
            echo "::error::Required Actions secret SYNC_APP_PRIVATE_KEY is missing."
            missing=1
          fi
          if [[ "$missing" -ne 0 ]]; then
            exit 1
          fi

  sync:
    needs: validate
    runs-on: ubuntu-latest
    steps:
      - name: Create GitHub App token
        id: app-token
        uses: actions/create-github-app-token@f418cff399f7aef4c2f0ad47e25ca7a6abbdd6fc # v3.4.0
        with:
          client-id: ${{ vars.SYNC_APP_CLIENT_ID }}
          private-key: ${{ secrets.SYNC_APP_PRIVATE_KEY }}

      - name: Checkout
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          ref: ${{ env.TARGET_BRANCH }}
          fetch-depth: 0
          token: ${{ steps.app-token.outputs.token }}

      - name: Fetch and compare upstream
        id: check
        shell: bash
        run: |
          set -euo pipefail
          git fetch origin "+refs/heads/$TARGET_BRANCH:refs/remotes/origin/$TARGET_BRANCH"
          git remote add upstream "$UPSTREAM_URL"
          # Do not send the copy's checkout credentials to the public upstream.
          git -c http.https://github.com/.extraheader= fetch --no-tags upstream \
            "+refs/heads/$UPSTREAM_BRANCH:refs/remotes/upstream/$UPSTREAM_BRANCH"
          if ! git merge-base "origin/$TARGET_BRANCH" "upstream/$UPSTREAM_BRANCH" >/dev/null; then
            echo "::error::The target and upstream do not share Git history."
            exit 1
          fi
          count=$(git rev-list --count "origin/$TARGET_BRANCH..upstream/$UPSTREAM_BRANCH")
          echo "New upstream commits: $count"
          echo "count=$count" >> "$GITHUB_OUTPUT"

      - name: Update sync branch and open a PR
        if: steps.check.outputs.count != '0'
        shell: bash
        env:
          GH_TOKEN: ${{ steps.app-token.outputs.token }}
          GH_ENTERPRISE_TOKEN: ${{ steps.app-token.outputs.token }}
          NEW_COMMITS: ${{ steps.check.outputs.count }}
        run: |
          set -euo pipefail
          remote_ref="refs/heads/$SYNC_BRANCH"
          old_sha=$(git ls-remote --heads origin "$remote_ref" | cut -f1)
          if [ -n "$old_sha" ]; then
            git fetch --no-tags origin "$remote_ref"
            old_sha=$(git rev-parse FETCH_HEAD)
            [ "$(git rev-list --parents -n 1 "$old_sha" | wc -w | tr -d ' ')" = "2" ] || { echo "Refusing to overwrite a merged sync branch." >&2; exit 1; }
            [ "$(git log -1 --format=%s "$old_sha")" = "Sync upstream excluding configured paths" ] || { echo "Refusing to overwrite an unmanaged sync branch." >&2; exit 1; }
            [ "$(git log -1 --format=%ae "$old_sha")" = "41898282+github-actions[bot]@users.noreply.github.com" ] || { echo "Refusing to overwrite a modified sync branch." >&2; exit 1; }
            [ "$(git log -1 --format=%ce "$old_sha")" = "41898282+github-actions[bot]@users.noreply.github.com" ] || { echo "Refusing to overwrite a modified sync branch." >&2; exit 1; }
            git merge-base --is-ancestor "$old_sha^" "upstream/$UPSTREAM_BRANCH" || { echo "Sync branch is not based on upstream history." >&2; exit 1; }
            if ! git diff --quiet "$old_sha^" "$old_sha" -- . \
              ':(exclude).github/workflows/governance-assessment.yml' \
              ':(exclude).github/workflows/deploy-pages.yml' \
              ':(exclude)pages' ':(exclude)docs/output'; then
              echo "Sync branch contains changes outside the configured paths." >&2
              exit 1
            fi
          fi

          git checkout --detach "upstream/$UPSTREAM_BRANCH"
          for path in .github/workflows/governance-assessment.yml .github/workflows/deploy-pages.yml pages docs/output; do
            # Remove upstream-only files before restoring the complete target version.
            git rm -f -r --ignore-unmatch -- "$path"
            if git cat-file -e "origin/$TARGET_BRANCH:$path" 2>/dev/null; then
              git checkout "origin/$TARGET_BRANCH" -- "$path"
            fi
          done
          git -c user.name="github-actions[bot]" \
            -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
            commit --allow-empty -m "Sync upstream excluding configured paths"
          git push --force-with-lease="$remote_ref:$old_sha" origin "HEAD:$remote_ref"
          export GH_HOST="${GITHUB_SERVER_URL#https://}"
          existing=$(gh pr list --repo "$GITHUB_REPOSITORY" \
            --head "$SYNC_BRANCH" --base "$TARGET_BRANCH" --state open \
            --json number --jq '.[0].number // empty')
          if [[ -z "$existing" ]]; then
            gh pr create --repo "$GITHUB_REPOSITORY" \
              --head "$SYNC_BRANCH" --base "$TARGET_BRANCH" \
              --title "Sync with upstream github-governance" \
              --body "Proposes $NEW_COMMITS new upstream commit(s). Review and merge with a merge commit, not squash."
          else
            echo "Updated sync PR #$existing."
          fi
```

## Review and merge updates

- Review upstream code, workflow and permission changes, resolve conflicts, and wait for required
  checks before merging. Adjust local configuration or exemptions as needed; do not assume an
  upstream change is safe for your environment.
- Merge each sync PR with a **merge commit**, not squash or rebase. Preserving upstream commit
  ancestry lets the next run recognize the changes already integrated.
- The sync branch is rewritten when new upstream commits arrive. The workflow checks its previous
  managed commit and uses `--force-with-lease` to prevent overwriting a concurrent update. If it
  refuses the branch, inspect it and any open PR manually. After its work is merged or otherwise
  safely accounted for, delete that dedicated branch through GitHub and rerun. Conflict resolution
  that adds commits to the sync branch can also require this cleanup after the PR is merged.
- If upstream is already included, the workflow does not create or update a PR. Review and close
  any stale sync PR manually. If upstream rewrites history or your copy has unrelated history,
  stop and resolve the history with your repository administrators.
