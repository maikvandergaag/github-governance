## Enable repository secret scanning

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Leaked credentials may remain undetected without secret scanning.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.5.1`. This check covers only part of the recommendation; complete the remaining review manually.

### Remediation

- [ ] Attach a code security configuration with secret scanning to this repository.
- [ ] Verify the setting and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
