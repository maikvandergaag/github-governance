## Require organization two-factor authentication

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Member accounts without a second factor are more vulnerable to credential theft.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.3.4`, `1.3.5`. This check covers only part of the recommendation; complete the remaining review manually.

### Remediation

- [ ] In Organization settings > Authentication security, require two-factor authentication.
- [ ] Verify the setting and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
