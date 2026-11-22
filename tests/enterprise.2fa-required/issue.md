## Enterprise-wide two-factor authentication

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Accounts without a second factor are more vulnerable to credential theft.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.3.4`, `1.3.5`. This check covers only part of the recommendation; complete the remaining review manually.

### Remediation

- [ ] In enterprise settings, open Authentication security and require two-factor authentication.
- [ ] For Enterprise Managed Users using identity-provider MFA, review whether a policy exemption is appropriate.
- [ ] Verify the setting and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
