# Support

This project is maintained on a best-effort basis. There is no guaranteed response time or service
level agreement.

## Support matrix

| Area | Support status | Notes |
| --- | --- | --- |
| GitHub Enterprise Cloud | Supported | Enterprise, standalone organization, and personal-account collection modes are documented. |
| GHE.com data residency | Supported | Configure the `https://api.<subdomain>.ghe.com` API URL as described in the [setup guide](docs/configuration/03-setup.md). |
| GitHub Enterprise Server | Not currently supported | It is not part of the documented API or CI validation matrix. |
| PowerShell | 7.2 or later | The module targets PowerShell Core. |
| Pester | 5.7.1 or later | Required for local offline validation and compliance evaluation. |
| Operating system | CI validated on Ubuntu | Local use depends on PowerShell 7.2+; other operating systems are not separately covered by CI. |
| Security fixes | Latest default-branch version | No older release is designated as supported; see [SECURITY.md](SECURITY.md). |

Support for a GitHub account mode is not a guarantee that every setting is available through the
GitHub API or accessible to every App installation. Missing or inaccessible data is reported as
unavailable, not compliant. See the [permissions reference](docs/configuration/reference/permissions.md)
and [coverage notes](docs/repo/README.md#notes).

## Getting help

- For usage questions, use a GitHub issue and include the relevant command, version, and sanitized
  error details.
- For bugs or feature requests, use the repository's issue forms.
- Do not post tokens, private keys, customer information, or unredacted organization snapshots.
- Report suspected vulnerabilities privately using the process in [SECURITY.md](SECURITY.md).
