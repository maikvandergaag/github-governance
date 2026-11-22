# Repository guide

[Home](../../README.md) · [Configuration handbook](../configuration/README.md) · [Generated documentation](../enterprise/README.md) · [Setup guide](SETUP.md)

Automatically generates Markdown documentation of a GitHub Enterprise Cloud environment,
a standalone organization, or a personal account and commits it to this repository on a weekly schedule.
Git history becomes the change log of your configuration.

## What is documented

| Level        | Content |
| ---          | --- |
| Enterprise   | Policies (enforced vs. "no policy"), 2FA, SAML/OIDC, IP allow list, owners, licenses, enterprise rulesets (incl. rules), Actions policy, runners, code security configurations, custom properties, audit log streaming, plus a list of settings that are *not* collected |
| Organization | General/security defaults, members, owners, outside collaborators, teams, rulesets (incl. conditions, bypass actors and rules), code security configurations, custom properties, custom repository roles, webhooks, Actions permissions, runner groups, self-hosted runners, Actions secret/variable names, installed GitHub Apps (with permissions), Copilot settings and seats |
| Repository   | Visibility, archived, default branch, language, GHAS / secret scanning / push protection status, last push |
| Code owners  | Per active repo: CODEOWNERS location, parsed rules, validation errors (unknown owners etc.); per org: owner → repositories overview and repos without CODEOWNERS (`organizations/<org>/codeowners.md`) |

**Getting started:** follow the [configuration handbook](../configuration/README.md), starting with
[prerequisites and access](../configuration/02-prerequisites-and-access.md) and [setup](../configuration/03-setup.md).

Standalone organizations include organization and repository checks; personal accounts include only
repositories owned by the account. Enterprise checks run only in enterprise mode.

