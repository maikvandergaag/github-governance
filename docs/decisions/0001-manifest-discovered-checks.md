# 0001: Discover compliance checks from manifests

- **Status:** Accepted
- **Date:** 2026-11-22

## Context

Compliance checks need to declare their scope, title, remediation, data requirements, and policy
defaults. Keeping those details in implementation code makes checks harder to inspect and extend.
Checks also need to report unavailable data as not evaluated rather than silently treating it as a
pass.

## Decision

Discover checks from a `check.json` manifest in each check's folder. Keep check-specific policy,
remediation text, and Pester evaluation alongside the manifest. Validate supported data sources
explicitly and fail on unsupported source types. Follow the [check authoring guide](../configuration/06-adding-checks.md)
when adding a check.

## Consequences

- New checks can use an existing supported data source without editing a central registry.
- The manifest provides a reviewable declaration of check scope and intent.
- A new data-source kind still requires implementation and validation in the module.
- Tests and evaluation must preserve the distinction between a failed check and data that could not
  be evaluated.
