## Limit organization Actions secrets

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Excessive privileges or broad access can expose organization resources and data.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `2.1.7` (partial assessment).

### Remediation

- [ ] Restrict organization secrets to selected or private repositories as appropriate.
### Manual review

- [ ] Review each secret's consumers, permissions, rotation and alternatives such as OIDC.
- [ ] Verify the configuration and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
