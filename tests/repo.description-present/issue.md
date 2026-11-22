## Add a repository description

**Target:** [{{target}}]({{target_url}}) - **Check:** `{{check}}` - **Severity:** {{severity}}

**Finding:** {{finding}}

Without a description, contributors may struggle to identify the repository's purpose when browsing or searching.
This is a repository policy check, not a CIS GitHub Benchmark requirement.

### Remediation

- [ ] Open the repository's main page and edit the **About** section.
- [ ] Enter a concise description of the project's purpose and save it.
- [ ] Review the description for accuracy; this check rejects null, empty and whitespace-only descriptions but does not assess their quality.
- [ ] Run the compliance workflow again.

A README does not replace the repository description.

[GitHub repository documentation](https://docs.github.com/en/repositories) - [Generated documentation]({{docs_url}})
To accept a deviation, add an exemption in `compliance/policy.json`.
