## Restrict repository deletion and transfer

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Repository deletion or transfer can cause data loss or move assets outside intended control.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.2.3`. This check covers only part of the recommendation; complete the remaining review manually.

### Remediation

- [ ] In Enterprise settings > Policies > Repositories, disable repository deletion and transfer by repository admins.
- [ ] Verify the setting and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
