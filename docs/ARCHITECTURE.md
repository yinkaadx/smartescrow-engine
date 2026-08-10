# SmartEscrow Engine Architecture

## Purpose

SmartEscrow Engine represents a milestone-based client/contractor payment
workflow as explicit, testable smart-contract state transitions.

The current implementation supports one client, one contractor, one arbiter,
native ETH, multiple milestones, review, payment, and dispute resolution.

## Actors

### Client

The client supplies the escrow principal, defines milestones, activates the
schedule, reviews submissions, and may open disputes.

### Contractor

The contractor submits milestone work, releases approved payments, and may
open disputes.

### Arbiter

The arbiter cannot perform client or contractor actions. The arbiter resolves
an active dispute by awarding its full milestone amount to the contractor or
refunding it to the client.

All three roles are immutable and must use distinct, nonzero addresses.

## Escrow states

- `Created`: Deployed but not funded
- `Funded`: Required ETH deposited; milestones may be configured
- `Active`: Fully allocated schedule activated
- `Disputed`: One milestone awaits an arbiter ruling
- `Completed`: All deposited ETH has been released or refunded

The current contract does not implement a cancelled state.

## Milestone states

- `Pending`: Configured but not submitted
- `Submitted`: Contractor submitted work for review
- `Approved`: Client approved the work
- `Rejected`: Client rejected the work
- `Paid`: Funds released to the contractor
- `Disputed`: Awaiting an arbiter ruling
- `Refunded`: Funds returned to the client

## Lifecycle

The contract requires one exact funding transaction. Milestones can then be
added up to `MAX_MILESTONES`, and their combined amount cannot exceed the
deposit.

Schedule activation requires:

```text
totalAllocated == requiredFunding
```

Once active, milestones proceed through submission and review. Approved
milestones are released by the contractor. Submitted or rejected milestones
can instead enter dispute resolution.

## Accounting

The primary conservation property is:

```text
contract balance + totalReleased + totalRefunded == totalDeposited
```

The following bounds must always hold:

```text
totalAllocated <= totalDeposited
totalApproved <= totalAllocated
totalReleased + totalRefunded <= totalDeposited
```

Completion occurs when:

```text
totalReleased + totalRefunded == totalDeposited
```

## External calls

ETH transfers occur during normal approved-payment release and dispute
resolution. The contract applies state and accounting effects before making
the external call. If the recipient rejects ETH, the transaction reverts and
all effects roll back.

## Trust model

- The client and contractor may behave adversarially.
- The arbiter is trusted to select a dispute ruling, but cannot redirect funds
  to an arbitrary recipient.
- Receiving contracts may reject ETH or attempt reentrancy.
- Block timestamps may vary slightly within consensus constraints.
- Evidence, submission, review, and resolution content remains off-chain;
  only nonzero hashes are recorded.

## Current limitations

- Native ETH only
- Full milestone award or refund only; no split rulings
- One active dispute at a time
- No cancellation or timeout recovery path
- No platform fees
- No administrator or emergency pause
- No upgradeability
- No on-chain evidence storage
- No deployment registry or factory
- No independent audit

These limitations should be evaluated before any production use.
