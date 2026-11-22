## Issue deletion is restricted at enterprise level

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Restricting deletion reduces the risk of losing or concealing issue history.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.2.4`. This check covers only part of the recommendation; complete the remaining review manually.

### Remediation

- [ ] In enterprise settings, open Policies > Repositories and disable issue deletion by repository administrators. Review the remaining privileged users.
- [ ] Verify the setting and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
