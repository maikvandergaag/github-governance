## Member repository creation is restricted

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Unrestricted creation can expose data and make repository inventory harder to govern.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.2.2`. This check covers only part of the recommendation; complete the remaining review manually.

### Remediation

- [ ] In organization settings > Member privileges > Repository creation, disable member creation of public and private repositories. Review other creation permissions and exceptions.
- [ ] Verify the setting and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
