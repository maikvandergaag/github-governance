# Repository creation is restricted at enterprise level

[Configuration handbook](../../docs/configuration/README.md) · [Adding checks](../../docs/configuration/06-adding-checks.md)

- **Check:** `enterprise.repo-creation-policy`
- **Scope:** enterprise
- **Default severity:** high
- **Requirement:** Repository creation is restricted at enterprise level.
- **Risk:** Unrestricted repository creation can expose code or data in public repositories.

## Remediation

Enterprise settings > Policies > Repositories > Repository creation: enforce a policy without public repositories.

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
  "severity": "high"
}
```

## Data source

GraphQL enterprise `ownerInfo`: `membersCanCreateRepositoriesSetting and membersCanCreatePublicRepositoriesSetting`.

## Running the test

Use PowerShell 7.2+, Pester 5.7.1+, and the GitHubGovernance module from this repository.
The App must be installed on the enterprise with permissions to read this setting. Connect the App before invoking Pester. For a data-residency endpoint, add
`-ApiBaseUrl https://api.<subdomain>.ghe.com` to `Connect-GHGovernance`.

```powershell
Import-Module ./src/GitHubGovernance/GitHubGovernance.psd1
Connect-GHGovernance -Enterprise $env:ENTERPRISE_SLUG -AppClientId $env:GH_APP_CLIENT_ID -AppPrivateKey $env:GH_APP_PRIVATE_KEY
Invoke-Pester -Path ./tests/enterprise.repo-creation-policy/enterprise.repo-creation-policy.Tests.ps1
Disconnect-GHGovernance
```
