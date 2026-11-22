## Restrict runner groups from public repositories

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Excessive privileges or broad access can expose organization resources and data.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `2.1.5` (partial assessment).

### Remediation

- [ ] Disable public repository access for runner groups that do not explicitly need it.
### Manual review

- [ ] Review runner group visibility, selected repositories, network access and self-hosted runner security.
- [ ] Verify the configuration and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
