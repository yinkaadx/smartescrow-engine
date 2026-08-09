// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { SmartEscrow } from "../../src/SmartEscrow.sol";
import { Test } from "forge-std/Test.sol";

contract SmartEscrowMilestoneFuzzTest is Test {
    SmartEscrow internal escrow;

    address internal client = makeAddr("client");
    address internal contractor = makeAddr("contractor");
    address internal arbiter = makeAddr("arbiter");

    uint256 internal constant REQUIRED_FUNDING = 100 ether;

    function setUp() public {
        escrow = new SmartEscrow(client, contractor, arbiter, REQUIRED_FUNDING);

        vm.deal(client, REQUIRED_FUNDING);

        vm.prank(client);
        escrow.fund{ value: REQUIRED_FUNDING }();
    }

    function testFuzz_ValidMilestonePreservesAccounting(
        uint256 amount,
        uint256 deadlineOffset,
        bytes32 detailsHash
    ) public {
        amount = bound(amount, 1, REQUIRED_FUNDING);
        deadlineOffset = bound(deadlineOffset, 1, 365 days);

        uint256 deadline = block.timestamp + deadlineOffset;

        vm.prank(client);

        uint256 milestoneId = escrow.addMilestone(amount, deadline, detailsHash);

        SmartEscrow.Milestone memory milestone = escrow.getMilestone(milestoneId);

        assertEq(milestone.amount, amount);
        assertEq(milestone.deadline, deadline);
        assertEq(milestone.detailsHash, detailsHash);
        assertEq(escrow.totalAllocated(), amount);
        assertEq(escrow.unallocatedFunding(), REQUIRED_FUNDING - amount);
        assertLe(escrow.totalAllocated(), escrow.requiredFunding());
    }

    function testFuzz_ExcessAllocationAlwaysReverts(
        uint256 excess
    ) public {
        excess = bound(excess, 1, type(uint128).max);

        uint256 requested = REQUIRED_FUNDING + excess;

        vm.prank(client);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.AllocationExceedsFunding.selector, REQUIRED_FUNDING, requested
            )
        );

        escrow.addMilestone(
            requested, block.timestamp + 30 days, keccak256("Excess fuzz allocation")
        );

        assertEq(escrow.totalAllocated(), 0);
        assertEq(escrow.unallocatedFunding(), REQUIRED_FUNDING);
    }
}
