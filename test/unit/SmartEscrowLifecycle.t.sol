// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { SmartEscrow } from "../../src/SmartEscrow.sol";
import { Test } from "forge-std/Test.sol";

contract SmartEscrowLifecycleTest is Test {
    event ScheduleActivated(address indexed client);

    event MilestoneSubmitted(
        uint256 indexed milestoneId, address indexed contractor, bytes32 indexed submissionHash
    );

    SmartEscrow internal escrow;

    address internal client = makeAddr("client");
    address internal contractor = makeAddr("contractor");
    address internal arbiter = makeAddr("arbiter");
    address internal outsider = makeAddr("outsider");

    uint256 internal constant REQUIRED_FUNDING = 10 ether;
    uint256 internal firstDeadline;
    uint256 internal secondDeadline;

    function setUp() public {
        escrow = new SmartEscrow(client, contractor, arbiter, REQUIRED_FUNDING);

        vm.deal(client, REQUIRED_FUNDING);

        vm.startPrank(client);

        escrow.fund{ value: REQUIRED_FUNDING }();

        firstDeadline = block.timestamp + 10 days;
        secondDeadline = block.timestamp + 20 days;

        escrow.addMilestone(4 ether, firstDeadline, keccak256("First milestone"));

        escrow.addMilestone(6 ether, secondDeadline, keccak256("Second milestone"));

        vm.stopPrank();
    }

    function test_ClientCanActivateFullyAllocatedSchedule() public {
        vm.prank(client);
        escrow.activateSchedule();

        assertEq(uint256(escrow.state()), uint256(SmartEscrow.EscrowState.Active));
    }

    function test_ActivationEmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit ScheduleActivated(client);

        vm.prank(client);
        escrow.activateSchedule();
    }

    function test_RevertWhenOutsiderActivatesSchedule() public {
        vm.prank(outsider);
        vm.expectRevert(SmartEscrow.Unauthorized.selector);

        escrow.activateSchedule();
    }

    function test_RevertWhenContractorActivatesSchedule() public {
        vm.prank(contractor);
        vm.expectRevert(SmartEscrow.Unauthorized.selector);

        escrow.activateSchedule();
    }

    function test_RevertWhenScheduleIsNotFullyAllocated() public {
        SmartEscrow partialEscrow = new SmartEscrow(client, contractor, arbiter, REQUIRED_FUNDING);

        vm.deal(client, REQUIRED_FUNDING);

        vm.startPrank(client);

        partialEscrow.fund{ value: REQUIRED_FUNDING }();

        partialEscrow.addMilestone(4 ether, block.timestamp + 10 days, keccak256("Partial"));

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.ScheduleNotFullyAllocated.selector, 4 ether, REQUIRED_FUNDING
            )
        );

        partialEscrow.activateSchedule();

        vm.stopPrank();
    }

    function test_RevertWhenActivatingBeforeFunding() public {
        SmartEscrow unfunded = new SmartEscrow(client, contractor, arbiter, REQUIRED_FUNDING);

        vm.prank(client);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.InvalidState.selector,
                SmartEscrow.EscrowState.Funded,
                SmartEscrow.EscrowState.Created
            )
        );

        unfunded.activateSchedule();
    }

    function test_RevertWhenAddingMilestoneAfterActivation() public {
        vm.startPrank(client);

        escrow.activateSchedule();

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.InvalidState.selector,
                SmartEscrow.EscrowState.Funded,
                SmartEscrow.EscrowState.Active
            )
        );

        escrow.addMilestone(1 ether, block.timestamp + 30 days, keccak256("Late addition"));

        vm.stopPrank();
    }

    function test_ContractorCanSubmitMilestone() public {
        bytes32 submissionHash = keccak256("Delivery evidence");

        vm.prank(client);
        escrow.activateSchedule();

        vm.prank(contractor);
        escrow.submitMilestone(0, submissionHash);

        SmartEscrow.Milestone memory milestone = escrow.getMilestone(0);

        assertEq(milestone.submissionHash, submissionHash);

        assertEq(uint256(milestone.status), uint256(SmartEscrow.MilestoneStatus.Submitted));

        assertEq(address(escrow).balance, REQUIRED_FUNDING);
    }

    function test_SubmissionEmitsEvent() public {
        bytes32 submissionHash = keccak256("Event evidence");

        vm.prank(client);
        escrow.activateSchedule();

        vm.expectEmit(true, true, true, false);

        emit MilestoneSubmitted(0, contractor, submissionHash);

        vm.prank(contractor);
        escrow.submitMilestone(0, submissionHash);
    }

    function test_RevertWhenClientSubmitsMilestone() public {
        vm.prank(client);
        escrow.activateSchedule();

        vm.prank(client);
        vm.expectRevert(SmartEscrow.Unauthorized.selector);

        escrow.submitMilestone(0, keccak256("Client submission"));
    }

    function test_RevertWhenArbiterSubmitsMilestone() public {
        vm.prank(client);
        escrow.activateSchedule();

        vm.prank(arbiter);
        vm.expectRevert(SmartEscrow.Unauthorized.selector);

        escrow.submitMilestone(0, keccak256("Arbiter submission"));
    }

    function test_RevertWhenSubmittingUnknownMilestone() public {
        vm.prank(client);
        escrow.activateSchedule();

        vm.prank(contractor);

        vm.expectRevert(abi.encodeWithSelector(SmartEscrow.InvalidMilestoneId.selector, 2));

        escrow.submitMilestone(2, keccak256("Unknown milestone"));
    }

    function test_RevertWhenSubmissionHashIsEmpty() public {
        vm.prank(client);
        escrow.activateSchedule();

        vm.prank(contractor);
        vm.expectRevert(SmartEscrow.EmptySubmissionHash.selector);

        escrow.submitMilestone(0, bytes32(0));
    }

    function test_RevertWhenMilestoneIsSubmittedTwice() public {
        bytes32 firstSubmission = keccak256("First submission");

        vm.prank(client);
        escrow.activateSchedule();

        vm.startPrank(contractor);

        escrow.submitMilestone(0, firstSubmission);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.InvalidMilestoneStatus.selector,
                SmartEscrow.MilestoneStatus.Pending,
                SmartEscrow.MilestoneStatus.Submitted
            )
        );

        escrow.submitMilestone(0, keccak256("Second submission"));

        vm.stopPrank();
    }

    function test_RevertWhenSubmissionIsAfterDeadline() public {
        vm.prank(client);
        escrow.activateSchedule();

        vm.warp(firstDeadline + 1);

        vm.prank(contractor);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.MilestoneDeadlinePassed.selector, firstDeadline, firstDeadline + 1
            )
        );

        escrow.submitMilestone(0, keccak256("Late submission"));
    }

    function test_SubmissionAtExactDeadlineSucceeds() public {
        bytes32 submissionHash = keccak256("On-time submission");

        vm.prank(client);
        escrow.activateSchedule();

        vm.warp(firstDeadline);

        vm.prank(contractor);
        escrow.submitMilestone(0, submissionHash);

        SmartEscrow.Milestone memory milestone = escrow.getMilestone(0);

        assertEq(milestone.submissionHash, submissionHash);

        assertEq(uint256(milestone.status), uint256(SmartEscrow.MilestoneStatus.Submitted));
    }
}
