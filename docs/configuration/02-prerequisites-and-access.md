# 2. Prerequisites and access

[Previous: Overview](01-overview.md) · [Handbook](README.md) · [Next: Setup](03-setup.md)

## Tools

- PowerShell 7.2 or later
- Pester 5.7.1 or later for live compliance evaluation and the smoke test
- A GitHub App installed on the target enterprise, organization or personal account

The workflow installs Pester 5.7.1 itself. For local Pester validation, install the same version:

```powershell
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser
```

## GitHub App

Create a GitHub App owned by the enterprise, standalone organization or personal account for read-only
collection. Disable webhooks and callbacks.
Keep its private key in the Actions environment secret described in [Setup](03-setup.md).

For enterprise mode, install the App on the enterprise and every organization, with access to all
repositories. Install it on new organizations as they are created. For standalone organization or
personal account mode, install it on the target with **all repositories** selected; selected-repository
installations are rejected to prevent incomplete inventories. Missing installations or permissions
cause affected sections and checks to be marked unavailable or not evaluated; they do not count as
compliant.

See the [permissions reference](reference/permissions.md) for the required access by scope and
endpoint.

## Write permissions

The reader App does not need write access. The workflow's `GITHUB_TOKEN` separately publishes
documentation, compliance issues and SARIF results. Documentation publishing can optionally use a
separate credential instead. Repository and organization policy must allow the required permissions;
see [Setup](03-setup.md#repository-settings).

## Data residency

For GHE.com, configure `ENTERPRISE_API_URL` as `https://api.<subdomain>.ghe.com`. The same endpoint
must be supplied to local `Connect-GHGovernance` calls with `-ApiBaseUrl`. See the [setup chapter](03-setup.md).
