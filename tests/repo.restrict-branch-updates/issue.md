## Restrict default branch updates

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Broad direct push access can bypass change review and expose important code to unauthorized modification.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.1.15` (partial assessment).

### Remediation

- [ ] Restrict direct updates to approved users, teams or apps using branch protection or an update ruleset.
### Manual review

- [ ] Review who is authorized, inherited permissions and bypass actors; rule presence alone does not establish that access is appropriate.
- [ ] Verify the configuration and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
