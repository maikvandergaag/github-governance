# 4. Compliance policy

[Previous: Setup](03-setup.md) · [Handbook](README.md) · [Next: Exemptions](05-exemptions.md)

Checks are discovered at runtime from `tests/<check-id>/check.json`. There is no separate code
registry to update. The check manifest supplies its scope, title, remediation and live data source;
the matching test file supplies the policy logic.

## Defaults and overrides

Each check's `policy.json` is its default configuration:

```json
{
  "enabled": true,
  "severity": "high",
  "params": {
    "max": 5
  }
}
```

`compliance/policy.json` can override `enabled`, `severity` or individual `params` for a check.
Checks do not need a central entry to be discovered and evaluated; when the central entry is absent,
the folder's defaults apply. The central policy also contains target-specific [exemptions](05-exemptions.md).

Severity must be `high`, `medium` or `low`. Parameters are check-specific and are passed to that
check's policy evaluator. See the [policy reference](reference/policy-schema.md) for merge behavior
and examples.

## Evaluation results

Each check returns one of these outcomes:

| Result | Meaning | Compliance issue |
| --- | --- | --- |
| `pass` | The observed setting satisfies the requirement. | No open issue is needed; a prior issue is closed. |
| `fail` | The setting does not satisfy the requirement. | A finding is reported and an issue may be created. |
| `na` | The setting could not be evaluated because data or access is missing. | No issue is created or closed based on incomplete data. |

Disabled checks and exempted target/check pairs are skipped. Exemption behavior and examples are in
the [Exemptions](05-exemptions.md) chapter.

## Repository description

The enabled-by-default, low-severity `repo.description-present` check is a repository policy,
not a CIS requirement. It requires a non-whitespace repository description, without assessing its
quality. It runs independently using repository metadata in live and snapshot modes, without
additional content requests. Explicitly null or blank descriptions fail; missing fields remain
unevaluated.

## CIS benchmark coverage

Related checks include CIS GitHub Benchmark v1.2.0 recommendation numbers in their manifests and
issue templates. These mappings are partial: a passing check does not replace the benchmark's manual
review or establish overall compliance. Controls involving systems or evidence not collected by
this project are not assessed.

The policy enables additional checks for enterprise issue deletion, organization repository
creation, and default Dependabot alerts and secret scanning for new repositories. The creation check
requires public and private member creation to be disabled; a separate check covers internal
repositories. The scanning checks use the default code security configurations for public and
private/internal repositories; they do not establish coverage for existing repositories or
third-party scanners. Unavailable settings are reported as `na`.

Additional checks assess default-branch rules and classic protection, app and secret access,
Actions token permissions, team creation and other organization settings. They are enabled by
default and may produce many new findings. Override their local defaults in
`compliance/policy.json` and use the issue sync's `MaxNewIssues` limit if needed.

Partial-control issue templates identify the CIS recommendation, the observed automated finding,
remediation and remaining manual review. Issues are created only for automated failures: a passing
check does not create an issue for manual review and does not prove the entire control is satisfied.
Branch checks do not assess bypass actors, reviewer trust or branches other than the default branch.
Snapshot collection adds per-repository API requests for branch evidence; live checks reuse that
evidence within each repository evaluation.

## Local versus workflow policy

An individual Pester test uses its folder's `policy.json`. The workflow uses
`compliance/policy.json` as overrides on top of those defaults. This lets a check be tested and
configured locally while keeping enterprise-wide tuning and exceptions together.

To add a new check, see [Adding a compliance check](06-adding-checks.md).
