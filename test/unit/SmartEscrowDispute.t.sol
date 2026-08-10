// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { SmartEscrow } from "../../src/SmartEscrow.sol";
import { Test } from "forge-std/Test.sol";

contract SmartEscrowDisputeTest is Test {
    event DisputeOpened(
        uint256 indexed milestoneId, address indexed openedBy, bytes32 indexed evidenceHash
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
        uint256 milestoneId,
        bytes32 submissionHash
    ) internal {
        vm.prank(contractor);
        escrow.submitMilestone(milestoneId, submissionHash);
    }

    function _reject(
        uint256 milestoneId,
        bytes32 reviewHash
    ) internal {
        vm.prank(client);
        escrow.rejectMilestone(milestoneId, reviewHash);
    }

    function _approve(
        uint256 milestoneId
    ) internal {
        vm.prank(client);
        escrow.approveMilestone(milestoneId);
    }

    function test_ClientCanDisputeSubmittedMilestone() public {
        bytes32 evidenceHash = keccak256("Client dispute evidence");

        _submit(0, keccak256("First delivery"));

        vm.prank(client);
        escrow.openDispute(0, evidenceHash);

        SmartEscrow.Milestone memory milestone = escrow.getMilestone(0);

        assertEq(uint256(milestone.status), uint256(SmartEscrow.MilestoneStatus.Disputed));

        assertEq(uint256(escrow.state()), uint256(SmartEscrow.EscrowState.Disputed));

        assertTrue(escrow.hasActiveDispute());
        assertEq(escrow.activeDisputeMilestoneId(), 0);
        assertEq(escrow.disputeEvidenceHashes(0), evidenceHash);

        assertEq(address(escrow).balance, REQUIRED_FUNDING);
        assertEq(escrow.totalReleased(), 0);
    }

    function test_ContractorCanDisputeSubmittedMilestone() public {
        bytes32 evidenceHash = keccak256("Contractor dispute evidence");

        _submit(0, keccak256("First delivery"));

        vm.prank(contractor);
        escrow.openDispute(0, evidenceHash);

        SmartEscrow.Milestone memory milestone = escrow.getMilestone(0);

        assertEq(uint256(milestone.status), uint256(SmartEscrow.MilestoneStatus.Disputed));

        assertEq(uint256(escrow.state()), uint256(SmartEscrow.EscrowState.Disputed));

        assertTrue(escrow.hasActiveDispute());
        assertEq(escrow.activeDisputeMilestoneId(), 0);
        assertEq(escrow.disputeEvidenceHashes(0), evidenceHash);
    }

    function test_EitherPartyCanDisputeRejectedMilestone() public {
        _submit(0, keccak256("First delivery"));
        _reject(0, keccak256("Revision required"));

        bytes32 evidenceHash = keccak256("Rejected milestone dispute");

        vm.prank(contractor);
        escrow.openDispute(0, evidenceHash);

        SmartEscrow.Milestone memory milestone = escrow.getMilestone(0);

        assertEq(uint256(milestone.status), uint256(SmartEscrow.MilestoneStatus.Disputed));

        assertEq(uint256(escrow.state()), uint256(SmartEscrow.EscrowState.Disputed));
        assertEq(escrow.disputeEvidenceHashes(0), evidenceHash);
    }

    function test_DisputeOpeningEmitsEvent() public {
        bytes32 evidenceHash = keccak256("Event dispute evidence");

        _submit(0, keccak256("First delivery"));

        vm.expectEmit(true, true, true, false);
        emit DisputeOpened(0, contractor, evidenceHash);

        vm.prank(contractor);
        escrow.openDispute(0, evidenceHash);
    }

    function test_RevertWhenOutsiderOpensDispute() public {
        _submit(0, keccak256("First delivery"));

        vm.prank(outsider);
        vm.expectRevert(SmartEscrow.Unauthorized.selector);

        escrow.openDispute(0, keccak256("Outsider evidence"));
    }

    function test_RevertWhenArbiterOpensDispute() public {
        _submit(0, keccak256("First delivery"));

        vm.prank(arbiter);
        vm.expectRevert(SmartEscrow.Unauthorized.selector);

        escrow.openDispute(0, keccak256("Arbiter evidence"));
    }

    function test_RevertWhenDisputeEvidenceHashIsEmpty() public {
        _submit(0, keccak256("First delivery"));

        vm.prank(contractor);
        vm.expectRevert(SmartEscrow.EmptyDisputeEvidenceHash.selector);

        escrow.openDispute(0, bytes32(0));
    }

    function test_RevertWhenDisputingUnknownMilestone() public {
        vm.prank(contractor);

        vm.expectRevert(abi.encodeWithSelector(SmartEscrow.InvalidMilestoneId.selector, 2));

        escrow.openDispute(2, keccak256("Unknown milestone"));
    }

    function test_RevertWhenDisputingPendingMilestone() public {
        vm.prank(contractor);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.MilestoneNotDisputable.selector, SmartEscrow.MilestoneStatus.Pending
            )
        );

        escrow.openDispute(0, keccak256("Pending milestone evidence"));
    }

    function test_RevertWhenDisputingApprovedMilestone() public {
        _submit(0, keccak256("First delivery"));
        _approve(0);

        vm.prank(contractor);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.MilestoneNotDisputable.selector, SmartEscrow.MilestoneStatus.Approved
            )
        );

        escrow.openDispute(0, keccak256("Approved milestone evidence"));
    }

    function test_RevertWhenOpeningSecondDispute() public {
        _submit(0, keccak256("First delivery"));
        _submit(1, keccak256("Second delivery"));

        vm.prank(contractor);
        escrow.openDispute(0, keccak256("First dispute"));

        vm.prank(client);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.InvalidState.selector,
                SmartEscrow.EscrowState.Active,
                SmartEscrow.EscrowState.Disputed
            )
        );

        escrow.openDispute(1, keccak256("Second dispute"));
    }

    function test_DisputeFreezesOtherSubmissions() public {
        _submit(0, keccak256("First delivery"));

        vm.prank(contractor);
        escrow.openDispute(0, keccak256("First dispute"));

        vm.prank(contractor);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.InvalidState.selector,
                SmartEscrow.EscrowState.Active,
                SmartEscrow.EscrowState.Disputed
            )
        );

        escrow.submitMilestone(1, keccak256("Second delivery"));
    }

    function test_DisputeFreezesOtherReviews() public {
        _submit(0, keccak256("First delivery"));
        _submit(1, keccak256("Second delivery"));

        vm.prank(contractor);
        escrow.openDispute(0, keccak256("First dispute"));

        vm.prank(client);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.InvalidState.selector,
                SmartEscrow.EscrowState.Active,
                SmartEscrow.EscrowState.Disputed
            )
        );

        escrow.approveMilestone(1);
    }

    function test_DisputeFreezesApprovedPayments() public {
        _submit(0, keccak256("First delivery"));
        _submit(1, keccak256("Second delivery"));

        _approve(1);

        vm.prank(contractor);
        escrow.openDispute(0, keccak256("First dispute"));

        vm.prank(contractor);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.InvalidState.selector,
                SmartEscrow.EscrowState.Active,
                SmartEscrow.EscrowState.Disputed
            )
        );

        escrow.releaseMilestonePayment(1);
    }
}
