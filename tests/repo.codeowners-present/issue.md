## Add a CODEOWNERS file

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Without CODEOWNERS, designated owners cannot be automatically requested for review.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.1.6`. This check covers only part of the recommendation; complete the remaining review manually.

### Remediation

- [ ] Add a CODEOWNERS file in `.github/`, the root or `docs/` on the default branch.
- [ ] Verify the file and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
