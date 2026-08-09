// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { SmartEscrow } from "../../src/SmartEscrow.sol";
import { Test } from "forge-std/Test.sol";

contract SmartEscrowFundingTest is Test {
    event EscrowFunded(address indexed client, uint256 amount);

    SmartEscrow internal escrow;

    address internal client = makeAddr("client");
    address internal contractor = makeAddr("contractor");
    address internal arbiter = makeAddr("arbiter");
    address internal outsider = makeAddr("outsider");

    uint256 internal constant REQUIRED_FUNDING = 10 ether;

    function setUp() public {
        escrow = new SmartEscrow(client, contractor, arbiter, REQUIRED_FUNDING);

        vm.deal(client, 100 ether);
        vm.deal(contractor, 100 ether);
        vm.deal(outsider, 100 ether);
    }

    function test_ConstructorStoresRequiredFunding() public view {
        assertEq(escrow.requiredFunding(), REQUIRED_FUNDING);
    }

    function test_InitialAccountingIsZero() public view {
        assertEq(escrow.totalDeposited(), 0);
        assertEq(address(escrow).balance, 0);
    }

    function test_ClientCanFundExactRequiredAmount() public {
        vm.prank(client);
        escrow.fund{ value: REQUIRED_FUNDING }();

        assertEq(escrow.totalDeposited(), REQUIRED_FUNDING);
        assertEq(address(escrow).balance, REQUIRED_FUNDING);

        assertEq(uint256(escrow.state()), uint256(SmartEscrow.EscrowState.Funded));
    }

    function test_FundingEmitsEscrowFundedEvent() public {
        vm.expectEmit(true, false, false, true);
        emit EscrowFunded(client, REQUIRED_FUNDING);

        vm.prank(client);
        escrow.fund{ value: REQUIRED_FUNDING }();
    }

    function test_RevertWhenFundingRequirementIsZero() public {
        vm.expectRevert(SmartEscrow.ZeroFundingRequirement.selector);

        new SmartEscrow(client, contractor, arbiter, 0);
    }

    function test_RevertWhenOutsiderAttemptsToFund() public {
        vm.prank(outsider);
        vm.expectRevert(SmartEscrow.Unauthorized.selector);

        escrow.fund{ value: REQUIRED_FUNDING }();
    }

    function test_RevertWhenContractorAttemptsToFund() public {
        vm.prank(contractor);
        vm.expectRevert(SmartEscrow.Unauthorized.selector);

        escrow.fund{ value: REQUIRED_FUNDING }();
    }

    function test_RevertWhenClientUnderfunds() public {
        uint256 received = REQUIRED_FUNDING - 1 wei;

        vm.prank(client);
        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.IncorrectFundingAmount.selector, REQUIRED_FUNDING, received
            )
        );

        escrow.fund{ value: received }();
    }

    function test_RevertWhenClientOverfunds() public {
        uint256 received = REQUIRED_FUNDING + 1 wei;

        vm.prank(client);
        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.IncorrectFundingAmount.selector, REQUIRED_FUNDING, received
            )
        );

        escrow.fund{ value: received }();
    }

    function test_RevertWhenClientSendsZeroFunding() public {
        vm.prank(client);
        vm.expectRevert(
            abi.encodeWithSelector(SmartEscrow.IncorrectFundingAmount.selector, REQUIRED_FUNDING, 0)
        );

        escrow.fund();
    }

    function test_RevertWhenClientAttemptsToFundTwice() public {
        vm.startPrank(client);

        escrow.fund{ value: REQUIRED_FUNDING }();

        vm.expectRevert(
            abi.encodeWithSelector(
                SmartEscrow.InvalidState.selector,
                SmartEscrow.EscrowState.Created,
                SmartEscrow.EscrowState.Funded
            )
        );

        escrow.fund{ value: REQUIRED_FUNDING }();

        vm.stopPrank();
    }

    function test_FailedUnderfundingLeavesAccountingUnchanged() public {
        vm.prank(client);

        try escrow.fund{ value: 1 ether }() {
            fail();
        } catch {
            assertEq(escrow.totalDeposited(), 0);
            assertEq(address(escrow).balance, 0);

            assertEq(uint256(escrow.state()), uint256(SmartEscrow.EscrowState.Created));
        }
    }

    function test_DirectEthTransferIsRejected() public {
        vm.prank(client);

        (bool success,) = address(escrow).call{ value: 1 ether }("");

        assertFalse(success);
        assertEq(address(escrow).balance, 0);
        assertEq(escrow.totalDeposited(), 0);
    }
}
