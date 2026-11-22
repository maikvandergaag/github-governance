# 6. Adding a compliance check

[Previous: Exemptions](05-exemptions.md) · [Handbook](README.md) · [Next: Operations and troubleshooting](07-operations-and-troubleshooting.md)

A check is automatically discovered when its folder contains a valid `check.json`. No central
registry entry or `compliance/policy.json` entry is required. The local `policy.json` controls its
default enabled state, severity and parameters.

## Required files

Create one folder per check under `tests/`:

```text
tests/
└── org.example-check/
    ├── check.json
    ├── org.example-check.Tests.ps1
    ├── policy.json
    └── issue.md
```

The folder name, manifest `id` and Pester filename must match exactly. The manifest `scope` must be
`enterprise`, `org` or `repo`, and its ID must start with that scope plus a dot.

## Manifest

The manifest provides the information needed to register, report and evaluate the check:

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

See [Check manifest reference](reference/check-manifest.md) for supported data sources and exact
fields. When a check relates to the CIS GitHub Benchmark, record its version and recommendation
numbers in the optional `cis` metadata. Mark partial coverage explicitly and describe any manual
review needed in the issue template.

## Local policy

Provide a `policy.json` with boolean `enabled` and `severity` set to `high`, `medium` or `low`.
Optional `params` are passed to the check's evaluator:

```json
{
  "enabled": true,
  "severity": "medium",
  "params": {}
}
```

The central policy can override these defaults later. It does not need to be updated merely to
register the new check.

## Policy and Pester test

The test script must accept `-PolicyOnly` and return a script block that evaluates the data collected
for the manifest's scope. Use the existing checks as examples of the input shape and status handling:

- Enterprise and organization evaluators receive a snapshot and parameters.
- Repository evaluators receive repository data, the organization snapshot, CODEOWNERS data and parameters.
- Return `Pass`, `Fail '<finding>'` or `NotEvaluated '<reason>'`; missing data must not be treated as a pass.

The Pester `Describe` must contain exactly one compliance `It` assertion. The workflow evaluates the
policy once and gives its result to that assertion. Individual live test runs call
`Invoke-GHComplianceCheck` and require an active GitHub App connection.

Every check must run independently: do not rely on another check executing first or populating a
cache. Shared helpers are allowed; caching is an optional optimization within a combined run.
For example, after connecting the App and setting `GHE_ORGANIZATION` and `GHE_REPOSITORY`, each
root-file check can be run on its own:

```powershell
Invoke-Pester -Path ./tests/repo.gitignore-present/repo.gitignore-present.Tests.ps1
Invoke-Pester -Path ./tests/repo.gitattributes-present/repo.gitattributes-present.Tests.ps1
Invoke-Pester -Path ./tests/repo.readme-present/repo.readme-present.Tests.ps1
```

Use an existing check folder as a starting point, keeping the `-PolicyOnly` path and `It` assertion
consistent with the existing conventions.

## Issue template

`issue.md` is required because issue sync validates templates before making GitHub changes. It may
use `{{target}}`, `{{target_url}}`, `{{docs_url}}`, `{{check}}`, `{{severity}}` and `{{finding}}`.
Follow the nearby check templates and explain the requirement, observed result and remediation.

## Validate

Run the offline policy suite, then the end-to-end fake-API smoke test:

```powershell
Invoke-Pester -Path ./tests/validation
pwsh ./tests/Invoke-SmokeTest.ps1
```

When developing a live check, run only its Pester file after connecting the App and setting any
required `GHE_ORGANIZATION` and `GHE_REPOSITORY` environment values.
