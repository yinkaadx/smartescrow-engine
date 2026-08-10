# Release Checklist

## Source

- [ ] Release commit is reviewed and immutable
- [ ] Worktree and index are clean
- [ ] Submodules are initialized and pinned
- [ ] Compiler and EVM settings are confirmed
- [ ] No secrets or `.env` files are tracked
- [ ] An explicit repository license decision has been made

## Verification

- [ ] `forge fmt --check` passes
- [ ] `forge lint --deny warnings` passes
- [ ] `forge build --sizes` passes
- [ ] `forge test -vvv` passes
- [ ] Unit tests pass
- [ ] Fuzz tests pass
- [ ] Stateful invariant tests pass
- [ ] Coverage is reviewed
- [ ] Gas report is reviewed
- [ ] Slither output is reviewed
- [ ] Aderyn output is reviewed
- [ ] Analyzer exceptions are documented

## Deployment

- [ ] Target chain and chain ID are confirmed
- [ ] Client address is confirmed
- [ ] Contractor address is confirmed
- [ ] Arbiter address and key controls are confirmed
- [ ] Required funding is confirmed in wei and ETH
- [ ] Constructor arguments are independently verified
- [ ] Deployment is simulated without `--broadcast`
- [ ] Deployed bytecode is verified against the release commit
- [ ] Deployment transaction and address are recorded
- [ ] Client funds only the verified deployment

## Operational review

- [ ] Parties understand that milestones require full allocation
- [ ] Parties understand deadline behavior
- [ ] Parties understand that rulings cannot split milestone funds
- [ ] Parties understand that only one dispute may be active
- [ ] Parties accept the absence of cancellation and timeout recovery
- [ ] Incident and arbiter-key compromise procedures exist

## Release evidence

Record:

```text
Release commit:
Release tag:
Network:
Chain ID:
Contract address:
Deployment transaction:
Compiler:
Optimizer:
EVM version:
Test result:
Runtime size:
Slither result:
Aderyn result:
Independent audit:
```
