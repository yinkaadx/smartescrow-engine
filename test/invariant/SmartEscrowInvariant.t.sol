// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { SmartEscrow } from "../../src/SmartEscrow.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { Test } from "forge-std/Test.sol";

contract SmartEscrowInvariantHandler is Test {
    SmartEscrow public immutable escrow;

    address public immutable client;
    address public immutable contractor;
    address public immutable arbiter;

    uint256 public submitCalls;
    uint256 public approveCalls;
    uint256 public rejectCalls;
    uint256 public releaseCalls;
    uint256 public disputeCalls;
    uint256 public resolveCalls;

    mapping(uint256 milestoneId => bool observed) public observedPaid;
    mapping(uint256 milestoneId => bool observed) public observedRefunded;

    constructor(
        SmartEscrow escrow_,
        address client_,
        address contractor_,
        address arbiter_
    ) {
        escrow = escrow_;
        client = client_;
        contractor = contractor_;
        arbiter = arbiter_;
    }

    function submit(
        uint256 milestoneSeed,
        bytes32 submissionSeed
    ) external {
        if (escrow.state() != SmartEscrow.EscrowState.Active) return;

        uint256 milestoneId = _milestoneId(milestoneSeed);
        SmartEscrow.Milestone memory milestone = escrow.getMilestone(milestoneId);

        if (
            milestone.status != SmartEscrow.MilestoneStatus.Pending
                && milestone.status != SmartEscrow.MilestoneStatus.Rejected
        ) {
            return;
        }

        bytes32 submissionHash = _nonzeroHash(submissionSeed, milestoneId, submitCalls);

        vm.prank(contractor);
        escrow.submitMilestone(milestoneId, submissionHash);

        submitCalls++;
    }

    function approve(
        uint256 milestoneSeed
    ) external {
        if (escrow.state() != SmartEscrow.EscrowState.Active) return;

        uint256 milestoneId = _milestoneId(milestoneSeed);
        SmartEscrow.Milestone memory milestone = escrow.getMilestone(milestoneId);

        if (milestone.status != SmartEscrow.MilestoneStatus.Submitted) {
            return;
        }

        vm.prank(client);
        escrow.approveMilestone(milestoneId);

        approveCalls++;
    }

    function reject(
        uint256 milestoneSeed,
        bytes32 reviewSeed
    ) external {
        if (escrow.state() != SmartEscrow.EscrowState.Active) return;

        uint256 milestoneId = _milestoneId(milestoneSeed);
        SmartEscrow.Milestone memory milestone = escrow.getMilestone(milestoneId);

        if (milestone.status != SmartEscrow.MilestoneStatus.Submitted) {
            return;
        }

        bytes32 reviewHash = _nonzeroHash(reviewSeed, milestoneId, rejectCalls);

        vm.prank(client);
        escrow.rejectMilestone(milestoneId, reviewHash);

        rejectCalls++;
    }

    function release(
        uint256 milestoneSeed
    ) external {
        if (escrow.state() != SmartEscrow.EscrowState.Active) return;

        uint256 milestoneId = _milestoneId(milestoneSeed);
        SmartEscrow.Milestone memory milestone = escrow.getMilestone(milestoneId);

        if (milestone.status != SmartEscrow.MilestoneStatus.Approved) {
            return;
        }

        vm.prank(contractor);
        escrow.releaseMilestonePayment(milestoneId);

        observedPaid[milestoneId] = true;
        releaseCalls++;
    }

    function openDispute(
        uint256 milestoneSeed,
        bytes32 evidenceSeed,
        bool openedByClient
    ) external {
        if (escrow.state() != SmartEscrow.EscrowState.Active) return;
        if (escrow.hasActiveDispute()) return;

        uint256 milestoneId = _milestoneId(milestoneSeed);
        SmartEscrow.Milestone memory milestone = escrow.getMilestone(milestoneId);

        if (
            milestone.status != SmartEscrow.MilestoneStatus.Submitted
                && milestone.status != SmartEscrow.MilestoneStatus.Rejected
        ) {
            return;
        }

        bytes32 evidenceHash = _nonzeroHash(evidenceSeed, milestoneId, disputeCalls);

        address openedBy = openedByClient ? client : contractor;

        vm.prank(openedBy);
        escrow.openDispute(milestoneId, evidenceHash);

        disputeCalls++;
    }

    function resolve(
        bool awardContractor,
        bytes32 resolutionSeed
    ) external {
        if (escrow.state() != SmartEscrow.EscrowState.Disputed) return;
        if (!escrow.hasActiveDispute()) return;

        uint256 milestoneId = escrow.activeDisputeMilestoneId();

        bytes32 resolutionHash = _nonzeroHash(resolutionSeed, milestoneId, resolveCalls);

        SmartEscrow.DisputeRuling ruling = awardContractor
            ? SmartEscrow.DisputeRuling.ContractorAward
            : SmartEscrow.DisputeRuling.ClientRefund;

        vm.prank(arbiter);
        escrow.resolveDispute(ruling, resolutionHash);

        if (awardContractor) {
            observedPaid[milestoneId] = true;
        } else {
            observedRefunded[milestoneId] = true;
        }

        resolveCalls++;
    }

    function _milestoneId(
        uint256 milestoneSeed
    ) internal view returns (uint256) {
        return bound(milestoneSeed, 0, escrow.milestoneCount() - 1);
    }

    function _nonzeroHash(
        bytes32 seed,
        uint256 milestoneId,
        uint256 callCount
    ) internal pure returns (bytes32 result) {
        result = keccak256(abi.encode(seed, milestoneId, callCount, "SmartEscrow invariant"));

        if (result == bytes32(0)) {
            result = bytes32(uint256(1));
        }
    }
}

