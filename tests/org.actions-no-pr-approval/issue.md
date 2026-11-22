## Disallow workflow pull request approvals

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Broad workflow token permissions can allow compromised workflows to modify code or approve changes.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `2.1.7` (partial assessment).

### Remediation

- [ ] Disable the option allowing workflows to create or approve pull requests.
### Manual review

- [ ] Review GitHub App tokens and other credentials used in workflows; this setting controls only the default workflow token.
- [ ] Verify the configuration and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
