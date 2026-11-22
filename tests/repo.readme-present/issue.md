## Add a root README.md

**Target:** [{{target}}]({{target_url}}) - **Check:** `{{check}}` - **Severity:** {{severity}}

**Finding:** {{finding}}

Without a root README.md, contributors may lack essential project purpose, setup and usage guidance.
This is a repository policy check, not a CIS GitHub Benchmark requirement.

### Remediation

- [ ] Add a regular file named exactly `README.md` at the repository root on the default branch.
- [ ] Describe the project's purpose, prerequisites, setup and usage, and link to further documentation where appropriate.
- [ ] Review the documentation for accuracy; this check verifies file presence only, not completeness or quality.
- [ ] Run the compliance workflow again.

A README in `.github/`, `docs/` or another subdirectory does not satisfy this root-file policy.

[GitHub README documentation](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes) - [Generated documentation]({{docs_url}})
To accept a deviation, add an exemption in `compliance/policy.json`.
