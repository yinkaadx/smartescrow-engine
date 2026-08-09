// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { SmartEscrow } from "../../src/SmartEscrow.sol";
import { Test } from "forge-std/Test.sol";

contract SmartEscrowReviewTest is Test {
    event MilestoneApproved(uint256 indexed milestoneId, address indexed client, uint256 amount);

    event MilestoneRejected(
        uint256 indexed milestoneId, address indexed client, bytes32 indexed reviewHash
    );

    SmartEscrow internal escrow;

    address internal client = makeAddr("client");
    address internal contractor = makeAddr("contractor");
    address internal arbiter = makeAddr("arbiter");
    address internal outsider = makeAddr("outsider");

    uint256 internal constant REQUIRED_FUNDING = 10 ether;
    uint256 internal deadline;

    function setUp() public {
        escrow = new SmartEscrow(client, contractor, arbiter, REQUIRED_FUNDING);

        deadline = block.timestamp + 30 days;

        vm.deal(client, REQUIRED_FUNDING);

        vm.startPrank(client);

        escrow.fund{ value: REQUIRED_FUNDING }();

        escrow.addMilestone(REQUIRED_FUNDING, deadline, keccak256("Complete project"));

        escrow.activateSchedule();

        vm.stopPrank();
    }

    function _submit(
        bytes32 submissionHash
    ) internal {
        vm.prank(contractor);
        escrow.submitMilestone(0, submissionHash);
    }

    function test_ClientCanApproveSubmittedMilestone() public {
        _submit(keccak256("Delivery"));

        vm.prank(client);
        escrow.approveMilestone(0);

        SmartEscrow.Milestone memory milestone = escrow.getMilestone(0);

        assertEq(uint256(milestone.status), uint256(SmartEscrow.MilestoneStatus.Approved));

        assertEq(escrow.totalApproved(), REQUIRED_FUNDING);
        assertEq(address(escrow).balance, REQUIRED_FUNDING);
    }

    function test_ApprovalEmitsEvent() public {
        _submit(keccak256("Delivery"));

        vm.expectEmit(true, true, false, true);

        emit MilestoneApproved(0, client, REQUIRED_FUNDING);

        vm.prank(client);
        escrow.approveMilestone(0);
    }

    function test_ClientCanRejectSubmittedMilestone() public {
        bytes32 reasonHash = keccak256("Revision required");

        _submit(keccak256("Initial delivery"));

        vm.prank(client);
        escrow.rejectMilestone(0, reasonHash);

        SmartEscrow.Milestone memory milestone = escrow.getMilestone(0);

        assertEq(milestone.reviewHash, reasonHash);

        assertEq(uint256(milestone.status), uint256(SmartEscrow.MilestoneStatus.Rejected));

        assertEq(escrow.totalApproved(), 0);
        assertEq(address(escrow).balance, REQUIRED_FUNDING);
    }

    function test_RejectionEmitsEvent() public {
        bytes32 reasonHash = keccak256("Revision required");

        _submit(keccak256("Initial delivery"));

        vm.expectEmit(true, true, true, false);

        emit MilestoneRejected(0, client, reasonHash);

        vm.prank(client);
        escrow.rejectMilestone(0, reasonHash);
    }

    function test_ContractorCanResubmitRejectedMilestone() public {
        bytes32 updatedSubmission = keccak256("Updated delivery");

        _submit(keccak256("Initial delivery"));

        vm.prank(client);

        escrow.rejectMilestone(0, keccak256("Please update the tests"));

        vm.prank(contractor);
        escrow.submitMilestone(0, updatedSubmission);

        SmartEscrow.Milestone memory milestone = escrow.getMilestone(0);

        assertEq(milestone.submissionHash, updatedSubmission);

        assertEq(milestone.reviewHash, bytes32(0));

        assertEq(uint256(milestone.status), uint256(SmartEscrow.MilestoneStatus.Submitted));
    }

    function test_ClientCanApproveResubmittedMilestone() public {
        _submit(keccak256("Initial delivery"));

        vm.prank(client);

        escrow.rejectMilestone(0, keccak256("Revision required"));

        vm.prank(contractor);

        escrow.submitMilestone(0, keccak256("Updated delivery"));

        vm.prank(client);
        escrow.approveMilestone(0);

        assertEq(escrow.totalApproved(), REQUIRED_FUNDING);
    }

    function test_RevertWhenContractorApproves() public {
        _submit(keccak256("Delivery"));

        vm.prank(contractor);
        vm.expectRevert(SmartEscrow.Unauthorized.selector);

        escrow.approveMilestone(0);
    }

    function test_RevertWhenOutsiderRejects() public {
        _submit(keccak256("Delivery"));

        vm.prank(outsider);
        vm.expectRevert(SmartEscrow.Unauthorized.selector);

        escrow.rejectMilestone(0, keccak256("Unauthorized review"));
    }

    function test_RevertWhenApprovingPendingMilestone() public {
        vm.prank(client);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.InvalidMilestoneStatus.selector,
                SmartEscrow.MilestoneStatus.Submitted,
                SmartEscrow.MilestoneStatus.Pending
            )
        );

        escrow.approveMilestone(0);
    }

    function test_RevertWhenReviewHashIsEmpty() public {
        _submit(keccak256("Delivery"));

        vm.prank(client);
        vm.expectRevert(SmartEscrow.EmptyReviewHash.selector);

        escrow.rejectMilestone(0, bytes32(0));
    }

    function test_RevertWhenApprovingTwice() public {
        _submit(keccak256("Delivery"));

        vm.startPrank(client);

        escrow.approveMilestone(0);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.InvalidMilestoneStatus.selector,
                SmartEscrow.MilestoneStatus.Submitted,
                SmartEscrow.MilestoneStatus.Approved
            )
        );

        escrow.approveMilestone(0);

        vm.stopPrank();
    }

    function test_MultipleApprovalsTrackExactTotal() public {
        SmartEscrow secondEscrow = new SmartEscrow(client, contractor, arbiter, REQUIRED_FUNDING);

        vm.deal(client, REQUIRED_FUNDING);

        vm.startPrank(client);

        secondEscrow.fund{ value: REQUIRED_FUNDING }();

        secondEscrow.addMilestone(4 ether, block.timestamp + 10 days, keccak256("First milestone"));

        secondEscrow.addMilestone(6 ether, block.timestamp + 20 days, keccak256("Second milestone"));

        secondEscrow.activateSchedule();

        vm.stopPrank();

        vm.startPrank(contractor);

        secondEscrow.submitMilestone(0, keccak256("First delivery"));

        secondEscrow.submitMilestone(1, keccak256("Second delivery"));

        vm.stopPrank();

        vm.startPrank(client);

        secondEscrow.approveMilestone(0);
        assertEq(secondEscrow.totalApproved(), 4 ether);

        secondEscrow.approveMilestone(1);

        vm.stopPrank();

        assertEq(secondEscrow.totalApproved(), REQUIRED_FUNDING);

        assertEq(address(secondEscrow).balance, REQUIRED_FUNDING);
    }
}
