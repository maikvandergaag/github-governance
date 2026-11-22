## Review inactive repository

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Unmaintained repositories may retain outdated dependencies, access, or configuration.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.2.7`. This check covers only part of the recommendation; complete the remaining review manually.

### Remediation

- [ ] Archive the repository if it is no longer used, or add an exemption.
- [ ] Verify the repository's status and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
