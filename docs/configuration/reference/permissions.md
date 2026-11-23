# GitHub App permissions

[Configuration handbook](../README.md) · [Prerequisites and access](../02-prerequisites-and-access.md)

The App needs the read permissions required for collection and compliance checks.
GitHub's permission labels can change; compare these functional scopes with the App settings shown
for your repository's host.

| Scope | Read permissions | Used for |
| --- | --- | --- |
| Enterprise | Enterprise settings, organization/repository policies, two-factor authentication, people, IP allow list, self-hosted runners and organization installations | Enterprise policies, 2FA, SSO, owners, runners and organization inventory |
| Organization | Administration, members, Actions, self-hosted runners, webhooks, secrets, variables, custom properties, custom repository roles and GitHub Copilot Business | Settings, teams, rulesets, security configuration defaults, workflow permissions, webhooks, names, Apps and Copilot |
| Repository | Metadata, administration and contents | Repository inventory, security settings and CODEOWNERS |

When target-repository issue routing is enabled, grant the App repository **Issues: read and write**
on each target repository. Repository issues must also be enabled.

For documentation pull requests, grant the App repository **Contents: read and write** and
**Pull requests: read and write**, and install it on the documentation repository. These App
permissions apply to its installations; review their repository access. The workflow restricts
the publishing token to the documentation repository and those two permissions.

The workflow uses its built-in `GITHUB_TOKEN` for other writes. Direct documentation publishing
can instead use an optional `DOCS_PUBLISH_TOKEN`:

| Permission | Job | Purpose |
| --- | --- | --- |
| `contents: write` | `commit_docs` | Commit generated documentation in direct mode |
| `pull-requests: write` | `commit_docs` | Available to the publishing job's workflow token |
| `security-events: write` | `publish_sarif` | Upload SARIF |
| `issues: write` | `sync-issues` | Create, update and close issues in the documentation repository |
| `actions: read` | `publish_sarif` | Read workflow-run metadata for SARIF |

Keep the private key in the protected `enterprise-compliance` environment.
GitHub may require an organization owner or security manager to read default code security
configurations. If a setting or endpoint is inaccessible, the affected check is not evaluated.
