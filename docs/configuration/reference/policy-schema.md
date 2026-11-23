# Policy file reference

[Configuration handbook](../README.md) · [Compliance policy](../04-policy.md) · [Exemptions](../05-exemptions.md)

There are two policy layers:

1. `tests/<check-id>/policy.json` is the check's default.
2. `compliance/policy.json` overrides a discovered check when it has a matching entry.

The runner validates both files before executing checks. JSON schemas are in `schemas/`:
[`check-policy.schema.json`](../../../schemas/check-policy.schema.json) validates each local or
central check entry, [`check-override.schema.json`](../../../schemas/check-override.schema.json)
validates partial central overrides, and
[`compliance-policy.schema.json`](../../../schemas/compliance-policy.schema.json) validates the
central policy structure. Check-specific `params` are validated against the `parameters` JSON
Schema in that check's manifest.

The workflow merges `enabled` and `severity` field-by-field. For `params`, local properties are
combined with central properties; a central parameter with the same name wins. An omitted central
check inherits its entire local default.

## Per-check fields

| Field | Type | Meaning |
| --- | --- | --- |
| `enabled` | Boolean | Whether the check runs by default or under the central override. |
| `severity` | String | `high`, `medium` or `low`; used in reports, issue labels and SARIF. |
| `params` | Object | Optional, check-specific values passed to the policy evaluator. |

Example local defaults:

```json
{
  "enabled": true,
  "severity": "low",
  "params": {
    "days": 365
  }
}
```

Example central override:

```json
{
  "checks": {
    "repo.stale": {
      "enabled": true,
      "severity": "medium",
      "params": {
        "days": 180
      }
    }
  },
  "exemptions": {}
}
```

Check-specific parameter names and defaults are described by each check's policy and its
documentation under `tests/<check-id>/README.md`.
Severity must be exactly `high`, `medium` or `low`; malformed shapes, unknown checks, invalid
exemptions, and undeclared or incorrectly typed parameters fail validation before execution.
