# Check manifest reference

[Configuration handbook](../README.md) · [Adding a compliance check](../06-adding-checks.md)

Every discovered check folder contains `check.json`. The manifest identifies the check and tells the
runner how to collect its live data.

## Fields

| Field | Required | Description |
| --- | --- | --- |
| `id` | Yes | Valid check ID; must match the folder and `<id>.Tests.ps1` filename. |
| `scope` | Yes | `enterprise`, `org` or `repo`; the ID must begin with `<scope>.`. |
| `title` | Yes | Requirement title used in reports, issues and SARIF. |
| `remediation` | Yes | Actionable remediation text used in issues and SARIF. |
| `dataSource` | Yes | Supported live data source and its options. |

## Supported data sources

### Enterprise GraphQL owner information

```json
"dataSource": {
  "type": "enterprise-owner-info",
  "fields": "twoFactorRequiredSetting"
}
```

`fields` is the owner-info GraphQL selection required by the evaluator.

### Enterprise Actions permissions

```json
"dataSource": {
  "type": "enterprise-actions-permissions"
}
```

### Organization REST section

```json
"dataSource": {
  "type": "organization-section",
  "section": "settings"
}
```

`section` must be one of `settings`, `actionsPermissions`, `webhooks`, `admins` or `rulesets`.
Rulesets include their individual details in the evaluation snapshot.

### Repository

```json
"dataSource": {
  "type": "repository"
}
```

For CODEOWNERS checks, set `codeOwners` to `present` or `valid`. `present` collects the locations;
`valid` also requests GitHub's CODEOWNERS validation errors.

An unsupported type fails manifest validation rather than silently skipping the check. To use a new
GitHub API shape, add and test a data-source handler before using that type in a manifest.
