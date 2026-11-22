## Restrict team creation

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Excessive privileges or broad access can expose organization resources and data.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.3.2` (partial assessment).

### Remediation

- [ ] Disable member team creation in organization member privileges.
### Manual review

- [ ] Review which owners can create teams and whether exceptions are appropriate.
- [ ] Verify the configuration and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
