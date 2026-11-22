## Dismiss stale pull request approvals

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Insufficient branch controls can allow unreviewed or unsafe changes to reach important code.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.1.4` (partial assessment).

### Remediation

- [ ] Enable dismissal of stale approvals on new commits.
### Manual review

- [ ] Review bypass actors and ensure the effective rule applies to the intended branches. This check inspects the default branch only and does not determine who can bypass rules.
- [ ] Verify the configuration and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
