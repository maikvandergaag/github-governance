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
| `cis` | No | Benchmark name, version, recommendation numbers and coverage. `partial` means the check assesses only a subset and does not establish compliance with the complete recommendation. |
| `parameters` | No | JSON Schema object that defines accepted evaluator parameters; use `properties`, `required` and `"additionalProperties": false` to reject undeclared parameter names. |

The machine-readable manifest schema is [`schemas/check-manifest.schema.json`](../../../schemas/check-manifest.schema.json).
When a check accepts parameters, declare their types and constraints in `parameters`; both the local
defaults and central overrides are validated against that schema before evaluation. Central
overrides may omit required parameter values supplied by the local defaults, but the merged
configuration must satisfy all requirements.

CIS references identify related controls, not a certification or a claim that the full manual
assessment is automated. Checks without a defensible mapping omit this field.

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

`section` must be one of `settings`, `actionsPermissions`, `actionsWorkflowPermissions`,
`webhooks`, `admins`, `rulesets`, `securityConfigDefaults`, `installations`, `actionsSecrets`
or `runnerGroups`.
Rulesets include their individual details in the evaluation snapshot.

### Repository

```json
"dataSource": {
  "type": "repository"
}
```

For CODEOWNERS checks, set `codeOwners` to `present` or `valid`. `present` collects the locations;
`valid` also requests GitHub's CODEOWNERS validation errors.

Set `gitAttributes` to `true` to collect whether a regular `.gitattributes` file exists at the
root of the default branch. The enabled-by-default `repo.gitattributes-present` check uses this
option in both live and snapshot evaluation. It checks presence only and has no CIS mapping.
Missing permissions, an unavailable default branch, an empty repository (HTTP 409), or
incomplete tree data remain unevaluated.

Set `gitIgnore` to `true` for the equivalent root `.gitignore` lookup used by the
enabled-by-default `repo.gitignore-present` policy check. It checks presence only, has no CIS
mapping, and shares the root tree lookup with `.gitattributes` during each repository evaluation.

Set `readme` to `true` for the root `README.md` lookup used by the enabled-by-default
`repo.readme-present` policy check. It requires the exact filename on the default branch:
READMEs in subdirectories or with different names do not satisfy this policy. It verifies
presence only, has no CIS mapping, and can run independently while sharing the root tree
lookup when other root-file checks run alongside it.

### Default-branch rules and classic protection

```json
"dataSource": { "type": "repository-branch-rules" }
```

This source collects active rules applying to the default branch, including inherited rules, and
classic branch protection. Inaccessible or ambiguous responses remain unevaluated. A branch check
only assesses the individual rule, not whether bypass actors or reviewers are trustworthy.

An unsupported type fails manifest validation rather than silently skipping the check. To use a new
GitHub API shape, add and test a data-source handler before using that type in a manifest.
