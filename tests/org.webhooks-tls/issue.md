## Enable TLS verification for webhooks

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

HTTP or disabled TLS verification can expose webhook payloads to interception or tampering.

**Benchmark:** CIS GitHub Benchmark v1.2.0, `1.4.4`. This check covers only part of the recommendation; complete the remaining review manually.

### Remediation

- [ ] Change the affected webhook URL to HTTPS and enable SSL verification.
- [ ] Review webhook authentication and the receiving service; this check does not inspect repository webhooks or verify signatures.
- [ ] Verify the configuration and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
