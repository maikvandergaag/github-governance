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

The workflow also uses its built-in `GITHUB_TOKEN` for writes:

| Permission | Job | Purpose |
| --- | --- | --- |
| `contents: write` | `commit_docs` | Commit generated documentation |
| `security-events: write` | `publish_sarif` | Upload SARIF |
| `issues: write` | `sync-issues` | Create, update and close issues in the documentation repository |
| `actions: read` | `publish_sarif` | Read workflow-run metadata for SARIF |

The App does not need write permissions when all issues stay in the documentation repository.
Keep the private key in the protected `enterprise-compliance` environment.
GitHub may require an organization owner or security manager to read default code security
configurations. If a setting or endpoint is inaccessible, the affected check is not evaluated.
