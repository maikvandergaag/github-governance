## Enable push protection for new repositories

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

New repositories without push protection may accept committed credentials.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.5.1`. This check covers only part of the recommendation; complete the remaining review manually.

### Remediation

- [ ] Apply a code security configuration with push protection as default for new repositories.
- [ ] Verify the setting and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
