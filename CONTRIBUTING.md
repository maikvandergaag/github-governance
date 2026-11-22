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

## Pull requests

Explain the user-visible change and how it was validated. Call out any permission, data collection,
or compatibility changes, and include documentation updates when appropriate. The pull-request
workflow runs the offline validations and smoke test.
