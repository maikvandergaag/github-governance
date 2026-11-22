## Add repository Git attributes

**Target:** [{{target}}]({{target_url}}) - **Check:** `{{check}}` - **Severity:** {{severity}}

**Finding:** {{finding}}

Without repository attributes, line endings and file handling can differ between contributors and build environments.
This is a repository policy check, not a CIS GitHub Benchmark requirement.

### Remediation

- [ ] Add a regular `.gitattributes` file at the repository root on the default branch.
- [ ] Configure line endings, text/binary handling and any project-specific attributes. For example, `* text=auto` enables automatic text normalization.
- [ ] Review any proposed normalization changes before committing; this check verifies presence only, not the file's contents.
- [ ] Run the compliance workflow again.

[Git attributes documentation](https://git-scm.com/docs/gitattributes) - [Generated documentation]({{docs_url}})
To accept a deviation, add an exemption in `compliance/policy.json`.
