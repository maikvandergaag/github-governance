# Maintainer and triage guide

This guide describes the repository's current best-effort maintainer process. It does not promise a
response time or replace GitHub repository permissions and branch protection.

## Triage

For each new issue, maintainers should:

1. Check that the issue is in scope and does not expose credentials, customer data, or sensitive
   account snapshots. If sensitive data is posted, remove or restrict it where possible and direct
   the reporter to a private channel.
2. Confirm the affected GitHub scope, module/commit version, PowerShell version, and reproduction
   details are sufficient. Ask for only the missing information needed to proceed.
3. Apply an issue-type label and, when useful, `needs-triage`. Apply at most one priority label
   after considering impact and urgency. See the [label catalog](labels.md).
4. Link duplicates and related work. Close issues that are duplicates, out of scope, will not be
   pursued, or remain blocked on requested information; explain the disposition when practical.
5. Convert a confirmed, actionable request into a focused issue with an outcome that can be reviewed
   and tested. Update the [roadmap](../../ROADMAP.md) only when project focus materially changes.

Priority labels communicate relative ordering only. They are not response-time or delivery
commitments.

## Pull request review

Reviewers should focus on correctness and regressions, test coverage, permission and data-handling
impact, compatibility, and relevant documentation. For PowerShell or compliance changes, check
fixture-based behavior and that unavailable data cannot be interpreted as compliant. For
permission, API, or workflow changes, verify that requested access and published outputs are
explained.

The repository `CODEOWNERS` file requests the maintainer's review for every path. Whether approval
is technically required is determined by the repository's branch protection settings. Contributors
should address blocking feedback or explain why it is not being followed, then resolve addressed
threads. No maintainer response time is guaranteed.
