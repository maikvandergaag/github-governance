# CODEOWNERS file has no errors

[Configuration handbook](../../docs/configuration/README.md) · [Adding checks](../../docs/configuration/06-adding-checks.md)

- **Check:** `repo.codeowners-valid`
- **Scope:** repo
- **Default severity:** medium
- **Requirement:** CODEOWNERS file has no errors.
- **Risk:** Invalid CODEOWNERS entries may prevent intended owners from being requested for review.

## Remediation

Fix the reported lines; typically renamed/removed teams or teams without write access.

Verify the setting and run the test again.

## Issue details

The compliance workflow runs this test for each target and uses [issue.md](issue.md)
to create one issue per failed check and target. Running the test independently does not create an issue. A missing or
unreadable setting is not evaluated and must not be reported as compliant.

## Policy

The local `policy.json` controls this individual check and is separate from the workflow policy. Its initial configuration is:

```json
{
  "enabled": true,
  "severity": "medium"
}
```

## Data source

REST `GET /repos/{org}/{repo}`, GraphQL repository CODEOWNERS files and REST `GET /repos/{org}/{repo}/codeowners/errors`.

## Running the test

Use PowerShell 7.2+, Pester 5.7.1+, and the GitHubGovernance module from this repository.
The App must be installed on the enterprise and target organization with permissions to read this setting. Connect the App before invoking Pester. For a data-residency endpoint, add
`-ApiBaseUrl https://api.<subdomain>.ghe.com` to `Connect-GHGovernance`.

```powershell
Import-Module ./src/GitHubGovernance/GitHubGovernance.psd1
Connect-GHGovernance -Enterprise $env:ENTERPRISE_SLUG -AppClientId $env:GH_APP_CLIENT_ID -AppPrivateKey $env:GH_APP_PRIVATE_KEY
$env:GHE_ORGANIZATION = 'my-org'
$env:GHE_REPOSITORY = 'my-repo'
Invoke-Pester -Path ./tests/repo.codeowners-valid/repo.codeowners-valid.Tests.ps1
Disconnect-GHGovernance
```
