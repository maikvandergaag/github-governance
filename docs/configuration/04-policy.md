# 4. Compliance policy

[Previous: Setup](03-setup.md) · [Handbook](README.md) · [Next: Exemptions](05-exemptions.md)

Checks are discovered at runtime from `tests/<check-id>/check.json`. There is no separate code
registry to update. The check manifest supplies its scope, title, remediation and live data source;
the matching test file supplies the policy logic.

## CIS benchmark reference

The Center for Internet Security's
[CIS GitHub Benchmark](https://www.cisecurity.org/benchmark/software-supply-chain-security) is a
reference when reviewing GitHub security settings and designing policies. Compare the benchmark
version and recommendations applicable to your environment with the
[built-in check catalog](../checks.md) and your configured policy.

The project does not currently provide a version-specific mapping between its checks and CIS
recommendations. A passing result does not establish CIS benchmark conformance or certification;
some recommendations may require additional checks or manual review.

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

## Local versus workflow policy

An individual Pester test uses its folder's `policy.json`. The workflow uses
`compliance/policy.json` as overrides on top of those defaults. This lets a check be tested and
configured locally while keeping enterprise-wide tuning and exceptions together.

To add a new check, see [Adding a compliance check](06-adding-checks.md).
