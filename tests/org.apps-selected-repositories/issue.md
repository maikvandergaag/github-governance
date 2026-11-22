## Limit installed apps to selected repositories

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Excessive privileges or broad access can expose organization resources and data.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.4.3` (partial assessment).

### Remediation

- [ ] Restrict each GitHub App installation to the repositories it needs.
### Manual review

- [ ] Review each app permission and business need; selected repository access alone does not prove least privilege.
- [ ] Verify the configuration and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
