# GitHub App permissions

[Configuration handbook](../README.md) · [Prerequisites and access](../02-prerequisites-and-access.md)

The reader App should have only the read permissions needed for collection and compliance checks.
GitHub's permission labels can change; compare these functional scopes with the App settings shown
for your repository's host.

| Scope | Read permissions | Used for |
| --- | --- | --- |
| Enterprise | Enterprise settings, organization/repository policies, two-factor authentication, people, IP allow list, self-hosted runners and organization installations | Enterprise policies, 2FA, SSO, owners, runners and organization inventory |
| Organization | Administration, members, self-hosted runners, webhooks, secrets, variables, custom properties, custom repository roles and GitHub Copilot Business | Settings, teams, rulesets, security configurations, webhooks, names, Apps and Copilot |
| Repository | Metadata, administration and contents | Repository inventory, security settings and CODEOWNERS |

The workflow also uses its built-in `GITHUB_TOKEN` for writes:

| Permission | Job | Purpose |
| --- | --- | --- |
| `contents: write` | `commit_docs` | Commit generated documentation |
| `security-events: write` | `publish_sarif` | Upload SARIF |
| `issues: write` | `sync-issues` | Create, update and close compliance issues |
| `actions: read` | `publish_sarif` | Read workflow-run metadata for SARIF |

The App itself does not need these write permissions. Grant only the read access required by the
reader App, and keep the private key in the protected `enterprise-compliance` environment.
