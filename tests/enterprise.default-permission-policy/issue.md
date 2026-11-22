## Enforce enterprise base repository permissions

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Unrestricted base permissions can give members broader repository access than intended.

### Remediation

- [ ] In Enterprise settings > Policies > Repositories > Base permissions, set No permission or Read.
- [ ] Verify the setting and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
