# Configuration handbook

[Repository guide](../repo/README.md) · [Generated documentation](../output/README.md) · [Home](../../README.md)

This handbook explains how to configure, operate and extend the GitHub Enterprise documentation
and compliance workflow. It is organized as a book: read the chapters in order for a first setup,
or jump to a topic from the contents below.

## Contents

1. [Overview](01-overview.md) — what the workflow collects and publishes
2. [Prerequisites and access](02-prerequisites-and-access.md) — tools, GitHub App and permissions
3. [Setup](03-setup.md) — repository settings, variables, secrets and first run
4. [Compliance policy](04-policy.md) — discovered checks, defaults, overrides and parameters
5. [Exemptions](05-exemptions.md) — scoped exceptions and their lifecycle
6. [Adding a compliance check](06-adding-checks.md) — manifests, tests and data sources
7. [Operations and troubleshooting](07-operations-and-troubleshooting.md) — runs, outputs and recovery

## Reference

- [Policy file reference](reference/policy-schema.md)
- [Check manifest reference](reference/check-manifest.md)
- [GitHub App permissions](reference/permissions.md)

## Choose a path

- **First-time setup:** start with [Overview](01-overview.md), then read chapters 2, 3 and 7.
- **Changing policy:** read [Compliance policy](04-policy.md) and [Exemptions](05-exemptions.md).
- **Adding a check:** read [Adding a compliance check](06-adding-checks.md) and its references.

The [repository guide](../repo/README.md) describes the generated documentation and compliance
outputs. The [setup guide](../repo/SETUP.md) remains a short entry point to this handbook.
