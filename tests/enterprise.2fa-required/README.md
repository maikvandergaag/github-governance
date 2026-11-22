# Enterprise-wide two-factor authentication

[Configuration handbook](../../docs/configuration/README.md) · [Adding checks](../../docs/configuration/06-adding-checks.md)

- **Check:** `enterprise.2fa-required`
- **Default severity:** high
- **Requirement:** the enterprise 2FA policy must be `ENABLED`.
- **Risk:** accounts without a second factor are more vulnerable to credential theft.

## Remediation

In enterprise settings, open **Authentication security** and require two-factor authentication.
For Enterprise Managed Users using identity-provider MFA, review whether a policy exemption is appropriate.
Verify the setting and run the test again.

## Issue details

The compliance workflow runs this test for each target and uses [issue.md](issue.md)
to create one issue per failed check and target. Running the test independently does not create an issue. A missing or
unreadable setting is not evaluated, not a failure.

## Policy and data source

The local `policy.json` controls whether this individual check runs. It is separate from the
workflow's `compliance/policy.json`. The test queries the enterprise's `ownerInfo.twoFactorRequiredSetting`
using GraphQL.

## Running the test

Use PowerShell 7.2+, Pester 5.7.1+, and the GitHubGovernance module from this repository.
The App must be installed on the enterprise with permissions to read this setting. Connect the App before invoking Pester. For a data-residency endpoint, add
`-ApiBaseUrl https://api.<subdomain>.ghe.com` to `Connect-GHGovernance`.

```powershell
Import-Module ./src/GitHubGovernance/GitHubGovernance.psd1
Connect-GHGovernance -Enterprise $env:ENTERPRISE_SLUG -AppClientId $env:GH_APP_CLIENT_ID -AppPrivateKey $env:GH_APP_PRIVATE_KEY
Invoke-Pester -Path ./tests/enterprise.2fa-required/enterprise.2fa-required.Tests.ps1
Disconnect-GHGovernance
```
