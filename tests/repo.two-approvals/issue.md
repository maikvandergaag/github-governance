## Require at least two pull request approvals

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Insufficient branch controls can allow unreviewed or unsafe changes to reach important code.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.1.3` (partial assessment).

### Remediation

- [ ] Require at least two pull request approvals on the default branch.
### Manual review

- [ ] Verify reviewers have strong authentication and that bypasses are justified. This check inspects the default branch only and does not determine who can bypass rules.
- [ ] Verify the configuration and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
