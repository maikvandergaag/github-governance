## Restrict enterprise repository creation

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Unrestricted repository creation can expose code or data in public repositories.

### Remediation

- [ ] In Enterprise settings > Policies > Repositories > Repository creation, enforce a policy without public repositories.
- [ ] Verify the setting and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
