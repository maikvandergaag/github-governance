## Enable secret scanning for new repositories

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

New repositories may otherwise contain exposed credentials without generating alerts.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.5.1`. This check covers only part of the recommendation; complete the remaining review manually.

### Remediation

- [ ] In organization code security settings, enable secret scanning by default for new repositories.
- [ ] Verify scanning on existing repositories and use push protection or other preventive controls as appropriate.
- [ ] Verify the setting and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
