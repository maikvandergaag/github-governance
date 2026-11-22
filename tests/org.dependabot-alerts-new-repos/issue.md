## Dependabot alerts are enabled for new repositories

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

New repositories may otherwise miss alerts for known vulnerable dependencies.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.5.5`, `3.2.2`. This check covers only part of the recommendation; complete the remaining review manually.

### Remediation

- [ ] In organization code security settings, enable Dependabot alerts by default for new repositories. Also verify scanning is enabled on existing repositories and review other package-scanning coverage.
- [ ] Verify the setting and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
