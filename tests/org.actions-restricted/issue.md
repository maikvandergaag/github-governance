## Restrict organization GitHub Actions

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Unapproved actions may execute untrusted code in workflows with repository access.

### Remediation

- [ ] In Organization settings > Actions > General > Policies, allow selected actions only.
- [ ] Verify the setting and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
