# Illustrative example

[Home](../README.md) · [Choose an account scope](repo/SETUP.md#choose-your-account-scope) ·
[Configuration handbook](configuration/README.md)

This fictional example illustrates the kinds of information GitHub Governance can collect and
evaluate. It is **not** a generated report, a live demo, or evidence of compliance; actual output,
checks, and findings depend on the account, policy, permissions, and GitHub features available.

Suppose a team runs an organization inventory for `example-org`. The generated documentation can
describe organization settings and repositories, while the compliance report identifies checks that
need attention:

| Target | Check | Example outcome |
| --- | --- | --- |
| `example-org/service-a` | `repo.secret-scanning` | Fail: secret scanning is disabled. |
| `example-org/service-b` | `repo.codeowners-present` | Fail: no CODEOWNERS file was found on the default branch. |
| `example-org/service-c` | `repo.secret-scanning` | Not evaluated: the necessary security data was not returned. |

Unavailable data is not considered a pass. A failed check can also create an issue or a SARIF
alert when the corresponding workflow outputs are enabled and available. Existing issues are not
closed solely because a check could not be evaluated. See
[policy outcomes](configuration/04-policy.md#evaluation-results) and
[outputs and lifecycle](configuration/07-operations-and-troubleshooting.md#outputs-and-lifecycle).

After a documentation PR is merged (or documentation is published directly), the repository contains
an inventory under `docs/enterprise/` and, when compliance is selected, a report at
`docs/enterprise/compliance/README.md`. These files may contain sensitive metadata and should be
kept in a private or internal repository.

To run the implementation against a fake GitHub API without credentials, use the
[offline smoke test](../CONTRIBUTING.md#run-the-offline-checks). For a real inventory, follow the
[setup guide](repo/SETUP.md).
