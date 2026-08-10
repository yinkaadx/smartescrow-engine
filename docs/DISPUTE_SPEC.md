# SmartEscrow Dispute Specification

## Scope

This specification defines milestone dispute opening and arbiter resolution.

## Eligible milestones

A dispute may be opened only when a milestone has one of these statuses:

- `Submitted`
- `Rejected`

The following statuses cannot be disputed:

- `Pending`
- `Approved`
- `Paid`
- `Disputed`
- `Refunded`

## Opening a dispute

- Only the client or contractor may open a dispute.
- The escrow must be `Active`.
- The milestone identifier must exist.
- The milestone must be `Submitted` or `Rejected`.
- A nonzero dispute evidence hash is required.
- Only one dispute may be active at a time.
- The milestone changes to `Disputed`.
- The escrow changes to `Disputed`.
- Ordinary submissions, reviews, and payment releases remain frozen.
- The contract records the disputed milestone identifier and evidence hash.
- A `DisputeOpened` event is emitted.

## Arbiter decisions

Only the immutable arbiter may resolve an active dispute.

The arbiter chooses one of two outcomes:

1. Contractor award
2. Client refund

A nonzero resolution hash is required for either outcome.

## Contractor award

- The disputed milestone changes to `Paid`.
- The milestone amount is added to `totalReleased`.
- ETH is transferred to the contractor.
- A `DisputeResolved` event records the contractor award.
- A failed transfer reverts the entire resolution.

## Client refund

- The disputed milestone changes to `Refunded`.
- The milestone amount is added to `totalRefunded`.
- ETH is transferred to the client.
- A `DisputeResolved` event records the client refund.
- A failed transfer reverts the entire resolution.

## Post-resolution state

After a successful ruling:

- Active dispute tracking is cleared.
- The escrow becomes `Completed` when:

  `totalReleased + totalRefunded == totalDeposited`

- Otherwise, the escrow returns to `Active`.

Previously paid milestones remain final and unaffected.

## Security requirements

- Follow Checks-Effects-Interactions for both ruling outcomes.
- Validate authorization, escrow state, milestone ID, milestone status,
  evidence hash, and resolution hash before changing state.
- Apply all milestone, accounting, and escrow-state effects before sending ETH.
- Revert every state change if the recipient rejects the transfer.
- Prevent duplicate dispute opening and duplicate resolution.
