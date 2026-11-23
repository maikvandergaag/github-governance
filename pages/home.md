<!-- This page is built at the site root; links are relative to the staged site. -->
<div class="hero" markdown>

# Understand your GitHub governance

Document configuration, evaluate it against your policies, and turn findings into practical next
steps across an enterprise, organization, or personal account.

[Get started](docs/repo/SETUP.md){ .md-button .md-button--primary }
[See an example](docs/example.md){ .md-button }
[Browse checks](docs/checks.md){ .md-button }

</div>

![Four stages: connect a GitHub App, collect configuration, evaluate policy, and review findings.](docs/assets/how-it-works.svg){ .diagram }

## Find your path

<div class="path-grid" markdown>

<div markdown>

### Set up an assessment

Choose a scope, configure access and run your first assessment.
[Start here →](docs/repo/SETUP.md)

</div>
<div markdown>

### Understand a finding

Explore checks, default severity, remediation and evaluation limits.
[Browse the catalog →](docs/checks.md)

</div>
<div markdown>

### Tailor your policy

Configure checks, exemptions and the outputs your team needs.
[Configure policy →](docs/configuration/04-policy.md)

</div>

</div>

## How it works

A read-only GitHub App collects accessible configuration. The toolkit evaluates checks against
your policy and can publish documentation, issues and SARIF results. Findings depend on access and
coverage: missing data is **not** treated as compliant.

[Explore the workflow](docs/configuration/01-overview.md) ·
[View a fictional assessment](docs/example.md)

> **Keep inventories private.** Generated documentation and snapshots can contain sensitive
> organization and repository metadata. This public site describes the toolkit; it does not
> publish generated inventories.

## See it in action

The [illustrative example](docs/example.md) uses fictional data. The
[offline smoke test](CONTRIBUTING.md#run-the-offline-checks) exercises the implementation
without GitHub credentials.

## Get started

Follow the [setup guide](docs/repo/SETUP.md) for enterprise, organization or personal account
assessments.

## Run locally

Use the [local commands](docs/repo/README.md#powershell-module) with PowerShell 7.2+ and the
appropriate [GitHub App permissions](docs/configuration/reference/permissions.md).

## Validate changes

See the [offline validation instructions](CONTRIBUTING.md#run-the-offline-checks).

## Publish the tooling documentation

The [repository README]({{SOURCE_URL}}/README.md#publish-the-tooling-documentation)
describes the Pages deployment and its privacy boundaries.

## Community

Read the [contribution guide](CONTRIBUTING.md), [code of conduct](CODE_OF_CONDUCT.md) and
[security policy](SECURITY.md).

## License

GitHub Governance is distributed under the [Apache License 2.0](LICENSE).
