## Fix CODEOWNERS errors

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Invalid CODEOWNERS entries may prevent intended owners from being requested for review.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.1.6`. This check covers only part of the recommendation; complete the remaining review manually.

### Remediation

- [ ] Fix the reported lines, including renamed or removed teams and teams without write access.
- [ ] Verify the file and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
