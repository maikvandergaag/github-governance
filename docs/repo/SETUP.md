# Setup guide

[Configuration handbook](../configuration/README.md) · [Repository guide](README.md) · [Home](../../README.md)

This page is a short entry point; the complete, chapter-based setup documentation is in the
[configuration handbook](../configuration/README.md).

## Choose your account scope

| Scope | What is evaluated | Start here |
| --- | --- | --- |
| Enterprise | Enterprise, organization, and repository checks | [Enterprise prerequisites](../configuration/02-prerequisites-and-access.md#github-app), then set `ENTERPRISE_SLUG` in [setup](../configuration/03-setup.md#actions-variables-and-secrets). |
| Organization | Organization and repository checks | Follow [standalone organization setup](../configuration/03-setup.md#standalone-organizations-and-personal-accounts) and choose `organization`. |
| Personal account | Repository checks for repositories owned by the account | Follow [personal account setup](../configuration/03-setup.md#standalone-organizations-and-personal-accounts) and choose `user`. |

All paths need PowerShell 7.2+ for local use and a read-only GitHub App with the permissions
appropriate to the scope. The workflow uses a separate token to publish results; generated
documentation should be stored in a private or internal repository. See
[prerequisites and access](../configuration/02-prerequisites-and-access.md) before configuring
credentials. For an introduction without credentials, see the [illustrative example](../example.md).

## Recommended reading

1. [Prerequisites and access](../configuration/02-prerequisites-and-access.md): create and install the
   read-only GitHub App and grant its permissions.
2. [Setup](../configuration/03-setup.md): configure Actions variables, the private-key secret,
   repository settings and run the workflow.
3. [Compliance policy](../configuration/04-policy.md): understand default check policies and
   overrides.
4. [Exemptions](../configuration/05-exemptions.md): add a reviewed exception for a target.
5. [Operations and troubleshooting](../configuration/07-operations-and-troubleshooting.md): inspect
   generated docs, findings, issues and workflow failures.

To extend the compliance catalog, see [Adding a compliance check](../configuration/06-adding-checks.md).
