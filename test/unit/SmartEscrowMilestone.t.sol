// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { SmartEscrow } from "../../src/SmartEscrow.sol";
import { Test } from "forge-std/Test.sol";

contract SmartEscrowMilestoneTest is Test {
    event MilestoneAdded(
        uint256 indexed milestoneId, uint256 amount, uint256 deadline, bytes32 indexed detailsHash
    );

    SmartEscrow internal escrow;

    address internal client = makeAddr("client");
    address internal contractor = makeAddr("contractor");
    address internal arbiter = makeAddr("arbiter");
    address internal outsider = makeAddr("outsider");

    uint256 internal constant REQUIRED_FUNDING = 10 ether;

    function setUp() public {
        escrow = new SmartEscrow(client, contractor, arbiter, REQUIRED_FUNDING);

        vm.deal(client, 100 ether);

        vm.prank(client);
        escrow.fund{ value: REQUIRED_FUNDING }();
    }

    function test_ClientCanAddMilestone() public {
        uint256 amount = 4 ether;
        uint256 deadline = block.timestamp + 30 days;
        bytes32 detailsHash = keccak256("Milestone one");

        vm.prank(client);

        uint256 milestoneId = escrow.addMilestone(amount, deadline, detailsHash);

        assertEq(milestoneId, 0);
        assertEq(escrow.milestoneCount(), 1);
        assertEq(escrow.totalAllocated(), amount);
        assertEq(escrow.unallocatedFunding(), REQUIRED_FUNDING - amount);

        SmartEscrow.Milestone memory milestone = escrow.getMilestone(milestoneId);

        assertEq(milestone.amount, amount);
        assertEq(milestone.deadline, deadline);
        assertEq(milestone.detailsHash, detailsHash);
        assertEq(uint256(milestone.status), uint256(SmartEscrow.MilestoneStatus.Pending));
    }

    function test_MilestoneIdsIncreaseSequentially() public {
        vm.startPrank(client);

        uint256 firstId =
            escrow.addMilestone(4 ether, block.timestamp + 10 days, keccak256("First"));

        uint256 secondId =
            escrow.addMilestone(6 ether, block.timestamp + 20 days, keccak256("Second"));

        vm.stopPrank();

        assertEq(firstId, 0);
        assertEq(secondId, 1);
        assertEq(escrow.milestoneCount(), 2);
        assertEq(escrow.totalAllocated(), REQUIRED_FUNDING);
        assertEq(escrow.unallocatedFunding(), 0);
    }

    function test_AddMilestoneEmitsEvent() public {
        uint256 deadline = block.timestamp + 30 days;
        bytes32 detailsHash = keccak256("Event evidence");

        vm.expectEmit(true, true, false, true);

        emit MilestoneAdded(0, 3 ether, deadline, detailsHash);

        vm.prank(client);

        escrow.addMilestone(3 ether, deadline, detailsHash);
    }

    function test_RevertWhenOutsiderAddsMilestone() public {
        vm.prank(outsider);
        vm.expectRevert(SmartEscrow.Unauthorized.selector);

        escrow.addMilestone(1 ether, block.timestamp + 1 days, keccak256("Unauthorized"));
    }

    function test_RevertWhenContractorAddsMilestone() public {
        vm.prank(contractor);
        vm.expectRevert(SmartEscrow.Unauthorized.selector);

        escrow.addMilestone(1 ether, block.timestamp + 1 days, keccak256("Unauthorized contractor"));
    }

    function test_RevertWhenMilestoneAmountIsZero() public {
        vm.prank(client);
        vm.expectRevert(SmartEscrow.ZeroMilestoneAmount.selector);

        escrow.addMilestone(0, block.timestamp + 1 days, keccak256("Zero amount"));
    }

    function test_RevertWhenDeadlineEqualsCurrentTime() public {
        vm.prank(client);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.InvalidDeadline.selector, block.timestamp, block.timestamp
            )
        );

        escrow.addMilestone(1 ether, block.timestamp, keccak256("Invalid deadline"));
    }

    function test_RevertWhenDeadlineIsInPast() public {
        uint256 pastDeadline = block.timestamp - 1;

        vm.prank(client);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.InvalidDeadline.selector, pastDeadline, block.timestamp
            )
        );

        escrow.addMilestone(1 ether, pastDeadline, keccak256("Past deadline"));
    }

    function test_RevertWhenAllocationExceedsFunding() public {
        vm.prank(client);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.AllocationExceedsFunding.selector,
                REQUIRED_FUNDING,
                REQUIRED_FUNDING + 1
            )
        );

        escrow.addMilestone(REQUIRED_FUNDING + 1, block.timestamp + 1 days, keccak256("Excess"));
    }

    function test_RevertWhenCombinedAllocationExceedsFunding() public {
        vm.startPrank(client);

        escrow.addMilestone(8 ether, block.timestamp + 10 days, keccak256("First"));

        vm.expectRevert(
            abi.encodeWithSelector(SmartEscrow.AllocationExceedsFunding.selector, 2 ether, 3 ether)
        );

        escrow.addMilestone(3 ether, block.timestamp + 20 days, keccak256("Second"));

        vm.stopPrank();
    }

    function test_RevertWhenAddingBeforeFunding() public {
        SmartEscrow unfunded = new SmartEscrow(client, contractor, arbiter, REQUIRED_FUNDING);

        vm.prank(client);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.InvalidState.selector,
                SmartEscrow.EscrowState.Funded,
                SmartEscrow.EscrowState.Created
            )
        );

        unfunded.addMilestone(1 ether, block.timestamp + 1 days, keccak256("Too early"));
    }

    function test_RevertWhenReadingUnknownMilestone() public {
        vm.expectRevert(abi.encodeWithSelector(SmartEscrow.InvalidMilestoneId.selector, 0));

        escrow.getMilestone(0);
    }

    function test_FailedAdditionLeavesAccountingUnchanged() public {
        vm.prank(client);

        try escrow.addMilestone(
            REQUIRED_FUNDING + 1, block.timestamp + 1 days, keccak256("Failure")
        ) {
            fail();
        } catch {
            assertEq(escrow.milestoneCount(), 0);
            assertEq(escrow.totalAllocated(), 0);
            assertEq(escrow.unallocatedFunding(), REQUIRED_FUNDING);
        }
    }
}
