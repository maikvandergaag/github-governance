## Resolve affiliated users without 2FA

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Affiliated accounts without 2FA are more vulnerable to credential theft.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.3.4`, `1.3.5`. This check covers only part of the recommendation; complete the remaining review manually.

### Remediation

- [ ] Enforce 2FA at enterprise level, or follow up with the users listed under Enterprise settings > People.
- [ ] Verify the users' 2FA status and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