Output (full description in the handbook's
[generated documentation layout](../configuration/07-operations-and-troubleshooting.md#generated-documentation-layout)):

```
docs/enterprise/
├── README.md              index
├── enterprise/            enterprise configuration (policies & access, rulesets, actions, security)
├── organizations/<org>/   one folder per organization, one page per topic (+ codeowners.md)
├── compliance/README.md   findings report
└── _data/                 raw JSON snapshots (used to discover compliance targets)
```

Sections the credentials cannot read are rendered as `Not available`; the run does not fail.
Run the commands in this guide from the repository root.

## Compliance issues

After the docs are generated, `Test-GHCompliance -UsePester` discovers targets from the snapshots
and runs the Pester checks against live GitHub data using `compliance/policy.json` and a GitHub App
connection established with `Connect-GHGovernance`.
The workflow evaluates each check in the connected module session, then Pester asserts its result.
Without `-UsePester`, it evaluates the same check-specific policy logic against the saved snapshots;
results can differ when snapshot data is stale or incomplete. Both modes require the check folders
under `tests/` (or the path supplied with `-TestsPath`).
For CODEOWNERS checks and nonempty organization rulesets, snapshots created before
collection-completeness markers were added are reported as not evaluated; regenerate the snapshots
to evaluate those checks.
It writes a findings report to `docs/enterprise/compliance/README.md`
(committed when documentation is selected). `Sync-GHComplianceIssue` manages issues in **this** repository:

- One issue per failed check and affected enterprise, organization or repository, labelled `compliance`, `compliance:enterprise|org|repo` and the check's `severity:<level>`.
- Issue text comes from `tests/<check-id>/issue.md`. Templates support `{{target}}`, `{{target_url}}`, `{{docs_url}}`, `{{check}}`, `{{severity}}` and `{{finding}}`; the sync adds hidden markers for tracking.
- Updated only when content changes; closed automatically when that check no longer fails, or the target is archived or removed. Disabling or exempting a check also removes its failure.
- Checks that cannot be evaluated (missing data/scopes) never create issues or close their existing issue on incomplete data.
- Paginated API requests keep authentication on each page and only follow links to the same API origin.
- Previously grouped issues are left untouched and need manual review; new per-check issues may overlap them.
- Max 150 new issues per run (`-MaxNewIssues`), so the first run doesn't flood the repo.
- Mutating issue requests are paced; GitHub rate-limit responses are retried with bounded backoff. If the limit persists, the sync fails and can be rerun after it resets.
- Use the local dry run below to see what would happen without touching issues.

Checks are discovered from `tests/<check-id>/check.json`; the table below is the built-in catalog.
Each discovered check also needs `<check-id>.Tests.ps1`, `policy.json` and `issue.md` in its folder.
The local `policy.json` supplies the default enabled state, severity and parameters. Individual live
tests require a connected GitHub App, not a PAT.

| Check | Level | Requirement |
| --- | --- | --- |
| `enterprise.2fa-required` | enterprise | 2FA required, enforced at enterprise level |
| `enterprise.users-without-2fa` | enterprise | No affiliated users without 2FA |
| `enterprise.sso-configured` | enterprise | SAML or OIDC configured |
| `enterprise.default-permission-policy` | enterprise | Base permission enforced (default: none/read) |
| `enterprise.repo-creation-policy` | enterprise | Repo creation enforced, no public repos |
| `enterprise.repo-deletion-restricted` | enterprise | Repo admins can't delete/transfer repos |
| `enterprise.visibility-change-restricted` | enterprise | Repo admins can't change visibility |
| `enterprise.ip-allow-list` | enterprise | IP allow list enabled (disabled by default in policy) |
| `enterprise.max-owners` | enterprise | At most N enterprise owners (default 3) |
| `enterprise.actions-restricted` | enterprise | Allowed actions = selected/local only |
| `org.2fa-required` | org | 2FA required for members |
| `org.default-permission` | org | Base permission in allowed list (default: none/read) |
| `org.no-public-repo-creation` | org | Members can't create public repos |
| `org.push-protection-new-repos` | org | Push protection on by default for new repos |
| `org.actions-restricted` | org | Allowed actions = selected/local only |
| `org.webhooks-tls` | org | No webhooks with TLS verification disabled |
| `org.max-owners` | org | At most N owners (default 5) |
| `org.default-branch-ruleset` | org | Active ruleset on default branches requiring PRs |
| `repo.not-public` | repo | Repository is not public |
| `repo.secret-scanning` | repo | Secret scanning enabled |
| `repo.push-protection` | repo | Push protection enabled |
| `repo.codeowners-present` | repo | CODEOWNERS present |
| `repo.codeowners-valid` | repo | CODEOWNERS without errors |
| `repo.stale` | repo | Pushed within N days (default 365) |

### Code scanning alerts

The same findings are converted to SARIF (`ConvertTo-GHComplianceSarif`) and uploaded to code scanning
(category `github-enterprise-compliance`), so they appear under **Security > Code scanning** of this repository:

SARIF publishing is selected by default. Manual runs can disable it and receive a findings summary
instead. SARIF publishing requires compliance tests and code scanning availability.

- Each alert points to the generated docs, or to the committed policy file when documentation is not selected.
- Results include the observed finding, requirement and configured policy parameters. When running in Actions, they also link to the affected resource and generated documentation.
- Rule help explains the potential impact, remediation, verification and relevant GitHub documentation.
- Severity maps to `security-severity` high 8.0 / medium 5.0 / low 2.0, so alerts can be filtered and used in security overview.
- Alerts close automatically when a finding disappears from the next upload. GitHub tracks alerts using the line fingerprint added by the upload action; changes to the documented line can affect alert continuity.
- Requires code scanning on this repository: public, or private/internal with GitHub Code Security (GHAS).

`compliance/policy.json` overrides local check defaults; see the [policy chapter](../configuration/04-policy.md)
and [exemption instructions](../configuration/05-exemptions.md). Exemptions go through a PR, so they
are reviewed and traceable.

To add a check, create a folder under `tests/` with a manifest, a `policy.json`, an issue template and
a Pester file named after the check ID. The Pester file must return its policy evaluator for
`-PolicyOnly` and define one compliance assertion. For example, a check using a supported data
source needs no registry or central-policy edits:

```json
{
  "id": "org.example-check",
  "scope": "org",
  "title": "Example organization requirement",
  "remediation": "Apply the required organization setting.",
  "dataSource": {
    "type": "organization-section",
    "section": "settings"
  }
}
```

The manifest's `dataSource` must use a supported type: `enterprise-owner-info`,
`enterprise-actions-permissions`, `organization-section` (`settings`, `actionsPermissions`,
`webhooks`, `admins` or `rulesets`), or `repository` (optionally with `codeOwners` set to `present`
or `valid`). Extend the live data-source handler when a check needs a new kind of GitHub request.
The check's folder, ID and Pester filename must match.

Local dry run:

```powershell
Import-Module ./src/GitHubGovernance/GitHubGovernance.psd1
Connect-GHGovernance -Enterprise $env:ENTERPRISE_SLUG -AppClientId $env:GH_APP_CLIENT_ID -AppPrivateKey $env:GH_APP_PRIVATE_KEY
try {
    Test-GHCompliance -UsePester -DataPath ./docs/enterprise/_data | Sync-GHComplianceIssue -Repository contoso/github-docs -DryRun
}
finally { Disconnect-GHGovernance }
```

## PowerShell module

All logic is in the module `src/GitHubGovernance` (PowerShell 7.2+). The workflow calls its functions;
you can use the same functions interactively.

The module was renamed from `GitHubEnterpriseDocs`. Update existing import paths and module-name
references to `GitHubGovernance`. Command names have also changed: replace the `GHE` prefix with
`GH` (for example, `Get-GHERepository` becomes `Get-GHRepository`), and replace
`Connect-GHEnterprise`/`Disconnect-GHEnterprise` with `Connect-GHGovernance`/`Disconnect-GHGovernance`.
The old command names are not exported. Connections support enterprise, organization, and personal account scopes.

```
src/GitHubGovernance/
├── GitHubGovernance.psd1   manifest
├── GitHubGovernance.psm1   loader
├── Public/                     one file per exported function
└── Private/                    auth (App JWT + installation tokens), API, snapshots, Markdown, compliance checks
```

| Area | Functions |
| --- | --- |
| Connection | `Connect-GHGovernance`, `Disconnect-GHGovernance`, `Get-GHConnection` |
| Enterprise | `Get-GHOrganization`, `Get-GHEnterprisePolicy`, `Get-GHEnterpriseRuleset`, `Get-GHEnterpriseActionsSetting`, `Get-GHEnterpriseSecuritySetting` |
| Organization | `Get-GHOrganizationSetting`, `Get-GHOrganizationMember`, `Get-GHOrganizationTeam`, `Get-GHOrganizationRuleset`, `Get-GHOrganizationWebhook`, `Get-GHOrganizationActionsSetting`, `Get-GHOrganizationApp`, `Get-GHOrganizationCopilot`, `Get-GHOrganizationSecuritySetting` |
| Repository | `Get-GHRepository`, `Get-GHCodeOwners` |
| Snapshots | `Get-GHEnterpriseConfiguration`, `Get-GHOrganizationConfiguration` (sections with `Ok`/`Status`/`Data`) |
| Docs & compliance | `Export-GHDocumentation`, `Test-GHCompliance`, `ConvertTo-GHComplianceSarif`, `Sync-GHComplianceIssue` |
| Ad hoc | `Invoke-GHRestMethod`, `Invoke-GHGraphQL` (right credential per enterprise/organization) |

Organization functions accept pipeline input, so `Get-GHOrganization | Get-GHOrganizationTeam` works.
A section that can't be read gives a normal non-terminating error (`-ErrorAction` applies).

```powershell
Import-Module ./src/GitHubGovernance/GitHubGovernance.psd1
Connect-GHGovernance -Enterprise contoso -AppClientId 'Iv23li...' -AppPrivateKey (Get-Content ./app.pem -Raw)
# or: Connect-GHGovernance -Enterprise contoso -Token $pat

Get-GHOrganization | Get-GHOrganizationMember -Role Admin
Export-GHDocumentation -OutputPath ./docs/enterprise -Organization my-org -SkipRepositories   # fast test run
```

### Tests

The **Validate pull request** workflow validates the PowerShell module manifest and import, checks
module syntax and error-level rules with PSScriptAnalyzer 1.25.0, and runs the offline validation
suite and fake-API smoke test on every pull request. It uses no GitHub App credentials and does not
change repository content.

`tests/Invoke-SmokeTest.ps1` runs the whole chain (App JWT and tokens, getters, export, Pester compliance,
report, SARIF, issue sync in dry run) against a fake GitHub API: no credentials or network needed.
It requires PowerShell 7.2+ and Pester 5.7.1+.

```powershell
pwsh ./tests/Invoke-SmokeTest.ps1
```

Each folder under [`tests/`](../../tests/) named after a policy check contains a Pester test,
its local policy, issue template and failure guidance. Import the GitHubGovernance module and
connect the GitHub App before running an individual live test; see each folder's README for its inputs.
Run the mocked offline validations with:

```powershell
Invoke-Pester -Path ./tests/validation
```

Running an individual test does not create issues and uses its local `policy.json`.
The workflow uses the central `compliance/policy.json` instead, including its parameters and exemptions.
Unexpected test errors stop the run before findings or issues are published.

## Notes

- Secret values are never returned by the API; variable values and webhook secrets are stripped before anything is written.
- The docs repository should be **private/internal**: it contains owners, outside collaborators and app permissions.
- Copilot "active this cycle" figures change every week, so expect a weekly commit from that alone.
- Not covered: enterprise-level policies that have no read API, the credential inventory
  (see the "Credentials" export under enterprise settings) and the audit log.
