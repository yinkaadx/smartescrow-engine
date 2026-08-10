# SmartEscrow Engine Architecture

## Purpose

SmartEscrow Engine is a milestone-based payment and dispute-resolution
system for clients and contractors.

It demonstrates how traditional project workflows can be represented as
secure, testable smart-contract state transitions.

## Initial scope

The first release will support:

1. One client per escrow.
2. One contractor per escrow.
3. One independent arbiter per escrow.
4. Native ETH deposits.
5. Multiple sequential milestones.
6. Contractor milestone submission.
7. Client approval or rejection.
8. Payment release after approval.
9. Dispute opening by either commercial party.
10. Dispute resolution by the arbiter.
11. Deadline-based cancellation and refunds.
12. Platform fees.
13. Emergency pause controls.
14. Complete event history.

ERC-20 support will be added only after native ETH accounting and
security invariants pass.

## Actors

### Client

The client creates and funds the escrow, reviews submitted milestones,
approves completed work, and can open a dispute.

### Contractor

The contractor performs the work, submits milestones for review,
receives approved payments, and can open a dispute.

### Arbiter

The arbiter cannot perform normal client or contractor actions. The
arbiter may resolve an active dispute and allocate the disputed funds
according to the contract rules.

### Platform administrator

The administrator manages the platform fee recipient and emergency
pause mechanism. The administrator must not be able to seize escrowed
funds.

## Escrow states

- Created: The escrow exists but has not been funded.
- Funded: The client has deposited the required amount.
- Active: Work may be submitted and reviewed.
- Disputed: Normal milestone processing is suspended.
- Completed: Every milestone has been paid.
- Cancelled: The escrow ended and refundable funds were returned.

## Milestone states

- Pending: Work has not been submitted.
- Submitted: The contractor has submitted work for review.
- Approved: The client approved the work.
- Rejected: The client rejected the submitted work.
- Paid: The milestone payment was released.
- Disputed: The milestone is under formal dispute.
- Refunded: The milestone funds were returned to the client.

## Core security properties

1. Only the client can fund the escrow.
2. Only the contractor can submit milestone work.
3. Only the client can approve or reject normal submissions.
4. Only the arbiter can resolve an active dispute.
5. A milestone cannot be paid twice.
6. A milestone cannot be both paid and refunded.
7. Released funds cannot exceed deposited funds.
8. Refunded funds cannot exceed deposited funds.
9. Platform fees cannot exceed the configured maximum.
10. Administrative controls cannot transfer escrow principal.
11. External transfers must follow checks-effects-interactions.
12. Reentrant calls must not corrupt accounting or state.

## Accounting invariant

At every successful state transition:

    contract balance
    + total released to contractor
    + total refunded to client
    + total platform fees withdrawn
    = total client deposits

Temporary differences are permitted only during a transaction before
the transaction completes. A reverted transaction must leave all values
unchanged.

## Trust assumptions

- The client and contractor may behave maliciously.
- The arbiter is trusted only for dispute decisions.
- The administrator is trusted only for configuration and emergency
  controls.
- External receiving addresses may reject ETH or attempt reentrancy.
- Timestamps may vary slightly within normal blockchain constraints.

## Out of scope for the first release

- Mainnet deployment.
- Upgradeable proxy contracts.
- Cross-chain settlement.
- Fiat payment processing.
- Decentralized arbiter selection.
- Token swaps.
- Yield generation.
- Custodial wallet management.
- Claims of formal security certification or audit.

## Delivery evidence

The finished repository will include:

- Unit tests.
- Failure-path tests.
- Fuzz tests.
- Stateful invariant tests.
- Integration tests.
- Anvil deployment scripts.
- Cast interaction examples.
- Gas reports.
- Continuous integration.
- Threat model and security documentation.
- Public testnet deployment evidence.
