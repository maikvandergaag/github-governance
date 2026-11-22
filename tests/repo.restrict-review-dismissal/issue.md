## Restrict review dismissal

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Insufficient branch controls can allow unreviewed or unsafe changes to reach important code.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.1.5` (partial assessment).

### Remediation

- [ ] Restrict who may dismiss pull request reviews.
### Manual review

- [ ] Review whether every allowed actor is trusted; a configured restriction alone does not establish that. This check inspects the default branch only and does not determine who can bypass rules.
- [ ] Verify the configuration and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
