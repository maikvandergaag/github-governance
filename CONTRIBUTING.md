# Contributing

Thanks for helping improve GitHub Governance. Issues and pull requests are welcome for bug fixes,
documentation, and compliance checks.

## Before opening a pull request

- For a bug or feature idea, use the matching GitHub issue form first when possible. Keep reports
  free of private keys, tokens, customer data, and unredacted organization snapshots.
- For a substantial change, describe the intended behavior in an issue before investing in a large
  implementation.
- Keep changes focused and update the relevant handbook or check documentation when behavior
  changes.
- Check [project support](SUPPORT.md) before relying on a particular GitHub platform or runtime.

## Run the offline checks

Use PowerShell 7.2 or later and Pester 5.7.1:

```powershell
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser
Invoke-Pester -Path ./tests/validation
pwsh ./tests/Invoke-SmokeTest.ps1
```

These checks use local fixtures and do not need GitHub credentials. Changes to live API collection
should include or update fake-API coverage where practical; never use real credentials or account
data in committed tests.

## Adding a compliance check

Follow [Adding a compliance check](docs/configuration/06-adding-checks.md). Checks are discovered
from their `check.json` manifests and need a policy, evaluator test, and issue template.

## Pull request expectations

Before requesting review, self-review the diff and:

- Explain the user-visible change, link the related issue when there is one, and report the exact
  validation performed. The pull-request workflow runs the offline validations and smoke test.
- Update relevant documentation and tests. For changes to collection, checks, or issue sync, add or
  update fixture-backed coverage where practical.
- Call out changes to permissions, collected data, supported platforms, or compatibility.
- Keep each pull request focused and respond to review feedback. Resolve discussion threads after
  addressing them; explain when a suggestion is intentionally not followed.

Maintainers review behavior and regression risk, test evidence, security and data-handling impact,
compatibility, and documentation. A CODEOWNER review is requested for covered paths; branch
protection, not this document or CODEOWNERS alone, determines whether an approval is required to
merge.

## Issue triage and maintainer guidance

Maintainers label new issues, ask for missing details, and route actionable work to the relevant
area. Contributors can help by using the issue forms and providing a minimal reproduction with
non-sensitive data. See the [label guide](docs/governance/labels.md) for label meanings and
the [maintainer notes](docs/governance/maintainers.md) for triage and review practices.

Priority labels are relative to the project and do not imply a response or delivery date. There is
no guaranteed response time. Issues may be closed when they are duplicates, out of scope, lack
requested information, or will not be pursued; maintainers should explain the outcome when practical.

## Project direction and decisions

The [roadmap](ROADMAP.md) records current direction without promising dates. Significant architectural
or policy choices are recorded in [decision records](docs/decisions/README.md).
