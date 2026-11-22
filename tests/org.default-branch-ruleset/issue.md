## Require pull requests on default branches

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Without a pull-request requirement, changes may reach default branches without review.

### Remediation

- [ ] Create an active organization ruleset targeting `~DEFAULT_BRANCH` with "Require a pull request before merging".
- [ ] Verify the ruleset and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
