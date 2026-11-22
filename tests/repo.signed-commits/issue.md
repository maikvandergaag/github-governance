## Require signed commits

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Unsigned commits make it harder to verify the identity associated with a change.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.1.12` (partial assessment).

### Remediation

- [ ] Require signed commits on the default branch.
### Manual review

- [ ] Review signer trust, signature verification, other protected branches and bypass actors; rule presence alone does not establish these.
- [ ] Verify the configuration and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
