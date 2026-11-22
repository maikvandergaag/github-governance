## Prevent public repository creation by members

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Public repositories can expose code or data to anyone.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.2.2`. This check covers only part of the recommendation; complete the remaining review manually.

### Remediation

- [ ] In Organization settings > Member privileges > Repository creation, disable Public.
- [ ] Verify the setting and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
