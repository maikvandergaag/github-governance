## Restrict internal repository creation

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Unrestricted configuration can increase exposure to untrusted or unintended changes.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.2.2` (partial assessment).

### Remediation

- [ ] Disable member creation of internal repositories in organization member privileges.
### Manual review

- [ ] Review allowed repository creation paths and enterprise-level exceptions.
- [ ] Verify the configuration and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
