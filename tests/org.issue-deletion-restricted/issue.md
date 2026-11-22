## Restrict issue deletion

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Excessive privileges or broad access can expose organization resources and data.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.2.4` (partial assessment).

### Remediation

- [ ] Disable issue deletion by repository administrators in member privileges.
### Manual review

- [ ] Review the remaining owner privileges and whether they are appropriate.
- [ ] Verify the configuration and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
