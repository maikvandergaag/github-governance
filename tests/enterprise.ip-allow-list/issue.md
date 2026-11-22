## Enable the enterprise IP allow list

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Without network restrictions, access is not limited to approved IP ranges.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.3.12`. This check covers only part of the recommendation; complete the remaining review manually.

### Remediation

- [ ] In Enterprise settings > Authentication security > IP allow list, add approved ranges and enable the list.
- [ ] Verify the setting and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
