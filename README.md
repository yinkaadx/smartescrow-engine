# SmartEscrow Engine

SmartEscrow Engine is a native-ETH milestone escrow contract for a client,
contractor, and independent arbiter.

The client funds an escrow and defines a fully allocated milestone schedule.
The contractor submits work, the client reviews it, and approved payments are
released to the contractor. Either commercial party can dispute submitted or
rejected work, with the arbiter awarding the milestone funds to the contractor
or refunding them to the client.

> This repository is an educational/reference implementation. It has not
> received an independent security audit and is not presented as production
> ready.

## Features

- Immutable client, contractor, and arbiter roles
- Exact native-ETH funding requirement
- Up to 50 milestones
- Fully allocated milestone schedules
- Submission, approval, rejection, and payment workflow
- One active dispute at a time
- Contractor awards and client refunds
- Evidence and resolution hashes
- Custom errors and complete lifecycle events
- Unit, fuzz, failure-path, and stateful invariant tests
- CI formatting, linting, build-size, and test checks

## Workflow

1. Deploy the contract with distinct client, contractor, and arbiter addresses.
2. The client calls `fund()` with exactly `requiredFunding`.
3. The client creates milestones whose amounts total `requiredFunding`.
4. The client calls `activateSchedule()`.
5. The contractor submits milestone evidence before its deadline.
6. The client approves or rejects the submission.
7. The contractor releases an approved milestone payment.
8. The client or contractor may dispute a submitted or rejected milestone.
9. The arbiter resolves the dispute with a contractor award or client refund.
10. The escrow completes when all deposited funds are released or refunded.

## Contract API

### State-changing functions

| Function | Authorized caller | Purpose |
|---|---|---|
| `fund()` | Client | Deposit the exact required ETH |
| `addMilestone(amount, deadline, detailsHash)` | Client | Add a milestone before activation |
| `activateSchedule()` | Client | Activate a fully allocated schedule |
| `submitMilestone(id, submissionHash)` | Contractor | Submit milestone work |
| `approveMilestone(id)` | Client | Approve submitted work |
| `rejectMilestone(id, reviewHash)` | Client | Reject submitted work |
| `releaseMilestonePayment(id)` | Contractor | Claim an approved payment |
| `openDispute(id, evidenceHash)` | Client or contractor | Dispute submitted or rejected work |
| `resolveDispute(ruling, resolutionHash)` | Arbiter | Award or refund disputed funds |

### Read functions

- `milestoneCount()`
- `getMilestone(uint256)`
- `unallocatedFunding()`
- Public immutable roles and funding requirement
- Public accounting totals and escrow state
- Public dispute evidence and resolution hashes

## Requirements

- Git
- Foundry
- Solidity 0.8.35, installed automatically by Foundry when required

Clone with submodules:

```bash
git clone --recurse-submodules \
  https://github.com/yinkaadx/smartescrow-engine.git
cd smartescrow-engine
```

For an existing clone:

```bash
git submodule update --init --recursive
```

## Development

Run the complete local verification suite:

```bash
forge fmt --check
forge lint --deny warnings
forge build --sizes
forge test -vvv
```

Run individual test classes:

```bash
forge test --match-path 'test/unit/*.t.sol'
forge test --match-path 'test/fuzz/*.t.sol'
forge test --match-path 'test/invariant/*.t.sol'
```

Generate a gas report:

```bash
forge test --gas-report
```

Generate coverage:

```bash
forge coverage
```

## Deployment

Copy the environment template and supply deployment values:

```bash
cp .env.example .env
```

Never commit `.env` or a private key.

Simulate deployment first:

```bash
source .env
forge script script/DeploySmartEscrow.s.sol:DeploySmartEscrow \
  --rpc-url "$RPC_URL"
```

Broadcast only after reviewing the simulation:

```bash
forge script script/DeploySmartEscrow.s.sol:DeploySmartEscrow \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast
```

Deployment does not fund the escrow. After deployment, the configured client
must call `fund()` with exactly `REQUIRED_FUNDING_WEI`.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Dispute specification](docs/DISPUTE_SPEC.md)
- [Security notes](SECURITY.md)
- [Release checklist](docs/RELEASE_CHECKLIST.md)

## Security

The repository uses Foundry tests, fuzzing, stateful invariants, Slither, and
Aderyn as development safeguards. Static analysis and automated tests do not
replace an independent audit.

Do not deploy with real value until the exact commit, compiler settings,
deployment parameters, and target network have been independently reviewed.

## License

No license has been granted yet. All rights remain with the repository owner
until an explicit license file is added.
