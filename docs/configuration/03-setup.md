# 3. Setup

[Previous: Prerequisites and access](02-prerequisites-and-access.md) · [Handbook](README.md) · [Next: Compliance policy](04-policy.md)

This chapter sets up the repository workflow. Read [Prerequisites and access](02-prerequisites-and-access.md)
first to create and install the reader App.

## Actions variables and secrets

Add these repository or environment variables under **Settings > Secrets and variables > Actions**:

| Name | Required | Value |
| --- | --- | --- |
| `ENTERPRISE_SLUG` | Enterprise mode | Enterprise slug from `github.com/enterprises/<slug>` |
| `ACCOUNT_LOGIN` | Organization or user mode | Organization or personal account login |
| `ACCOUNT_SCOPE` | No | Scheduled-run mode: `enterprise` (default), `organization`, or `user`; manual runs use the dropdown |
| `SYNC_ISSUES` | No | Set to `false` to disable issue synchronization on scheduled runs; defaults to enabled |
| `TARGET_REPOSITORY_ISSUES` | No | Set to `true` to manage repository issues in their target repositories on scheduled runs; defaults to disabled |
| `GH_APP_CLIENT_ID` | Yes | GitHub App client ID (starts with `Iv`) |
| `ENTERPRISE_API_URL` | GHE.com only | `https://api.<subdomain>.ghe.com`; empty defaults to `https://api.github.com` |

Create the `enterprise-compliance` environment and add `GH_APP_PRIVATE_KEY` as an environment
secret containing the complete PEM private key. Do not commit the key or store it in a plain
repository variable.

Configure the environment to allow deployment from `main`. Runs from other branches will not receive
the private key. Add environment reviewers only if approval for every scheduled run is intended;
validation, inventory, Pester and issue-sync jobs use this environment and may each require approval.

`GITHUB_TOKEN` is provided by GitHub Actions; do not create it manually.

## Repository settings

| Setting | Why it matters |
| --- | --- |
| `main` branch protection or rulesets | The publishing job pushes a docs commit. Allow the GitHub Actions bot to bypass the rule, or change the publishing design. |
| Workflow token permissions | Allow the workflow's declared permissions for contents, issues, actions and security events. |
| Code scanning | Private/internal repositories need GitHub Code Security for SARIF upload; disable SARIF for manual runs if unavailable. |
| Repository visibility and access | Generated documentation includes owners, collaborators, App permissions and findings. Keep access restricted. |

## First run

1. Review [Compliance policy](04-policy.md) and [Exemptions](05-exemptions.md).
2. Start **Actions > Check - GitHub Enterprise > Run workflow** and select the account mode and desired
   actions. The default is enterprise mode with documentation, tests, issue synchronization and SARIF
   enabled. Select target-repository issues to route repository findings to their own repositories.
3. Review `docs/output/README.md` for missing App installations and unavailable sections.
4. Review `docs/output/compliance/README.md`, issues and **Security > Code scanning** for findings.
5. Adjust policy or exemptions and run the workflow again.

The issue sync creates at most 500 new issues per run by default. Subsequent runs continue with remaining
findings.

## Standalone organizations and personal accounts

Set `ACCOUNT_LOGIN` to the target organization or personal login and leave `ENTERPRISE_SLUG` unset.
For manual runs select `organization` or `user` as the account mode; for scheduled runs set
`ACCOUNT_SCOPE` accordingly. Install the account-owned App on the target with all repositories
selected and grant repository Metadata, Administration and Contents read permissions. Organizations
also need the applicable organization permissions in the [permissions reference](reference/permissions.md).

Standalone organizations run organization and repository checks; personal accounts run repository
checks only. Inventory includes repositories owned by the configured account, not repositories owned
by other accounts where it collaborates. Use one scope per documentation repository; scoped issue
synchronization leaves findings for other accounts untouched. Personal-account documentation and live
compliance require App authentication.

## Run locally

From the repository root, import the module and connect the reader App:

```powershell
Import-Module ./src/GitHubGovernance/GitHubGovernance.psd1
Connect-GHGovernance -Enterprise $env:ENTERPRISE_SLUG `
    -AppClientId $env:GH_APP_CLIENT_ID `
    -AppPrivateKey $env:GH_APP_PRIVATE_KEY

Export-GHDocumentation
Disconnect-GHGovernance
```

For GHE.com, add `-ApiBaseUrl $env:ENTERPRISE_API_URL`. For an end-to-end dry run of compliance,
issues and SARIF, see [Operations and troubleshooting](07-operations-and-troubleshooting.md#local-validation).
For local commands, load the Actions App client ID and private key into `GH_APP_CLIENT_ID` and
`GH_APP_PRIVATE_KEY`.
For standalone accounts replace `-Enterprise $env:ENTERPRISE_SLUG` with `-Organization my-org` or
`-User my-login`.

## Continue

- [Compliance policy](04-policy.md)
- [Generated documentation layout](07-operations-and-troubleshooting.md#generated-documentation-layout)
