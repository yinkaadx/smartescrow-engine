// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { SmartEscrow } from "../../src/SmartEscrow.sol";
import { Test } from "forge-std/Test.sol";

contract RejectingContractor {
    function releasePayment(
        SmartEscrow escrow,
        uint256 milestoneId
    ) external {
        escrow.releaseMilestonePayment(milestoneId);
    }

    receive() external payable {
        revert();
    }
}

contract SmartEscrowPaymentTest is Test {
    event MilestonePaid(uint256 indexed milestoneId, address indexed contractor, uint256 amount);

    event EscrowCompleted(address indexed contractor, uint256 totalReleased);

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

        firstDeadline = block.timestamp + 10 days;
        secondDeadline = block.timestamp + 20 days;

        vm.deal(client, REQUIRED_FUNDING);

        vm.startPrank(client);

        escrow.fund{ value: REQUIRED_FUNDING }();

        escrow.addMilestone(4 ether, firstDeadline, keccak256("First milestone"));
        escrow.addMilestone(6 ether, secondDeadline, keccak256("Second milestone"));

        escrow.activateSchedule();

        vm.stopPrank();
    }

    function _submitAndApprove(
        uint256 milestoneId,
        bytes32 submissionHash
    ) internal {
        vm.prank(contractor);
        escrow.submitMilestone(milestoneId, submissionHash);

        vm.prank(client);
        escrow.approveMilestone(milestoneId);
    }

    function test_ContractorCanReleaseApprovedMilestone() public {
        _submitAndApprove(0, keccak256("First delivery"));

        uint256 contractorBalanceBefore = contractor.balance;

        vm.prank(contractor);
        escrow.releaseMilestonePayment(0);

        SmartEscrow.Milestone memory milestone = escrow.getMilestone(0);

        assertEq(uint256(milestone.status), uint256(SmartEscrow.MilestoneStatus.Paid));

        assertEq(contractor.balance, contractorBalanceBefore + 4 ether);
        assertEq(address(escrow).balance, 6 ether);

        assertEq(escrow.totalApproved(), 4 ether);
        assertEq(escrow.totalReleased(), 4 ether);

        assertEq(uint256(escrow.state()), uint256(SmartEscrow.EscrowState.Active));
    }

    function test_PaymentEmitsMilestonePaidEvent() public {
        _submitAndApprove(0, keccak256("First delivery"));

        vm.expectEmit(true, true, false, true);
        emit MilestonePaid(0, contractor, 4 ether);

        vm.prank(contractor);
        escrow.releaseMilestonePayment(0);
    }

    function test_RevertWhenClientReleasesPayment() public {
        _submitAndApprove(0, keccak256("First delivery"));

        vm.prank(client);
        vm.expectRevert(SmartEscrow.Unauthorized.selector);

        escrow.releaseMilestonePayment(0);
    }

    function test_RevertWhenOutsiderReleasesPayment() public {
        _submitAndApprove(0, keccak256("First delivery"));

        vm.prank(outsider);
        vm.expectRevert(SmartEscrow.Unauthorized.selector);

        escrow.releaseMilestonePayment(0);
    }

    function test_RevertWhenReleasingPendingMilestone() public {
        vm.prank(contractor);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.InvalidMilestoneStatus.selector,
                SmartEscrow.MilestoneStatus.Approved,
                SmartEscrow.MilestoneStatus.Pending
            )
        );

        escrow.releaseMilestonePayment(0);
    }

    function test_RevertWhenReleasingSubmittedMilestone() public {
        vm.prank(contractor);
        escrow.submitMilestone(0, keccak256("Unreviewed delivery"));

        vm.prank(contractor);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.InvalidMilestoneStatus.selector,
                SmartEscrow.MilestoneStatus.Approved,
                SmartEscrow.MilestoneStatus.Submitted
            )
        );

        escrow.releaseMilestonePayment(0);
    }

    function test_RevertWhenReleasingUnknownMilestone() public {
        vm.prank(contractor);

        vm.expectRevert(abi.encodeWithSelector(SmartEscrow.InvalidMilestoneId.selector, 2));

        escrow.releaseMilestonePayment(2);
    }

    function test_RevertWhenReleasingMilestoneTwice() public {
        _submitAndApprove(0, keccak256("First delivery"));

        vm.startPrank(contractor);

        escrow.releaseMilestonePayment(0);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.InvalidMilestoneStatus.selector,
                SmartEscrow.MilestoneStatus.Approved,
                SmartEscrow.MilestoneStatus.Paid
            )
        );

        escrow.releaseMilestonePayment(0);

        vm.stopPrank();

        assertEq(contractor.balance, 4 ether);
        assertEq(address(escrow).balance, 6 ether);
        assertEq(escrow.totalReleased(), 4 ether);
    }

    function test_MultiplePaymentsTrackExactTotal() public {
        _submitAndApprove(0, keccak256("First delivery"));
        _submitAndApprove(1, keccak256("Second delivery"));

        vm.startPrank(contractor);

        escrow.releaseMilestonePayment(0);

        assertEq(escrow.totalReleased(), 4 ether);
        assertEq(address(escrow).balance, 6 ether);

        escrow.releaseMilestonePayment(1);

        vm.stopPrank();

        assertEq(escrow.totalReleased(), REQUIRED_FUNDING);
        assertEq(contractor.balance, REQUIRED_FUNDING);
        assertEq(address(escrow).balance, 0);

        assertEq(uint256(escrow.state()), uint256(SmartEscrow.EscrowState.Completed));
    }

    function test_FinalPaymentEmitsEscrowCompletedEvent() public {
        _submitAndApprove(0, keccak256("First delivery"));
        _submitAndApprove(1, keccak256("Second delivery"));

        vm.prank(contractor);
        escrow.releaseMilestonePayment(0);

        vm.expectEmit(true, false, false, true);
        emit EscrowCompleted(contractor, REQUIRED_FUNDING);

        vm.prank(contractor);
        escrow.releaseMilestonePayment(1);
    }

    function test_FailedTransferRollsBackAllPaymentState() public {
        RejectingContractor rejectingContractor = new RejectingContractor();

        SmartEscrow rejectingEscrow =
            new SmartEscrow(client, address(rejectingContractor), arbiter, REQUIRED_FUNDING);

        vm.deal(client, REQUIRED_FUNDING);

        vm.startPrank(client);

        rejectingEscrow.fund{ value: REQUIRED_FUNDING }();

        rejectingEscrow.addMilestone(
            REQUIRED_FUNDING, block.timestamp + 10 days, keccak256("Rejecting milestone")
        );

        rejectingEscrow.activateSchedule();

        vm.stopPrank();

        vm.prank(address(rejectingContractor));
        rejectingEscrow.submitMilestone(0, keccak256("Rejecting delivery"));

        vm.prank(client);
        rejectingEscrow.approveMilestone(0);

        vm.expectRevert(SmartEscrow.PaymentTransferFailed.selector);

        rejectingContractor.releasePayment(rejectingEscrow, 0);

        SmartEscrow.Milestone memory milestone = rejectingEscrow.getMilestone(0);

        assertEq(uint256(milestone.status), uint256(SmartEscrow.MilestoneStatus.Approved));

        assertEq(rejectingEscrow.totalApproved(), REQUIRED_FUNDING);
        assertEq(rejectingEscrow.totalReleased(), 0);
        assertEq(address(rejectingEscrow).balance, REQUIRED_FUNDING);
        assertEq(address(rejectingContractor).balance, 0);

        assertEq(uint256(rejectingEscrow.state()), uint256(SmartEscrow.EscrowState.Active));
    }
}
