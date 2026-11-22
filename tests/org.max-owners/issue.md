## Limit organization owners

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Excess organization owners increase the number of accounts with broad administrative privileges.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.3.3`. This check covers only part of the recommendation; complete the remaining review manually.

### Remediation

- [ ] Reduce owners; use teams with appropriate organization roles instead.
- [ ] Verify the owner count and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
