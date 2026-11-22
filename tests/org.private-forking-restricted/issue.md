## Restrict private repository forks

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Excessive privileges or broad access can expose organization resources and data.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.2.5` (partial assessment).

### Remediation

- [ ] Restrict private repository forking in organization member privileges.
### Manual review

- [ ] Inventory existing forks and confirm that each is tracked and authorized.
- [ ] Verify the configuration and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
