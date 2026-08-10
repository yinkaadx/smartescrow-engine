// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { SmartEscrow } from "../../src/SmartEscrow.sol";
import { Test } from "forge-std/Test.sol";

contract RejectingDisputeParty {
    function fundEscrow(
        SmartEscrow escrow,
        uint256 amount
    ) external {
        escrow.fund{ value: amount }();
    }

    function addEscrowMilestone(
        SmartEscrow escrow,
        uint256 amount,
        uint256 deadline,
        bytes32 detailsHash
    ) external {
        escrow.addMilestone(amount, deadline, detailsHash);
    }

    function activateEscrow(
        SmartEscrow escrow
    ) external {
        escrow.activateSchedule();
    }

    function submitEscrowMilestone(
        SmartEscrow escrow,
        uint256 milestoneId,
        bytes32 submissionHash
    ) external {
        escrow.submitMilestone(milestoneId, submissionHash);
    }

    function openEscrowDispute(
        SmartEscrow escrow,
        uint256 milestoneId,
        bytes32 evidenceHash
    ) external {
        escrow.openDispute(milestoneId, evidenceHash);
    }

    receive() external payable {
        revert();
    }
}

contract SmartEscrowResolutionTest is Test {
    event DisputeResolved(
        uint256 indexed milestoneId,
        address indexed arbiter,
        SmartEscrow.DisputeRuling indexed ruling,
        bytes32 resolutionHash,
        uint256 amount
    );

    event EscrowCompleted(address indexed recipient, uint256 totalSettled);

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

    function _submit(
        SmartEscrow target,
        address targetContractor,
        uint256 milestoneId,
        bytes32 submissionHash
    ) internal {
        vm.prank(targetContractor);
        target.submitMilestone(milestoneId, submissionHash);
    }

    function _openDispute(
        SmartEscrow target,
        address openedBy,
        uint256 milestoneId,
        bytes32 evidenceHash
    ) internal {
        vm.prank(openedBy);
        target.openDispute(milestoneId, evidenceHash);
    }

    function _submitAndDispute(
        uint256 milestoneId
    ) internal {
        _submit(escrow, contractor, milestoneId, keccak256("Delivery evidence"));

        _openDispute(escrow, contractor, milestoneId, keccak256("Dispute evidence"));
    }

    function test_ArbiterCanAwardDisputeToContractor() public {
        _submitAndDispute(0);

        bytes32 resolutionHash = keccak256("Contractor ruling");
        uint256 contractorBalanceBefore = contractor.balance;

        vm.prank(arbiter);
        escrow.resolveDispute(SmartEscrow.DisputeRuling.ContractorAward, resolutionHash);

        SmartEscrow.Milestone memory milestone = escrow.getMilestone(0);

        assertEq(uint256(milestone.status), uint256(SmartEscrow.MilestoneStatus.Paid));

        assertEq(contractor.balance, contractorBalanceBefore + 4 ether);
        assertEq(address(escrow).balance, 6 ether);

        assertEq(escrow.totalReleased(), 4 ether);
        assertEq(escrow.totalRefunded(), 0);
        assertEq(escrow.resolutionHashes(0), resolutionHash);

        assertFalse(escrow.hasActiveDispute());
        assertEq(escrow.activeDisputeMilestoneId(), 0);

        assertEq(uint256(escrow.state()), uint256(SmartEscrow.EscrowState.Active));
    }

    function test_ArbiterCanRefundDisputeToClient() public {
        _submitAndDispute(0);

        bytes32 resolutionHash = keccak256("Client ruling");
        uint256 clientBalanceBefore = client.balance;

        vm.prank(arbiter);
        escrow.resolveDispute(SmartEscrow.DisputeRuling.ClientRefund, resolutionHash);

        SmartEscrow.Milestone memory milestone = escrow.getMilestone(0);

        assertEq(uint256(milestone.status), uint256(SmartEscrow.MilestoneStatus.Refunded));

        assertEq(client.balance, clientBalanceBefore + 4 ether);
        assertEq(address(escrow).balance, 6 ether);

        assertEq(escrow.totalReleased(), 0);
        assertEq(escrow.totalRefunded(), 4 ether);
        assertEq(escrow.resolutionHashes(0), resolutionHash);

        assertFalse(escrow.hasActiveDispute());
        assertEq(escrow.activeDisputeMilestoneId(), 0);

        assertEq(uint256(escrow.state()), uint256(SmartEscrow.EscrowState.Active));
    }

    function test_ContractorAwardEmitsResolutionEvent() public {
        _submitAndDispute(0);

        bytes32 resolutionHash = keccak256("Contractor ruling");

        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(
            0, arbiter, SmartEscrow.DisputeRuling.ContractorAward, resolutionHash, 4 ether
        );

        vm.prank(arbiter);
        escrow.resolveDispute(SmartEscrow.DisputeRuling.ContractorAward, resolutionHash);
    }

    function test_ClientRefundEmitsResolutionEvent() public {
        _submitAndDispute(0);

        bytes32 resolutionHash = keccak256("Client ruling");

        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(
            0, arbiter, SmartEscrow.DisputeRuling.ClientRefund, resolutionHash, 4 ether
        );

        vm.prank(arbiter);
        escrow.resolveDispute(SmartEscrow.DisputeRuling.ClientRefund, resolutionHash);
    }

    function test_RevertWhenClientResolvesDispute() public {
        _submitAndDispute(0);

        vm.prank(client);
        vm.expectRevert(SmartEscrow.Unauthorized.selector);

        escrow.resolveDispute(
            SmartEscrow.DisputeRuling.ClientRefund, keccak256("Unauthorized ruling")
        );
    }

    function test_RevertWhenContractorResolvesDispute() public {
        _submitAndDispute(0);

        vm.prank(contractor);
        vm.expectRevert(SmartEscrow.Unauthorized.selector);

        escrow.resolveDispute(
            SmartEscrow.DisputeRuling.ContractorAward, keccak256("Unauthorized ruling")
        );
    }

    function test_RevertWhenOutsiderResolvesDispute() public {
        _submitAndDispute(0);

        vm.prank(outsider);
        vm.expectRevert(SmartEscrow.Unauthorized.selector);

        escrow.resolveDispute(
            SmartEscrow.DisputeRuling.ContractorAward, keccak256("Unauthorized ruling")
        );
    }

    function test_RevertWhenResolutionHashIsEmpty() public {
        _submitAndDispute(0);

        vm.prank(arbiter);
        vm.expectRevert(SmartEscrow.EmptyResolutionHash.selector);

        escrow.resolveDispute(SmartEscrow.DisputeRuling.ContractorAward, bytes32(0));
    }

    function test_RevertWhenNoDisputeIsActive() public {
        vm.prank(arbiter);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.InvalidState.selector,
                SmartEscrow.EscrowState.Disputed,
                SmartEscrow.EscrowState.Active
            )
        );

        escrow.resolveDispute(
            SmartEscrow.DisputeRuling.ContractorAward, keccak256("No active dispute")
        );
    }

    function test_RevertWhenResolvingDisputeTwice() public {
        _submitAndDispute(0);

        vm.prank(arbiter);
        escrow.resolveDispute(SmartEscrow.DisputeRuling.ContractorAward, keccak256("First ruling"));

        vm.prank(arbiter);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.InvalidState.selector,
                SmartEscrow.EscrowState.Disputed,
                SmartEscrow.EscrowState.Active
            )
        );

        escrow.resolveDispute(SmartEscrow.DisputeRuling.ContractorAward, keccak256("Second ruling"));
    }

    function test_FinalContractorAwardCompletesEscrow() public {
        _submitAndDispute(0);

        vm.prank(arbiter);
        escrow.resolveDispute(
            SmartEscrow.DisputeRuling.ContractorAward, keccak256("First contractor ruling")
        );

        _submit(escrow, contractor, 1, keccak256("Second delivery"));

        _openDispute(escrow, contractor, 1, keccak256("Second dispute"));

        vm.expectEmit(true, false, false, true);
        emit EscrowCompleted(contractor, REQUIRED_FUNDING);

        vm.prank(arbiter);
        escrow.resolveDispute(
            SmartEscrow.DisputeRuling.ContractorAward, keccak256("Second contractor ruling")
        );

        assertEq(escrow.totalReleased(), REQUIRED_FUNDING);
        assertEq(escrow.totalRefunded(), 0);
        assertEq(address(escrow).balance, 0);
        assertEq(contractor.balance, REQUIRED_FUNDING);

        assertEq(uint256(escrow.state()), uint256(SmartEscrow.EscrowState.Completed));
    }

    function test_MixedPaymentAndRefundCompleteEscrow() public {
        _submit(escrow, contractor, 0, keccak256("First delivery"));

        vm.prank(client);
        escrow.approveMilestone(0);

        vm.prank(contractor);
        escrow.releaseMilestonePayment(0);

        _submit(escrow, contractor, 1, keccak256("Second delivery"));

        _openDispute(escrow, client, 1, keccak256("Second milestone dispute"));

        uint256 clientBalanceBefore = client.balance;

        vm.expectEmit(true, false, false, true);
        emit EscrowCompleted(client, REQUIRED_FUNDING);

        vm.prank(arbiter);
        escrow.resolveDispute(
            SmartEscrow.DisputeRuling.ClientRefund, keccak256("Refund second milestone")
        );

        assertEq(escrow.totalReleased(), 4 ether);
        assertEq(escrow.totalRefunded(), 6 ether);
        assertEq(contractor.balance, 4 ether);
        assertEq(client.balance, clientBalanceBefore + 6 ether);
        assertEq(address(escrow).balance, 0);

        assertEq(uint256(escrow.state()), uint256(SmartEscrow.EscrowState.Completed));
    }

    function test_RefundThenOrdinaryPaymentCompletesEscrow() public {
        _submit(escrow, contractor, 0, keccak256("First delivery"));

        _openDispute(escrow, client, 0, keccak256("First milestone dispute"));

        vm.prank(arbiter);
        escrow.resolveDispute(
            SmartEscrow.DisputeRuling.ClientRefund, keccak256("Refund first milestone")
        );

        assertEq(escrow.totalRefunded(), 4 ether);
        assertEq(escrow.totalReleased(), 0);

        assertEq(uint256(escrow.state()), uint256(SmartEscrow.EscrowState.Active));

        _submit(escrow, contractor, 1, keccak256("Second delivery"));

        vm.prank(client);
        escrow.approveMilestone(1);

        vm.expectEmit(true, false, false, true);
        emit EscrowCompleted(contractor, REQUIRED_FUNDING);

        vm.prank(contractor);
        escrow.releaseMilestonePayment(1);

        assertEq(escrow.totalRefunded(), 4 ether);
        assertEq(escrow.totalReleased(), 6 ether);
        assertEq(client.balance, 4 ether);
        assertEq(contractor.balance, 6 ether);
        assertEq(address(escrow).balance, 0);

        assertEq(uint256(escrow.state()), uint256(SmartEscrow.EscrowState.Completed));
    }

    function test_FailedContractorAwardRollsBackResolution() public {
        RejectingDisputeParty rejectingContractor = new RejectingDisputeParty();

        SmartEscrow rejectingEscrow =
            new SmartEscrow(client, address(rejectingContractor), arbiter, REQUIRED_FUNDING);

        vm.deal(client, REQUIRED_FUNDING);

        vm.startPrank(client);

        rejectingEscrow.fund{ value: REQUIRED_FUNDING }();

        rejectingEscrow.addMilestone(
            REQUIRED_FUNDING, block.timestamp + 10 days, keccak256("Rejecting contractor milestone")
        );

        rejectingEscrow.activateSchedule();

        vm.stopPrank();

        rejectingContractor.submitEscrowMilestone(
            rejectingEscrow, 0, keccak256("Rejecting contractor delivery")
        );

        rejectingContractor.openEscrowDispute(
            rejectingEscrow, 0, keccak256("Rejecting contractor dispute")
        );

        vm.prank(arbiter);
        vm.expectRevert(SmartEscrow.PaymentTransferFailed.selector);

        rejectingEscrow.resolveDispute(
            SmartEscrow.DisputeRuling.ContractorAward, keccak256("Failed contractor award")
        );

        SmartEscrow.Milestone memory milestone = rejectingEscrow.getMilestone(0);

        assertEq(uint256(milestone.status), uint256(SmartEscrow.MilestoneStatus.Disputed));

        assertTrue(rejectingEscrow.hasActiveDispute());
        assertEq(rejectingEscrow.activeDisputeMilestoneId(), 0);

        assertEq(rejectingEscrow.totalReleased(), 0);
        assertEq(rejectingEscrow.totalRefunded(), 0);
        assertEq(rejectingEscrow.resolutionHashes(0), bytes32(0));

        assertEq(address(rejectingEscrow).balance, REQUIRED_FUNDING);
        assertEq(address(rejectingContractor).balance, 0);

        assertEq(uint256(rejectingEscrow.state()), uint256(SmartEscrow.EscrowState.Disputed));
    }

    function test_FailedClientRefundRollsBackResolution() public {
        RejectingDisputeParty rejectingClient = new RejectingDisputeParty();

        SmartEscrow rejectingEscrow =
            new SmartEscrow(address(rejectingClient), contractor, arbiter, REQUIRED_FUNDING);

        vm.deal(address(rejectingClient), REQUIRED_FUNDING);

        rejectingClient.fundEscrow(rejectingEscrow, REQUIRED_FUNDING);

        rejectingClient.addEscrowMilestone(
            rejectingEscrow,
            REQUIRED_FUNDING,
            block.timestamp + 10 days,
            keccak256("Rejecting client milestone")
        );

        rejectingClient.activateEscrow(rejectingEscrow);

        _submit(rejectingEscrow, contractor, 0, keccak256("Rejecting client delivery"));

        rejectingClient.openEscrowDispute(rejectingEscrow, 0, keccak256("Rejecting client dispute"));

        vm.prank(arbiter);
        vm.expectRevert(SmartEscrow.PaymentTransferFailed.selector);

        rejectingEscrow.resolveDispute(
            SmartEscrow.DisputeRuling.ClientRefund, keccak256("Failed client refund")
        );

        SmartEscrow.Milestone memory milestone = rejectingEscrow.getMilestone(0);

        assertEq(uint256(milestone.status), uint256(SmartEscrow.MilestoneStatus.Disputed));

        assertTrue(rejectingEscrow.hasActiveDispute());
        assertEq(rejectingEscrow.activeDisputeMilestoneId(), 0);

        assertEq(rejectingEscrow.totalReleased(), 0);
        assertEq(rejectingEscrow.totalRefunded(), 0);
        assertEq(rejectingEscrow.resolutionHashes(0), bytes32(0));

        assertEq(address(rejectingEscrow).balance, REQUIRED_FUNDING);
        assertEq(address(rejectingClient).balance, 0);

        assertEq(uint256(rejectingEscrow.state()), uint256(SmartEscrow.EscrowState.Disputed));
    }
}
