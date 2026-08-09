// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title SmartEscrow
/// @notice Provides controlled ETH funding and milestone scheduling for a
/// client-contractor escrow agreement.
/// @dev Payment release, disputes, and refunds are introduced incrementally
/// with unit, fuzz, and invariant tests.
contract SmartEscrow {
    uint256 public constant MAX_MILESTONES = 50;

    enum EscrowState {
        Created,
        Funded,
        Active,
        Disputed,
        Completed,
        Cancelled
    }

    enum MilestoneStatus {
        Pending,
        Submitted,
        Approved,
        Rejected,
        Paid,
        Disputed,
        Refunded
    }

    struct Milestone {
        uint256 amount;
        uint256 deadline;
        bytes32 detailsHash;
        bytes32 submissionHash;
        bytes32 reviewHash;
        MilestoneStatus status;
    }

    error ZeroAddress();
    error ZeroFundingRequirement();
    error DuplicateParty();
    error Unauthorized();
    error IncorrectFundingAmount(uint256 expected, uint256 received);
    error InvalidState(EscrowState expected, EscrowState actual);
    error DirectPaymentNotAllowed();
    error ZeroMilestoneAmount();
    error InvalidDeadline(uint256 supplied, uint256 currentTime);
    error AllocationExceedsFunding(uint256 available, uint256 requested);
    error MilestoneLimitReached(uint256 maximum);
    error InvalidMilestoneId(uint256 milestoneId);
    error ScheduleNotFullyAllocated(uint256 allocated, uint256 required);
    error EmptySubmissionHash();
    error EmptyReviewHash();
    error MilestoneDeadlinePassed(uint256 deadline, uint256 currentTime);
    error InvalidMilestoneStatus(MilestoneStatus expected, MilestoneStatus actual);

    event EscrowCreated(
        address indexed client,
        address indexed contractor,
        address indexed arbiter,
        uint256 requiredFunding
    );

    event EscrowFunded(address indexed client, uint256 amount);

    event MilestoneAdded(
        uint256 indexed milestoneId, uint256 amount, uint256 deadline, bytes32 indexed detailsHash
    );

    event ScheduleActivated(address indexed client);

    event MilestoneSubmitted(
        uint256 indexed milestoneId, address indexed contractor, bytes32 indexed submissionHash
    );

    event MilestoneApproved(uint256 indexed milestoneId, address indexed client, uint256 amount);

    event MilestoneRejected(
        uint256 indexed milestoneId, address indexed client, bytes32 indexed reviewHash
    );

    address public immutable client;
    address public immutable contractor;
    address public immutable arbiter;

    uint256 public immutable requiredFunding;
    uint256 public totalDeposited;
    uint256 public totalAllocated;
    uint256 public totalApproved;

    EscrowState public state;

    Milestone[] private milestones;

    modifier onlyClient() {
        if (msg.sender != client) revert Unauthorized();
        _;
    }

    modifier onlyContractor() {
        if (msg.sender != contractor) revert Unauthorized();
        _;
    }

    modifier onlyArbiter() {
        if (msg.sender != arbiter) revert Unauthorized();
        _;
    }

    constructor(
        address client_,
        address contractor_,
        address arbiter_,
        uint256 requiredFunding_
    ) {
        if (client_ == address(0) || contractor_ == address(0) || arbiter_ == address(0)) {
            revert ZeroAddress();
        }

        if (client_ == contractor_ || client_ == arbiter_ || contractor_ == arbiter_) {
            revert DuplicateParty();
        }

        if (requiredFunding_ == 0) revert ZeroFundingRequirement();

        client = client_;
        contractor = contractor_;
        arbiter = arbiter_;
        requiredFunding = requiredFunding_;
        state = EscrowState.Created;

        emit EscrowCreated(client_, contractor_, arbiter_, requiredFunding_);
    }

    /// @notice Deposits the complete agreed escrow amount.
    function fund() external payable onlyClient {
        if (state != EscrowState.Created) {
            revert InvalidState(EscrowState.Created, state);
        }

        if (msg.value != requiredFunding) {
            revert IncorrectFundingAmount(requiredFunding, msg.value);
        }

        totalDeposited = msg.value;
        state = EscrowState.Funded;

        emit EscrowFunded(msg.sender, msg.value);
    }

    /// @notice Adds a milestone to a funded escrow.
    function addMilestone(
        uint256 amount,
        uint256 deadline,
        bytes32 detailsHash
    ) external onlyClient returns (uint256 milestoneId) {
        if (state != EscrowState.Funded) {
            revert InvalidState(EscrowState.Funded, state);
        }

        if (amount == 0) revert ZeroMilestoneAmount();

        // Milestone deadlines use day-scale scheduling, not randomness or
        // a fine-grained competitive cutoff.
        // forge-lint: disable-next-line(block-timestamp)
        if (deadline <= block.timestamp) {
            revert InvalidDeadline(deadline, block.timestamp);
        }

        if (milestones.length >= MAX_MILESTONES) {
            revert MilestoneLimitReached(MAX_MILESTONES);
        }

        uint256 available = requiredFunding - totalAllocated;

        if (amount > available) {
            revert AllocationExceedsFunding(available, amount);
        }

        milestoneId = milestones.length;

        milestones.push(
            Milestone({
                amount: amount,
                deadline: deadline,
                detailsHash: detailsHash,
                submissionHash: bytes32(0),
                reviewHash: bytes32(0),
                status: MilestoneStatus.Pending
            })
        );

        totalAllocated += amount;

        emit MilestoneAdded(milestoneId, amount, deadline, detailsHash);
    }

    /// @notice Locks the completed milestone schedule and starts the work.
    function activateSchedule() external onlyClient {
        if (state != EscrowState.Funded) {
            revert InvalidState(EscrowState.Funded, state);
        }

        if (milestones.length == 0 || totalAllocated != requiredFunding) {
            revert ScheduleNotFullyAllocated(totalAllocated, requiredFunding);
        }

        state = EscrowState.Active;

        emit ScheduleActivated(msg.sender);
    }

    /// @notice Records the contractor's evidence for one milestone.
    /// @param milestoneId Zero-based milestone identifier.
    /// @param submissionHash Hash of the off-chain delivery evidence.
    function submitMilestone(
        uint256 milestoneId,
        bytes32 submissionHash
    ) external onlyContractor {
        if (state != EscrowState.Active) {
            revert InvalidState(EscrowState.Active, state);
        }

        if (milestoneId >= milestones.length) {
            revert InvalidMilestoneId(milestoneId);
        }

        Milestone storage milestone = milestones[milestoneId];

        if (
            milestone.status != MilestoneStatus.Pending
                && milestone.status != MilestoneStatus.Rejected
        ) {
            revert InvalidMilestoneStatus(MilestoneStatus.Pending, milestone.status);
        }

        if (submissionHash == bytes32(0)) {
            revert EmptySubmissionHash();
        }

        // Submission deadlines use day-scale scheduling, not randomness or
        // a fine-grained competitive cutoff.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > milestone.deadline) {
            revert MilestoneDeadlinePassed(milestone.deadline, block.timestamp);
        }

        milestone.submissionHash = submissionHash;
        milestone.reviewHash = bytes32(0);
        milestone.status = MilestoneStatus.Submitted;

        emit MilestoneSubmitted(milestoneId, msg.sender, submissionHash);
    }

    /// @notice Approves submitted work without transferring ETH.
    function approveMilestone(
        uint256 milestoneId
    ) external onlyClient {
        if (state != EscrowState.Active) {
            revert InvalidState(EscrowState.Active, state);
        }

        if (milestoneId >= milestones.length) {
            revert InvalidMilestoneId(milestoneId);
        }

        Milestone storage milestone = milestones[milestoneId];

        if (milestone.status != MilestoneStatus.Submitted) {
            revert InvalidMilestoneStatus(MilestoneStatus.Submitted, milestone.status);
        }

        milestone.status = MilestoneStatus.Approved;
        totalApproved += milestone.amount;

        emit MilestoneApproved(milestoneId, msg.sender, milestone.amount);
    }

    /// @notice Rejects submitted work and records the reason hash.
    function rejectMilestone(
        uint256 milestoneId,
        bytes32 reviewHash
    ) external onlyClient {
        if (state != EscrowState.Active) {
            revert InvalidState(EscrowState.Active, state);
        }

        if (milestoneId >= milestones.length) {
            revert InvalidMilestoneId(milestoneId);
        }

        Milestone storage milestone = milestones[milestoneId];

        if (milestone.status != MilestoneStatus.Submitted) {
            revert InvalidMilestoneStatus(MilestoneStatus.Submitted, milestone.status);
        }

        if (reviewHash == bytes32(0)) {
            revert EmptyReviewHash();
        }

        milestone.reviewHash = reviewHash;
        milestone.status = MilestoneStatus.Rejected;

        emit MilestoneRejected(milestoneId, msg.sender, reviewHash);
    }

    function milestoneCount() external view returns (uint256) {
        return milestones.length;
    }

    function getMilestone(
        uint256 milestoneId
    ) external view returns (Milestone memory) {
        if (milestoneId >= milestones.length) {
            revert InvalidMilestoneId(milestoneId);
        }

        return milestones[milestoneId];
    }

    function unallocatedFunding() external view returns (uint256) {
        return requiredFunding - totalAllocated;
    }

    function isClient(
        address account
    ) external view returns (bool) {
        return account == client;
    }

    function isContractor(
        address account
    ) external view returns (bool) {
        return account == contractor;
    }

    function isArbiter(
        address account
    ) external view returns (bool) {
        return account == arbiter;
    }

    function clientRestrictedAction() external view onlyClient returns (bool) {
        return true;
    }

    function contractorRestrictedAction() external view onlyContractor returns (bool) {
        return true;
    }

    function arbiterRestrictedAction() external view onlyArbiter returns (bool) {
        return true;
    }

    receive() external payable {
        revert DirectPaymentNotAllowed();
    }
}
