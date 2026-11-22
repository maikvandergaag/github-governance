## Require Actions to use immutable SHA references

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Unrestricted configuration can increase exposure to untrusted or unintended changes.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `2.4.2` (partial assessment).

### Remediation

- [ ] Require actions to be pinned to full commit SHAs in organization Actions policy.
### Manual review

- [ ] Review reusable workflows, third-party packages and other build dependencies separately; this setting does not pin them.
- [ ] Verify the configuration and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
