# 7. Operations and troubleshooting

[Previous: Adding a compliance check](06-adding-checks.md) · [Handbook](README.md)

## Workflow

The `Check - GitHub Enterprise` workflow runs weekly and supports manual dispatch:

1. `validate` checks selections, configuration and authentication.
2. `inventory` collects snapshots and generates documentation.
3. `pester` evaluates compliance when selected; `sync-issues` synchronizes findings and `summarize`
   reports them when SARIF is disabled.
4. `commit_docs` proposes documentation in a PR by default, or pushes directly when configured;
   `publish_sarif` uploads SARIF when selected.

Manual runs can select documentation, compliance tests and SARIF independently, except that SARIF
requires tests. Scheduled runs enable all three. With documentation disabled, compliance collects a
temporary inventory and issue links may point to older or absent pages; SARIF points to the committed
policy instead. With PR publishing, documentation remains unmerged until the PR is approved and
merged: issues can likewise link to older or absent pages, and SARIF points to the policy in the
triggering commit rather than to unmerged documentation. After a later run, SARIF is refreshed; PR
merging alone does not trigger a new inventory or SARIF upload. With neither documentation nor tests
selected, no collection runs. The
`documentation-patch` artifact transfers inventory to Pester, and `compliance-findings` contains
findings and the documentation patch when compliance runs.

Review the [workflow definition](../../.github/workflows/document-enterprise.yml) for exact triggers
and token permissions.

## Generated documentation layout

```text
docs/enterprise/
├── README.md                     enterprise and organization index
├── enterprise/                   enterprise configuration pages
├── organizations/<org>/           one folder per organization and its pages
├── compliance/README.md            findings report
└── _data/                          raw snapshots used for target discovery
```

Generated pages and snapshots are overwritten when documentation is selected. Do not edit them
manually; update the source code or configuration and let a later run regenerate them.

## Outputs and lifecycle

- The compliance report groups findings by check and target.
- Each failed check/target pair can create one issue using `tests/<check-id>/issue.md`.
- Issues close when the check stops failing, is disabled or exempted, or its target is archived or
  removed. Checks that cannot be evaluated do not create or close issues.
- SARIF results appear in **Security > Code scanning**. They include severity, requirement,
  remediation and target links.
- At most 150 new issues are created in a run. Rate-limit responses use bounded retries; rerun after
  the limit resets if synchronization still fails.

## Local validation

Run the mocked end-to-end test without credentials or network access:

```powershell
pwsh ./tests/Invoke-SmokeTest.ps1
```

Run the offline Pester checks:

```powershell
Invoke-Pester -Path ./tests/validation
```

For live checks, connect the App and run the appropriate Pester test or use the workflow. A local
dry run of issue synchronization is documented in the [repository guide](../repo/README.md#compliance-issues).

## Troubleshooting

| Symptom | Likely cause or action |
| --- | --- |
| Environment protection blocks a run | The run is not on an allowed branch, or `enterprise-compliance` does not exist. |
| App credential error | Check `DOCS_APP_CLIENT_ID`, the `DOCS_APP_PRIVATE_KEY` environment secret and App installation. |
| Organization is listed as missing an installation | Install the reader App on that organization. |
| Section is *Not available* (HTTP 403) | Grant the App the required read permission; see [permissions](reference/permissions.md). |
| Section is *Not available* (HTTP 404) | The feature may be unavailable for the plan or token type. |
| Check is not evaluated | Required data is incomplete or inaccessible; inspect App permissions and installation. |
| Manifest discovery fails | Check the JSON, scope prefix, matching folder/test ID, local `policy.json` and `issue.md`. |
| Documentation PR cannot be created | Allow Actions to create PRs, or configure a suitably scoped `DOCS_PUBLISH_TOKEN`; see [setup](03-setup.md#repository-settings). |
| Documentation PR has no required checks | `GITHUB_TOKEN` does not trigger ordinary PR workflows; use a suitable publishing credential or another trusted check mechanism, as described in [setup](03-setup.md#actions-variables-and-secrets). |
| Publishing branch is unmanaged or modified | Review the branch and its PR manually; the workflow refuses to overwrite it. |
| Protected-branch push fails in direct mode | Use the default PR mode, or allow the publishing credential to push under the branch rules. |
| SARIF upload fails | Confirm workflow token permissions and that Code Security is enabled for a private/internal repository. |
| Issue sync is rate-limited | Wait for the rate limit to reset, then rerun the workflow. |

For repository-specific setup and generated content, return to the [repository guide](../repo/README.md).