contract SmartEscrowInvariantTest is StdInvariant, Test {
    SmartEscrow internal escrow;
    SmartEscrowInvariantHandler internal handler;

    address internal client = makeAddr("invariant-client");
    address internal contractor = makeAddr("invariant-contractor");
    address internal arbiter = makeAddr("invariant-arbiter");

    uint256 internal constant REQUIRED_FUNDING = 12 ether;

    function setUp() public {
        escrow = new SmartEscrow(client, contractor, arbiter, REQUIRED_FUNDING);

        vm.deal(client, REQUIRED_FUNDING);

        vm.startPrank(client);

        escrow.fund{ value: REQUIRED_FUNDING }();

        escrow.addMilestone(
            3 ether, block.timestamp + 100 days, keccak256("Invariant milestone one")
        );

        escrow.addMilestone(
            4 ether, block.timestamp + 200 days, keccak256("Invariant milestone two")
        );

        escrow.addMilestone(
            5 ether, block.timestamp + 300 days, keccak256("Invariant milestone three")
        );

        escrow.activateSchedule();

        vm.stopPrank();

        handler = new SmartEscrowInvariantHandler(escrow, client, contractor, arbiter);

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.submit.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.reject.selector;
        selectors[3] = handler.release.selector;
        selectors[4] = handler.openDispute.selector;
        selectors[5] = handler.resolve.selector;

        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
    }

    function invariant_SettlementNeverExceedsDeposits() public view {
        uint256 totalSettled = escrow.totalReleased() + escrow.totalRefunded();

        assertLe(totalSettled, escrow.totalDeposited());
    }

    function invariant_BalanceMatchesUnsettledFunds() public view {
        uint256 totalSettled = escrow.totalReleased() + escrow.totalRefunded();

        uint256 expectedBalance = escrow.totalDeposited() - totalSettled;

        assertEq(address(escrow).balance, expectedBalance);
    }

    function invariant_MilestoneAllocationIsConserved() public view {
        uint256 count = escrow.milestoneCount();
        uint256 milestoneAmountSum;

        for (uint256 i = 0; i < count; i++) {
            milestoneAmountSum += escrow.getMilestone(i).amount;
        }

        assertEq(milestoneAmountSum, escrow.totalAllocated());
        assertEq(escrow.totalAllocated(), escrow.requiredFunding());
        assertEq(escrow.totalDeposited(), escrow.requiredFunding());
    }

    function invariant_SettlementMatchesTerminalMilestones() public view {
        uint256 count = escrow.milestoneCount();
        uint256 paidAmount;
        uint256 refundedAmount;

        for (uint256 i = 0; i < count; i++) {
            SmartEscrow.Milestone memory milestone = escrow.getMilestone(i);

            if (milestone.status == SmartEscrow.MilestoneStatus.Paid) {
                paidAmount += milestone.amount;
            }

            if (milestone.status == SmartEscrow.MilestoneStatus.Refunded) {
                refundedAmount += milestone.amount;
            }
        }

        assertEq(paidAmount, escrow.totalReleased());
        assertEq(refundedAmount, escrow.totalRefunded());
    }

    function invariant_AtMostOneMilestoneIsDisputed() public view {
        uint256 count = escrow.milestoneCount();
        uint256 disputedCount;

        for (uint256 i = 0; i < count; i++) {
            SmartEscrow.Milestone memory milestone = escrow.getMilestone(i);

            if (milestone.status == SmartEscrow.MilestoneStatus.Disputed) {
                disputedCount++;
            }
        }

        assertLe(disputedCount, 1);
    }

    function invariant_DisputeTrackingIsConsistent() public view {
        uint256 count = escrow.milestoneCount();
        uint256 disputedCount;
        uint256 disputedMilestoneId;

        for (uint256 i = 0; i < count; i++) {
            SmartEscrow.Milestone memory milestone = escrow.getMilestone(i);

            if (milestone.status == SmartEscrow.MilestoneStatus.Disputed) {
                disputedCount++;
                disputedMilestoneId = i;
            }
        }

        bool hasActiveDispute = escrow.hasActiveDispute();
        bool stateIsDisputed = escrow.state() == SmartEscrow.EscrowState.Disputed;

        assertEq(hasActiveDispute, stateIsDisputed);

        if (hasActiveDispute) {
            assertEq(disputedCount, 1);
            assertEq(escrow.activeDisputeMilestoneId(), disputedMilestoneId);

            assertTrue(escrow.disputeEvidenceHashes(disputedMilestoneId) != bytes32(0));
        } else {
            assertEq(disputedCount, 0);
        }
    }

    function invariant_CompletedEscrowIsFullySettled() public view {
        if (escrow.state() != SmartEscrow.EscrowState.Completed) return;

        uint256 totalSettled = escrow.totalReleased() + escrow.totalRefunded();

        assertEq(totalSettled, escrow.totalDeposited());
        assertEq(address(escrow).balance, 0);
        assertFalse(escrow.hasActiveDispute());
    }

    function invariant_TerminalMilestonesNeverRegress() public view {
        uint256 count = escrow.milestoneCount();

        for (uint256 i = 0; i < count; i++) {
            SmartEscrow.MilestoneStatus status = escrow.getMilestone(i).status;

            if (handler.observedPaid(i)) {
                assertEq(uint256(status), uint256(SmartEscrow.MilestoneStatus.Paid));
            }

            if (handler.observedRefunded(i)) {
                assertEq(uint256(status), uint256(SmartEscrow.MilestoneStatus.Refunded));
            }

            assertFalse(handler.observedPaid(i) && handler.observedRefunded(i));
        }
    }
}
