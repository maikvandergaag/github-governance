# 5. Exemptions

[Previous: Compliance policy](04-policy.md) · [Handbook](README.md) · [Next: Adding a compliance check](06-adding-checks.md)

An exemption suppresses one check for one target. Add it under `exemptions` in
`compliance/policy.json`; the value is a list of discovered check IDs.

```json
"exemptions": {
  "enterprise:contoso": ["enterprise.ip-allow-list"],
  "my-org": ["org.max-owners"],
  "my-org/public-website": ["repo.not-public"]
}
```

Use the target key for the scope:

| Target | Key format | Example |
| --- | --- | --- |
| Enterprise | `enterprise:<slug>` | `enterprise:contoso` |
| Organization | `<org>` | `my-org` |
| Repository | `<org>/<repo>` | `my-org/public-website` |

## Add or remove an exemption

1. Find the exact check ID in the [check catalog](../checks.md) or its
   `tests/<check-id>/check.json`.
2. Add the target key to `exemptions` in `compliance/policy.json`, then add the check ID to its list.
3. Submit the policy change through the repository's normal review process.
4. Run the workflow and confirm the result in the compliance report.

To remove an exemption, remove the check ID from the target list. Remove the target entry too if its
list becomes empty.

An exemption affects only the named target and check; it does not disable the check for other targets.
The evaluation skips the exempted check. If it previously had an open compliance issue, issue sync
closes that issue because the check no longer fails for the exempted target, provided issue
synchronization is enabled and the issue remains accessible in the configured destination.

Exemptions are governance decisions. Protect `compliance/policy.json` with CODEOWNERS and required
review, and include rationale in the pull request.
