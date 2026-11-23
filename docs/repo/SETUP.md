# Setup guide

[Configuration handbook](../configuration/README.md) · [Repository guide](README.md) · [Home](../../README.md)

This guide helps you create your own copy and configure it for an enterprise, standalone
organization, or personal account. The [configuration handbook](../configuration/README.md)
provides detailed instructions.

![Five steps: choose a scope, configure the GitHub App, review policy, run the workflow, and review results.](../assets/setup-journey.svg)

## Create your repository

Generated inventories can contain sensitive organization and repository metadata. For real
inventories, create an **empty private or internal repository** in the account or organization
where you want to store the results. Do not initialize it with a README, license, or `.gitignore`:
the initial push below needs the upstream history. A GitHub fork of a public repository is public;
do not use a public fork to store sensitive generated output. If Actions are enabled by default,
disable them in the new repository until you have reviewed the workflow and configured credentials;
the copied workflow includes a schedule.

Clone the public upstream repository and push its `main` branch to your empty copy, preserving
history for later updates. Replace the URL after `git remote add origin` with the HTTPS or SSH
clone URL of your new repository, including your GitHub Enterprise Cloud host if applicable:

```bash
git clone --branch main --single-branch https://github.com/maikvandergaag/github-governance.git github-governance
cd github-governance
git remote rename origin upstream
git remote add origin https://github.com/YOUR-ORG/YOUR-PRIVATE-REPO.git
git push -u origin main
```

## Prepare the governance workflow

The reusable workflow template is `templates/governance-assessment.yml`. It is outside
`.github/workflows/`, so GitHub Actions does not run it from that location. In your copy, replace
the active workflow with the template:

```bash
cp templates/governance-assessment.yml .github/workflows/governance-assessment.yml
```

Before enabling Actions, edit the copied workflow's `workflow_dispatch.inputs.mode.default` to match
your account (`enterprise`, `organization`, or `user`). Set the defaults for the other manual-run
inputs (`documentation`, `compliance`, `sync_issues`, `target_repository_issues`, and `publish_sarif`)
to the actions you want selected when starting a run manually.

Scheduled runs do not use those manual input defaults. Set the `ACCOUNT_SCOPE` repository variable
to the same account mode, and set `ENTERPRISE_SLUG` for enterprise mode or `ACCOUNT_LOGIN` for
organization or user mode, as described in [Actions variables and secrets](../configuration/03-setup.md#actions-variables-and-secrets).
Keep Actions disabled until the workflow and credentials are configured and reviewed, then enable
them when you are ready to run it.

The credential used to push must be permitted to add workflow files under `.github/workflows/`;
for example, a classic personal access token needs the `workflow` scope. Follow your organization's
credential policy.

Set `main` as the default branch of your copy if it is not already. If you need branch protection,
create or adjust its rules after the initial push. Enable Actions only when you are ready to
configure the workflow. Never push your generated inventory, credentials, or internal configuration
to the public upstream repository.

For ongoing updates, the optional [upstream sync guide](UPSTREAM_SYNC.md) provides a workflow that
proposes public upstream changes to your private copy for review.

## Allow generated documentation in Git

The publishing workflow stages `docs/output/`. The current upstream `.gitignore` does not ignore
this directory, so no change is needed for an unmodified copy. If your organization's ignore rules
exclude it, update `.gitignore` **in your private or internal copy** before the first run. For
example, add these exceptions after the rules that ignore the directory:

```gitignore
!/docs/
!/docs/output/
!/docs/output/**
```

Check which rules apply with:

```bash
git check-ignore -v --no-index docs/output/README.md docs/output/_data/example.json
```

No output means no ignore rule matched; a matching exception starts with `!`. If a positive ignore
rule still applies, adjust it or its parent-directory rules so generated files can be staged.
Review and commit any `.gitignore` change to your copy before running the workflow. These
exceptions allow generated files and snapshots to be committed, so ensure the repository is
private or internal and access is restricted.

## Choose your account scope

| Scope | What is evaluated | Start here |
| --- | --- | --- |
| Enterprise | Enterprise, organization, and repository checks | [Enterprise prerequisites](../configuration/02-prerequisites-and-access.md#github-app), then set `ENTERPRISE_SLUG` in [setup](../configuration/03-setup.md#actions-variables-and-secrets). |
| Organization | Organization and repository checks | Follow [standalone organization setup](../configuration/03-setup.md#standalone-organizations-and-personal-accounts) and choose `organization`. |
| Personal account | Repository checks for repositories owned by the account | Follow [personal account setup](../configuration/03-setup.md#standalone-organizations-and-personal-accounts) and choose `user`. |

All paths need PowerShell 7.2+ for local use and a read-only GitHub App with the permissions
appropriate to the scope. The workflow uses a separate token to publish results; generated
documentation should be stored in a private or internal repository. See
[prerequisites and access](../configuration/02-prerequisites-and-access.md) before configuring
credentials. For an introduction without credentials, see the [illustrative example](../example.md).

## Recommended reading

1. [Prerequisites and access](../configuration/02-prerequisites-and-access.md): create and install the
   GitHub App and grant its permissions. Target-repository issue routing additionally requires
   repository Issues read and write permission.
2. [Setup](../configuration/03-setup.md): configure Actions variables, the private-key secret,
   repository settings and run the workflow.
3. [Compliance policy](../configuration/04-policy.md): understand default check policies and
   overrides.
4. [Exemptions](../configuration/05-exemptions.md): add a reviewed exception for a target.
5. [Operations and troubleshooting](../configuration/07-operations-and-troubleshooting.md): inspect
   generated docs, findings, issues and workflow failures.

For your first run, review the policy and choose the correct account scope. The default publishing
mode opens a documentation pull request: review and merge it before expecting generated pages on
`main`. Compliance runs also synchronize issues; SARIF needs code scanning to be available.
Scheduled runs enable documentation, compliance, and SARIF, so review those requirements before
enabling the schedule. See [first run](../configuration/03-setup.md#first-run).

To extend the compliance catalog, see [Adding a compliance check](../configuration/06-adding-checks.md).
