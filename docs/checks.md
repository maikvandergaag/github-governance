# Governance check catalog

[Home](../README.md) · [Policy configuration](configuration/04-policy.md) ·
[Adding a check](configuration/06-adding-checks.md)

These are the built-in compliance checks currently discovered under `tests/`. Follow a check's link
for its detailed guidance. Enterprise mode runs enterprise, organization, and repository checks;
standalone organization mode runs organization and repository checks; personal account mode runs
repository checks for repositories owned by that account.

The tables show each check's **local default** severity and parameters. All are enabled by default
except `enterprise.ip-allow-list`. The central [`compliance/policy.json`](../compliance/policy.json)
can override these defaults, and exemptions can skip specific targets. See
[policy configuration](configuration/04-policy.md) and
[exemptions](configuration/05-exemptions.md). A check with unavailable or incomplete data is
reported as not evaluated, not as passing.

The [CIS GitHub Benchmark](https://www.cisecurity.org/benchmark/software-supply-chain-security)
is a reference for reviewing security settings. These checks are not currently mapped to a specific
benchmark version, and passing them does not establish CIS conformance or certification.

## Enterprise checks

| Check | Requirement | Default severity | Default parameters |
| --- | --- | --- | --- |
| [`enterprise.2fa-required`](../tests/enterprise.2fa-required/README.md) | Require enterprise-wide two-factor authentication. | High | — |
| [`enterprise.actions-restricted`](../tests/enterprise.actions-restricted/README.md) | Restrict GitHub Actions to selected or local actions. | Medium | `allowed`: `selected`, `local_only` |
| [`enterprise.default-permission-policy`](../tests/enterprise.default-permission-policy/README.md) | Enforce a restricted base repository permission. | Medium | `allowed`: `NONE`, `READ` |
| [`enterprise.ip-allow-list`](../tests/enterprise.ip-allow-list/README.md) | Enable the enterprise IP allow list. **Disabled by default.** | Medium | — |
| [`enterprise.max-owners`](../tests/enterprise.max-owners/README.md) | Limit the number of enterprise owners. | Medium | `max`: 3 |
| [`enterprise.repo-creation-policy`](../tests/enterprise.repo-creation-policy/README.md) | Enforce a repository creation policy without public repositories. | High | — |
| [`enterprise.repo-deletion-restricted`](../tests/enterprise.repo-deletion-restricted/README.md) | Restrict repository deletion and transfer by repository administrators. | Medium | — |
| [`enterprise.sso-configured`](../tests/enterprise.sso-configured/README.md) | Configure SAML or OIDC single sign-on. | High | — |
| [`enterprise.users-without-2fa`](../tests/enterprise.users-without-2fa/README.md) | Have no affiliated users without two-factor authentication. | High | — |
| [`enterprise.visibility-change-restricted`](../tests/enterprise.visibility-change-restricted/README.md) | Restrict repository visibility changes by repository administrators. | Medium | — |

## Organization checks

| Check | Requirement | Default severity | Default parameters |
| --- | --- | --- | --- |
| [`org.2fa-required`](../tests/org.2fa-required/README.md) | Require two-factor authentication for members. | High | — |
| [`org.actions-restricted`](../tests/org.actions-restricted/README.md) | Restrict GitHub Actions to selected or local actions. | Medium | `allowed`: `selected`, `local_only` |
| [`org.default-branch-ruleset`](../tests/org.default-branch-ruleset/README.md) | Require pull requests via an active default-branch ruleset. | High | — |
| [`org.default-permission`](../tests/org.default-permission/README.md) | Restrict the base repository permission. | Medium | `allowed`: `none`, `read` |
| [`org.max-owners`](../tests/org.max-owners/README.md) | Limit the number of organization owners. | Medium | `max`: 5 |
| [`org.no-public-repo-creation`](../tests/org.no-public-repo-creation/README.md) | Prevent members from creating public repositories. | High | — |
| [`org.push-protection-new-repos`](../tests/org.push-protection-new-repos/README.md) | Enable push protection by default for new repositories. | Medium | — |
| [`org.webhooks-tls`](../tests/org.webhooks-tls/README.md) | Require webhook TLS certificate verification. | High | — |

## Repository checks

| Check | Requirement | Default severity | Default parameters |
| --- | --- | --- | --- |
| [`repo.codeowners-present`](../tests/repo.codeowners-present/README.md) | Have a CODEOWNERS file on the default branch. | Medium | — |
| [`repo.codeowners-valid`](../tests/repo.codeowners-valid/README.md) | Have a CODEOWNERS file without validation errors. | Medium | — |
| [`repo.not-public`](../tests/repo.not-public/README.md) | Keep the repository non-public. | High | — |
| [`repo.push-protection`](../tests/repo.push-protection/README.md) | Enable secret scanning push protection. | High | — |
| [`repo.secret-scanning`](../tests/repo.secret-scanning/README.md) | Enable secret scanning. | High | — |
| [`repo.stale`](../tests/repo.stale/README.md) | Have a push within the configured number of days. | Low | `days`: 365 |

## Running checks

The workflow evaluates the discovered checks using the central policy. For local or individual
checks, see [testing and execution](repo/README.md#tests). Developer-facing offline validations and
the fake-API smoke test are also documented there; they test the toolkit rather than assess an
account's governance.
