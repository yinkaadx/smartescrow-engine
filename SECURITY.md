# Security Policy

## Status

SmartEscrow Engine is an unaudited reference implementation. Automated tests
and static analyzers provide useful evidence, but they do not certify security
or production readiness.

## Supported versions

Security review currently applies only to the latest commit on `main`. No
stable production release is supported yet.

## Reporting

Do not disclose an exploitable issue publicly before the repository owner has
had a reasonable opportunity to investigate it.

Report suspected vulnerabilities privately through GitHub's private
vulnerability reporting feature when enabled. If that feature is unavailable,
contact the repository owner through a private channel listed on their GitHub
profile.

A useful report includes:

- Affected commit
- Impact and threat scenario
- Minimal reproduction
- Required attacker capabilities
- Suggested mitigation, if known

Never include real private keys, credentials, or third-party personal data.

## Reviewed analyzer findings

The final local triage produced:

- Aderyn: zero high issues and zero low issues
- Slither: two low-impact timestamp findings
- Slither: two informational low-level-call findings

The timestamp findings correspond to milestone deadline checks. Timestamps are
not used for randomness.

The low-level calls are intentional native-ETH transfers in
`releaseMilestonePayment` and `resolveDispute`. State effects are applied
before interaction, transfer success is checked, and failure reverts the
transaction.

These are manual triage decisions, not claims that the contract is free of
vulnerabilities.

## Security properties

The test suite covers these principal properties:

- Role-restricted actions
- Exact funding
- Allocation bounds
- No duplicate payment or refund
- Released and refunded funds bounded by deposits
- One active dispute at a time
- Arbiter-only resolution
- Failed-transfer rollback
- Stateful accounting invariants

## Deployment warning

Before deployment with real value:

1. Commission an independent audit of the exact release commit.
2. Review the absence of cancellation and timeout recovery.
3. Confirm the arbiter trust and key-management model.
4. Test recipient behavior and operational recovery.
5. Verify compiler, optimizer, EVM, network, and constructor parameters.
6. Re-run all tests and analyzers from a clean clone.
