## Restrict default workflow token permissions

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Broad workflow token permissions can allow compromised workflows to modify code or approve changes.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `2.1.7` (partial assessment).

### Remediation

- [ ] Set default workflow permissions to read-only in organization Actions settings.
### Manual review

- [ ] Workflows may still request elevated permissions; review workflow files and exceptions.
- [ ] Verify the configuration and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
