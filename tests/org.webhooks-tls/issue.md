## Enable TLS verification for webhooks

**Target:** [{{target}}]({{target_url}}) · **Check:** `{{check}}` · **Severity:** {{severity}}

**Finding:** {{finding}}

Disabling TLS verification can expose webhook payloads to interception or tampering.

### Remediation

- [ ] Edit the affected webhook and enable SSL verification.
- [ ] Verify the configuration and run the compliance workflow again.

[Generated documentation]({{docs_url}}) · To accept a deviation, add an exemption in `compliance/policy.json`.
