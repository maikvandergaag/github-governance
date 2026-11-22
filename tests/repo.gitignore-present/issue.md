## Add repository ignore rules

**Target:** [{{target}}]({{target_url}}) - **Check:** `{{check}}` - **Severity:** {{severity}}

**Finding:** {{finding}}

Without repository ignore rules, generated files and local configuration may be committed unintentionally.
This is a repository policy check, not a CIS GitHub Benchmark requirement.

### Remediation

- [ ] Add a regular `.gitignore` file at the repository root on the default branch.
- [ ] Configure ignore rules for the project's build output, temporary files and local configuration.
- [ ] Review the rules; this check verifies presence only, not their effectiveness. Ignore rules do not remove tracked files or protect secrets already committed.
- [ ] Run the compliance workflow again.

[Git ignore documentation](https://git-scm.com/docs/gitignore) - [Generated documentation]({{docs_url}})
To accept a deviation, add an exemption in `compliance/policy.json`.
