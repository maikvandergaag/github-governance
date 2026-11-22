## Require code owner review

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Insufficient branch controls can allow unreviewed or unsafe changes to reach important code.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.1.7` (partial assessment).

### Remediation

- [ ] Require code owner reviews before merging.
### Manual review

- [ ] Verify CODEOWNERS covers sensitive paths and owners have appropriate access. This check inspects the default branch only and does not determine who can bypass rules.
- [ ] Verify the configuration and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
