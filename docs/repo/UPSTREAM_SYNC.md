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
   `SYNC_APP_ID` with the App's numeric ID and the repository secret `SYNC_APP_PRIVATE_KEY` with
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
review it, and merge it into the target branch. It runs each Monday at 05:47 UTC and can also be
started from **Actions > Sync upstream > Run workflow** on the target branch. This example is
opt-in; it is not installed automatically by GitHub Governance.

```yaml
name: Sync upstream

on:
  schedule:
    - cron: '47 5 * * 1'
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
          SYNC_APP_ID: ${{ vars.SYNC_APP_ID }}
          SYNC_APP_PRIVATE_KEY: ${{ secrets.SYNC_APP_PRIVATE_KEY }}
        run: |
          set -euo pipefail
          missing=0
          if [[ -z "$SYNC_APP_ID" ]]; then
            echo "::error::Required Actions variable SYNC_APP_ID is missing."
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
        uses: actions/create-github-app-token@fee1f7d63c2ff003460e3d139729b119787bc349 # v2
        with:
          app-id: ${{ vars.SYNC_APP_ID }}
          private-key: ${{ secrets.SYNC_APP_PRIVATE_KEY }}

      - name: Checkout
        uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # v6.1.0
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
          # Never force-push: a divergent or manually edited sync branch requires review.
          git push origin "refs/remotes/upstream/$UPSTREAM_BRANCH:refs/heads/$SYNC_BRANCH"
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
- Reserve `feature/sync-upstream` for this workflow. The sample uses a normal fast-forward push,
  rather than the original force push, so it refuses to overwrite a divergent branch. If it fails,
  inspect the branch and any open PR manually. After its work is merged or otherwise safely
  accounted for, delete that dedicated branch through GitHub and rerun. Conflict resolution that
  adds commits to the sync branch can also require this cleanup after the PR is merged.
- If upstream is already included, the workflow does not create or update a PR. Review and close
  any stale sync PR manually. If upstream rewrites history or your copy has unrelated history,
  stop and resolve the history with your repository administrators.
